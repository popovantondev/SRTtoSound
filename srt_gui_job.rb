#!/usr/bin/ruby
# frozen_string_literal: true

# One cancellable job. The native GUI starts jobs sequentially, never concurrently.
require "json"
require "open3"
require "optparse"
require "tmpdir"
require "fileutils"
require_relative "srt_voiceover"
require_relative "srt_output_policy"

def preferred_aac_encoder(ffmpeg)
  stdout, _stderr, status = Open3.capture3(ffmpeg, "-hide_banner", "-encoders")
  status.success? && stdout.match?(/^\s*A\S*\s+aac_at\s/m) ? "aac_at" : "aac"
rescue SystemCallError
  "aac"
end

def voice_test_sample_srt
  <<~SRT
    1
    00:00:00,000 --> 00:00:14,000
    Пять миллилитров, 12,5 процента, ромашка и Crataegus. Проверяем ясную русскую речь.
  SRT
end

def normalized_voice_test_sample(rhythm = "smooth", speaker: "kseniya", data_dir: nil)
  require "tempfile"
  Tempfile.create(["srt-voice-test-", ".ru.srt"]) do |file|
    file.write(voice_test_sample_srt)
    file.flush
    prepared = prepare_speech_file(file.path, rhythm: rhythm, speaker: speaker, data_dir: data_dir)
    results = prepared.fetch(:results)
    warnings = results.flat_map do |result|
      result.audit[:foreign_tokens].map do |token|
        "#{token[:source]} → #{token[:replacement]} (#{token[:strategy]})"
      end
    end.uniq
    {
      source_srt: voice_test_sample_srt,
      source_text: prepared.fetch(:source_cues).map(&:text).join("\n\n"),
      text: results.map(&:text).join("\n\n"),
      warnings: warnings,
      preparation_fingerprint: prepared.fetch(:fingerprint)
    }
  end
end

# Keep scratch data on the output filesystem for atomic publication, but put it
# outside the destination directory when its parent is writable. If the user
# loses write access to the destination while a long synthesis is running, the
# job can still clean its staging files and preserve the original I/O error.
def staging_parent_for_output(output)
  directory = File.dirname(File.expand_path(output))
  parent = File.dirname(directory)
  return directory if parent == directory
  return directory unless File.directory?(parent) && File.writable?(parent)
  return directory unless File.stat(parent).dev == File.stat(directory).dev

  parent
rescue SystemCallError
  directory
end

def cleanup_staging_directory(path)
  3.times do |attempt|
    begin
      FileUtils.remove_entry(path, true)
    rescue SystemCallError
      # APFS/FAT metadata sidecars can disappear together with their data file
      # while Ruby 2.6 is traversing the temporary directory.
    end
    return true unless File.exist?(path)

    sleep 0.05 if attempt < 2
  end
  false
rescue StandardError
  false
end

