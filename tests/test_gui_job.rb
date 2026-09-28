require "minitest/autorun"
require "timeout"
require_relative "../srt_gui_job"

class GuiJobTest < Minitest::Test
  def process_exists?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  rescue Errno::EPERM
    true
  end

  def wait_until_process_exits(pid, timeout: 2)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      return true unless process_exists?(pid)
      sleep 0.02
    end
    !process_exists?(pid)
  end

  def setup
    @dir = Dir.mktmpdir("srt-gui-unit-")
    @input = File.join(@dir, "01 Тест.ru.srt")
    @output = File.join(@dir, "01 Тест.ru.silero.voice.wav")
    @source = "1\n00:00:00,000 --> 00:00:04,000\nПроверка голоса.\n"
    File.write(@input, @source)
    @events = []
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def job
    VoiceoverJob.new(input: @input, output: @output, voice: "silero", rhythm: "strict",
                     reports_dir: File.join(@dir, "reports"),
                     engine: File.join(__dir__, "fake_engine.rb")) { |event| @events << event }
  end

  def staging_entries(output = @output)
    Dir.glob(File.join(staging_parent_for_output(output), ".srt-voiceover-*")).sort
  end

  def test_bom_crlf_and_multiline
    File.write(@input, "\uFEFF" + @source.sub("Проверка голоса.", "<i>Проверка</i>\nголоса.").gsub("\n", "\r\n"))
    cue = parse_srt(@input).first
    assert_equal "Проверка голоса.", cue.text
    assert_equal 4000, cue.end_ms
  end

  def test_manual_srt_selection_receives_ru_suffix
    bare = File.join(@dir, "lecture.srt")
    assert_equal File.join(@dir, "lecture.ru.m4a"), default_audio_output_path(bare, "m4a")
    assert_equal File.join(@dir, "lecture.ru.wav"), default_audio_output_path(bare, "wav")
    assert_equal File.join(@dir, "lecture.ru.m4a"), default_audio_output_path(File.join(@dir, "lecture.ru.srt"), "m4a")
  end

  def test_staging_uses_writable_same_volume_parent_and_falls_back_when_needed
    output_directory = File.join(@dir, "destination")
    FileUtils.mkdir_p(output_directory)
    output = File.join(output_directory, "lecture.ru.wav")
    assert_equal @dir, staging_parent_for_output(output)

    original_writable = File.method(:writable?)
    File.stub(:writable?, proc { |path| path == @dir ? false : original_writable.call(path) }) do
      assert_equal output_directory, staging_parent_for_output(output)
    end
  end

  def test_staging_cleanup_retries_when_appledouble_entry_vanishes_during_removal
    staging = File.join(@dir, ".srt-voiceover-race")
    FileUtils.mkdir_p(staging)
    audio = File.join(staging, "audio.wav")
    sidecar = File.join(staging, "._audio.wav")
    File.write(audio, "synthetic audio")
    File.write(sidecar, "synthetic AppleDouble metadata")

    original_remove_entry = FileUtils.method(:remove_entry)
    attempts = 0
    FileUtils.stub(:remove_entry, proc do |path, force = false|
      attempts += 1
      if attempts == 1
        FileUtils.rm_f(audio)
        FileUtils.rm_f(sidecar)
        raise Errno::ENOENT, sidecar
      end
      original_remove_entry.call(path, force)
    end) do
      assert cleanup_staging_directory(staging)
    end

    assert_equal 2, attempts
    refute File.exist?(staging)
  end

  def test_multi_file_preflight_prepares_all_files_and_reports_unsafe_cue
    second = File.join(@dir, "02 Synthetic.ru.srt")
    source = "1\n00:00:00,000 --> 00:00:04,000\nПроверка голоса.\n"
    File.write(second, source)
    digest = Digest::SHA256.file(second).hexdigest
    prepared = prepare_speech_file(second, rhythm: "strict")
    assert_equal 1, prepared[:phrases].length
    assert_equal digest, Digest::SHA256.file(second).hexdigest
    assert_match(/\A[0-9a-f]{64}\z/, prepared.fetch(:fingerprint))
    assert_equal 4000, prepared.fetch(:source_end_ms)

    File.write(@input, source.sub("Проверка голоса.", "Название Crаtaegus"))
    error = assert_raises(VoiceoverError) { prepare_speech_file(@input, rhythm: "strict") }
    assert_includes error.message, "реплики 1–1"
    assert_includes error.message, "00:00:00,000–00:00:04,000"
    assert_includes error.message, "U+0430"
  end

  def test_preparation_fingerprint_changes_with_dictionary_and_voice
    base = prepare_speech_file(@input, rhythm: "strict", replacements: {})
    dictionary = prepare_speech_file(@input, rhythm: "strict", replacements: { "Проверка" => "ПРОВЕРКА" })
    voice = prepare_speech_file(@input, rhythm: "strict", replacements: {}, speaker: "baya")
    refute_equal base.fetch(:fingerprint), dictionary.fetch(:fingerprint)
    refute_equal base.fetch(:fingerprint), voice.fetch(:fingerprint)
  end

  def test_preparation_preserves_timeline_when_final_cue_is_punctuation_only
    File.write(@input, @source + "\n2\n00:00:04,000 --> 00:00:09,000\n…\n")
    prepared = prepare_speech_file(@input, rhythm: "smooth")
    assert_equal 9000, prepared.fetch(:source_end_ms)
    assert_equal 4000, prepared.fetch(:phrases).last.end_ms
    assert_equal [2], prepared.fetch(:silent_cues).map(&:number)
  end

  def test_preflight_reports_every_invalid_phrase_in_one_file
    File.write(@input, <<~SRT)
      1
      00:00:00,000 --> 00:00:02,000
      Первая доза × два.

      2
      00:00:03,000 --> 00:00:05,000
      Вторая доза / день.
    SRT
    reports = File.join(@dir, "reports")
    output, = Open3.capture3("/usr/bin/ruby", File.join(__dir__, "../srt_gui_job.rb"),
      "--preflight", "--reports-dir", reports, "strict", @input)
    item = JSON.parse(output).fetch("files").first
    assert_equal "error", item.fetch("status")
    assert_equal ["1", "2"], item.fetch("issues").map { |issue| issue.fetch("cue") }
    assert_equal ["U+00D7", "U+002F"], item.fetch("issues").map { |issue| issue.fetch("codepoint") }
  end

  def test_cancelled_preflight_writes_private_report_for_each_unprocessed_input
    reports = File.join(@dir, "reports")
    second = File.join(@dir, "02 Другая.ru.srt")
    File.write(second, @source)
    output, error, status = Open3.capture3("/usr/bin/ruby", File.join(__dir__, "../srt_gui_job.rb"),
      "--preflight-cancelled-reports", "--reports-dir", reports,
      "--item", @input, "--output", @output,
      "--item", second, "--output", second.sub(/\.srt\z/, ".ru.m4a"))
    assert status.success?, error
    payload = JSON.parse(output)
    assert_equal 1, payload.fetch("protocol_version")
    assert_equal "preflight_cancellation_reports", payload.fetch("type")
    entries = payload.fetch("files")
    assert_equal [@input, second], entries.map { |entry| entry.fetch("file") }
    assert entries.all? { |entry| entry.fetch("status") == "cancelled" }
    entries.each do |entry|
      body = File.read(entry.fetch("report"))
      assert body.start_with?(VoiceoverReports::MARKER)
      assert_includes body, "Статус: cancelled"
      assert_includes body, "Синтез для этого файла не запускался"
    end
    assert_equal @source, File.read(@input)
    assert_equal @source, File.read(second)
    refute File.exist?(@output)
  end

  def test_queue_preflight_cli_returns_results_for_every_synthetic_file
    second = File.join(@dir, "02 Synthetic.ru.srt")
    File.write(second, @source)
    File.write(@input, @source.sub("Проверка голоса.", "Название Crаtaegus"))
    reports = File.join(@dir, "preflight reports")
    output, _error, status = Open3.capture3("/usr/bin/ruby", File.join(__dir__, "../srt_gui_job.rb"),
      "--preflight", "--reports-dir", reports, "strict", "--request-id", "11111111-1111-4111-8111-111111111111", @input, second)
    report = JSON.parse(output)
    assert_equal 1, report.fetch("protocol_version")
    assert_equal "preflight", report.fetch("type")
    assert_equal "11111111-1111-4111-8111-111111111111", report.fetch("request_id")
    assert_equal 2, report.fetch("files").length
    issue = report.fetch("files").first.fetch("issues").first
    assert_equal "1", issue.fetch("cue")
    assert_equal "00:00:00,000–00:00:04,000", issue.fetch("timestamps")
    assert_equal "error", issue.fetch("severity")
    assert_equal "U+0430", issue.fetch("codepoint")
    assert_includes issue.fetch("explanation"), "Crаtaegus"
    refute status.success?
    assert_equal "ok", report.fetch("files").last.fetch("status")
    assert_match(/\A[0-9a-f]{64}\z/, report.fetch("files").last.fetch("preparation_fingerprint"))
  end

  def test_59_file_queue_reports_all_three_bad_files_without_losing_ready_inputs
    good_inputs = 56.times.map do |index|
      path = File.join(@dir, format("good-%02d.ru.srt", index + 1))
      File.write(path, @source)
      path
    end
    malformed = File.join(@dir, "bad-timestamps.ru.srt")
    mixed = File.join(@dir, "bad-symbol.ru.srt")
    ambiguous = File.join(@dir, "bad-number.ru.srt")
    File.write(malformed, @source.sub("00:00:04,000", "00:00:XX,000"))
    File.write(mixed, @source.sub("Проверка голоса.", "Доза × два."))
    File.write(ambiguous, @source.sub("Проверка голоса.", "Принимать 1/2/3."))
    reports = File.join(@dir, "reports-59")

    stdout, stderr, status = Open3.capture3("/usr/bin/ruby", File.join(__dir__, "../srt_gui_job.rb"),
      "--preflight", "--reports-dir", reports, "strict", *(good_inputs + [malformed, mixed, ambiguous]))
    report = JSON.parse(stdout)
    results = report.fetch("files")

    assert_equal 59, results.length, stderr
    assert_equal 56, results.count { |item| item.fetch("status") == "ok" }, results.reject { |item| item.fetch("status") == "ok" }.inspect
    invalid = results.select { |item| item.fetch("status") == "error" }
    assert_equal [malformed, mixed, ambiguous].sort, invalid.map { |item| item.fetch("file") }.sort
    assert invalid.all? { |item| item.fetch("issues").any? }
    assert_equal 3, Dir.glob(File.join(reports, "voiceover-*.report.txt")).length
    refute status.success?
  end

  def test_preflight_keeps_good_file_runnable_and_persists_bad_file_report
    second = File.join(@dir, "02 Synthetic.ru.srt")
    File.write(second, @source)
    File.write(@input, @source.sub("Проверка голоса.", "Название Crаtaegus"))
    reports = File.join(@dir, "private reports")
    output, = Open3.capture3("/usr/bin/ruby", File.join(__dir__, "../srt_gui_job.rb"),
      "--preflight", "--reports-dir", reports, "strict", @input, second)
    files = JSON.parse(output).fetch("files")
    assert_equal %w[error ok], files.map { |file| file.fetch("status") }
    assert File.file?(files.first.fetch("report"))
    assert_includes File.read(files.first.fetch("report")), "Статус: failed"
    runnable = VoiceoverJob.new(input: second, output: File.join(@dir, "good.wav"), voice: "silero",
      rhythm: "strict", reports_dir: reports, engine: File.join(__dir__, "fake_engine.rb")) { |event| @events << event }
    assert_equal 0, runnable.run
    assert File.file?(File.join(@dir, "good.wav"))
  end

  def test_job_rejects_input_changed_after_preflight
    expected = Digest::SHA256.hexdigest(@source)
    File.write(@input, @source + "\n")
    current = VoiceoverJob.new(input: @input, output: @output, voice: "silero", rhythm: "strict",
      expected_sha256: expected, reports_dir: File.join(@dir, "reports"),
      engine: File.join(__dir__, "fake_engine.rb")) { |event| @events << event }
    assert_equal 1, current.run
    assert_includes @events.last[:text], "изменился после предварительной проверки"
    refute File.exist?(@output)
  end

  def test_engine_rejects_a_changed_preparation_fingerprint_before_loading_silero
    output = File.join(@dir, "changed.wav")
    _stdout, stderr, status = Open3.capture3("/usr/bin/ruby", File.join(__dir__, "../srt_voiceover.rb"),
      "--rhythm", "strict", "--output", output, "--expected-preparation-fingerprint", "0" * 64, @input)
    refute status.success?
    assert_includes stderr, "Текст или настройки подготовки изменились после проверки"
    refute File.exist?(output)
  end

  def test_rejects_invalid_inputs
    ["", "bad", @source.sub("00:00:04,000", "00:60:04,000"),
     @source.sub("00:00:04,000", "00:00:00,000"),
     @source + "\n" + @source,
     @source.sub("00:00:00,000", "00:00:02,000") + "\n" + @source.sub(/^1$/, "2")].each do |source|
      File.write(@input, source)
      assert_raises(VoiceoverError) { parse_srt(@input) }
    end
  end

  def test_success_and_fragmented_progress
    staging_before = staging_entries
    assert_equal 0, job.run
    assert_equal @source, File.read(@input)
    assert_equal "RIFF", File.binread(@output, 4)
    assert File.file?(@events.last[:report])
    assert_equal File.join(@dir, "reports"), File.dirname(@events.last[:report])
    refute File.exist?(@output.sub(/\.wav\z/, ".report.txt"))
    assert_equal [50, 100], @events.select { |e| e[:type] == "progress" }.map { |e| e[:percent] }
    assert_equal "done", @events.last[:type]
    assert @events.all? { |event| event[:code] && event[:protocol_version] == 1 && event[:job_id] }
    assert_equal staging_before, staging_entries
  end

  def test_string_event_types_map_to_stable_protocol_codes
    current = job
    assert_equal "audio_ready", current.event_code("done")
    assert_equal "progress_update", current.event_code("progress")
    assert_equal "voiceover_failed", current.event_code("error")
  end

  def test_gui_correlation_id_is_preserved_and_validated
    correlation_id = SecureRandom.uuid
    current = VoiceoverJob.new(input: @input, output: @output, job_id: correlation_id)
    assert_equal correlation_id, current.instance_variable_get(:@job_id)
    assert_raises(ArgumentError) do
      VoiceoverJob.new(input: @input, output: @output, job_id: "not-a-uuid")
    end
  end

  def test_explicit_ffmpeg_selection_is_shared_and_never_silently_replaced
    previous = ENV["SRT_VOICEOVER_FFMPEG"]
    selected = File.join(@dir, "chosen-ffmpeg")
    File.write(selected, "test placeholder")
    File.chmod(0o755, selected)
    ENV["SRT_VOICEOVER_FFMPEG"] = selected
    assert_equal selected, find_ffmpeg
    ENV["SRT_VOICEOVER_FFMPEG"] = File.join(@dir, "missing-ffmpeg")
    assert_nil find_ffmpeg
  ensure
    previous ? ENV["SRT_VOICEOVER_FFMPEG"] = previous : ENV.delete("SRT_VOICEOVER_FFMPEG")
  end

  def test_byte_by_byte_utf8_events
    current = job
    line = JSON.generate(protocol_version: 1, type: "progress", stage: "speech",
      current: 1, total: 4, percent: 25) + "\n"
    line.bytes.each { |b| current.consume(b.chr) }
    "Русский текст\n".bytes.each { |b| current.consume(b.chr) }
    assert_equal "progress", @events.first[:type]
    assert_equal 25, @events.first[:percent]
    assert_equal "Русский текст", @events.last[:diagnostic]
    assert @events.all? { |event| event[:protocol_version] == 1 && event[:job_id] }
  end

  def test_only_silero_engine_and_five_speakers_are_available
    assert_equal %w[xenia kseniya baya aidar eugene], SILERO_SPEAKERS
    assert_equal "kseniya", VoiceoverJob.new(input: @input, output: @output).instance_variable_get(:@speaker)
  end

  def test_legacy_engine_is_rejected_without_fallback_or_output
    %w[siri Milena system].each do |legacy_engine|
      _out, err = capture_io do
        assert_equal 1, run_voiceover(["--voice", legacy_engine, "--output", @output, @input])
      end
      assert_includes err, "Недоступный движок"
      refute File.exist?(@output)
    end
  end

  def test_existing_output_and_report_are_never_overwritten
    File.write(@output, "KEEP AUDIO")
    report = @output.sub(/\.wav\z/, ".report.txt")
    File.write(report, "KEEP REPORT")
    assert_equal 0, job.run
    assert_equal "KEEP AUDIO", File.read(@output)
    assert_equal "KEEP REPORT", File.read(report)
    assert_equal @output.sub(/\.wav\z/, " (2).wav"), @events.last[:output]
    assert_equal 0, job.run
    assert_equal @output.sub(/\.wav\z/, " (3).wav"), @events.last[:output]
  end

  def test_replacement_asks_again_if_target_changes_during_confirmation
    File.write(@output, "ORIGINAL AUDIO")
    staged = File.join(@dir, "ready.wav")
    File.write(staged, "NEW VERIFIED AUDIO")
    decisions = 0
    destination = VoiceoverDestination.new(@output, input: @input, policy: "ask",
      cancelled: proc { false }) do |path, can_replace|
      decisions += 1
      assert can_replace
      File.write(path, "UPDATED WHILE DIALOG WAS OPEN") if decisions == 1
      "replace"
    end

    assert_equal @output, destination.publish(staged)
    assert_equal 2, decisions, "A changed target requires a fresh replacement decision"
    assert_equal "NEW VERIFIED AUDIO", File.read(@output)
    refute File.exist?(staged)
  end

  def test_insufficient_disk_space_fails_before_synthesis_and_preserves_output
    staging_before = staging_entries
    File.write(@output, "KEEP OLD AUDIO")
    fake_status = Struct.new(:success?).new(true)
    current = job
    Open3.stub(:capture3,
      ["Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/disk 100 99 1 99% /tmp\n", "", fake_status]) do
      assert_equal 1, current.run
    end

    assert_equal "error", @events.last[:type]
    assert_includes @events.last[:text], "Недостаточно места"
    assert_equal "KEEP OLD AUDIO", File.read(@output)
    assert_equal [File.basename(@input), File.basename(@output), "reports"].sort, Dir.children(@dir).sort
    report = Dir.glob(File.join(@dir, "reports", "*.report.txt")).fetch(0)
    assert_includes File.read(report), "Статус: failed"
    assert_equal staging_before, staging_entries
  end

  def test_permission_denied_while_publishing_new_output_writes_failure_report_and_cleans_staging
    staging_before = staging_entries
    original_link = File.method(:link)
    denied = proc do |source, target|
      raise Errno::EACCES, "simulated output permission denial" if target == @output
      original_link.call(source, target)
    end

    File.stub(:link, denied) { assert_equal 1, job.run }

    refute File.exist?(@output)
    assert_equal "error", @events.last[:type]
    assert_includes @events.last[:diagnostic], "permission"
    reports = Dir.glob(File.join(@dir, "reports", "*.report.txt"))
    assert_equal 1, reports.length
    assert_includes File.read(reports.first), "Статус: failed"
    assert_equal staging_before, staging_entries
  end

  def test_permission_denied_while_replacing_preserves_old_audio_and_cleans_staging
    staging_before = staging_entries
    File.write(@output, "KEEP OLD AUDIO")
    current = VoiceoverJob.new(input: @input, output: @output, voice: "silero", rhythm: "strict",
      reports_dir: File.join(@dir, "reports"), engine: File.join(__dir__, "fake_engine.rb"),
      conflict: "replace", decision: proc { |_path, _can_replace| "replace" }) { |event| @events << event }
    original_rename = File.method(:rename)
    denied = proc do |source, target|
      raise Errno::EACCES, "simulated replacement permission denial" if target == @output
      original_rename.call(source, target)
    end

    File.stub(:rename, denied) { assert_equal 1, current.run }

    assert_equal "KEEP OLD AUDIO", File.read(@output)
    assert_equal "error", @events.last[:type]
    assert_includes @events.last[:diagnostic], "permission"
    reports = Dir.glob(File.join(@dir, "reports", "*.report.txt"))
    assert_equal 1, reports.length
    assert_includes File.read(reports.first), "Статус: failed"
    assert_equal staging_before, staging_entries
  end

  def test_late_real_destination_permission_loss_keeps_original_error_and_cleans_staging
    output_directory = File.join(@dir, "destination")
    FileUtils.mkdir_p(output_directory)
    output = File.join(output_directory, "lecture.ru.wav")
    previous = ENV["SRT_TEST_FAKE_ENGINE_READ_ONLY_DIRECTORY"]
    staging_before = staging_entries(output)
    ENV["SRT_TEST_FAKE_ENGINE_READ_ONLY_DIRECTORY"] = output_directory
    current = VoiceoverJob.new(input: @input, output: output, voice: "silero", rhythm: "strict",
      reports_dir: File.join(@dir, "reports"), engine: File.join(__dir__, "fake_engine.rb")) do |event|
      @events << event
    end

    assert_equal 1, current.run
    assert_equal "error", @events.last[:type]
    assert_match(/Permission denied/i, @events.last[:diagnostic])
    refute File.exist?(output)
    reports = Dir.glob(File.join(@dir, "reports", "*.report.txt"))
    assert_equal 1, reports.length
    assert_match(/Permission denied/i, File.read(reports.first))
    assert_equal staging_before, staging_entries(output)
  ensure
    File.chmod(0o755, output_directory) if output_directory && File.directory?(output_directory)
    ENV["SRT_TEST_FAKE_ENGINE_READ_ONLY_DIRECTORY"] = previous
  end

  def test_output_appearing_at_publish_is_preserved_and_job_copies
    staged = File.join(@dir, "ready.wav")
    File.write(staged, "NEW VERIFIED AUDIO")
    decisions = 0
    destination = VoiceoverDestination.new(@output, input: @input, policy: "ask",
      cancelled: proc { false }) do |_path, _can_replace|
      decisions += 1
      "copy"
    end
    original_link = File.method(:link)
    injected = false

    File.stub(:link, proc { |source, target|
      if target == @output && !injected
        injected = true
        File.write(target, "ANOTHER PROCESS CREATED THIS")
        raise Errno::EEXIST
      end
      original_link.call(source, target)
    }) do
      assert_equal @output.sub(/\.wav\z/, " (2).wav"), destination.publish(staged)
    end

    assert injected
    assert_equal 1, decisions
    assert_equal "ANOTHER PROCESS CREATED THIS", File.read(@output)
    assert_equal "NEW VERIFIED AUDIO", File.read(@output.sub(/\.wav\z/, " (2).wav"))
  end

  def test_report_only_collision_is_preserved
    report = @output.sub(/\.wav\z/, ".report.txt")
    File.write(report, "KEEP REPORT")
    assert_equal 0, job.run
    assert_equal "KEEP REPORT", File.read(report)
    assert_equal @output, @events.last[:output]
  end

  def test_failed_job_leaves_no_output
    File.write(@input, @source.sub("Проверка голоса.", "FAIL"))
    assert_equal 1, job.run
    assert_equal "error", @events.last[:type]
    assert_includes @events.last[:text], "Ошибка тестового голоса"
    report = Dir.glob(File.join(@dir, "reports", "*.report.txt")).first
    assert report
    assert_includes File.read(report), "Статус: failed"
    assert_equal [File.basename(@input)], Dir.children(@dir) - ["reports"]
  end

  def test_crashed_engine_preserves_existing_replacement_and_cleans_staging
    staging_before = staging_entries
    File.write(@output, "KEEP OLD AUDIO")
    previous = ENV["SRT_TEST_FAKE_ENGINE_CRASH"]
    ENV["SRT_TEST_FAKE_ENGINE_CRASH"] = "1"
    current = VoiceoverJob.new(input: @input, output: @output, voice: "silero", rhythm: "strict",
      reports_dir: File.join(@dir, "reports"), engine: File.join(__dir__, "fake_engine.rb"),
      conflict: "replace") { |event| @events << event }

    assert_equal 1, current.run
    assert_equal "KEEP OLD AUDIO", File.read(@output)
    assert_equal "error", @events.last[:type]
    report = Dir.glob(File.join(@dir, "reports", "*.report.txt")).first
    assert report
    assert_includes File.read(report), "Статус: failed"
    assert_equal staging_before, staging_entries
  ensure
    ENV["SRT_TEST_FAKE_ENGINE_CRASH"] = previous
  end

  def test_idle_timeout_kills_unresponsive_engine_and_preserves_replacement
    staging_before = staging_entries
    File.write(@output, "KEEP OLD AUDIO")
    File.write(@input, @source.sub("Проверка голоса.", "QUIET"))
    current = VoiceoverJob.new(input: @input, output: @output, voice: "silero", rhythm: "strict",
      reports_dir: File.join(@dir, "reports"), engine: File.join(__dir__, "fake_engine.rb"),
      conflict: "replace", idle_timeout: 0.25) { |event| @events << event }

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_equal 1, current.run
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_operator elapsed, :<, 4
    assert_equal "KEEP OLD AUDIO", File.read(@output)
    assert_equal "error", @events.last[:type]
    assert_match(/не отвечает более 1 с/, @events.last[:text])
    report = Dir.glob(File.join(@dir, "reports", "*.report.txt")).first
    assert report
    assert_match(/Статус: failed/, File.read(report))
    assert_equal staging_before, staging_entries
  end

  def test_cancel_stops_child_group_and_discards_partial_output
    File.write(@input, @source.sub("Проверка голоса.", "CANCEL"))
    current = job
    worker = Thread.new { current.run }
    Timeout.timeout(8) do
      sleep 0.02 until @events.any? { |e| e[:diagnostic].to_s.start_with?("CHILD ") }
      current.cancel
      assert_equal 130, worker.value
    end
    assert_equal "cancelled", @events.last[:type]
    report = Dir.glob(File.join(@dir, "reports", "*.report.txt")).first
    assert report
    assert_includes File.read(report), "Статус: cancelled"
    assert_equal [File.basename(@input)], Dir.children(@dir) - ["reports"]
    child = @events.find { |e| e[:diagnostic].to_s.start_with?("CHILD ") }[:diagnostic].split.last
    assert wait_until_process_exits(child.to_i),
           "Descendant still exists after cancellation: #{child}"
  ensure
    current&.cancel
    worker&.join(5)
  end

  def test_engine_lock_rejects_second_run_before_synthesis
    Dir.stub(:tmpdir, @dir) do
      File.open(File.join(@dir, "srt-voiceover-#{Process.uid}.lock"), "w") do |lock|
        assert lock.flock(File::LOCK_EX | File::LOCK_NB)
        _out, err = capture_io do
          assert_equal 1, run_voiceover(["--voice", "silero", "--output", @output, @input])
        end
        assert_includes err, "Уже идёт другая озвучка"
        refute File.exist?(@output)
      end
    end
  end

  def test_voice_test_sample_is_normalized
    output, error, status = Open3.capture3("/usr/bin/ruby", File.join(__dir__, "../srt_gui_job.rb"),
      "--voice-test-sample", "smooth", "baya")
    assert status.success?, error
    result = JSON.parse(output)
    assert_equal "voice_test_sample", result.fetch("type")
    text = result.fetch("text")
    refute_match(/[\p{N}\p{Latin}]/, text)
    assert_includes text, "двенадцать целых пять десятых процента"
    assert_includes text, "Кратэгус"
    assert_includes result.fetch("source_text"), "Crataegus"
    assert_match(/Crataegus → Кратэгус/, result.fetch("warnings").join)
    assert_match(/\A[0-9a-f]{64}\z/, result.fetch("preparation_fingerprint"))

    sample_file = File.join(@dir, "voice-test.ru.srt")
    File.write(sample_file, result.fetch("source_srt"))
    prepared = prepare_speech_file(sample_file, rhythm: "smooth", speaker: "baya")
    assert_equal result.fetch("preparation_fingerprint"), prepared.fetch(:fingerprint)
    assert_equal text, prepared.fetch(:results).map(&:text).join("\n\n")
  end
end