class VoiceoverJob
  def initialize(input:, output: nil, voice: "silero", speaker: "kseniya", format: nil, rhythm: "smooth",
                 engine: File.join(__dir__, "srt_voiceover.rb"), ffmpeg: nil,
                 reports_dir: VoiceoverReports::DEFAULT_DIRECTORY, conflict: "copy", decision: nil,
                 idle_timeout: 180, expected_sha256: nil, expected_preparation_fingerprint: nil,
                 job_id: nil, &events)
    @input = File.expand_path(input)
    @format = format || (output && File.extname(output).delete_prefix(".").downcase) || "m4a"
    @format = "m4a" if @format == "aac"
    @output = File.expand_path(output || default_audio_output_path(@input, @format))
    @voice, @speaker, @engine, @rhythm = voice, speaker, engine, rhythm
    @ffmpeg = ffmpeg
    @events = events || proc { |event| puts JSON.generate(event) }
    @job_id = job_id || SecureRandom.uuid
    unless @job_id.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i)
      raise ArgumentError, "Invalid job ID"
    end
    @cancelled = false
    @buffer = "".b
    @tail = []
    @phase = :speech
    @media_time = nil
    @warnings = 0
    @last_progress = 0
    @progress_measure_stage = "speech"
    @idle_timeout = idle_timeout
    @expected_sha256 = expected_sha256
    @expected_preparation_fingerprint = expected_preparation_fingerprint
    @reports = VoiceoverReports.new(reports_dir)
    @decision = decision
    @destination = VoiceoverDestination.new(@output, input: @input, policy: conflict,
      cancelled: proc { @cancelled }) { |path, can_replace| request_decision(path, can_replace) }
  end

  def cancel
    @cancelled = true
  end

  def cancelled?
    @cancelled
  end

  def emit(event)
    if event[:type] == "progress" && event[:percent]
      event = event.merge(percent: [event[:percent].to_i, @last_progress].max)
      @last_progress = event[:percent]
    end
    event = event.merge(code: event_code(event[:type])) unless event[:code]
    @events.call({ protocol_version: 1, job_id: @job_id }.merge(event))
  end

  def event_code(type)
    {
      conflict: "output_conflict", progress: "progress_update", status: "status_update",
      warning: "warning", diagnostic: "backend_diagnostic", done: "audio_ready",
      report: "report_written", skipped: "user_skipped", cancelled: "user_cancelled",
      error: "voiceover_failed"
    }.fetch(type.to_s.to_sym, "worker_event")
  end

  def record(line)
    line = line.force_encoding("UTF-8").scrub.strip
    return if line.empty?
    if line.start_with?("{")
      begin
        event = JSON.parse(line)
        if event["protocol_version"] == 1
          consume_engine_event(event)
          return
        end
      rescue JSON::ParserError
        # Keep malformed child output in diagnostics, never interpret it as UI protocol.
      end
    end
    if @phase != :speech
      if line.start_with?("out_time_us=")
        @media_time = Float(line.split("=", 2).last) / 1_000_000.0 rescue nil
        if @media_time && @expected_duration
          fraction = [[@media_time / @expected_duration, 0].max, 1].min
          base, span = @phase == :encode ? [90, 8] : [98, 1]
          emit(type: "progress", percent: (base + fraction * span).round, stage: @phase.to_s)
        end
        return
      end
      # FFmpeg progress protocol is not a user-facing log.
      return if line.match?(/\A(?:bitrate|total_size|out_time_ms|out_time|dup_frames|drop_frames|speed|progress)=/)
    end
    # These backend paths point into temporary staging, not to final results.
    @tail << line
    @tail.shift while @tail.length > 12
    emit(type: "diagnostic", code: "backend_output", diagnostic: line)
  end

  def consume_engine_event(event)
    case event["type"]
    when "progress"
      stage = event["stage"].to_s
      current = event["current"].to_i
      total = event["total"].to_i
      return unless total.positive?
      speech_end = @format == "m4a" ? 90 : 100
      synthesis_end = (speech_end * 0.70).round
      raw_percent = event["percent"]
      percent = case stage
                when "synthesis" then (current * synthesis_end.to_f / total).round
                when "assembly" then synthesis_end + ((raw_percent || 0).to_f * (speech_end - synthesis_end) / 100).round
                else ((raw_percent || 0).to_f * speech_end / 100).round
                end
      emit_phrase_progress(percent, current, total, stage)
    when "warning"
      @warnings += 1
      case event["code"]
      when "tempo_fit"
        emit(type: "warning", code: "tempo_fit", phrase: event["phrase"],
          first_cue: event["first_cue"], last_cue: event["last_cue"],
          factor: event["factor"], all_words_kept: event["all_words_kept"] == true)
      when "silent_cues"
        emit(type: "warning", code: "silent_cues", cues: event["cues"] || [])
      end
    when "engine_error"
      @tail << event["diagnostic"].to_s
      @tail.shift while @tail.length > 12
    when "status"
      emit(type: "status", code: event["code"] || "backend_status")
    else
      emit(type: "diagnostic", code: "backend_output", diagnostic: JSON.generate(event))
    end
  end

  def emit_phrase_progress(percent, current, total, stage)
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    if @progress_measure_stage != stage || !@first_progress
      @progress_measure_stage = stage
      @first_progress = [now, current]
    end
    event = { type: "progress", code: "phrase_progress", percent: percent,
      current: current, total: total, stage: stage }
    measured = current - @first_progress[1]
    if measured >= 2 && now - @first_progress[0] >= 1
      event[:eta_seconds] = ((now - @first_progress[0]) / measured * (total - current)).round
    end
    emit(event)
  end

  def consume(bytes, flush: false)
    @buffer << bytes.b
    while (index = @buffer.index(/[\r\n]/))
      record(@buffer.slice!(0, index + 1))
    end
    record(@buffer.slice!(0, @buffer.bytesize)) if flush && !@buffer.empty?
  end

  def request_decision(path, can_replace)
    return @decision.call(path, can_replace) if @decision
    request_id = SecureRandom.uuid
    emit(type: "conflict", path: path, can_replace: can_replace, request_id: request_id)
    pending = "".b
    loop do
      raise VoiceoverCancelled if @cancelled
      next unless IO.select([$stdin], nil, nil, 0.1)
      chunk = $stdin.read_nonblock(4096, exception: false)
      raise VoiceoverError, "Не получен ответ о сохранении. Файлы не изменены." if chunk.nil?
      next if chunk == :wait_readable
      pending << chunk
      raise VoiceoverError, "Некорректный ответ о сохранении" if pending.bytesize > 8192
      while (newline = pending.index("\n"))
        answer = JSON.parse(pending.slice!(0, newline + 1))
        return answer.fetch("action") if answer["request_id"] == request_id
      end
    end
  end

  # Check space for timeline PCM + AAC + temporary speech, not only final M4A.
  def preflight(cues)
    directory = File.dirname(@output)
    raise VoiceoverError, "Папка сохранения недоступна: #{directory}" unless File.directory?(directory) && File.writable?(directory)
    out, _err, status = Open3.capture3("/bin/df", "-Pk", directory)
    available = out.lines.last.to_s.split[3]
    unless status.success? && available && available.match?(/\A\d+\z/)
      raise VoiceoverError, "Не удалось проверить свободное место: #{directory}"
    end
    # Final PCM, generated speech and one island's tempo intermediates all use
    # this volume.  A generous reserve prevents late failures on long lectures.
    timeline_seconds = cues.last.end_ms / 1000.0
    timeline_estimate = timeline_seconds * 260_000
    dense_speech_estimate = timeline_seconds * 64_000 + cues.sum { |cue| cue.text.length } * 4_000
    required = [timeline_estimate, dense_speech_estimate].max + 128 * 1024 * 1024
    if available.to_i * 1024 < required
      raise VoiceoverError, "Недостаточно места. Нужно примерно #{(required / 1024 / 1024).ceil} МБ для временной и готовой дорожки."
    end
    @reports.prepare
  end

  def publish(audio, report)
    @destination.resolve
    destination_report = @reports.publish(report, input: @input, output: @output)
    destination = @destination.publish(audio)
    [destination, destination_report]
  rescue StandardError
    File.unlink(destination_report) if destination_report && !destination
    raise
  end

  def run
    raise VoiceoverError, "Выберите файл SRT" unless File.extname(@input).downcase == ".srt"
    raise VoiceoverError, "Формат должен быть AAC (m4a) или WAV" unless %w[m4a wav].include?(@format)
    raise VoiceoverError, "Расширение выходного файла не совпадает с форматом #{@format}" unless File.extname(@output).downcase == ".#{@format}"
    raise VoiceoverError, "Недопустимый движок голоса: #{@voice}. Поддерживается только Silero." unless @voice == "silero"
    raise VoiceoverError, "Недопустимый голос Silero" unless %w[xenia kseniya baya aidar eugene].include?(@speaker)
    raise VoiceoverError, "Недопустимый режим ритма" unless %w[smooth strict].include?(@rhythm)
    cues = parse_srt(@input) # Reject malformed inputs before loading a voice/model.
    if @expected_sha256 && Digest::SHA256.file(@input).hexdigest != @expected_sha256
      raise VoiceoverError, "SRT изменился после предварительной проверки. Запустите очередь снова."
    end
    if @rhythm == "smooth"
      smooth_islands(smooth_phrases(cues), cues.last.end_ms)
    else
      phrase_windows(group_cues(cues))
    end
    @timeline_duration = cues.last.end_ms / 1000.0
    @destination.resolve # A skipped file must not load the model or generate audio.
    preflight(cues)
    raise VoiceoverError, "Не найдена программа озвучки" unless File.file?(@engine)
    if @format == "m4a"
      @ffmpeg ||= find_ffmpeg
      raise VoiceoverError, "Для AAC не найден FFmpeg. Установите Subtitle Edit или выберите WAV." unless @ffmpeg && File.executable?(@ffmpeg)
    end
    return cancelled if @cancelled
    emit(type: "status", code: "preparing_voice", text: "Подготовка голоса…")
    staging_parent = staging_parent_for_output(@output)
    staging = Dir.mktmpdir(".srt-voiceover-", staging_parent)
    begin
      wav = File.join(staging, "audio.wav")
      report = File.join(staging, "audio.report.txt")
      args = ["/usr/bin/ruby", @engine, "--voice", @voice, "--rhythm", @rhythm, "--output", wav]
      args << "--machine-events"
      args += ["--expected-preparation-fingerprint", @expected_preparation_fingerprint] if @expected_preparation_fingerprint
      args += ["--silero-speaker", @speaker] if File.basename(@engine) == "srt_voiceover.rb"
      args << @input
      status = run_process(args)
      return cancelled if @cancelled
      raise VoiceoverError, failure_message("Озвучка завершилась с ошибкой") unless status.success?
      validate_wav(wav)
      raise VoiceoverError, "Не получен отчёт об озвучке" unless File.file?(report)
      audio = wav
      if @format == "m4a"
        audio = File.join(staging, "audio.m4a")
        aac_encoder = preferred_aac_encoder(@ffmpeg)
        @phase = :encode
        @tail.clear
        encoder_label = aac_encoder == "aac_at" ? "ускорение Apple" : "FFmpeg"
        emit(type: "status", code: "saving_aac", encoder: aac_encoder, text: "Сохраняю AAC для MP4 · 128 кбит/с · #{encoder_label}…")
        encode = lambda do |encoder|
          encoder_options = ["-c:a", encoder]
          encoder_options += ["-profile:a", "aac_low"] if encoder == "aac"
          run_process([@ffmpeg, "-hide_banner", "-nostdin", "-n", "-loglevel", "error",
            "-progress", "pipe:1", "-i", wav, "-map", "0:a:0", "-map_metadata", "-1",
            *encoder_options, "-b:a", "128k", "-ar", "48000", "-ac", "2",
            "-metadata:s:a:0", "language=rus", "-metadata:s:a:0", "handler_name=Русский",
            "-movflags", "+faststart", "-f", "ipod", audio])
        end
        status = encode.call(aac_encoder)
        if !status.success? && aac_encoder == "aac_at" && !@cancelled
          FileUtils.rm_f(audio)
          aac_encoder = "aac"
          @tail.clear
          emit(type: "status", code: "aac_hardware_fallback", text: "Ускорение Apple недоступно — использую обычный FFmpeg AAC…")
          status = encode.call(aac_encoder)
        end
        return cancelled if @cancelled
        raise VoiceoverError, failure_message("Не удалось сохранить AAC") unless status.success?
        @phase = :verify
        @media_time = nil
        @tail.clear
        emit(type: "status", code: "verifying_aac", text: "Проверяю AAC и длительность дорожки…")
        # Decode the completed AAC before publication. This also checks that
        # encoder priming/edit lists did not truncate the lecture timeline.
        status = run_process([@ffmpeg, "-hide_banner", "-nostdin", "-loglevel", "error", "-xerror",
          "-progress", "pipe:1", "-i", audio, "-map", "0:a:0", "-c:a", "pcm_s16le", "-f", "null", "-"])
        return cancelled if @cancelled
        raise VoiceoverError, failure_message("Готовый AAC не прошёл проверку") unless status.success?
        unless @media_time && (@media_time - @expected_duration).abs <= 0.1
          raise VoiceoverError, "Длительность AAC не совпадает с WAV. Готовый файл не опубликован."
        end
        File.open(report, "a:utf-8") do |file|
          file.puts "\nВыходной формат: AAC-LC в M4A, 128 кбит/с, 48 кГц, стерео."
          file.puts "Кодировщик AAC: #{aac_encoder}."
          file.puts "AAC проверен декодированием; длительность #{format('%.3f', @media_time)} с."
        end
      end
      return cancelled if @cancelled
      destination, destination_report = publish(audio, report)
      emit(type: "done", output: destination, report: destination_report, format: @format, warnings: @warnings)
    ensure
      unless cleanup_staging_directory(staging)
        emit(type: "diagnostic", code: "staging_cleanup_failed",
          diagnostic: "Не удалось полностью удалить временную папку: #{staging}")
      end
    end
    0
  rescue VoiceoverSkipped
    persist_outcome("skipped", "Пропущено по выбору пользователя. Старый файл сохранён.")
    emit(type: "skipped", code: "user_skipped", text: "Пропущено по выбору пользователя. Старый файл сохранён.", output: @destination.path)
    0
  rescue VoiceoverCancelled
    cancelled
  rescue StandardError => error
    persist_outcome("failed", error.message)
    emit(type: "error", code: "voiceover_failed", diagnostic: error.message, text: error.message)
    1
  end

  def persist_outcome(status, detail)
    path = @reports.publish_outcome(input: @input, output: @output, status: status, detail: detail)
    emit(type: "report", status: status, report: path)
  rescue StandardError => report_error
    emit(type: "diagnostic", code: "report_write_failed", diagnostic: report_error.message,
      text: "Не удалось сохранить приватный отчёт: #{report_error.message}")
  end

  def validate_wav(wav)
    File.open(wav, "rb") do |file|
      header = file.read(44)
      unless header && header.bytesize == 44 && header.start_with?("RIFF") &&
             header[8, 4] == "WAVE" && header[36, 4] == "data" && File.size(wav) > 44
        raise VoiceoverError, "Не получен готовый WAV"
      end
      data_bytes = header[40, 4].unpack1("V")
      byte_rate = header[28, 4].unpack1("V")
      raise VoiceoverError, "Повреждён WAV" unless byte_rate.positive? && data_bytes == File.size(wav) - 44
      @expected_duration = data_bytes.to_f / byte_rate
      if @timeline_duration && (@expected_duration - @timeline_duration).abs > 0.001
        raise VoiceoverError, "Длительность WAV не совпадает с таймкодами SRT. Результат не опубликован."
      end
    end
  end

  def cancelled
    persist_outcome("cancelled", "Остановлено. Незавершённая дорожка не сохранена.")
    emit(type: "cancelled", code: "user_cancelled", text: "Остановлено. Незавершённая дорожка не сохранена.")
    130
  end

  def failure_message(fallback)
    @tail.empty? ? fallback : "#{fallback}: #{@tail.last(5).join("\n")}"
  end

  # The same cancellation applies to synthesis, AAC encoding and validation.
  def run_process(args)
    Open3.popen2e(*args, pgroup: true) do |stdin, stream, wait|
        stdin.close
        termination_sent = nil
        killed = false
        eof = false
        last_activity = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        begin
          loop do
            if !@cancelled && Process.clock_gettime(Process::CLOCK_MONOTONIC) - last_activity > @idle_timeout
              raise VoiceoverError, "Движок не отвечает более #{@idle_timeout.ceil} с. Задание остановлено, существующее аудио не изменено. Проверьте окно «Команды» и доступность голоса."
            end
            if @cancelled && !termination_sent
              signal_group("TERM", wait.pid)
              termination_sent = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            elsif termination_sent && !killed && Process.clock_gettime(Process::CLOCK_MONOTONIC) - termination_sent > 2
              signal_group("KILL", wait.pid)
              killed = true
            end
            unless eof
              chunk = stream.read_nonblock(8192, exception: false)
              case chunk
              when nil then eof = true
              when :wait_readable then IO.select([stream], nil, nil, 0.1)
              else
                last_activity = Process.clock_gettime(Process::CLOCK_MONOTONIC)
                consume(chunk)
              end
            end
            break if !wait.alive? && eof
            sleep(0.05) if eof
          end
          consume("", flush: true)
          wait.value
        ensure
          signal_group("KILL", wait.pid) if wait.alive?
        end
    end
  end

  def signal_group(signal, pid)
    Process.kill(signal, -pid)
  rescue Errno::ESRCH, Errno::EPERM
    # The worker may exit between the cancellation check and signal delivery.
    # In that race the process-group id can already be gone or no longer be
    # signalable; the caller still reaps the direct child and never publishes
    # its staged output after cancellation.
    nil
  end
end

if $PROGRAM_NAME == __FILE__
  $stdout.sync = true
  options = { voice: "silero", speaker: "kseniya", rhythm: "smooth" }
  human = false
  cleanup_reports = false
  job = nil
  begin
    if ARGV.first == "--preflight-cancelled-reports"
      ARGV.shift
      raise ArgumentError, "Нужна папка отчётов" unless ARGV.shift == "--reports-dir"
      reports = VoiceoverReports.new(ARGV.shift || raise(ArgumentError, "Нужна папка отчётов"))
      files = []
      until ARGV.empty?
        raise ArgumentError, "Ожидался --item" unless ARGV.shift == "--item"
        input = ARGV.shift || raise(ArgumentError, "Не указан исходный SRT")
        raise ArgumentError, "Ожидался --output" unless ARGV.shift == "--output"
        output = ARGV.shift || raise(ArgumentError, "Не указан ожидаемый путь результата")
        report = reports.publish_outcome(input: input, output: output, status: "cancelled",
          detail: "Очередь отменена во время предварительной проверки. Синтез для этого файла не запускался; существующий аудиофайл не изменён.")
        files << { file: input, report: report, status: "cancelled" }
      end
      puts JSON.generate(protocol_version: 1, type: "preflight_cancellation_reports", files: files)
      exit 0
    end
    if ARGV.first == "--voice-test-sample"
      ARGV.shift
      rhythm = ARGV.shift || "smooth"
      speaker = ARGV.shift || "kseniya"
      raise ArgumentError, "Нужен режим ритма smooth или strict" unless %w[smooth strict].include?(rhythm)
      raise ArgumentError, "Недопустимый голос Silero" unless SILERO_SPEAKERS.include?(speaker)
      puts JSON.generate({ type: "voice_test_sample" }.merge(normalized_voice_test_sample(
        rhythm, speaker: speaker, data_dir: voiceover_data_dir(File.expand_path(__dir__)))))
      exit 0
    end
    if ARGV.first == "--preflight"
      ARGV.shift
      preflight_reports = VoiceoverReports.new(VoiceoverReports::DEFAULT_DIRECTORY)
      preflight_format = "m4a"
      if ARGV.first == "--reports-dir"
        ARGV.shift
        preflight_reports = VoiceoverReports.new(ARGV.shift || raise(ArgumentError, "Нужна папка отчётов"))
      end
      if ARGV.first == "--format"
        ARGV.shift
        preflight_format = ARGV.shift || raise(ArgumentError, "Нужен формат выхода")
        raise ArgumentError, "Формат должен быть m4a или wav" unless %w[m4a wav].include?(preflight_format)
      end
      rhythm = ARGV.shift
      raise ArgumentError, "Нужен режим ритма smooth или strict" unless %w[smooth strict].include?(rhythm)
      speaker = "kseniya"
      grouping = true
      request_id = nil
      while ARGV.first&.start_with?("--")
        flag = ARGV.shift
        case flag
        when "--speaker" then speaker = ARGV.shift || raise(ArgumentError, "Нужен голос Silero")
        when "--request-id" then request_id = ARGV.shift || raise(ArgumentError, "Нужен ID предварительной проверки")
        when "--no-group" then grouping = false
        else raise ArgumentError, "Неизвестный параметр предварительной проверки: #{flag}"
        end
      end
      results = ARGV.map do |path|
        begin
          prepared = prepare_speech_file(path, rhythm: rhythm, speaker: speaker, grouping: grouping)
          { file: File.expand_path(path), status: "ok", cues: prepared[:cues].length,
            phrases: prepared[:phrases].length, sha256: prepared[:source_sha256],
            preparation_fingerprint: prepared[:fingerprint] }
        rescue StandardError => error
          detail = "Ошибка предварительной проверки: #{error.message}"
          report_path = preflight_reports.publish_outcome(input: File.expand_path(path),
            output: default_audio_output_path(File.expand_path(path), preflight_format), status: "failed", detail: detail)
          issues = if error.is_a?(PreparationIssuesError)
                     error.issues
                   else
                     [{ cue: nil, timestamps: nil, severity: "error", code: "preflight_error",
                        codepoint: error.message.scan(/U\+[0-9A-F]{4,6}/).first,
                        explanation: error.message, action: "Проверьте целостность SRT и таймкодов." }]
                   end
          { file: File.expand_path(path), status: "error", report: report_path, issues: issues }
        end
      end
      puts JSON.generate(protocol_version: 1, type: "preflight", request_id: request_id, files: results)
      exit(results.any? { |item| item[:status] == "error" } ? 1 : 0)
    end
    OptionParser.new do |parser|
      parser.on("--voice NAME") { |v| options[:voice] = v }
      parser.on("--engine PATH", "test-only override for the speech worker") { |v| options[:engine] = v }
      parser.on("--speaker NAME") { |v| options[:speaker] = v }
      parser.on("--format NAME", "m4a (AAC, по умолчанию) или wav") { |v| options[:format] = v }
      parser.on("--rhythm NAME", "smooth (по умолчанию) или strict") { |v| options[:rhythm] = v }
      parser.on("--output PATH") { |v| options[:output] = v }
      parser.on("--expected-sha256 HASH") { |v| options[:expected_sha256] = v }
      parser.on("--expected-preparation-fingerprint HASH") { |v| options[:expected_preparation_fingerprint] = v }
      parser.on("--reports-dir PATH") { |v| options[:reports_dir] = v }
      parser.on("--job-id UUID", "correlation ID supplied by the GUI") { |v| options[:job_id] = v }
      parser.on("--conflict ACTION", "copy (по умолчанию), ask, skip, replace") { |v| options[:conflict] = v }
      parser.on("--cleanup-reports") { cleanup_reports = true }
      parser.on("--human", "Понятный вывод для Терминала") { human = true }
    end.parse!
    raise ArgumentError, "Нужен один входной SRT" unless ARGV.length <= 1
    if cleanup_reports
      removed = VoiceoverReports.new(options[:reports_dir] || VoiceoverReports::DEFAULT_DIRECTORY).cleanup
      puts JSON.generate(type: "cleanup", removed: removed)
      exit 0
    end
    if human && options[:conflict] == "ask"
      options[:decision] = proc do |path, can_replace|
        puts "\nФайл уже существует:\n#{path}\n1 — сохранить копию (Enter), 2 — заменить, 3 — пропустить."
        puts "Заменять ссылки и папки нельзя." unless can_replace
        until IO.select([$stdin], nil, nil, 0.1)
          raise VoiceoverCancelled if job&.cancelled?
        end
        raise VoiceoverCancelled if job&.cancelled?
        answer = $stdin.gets
        raise VoiceoverError, "Нет ответа. Файлы не изменены." unless answer
        { "" => "copy", "1" => "copy", "2" => "replace", "3" => "skip" }.fetch(answer.strip, "skip")
      end
    end
    events = if human
               proc do |event|
                 case event[:type]
                 when "progress"
                   print "\r#{event[:percent]}%   "
                 when "done"
                   puts "\nГотово: #{event[:output]}\nОтчёт: #{event[:report]}"
                 else
                   puts "\n#{event[:text]}" if event[:text]
                 end
               end
             end
    options[:engine] ||= File.join(__dir__, "srt_voiceover.rb")
    job = VoiceoverJob.new(input: ARGV.first || choose_srt, **options, &events)
    Signal.trap("TERM") { job.cancel }
    Signal.trap("INT") { job.cancel }
    exit(job.run)
  rescue StandardError => error
    puts JSON.generate(type: "error", text: error.message)
    exit 1
  end
end
