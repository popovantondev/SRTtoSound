require "minitest/autorun"
require "digest"
require_relative "../srt_gui_job"

class AacExportTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("srt-aac-unit-")
    @input = File.join(@dir, "01 Тест ' и пробелы.ru.srt")
    @source = "1\n00:00:00,000 --> 00:00:04,000\nSIGNAL\n"
    File.write(@input, @source)
    @ffmpeg = find_ffmpeg
    @events = []
    skip "FFmpeg required for AAC integration checks" unless @ffmpeg
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir
  end

  def job(**options, &callback)
    VoiceoverJob.new(input: @input, voice: "silero", speaker: "kseniya", rhythm: "strict", ffmpeg: @ffmpeg,
      reports_dir: File.join(@dir, "reports"),
      engine: File.join(__dir__, "fake_engine.rb"), **options) do |event|
        @events << event
        callback.call(event) if callback
      end
  end

  def successful(current = job)
    assert_equal 0, current.run, @events.inspect
    assert_equal "done", @events.last[:type]
    @events.last[:output]
  end

  def media_command(*args)
    stdout, stderr, status = Open3.capture3(@ffmpeg, "-hide_banner", "-loglevel", "error", *args)
    assert status.success?, stderr
    stdout
  end

  def decoded(path)
    media_command("-i", path, "-map", "0:a:0", "-ar", "24000", "-ac", "1", "-f", "s16le", "-").unpack("s<*")
  end

  def staging_glob
    File.join(staging_parent_for_output(default_audio_output_path(@input, "m4a")), ".srt-voiceover-*")
  end

  def test_default_is_aac_lc_in_m4a_with_unshifted_timeline_and_copy_to_mp4
    output = successful
    assert_equal @input.sub(/\.srt\z/, ".m4a"), output
    assert_equal @source, File.read(@input)
    assert_empty Dir.glob(File.join(@dir, "*.wav"))
    assert_empty Dir.glob(staging_glob)
    assert_includes File.read(@events.last[:report]), "AAC-LC"
    # Inspect the actual codec, not just the filename extension.
    _out, description, = Open3.capture3(@ffmpeg, "-hide_banner", "-i", output)
    assert_match(/Audio: aac \(LC\).*48000 Hz, stereo/, description)
    assert_equal "ftyp", File.binread(output, 8)[4, 4]
    samples = decoded(output)
    # AudioToolbox AAC may expose about 31 ms of encoder priming; the runtime
    # verification limit is 100 ms and the first audible sample remains exact.
    assert_in_delta 4.0, samples.length.to_f / SAMPLE_RATE, 0.05
    [0.5, 2.0, 3.5].each do |start|
      first = samples.each_index.find { |index| index >= ((start - 0.1) * SAMPLE_RATE).to_i && samples[index].abs > 1000 }
      assert first, "Missing tone at #{start}"
      assert_in_delta start, first.to_f / SAMPLE_RATE, 0.005
    end
    assert samples.take((0.45 * SAMPLE_RATE).to_i).all? { |value| value.abs < 200 }
    assert samples.last((0.25 * SAMPLE_RATE).to_i).all? { |value| value.abs < 200 }
    # Repackage as MP4 with stream copy and compare compressed AAC packets.
    mp4 = File.join(@dir, "copy.mp4")
    media_command("-n", "-i", output, "-map", "0:a:0", "-c:a", "copy", mp4)
    hashes = [output, mp4].map do |file|
      Digest::SHA256.hexdigest(media_command("-i", file, "-map", "0:a:0", "-c:a", "copy", "-f", "adts", "-"))
    end
    assert_equal hashes[0], hashes[1], "AAC packets changed during MP4 copy"
    assert_equal samples, decoded(mp4), "Timeline changed during stream copy"
    percents = @events.select { |e| e[:type] == "progress" }.map { |e| e[:percent] }
    assert_equal percents.sort, percents
    assert percents.all? { |value| value < 100 }, "100% must wait for publication"
  end

  def test_explicit_wav_still_works_without_ffmpeg
    output = successful(job(format: "wav", ffmpeg: "/missing/ffmpeg"))
    assert_equal ".wav", File.extname(output)
    assert_equal "RIFF", File.binread(output, 4)
    assert_empty @events.select { |event| %w[encode verify].include?(event[:stage]) }
  end

  def test_aac_existing_files_and_reports_are_preserved
    output = successful
    report = @events.last[:report]
    digest = Digest::SHA256.file(output).hexdigest
    report_text = File.read(report)
    second = successful
    assert_equal output.sub(/\.m4a\z/, " (2).m4a"), second
    assert_equal digest, Digest::SHA256.file(output).hexdigest
    assert_equal report_text, File.read(report)
  end

  def test_wav_report_collision_does_not_overwrite_either_format
    old_wav = @input.sub(/\.srt\z/, ".legacy.voice.wav")
    old_report = old_wav.sub(/\.wav\z/, ".report.txt")
    File.write(old_wav, "OLD WAV")
    File.write(old_report, "OLD REPORT")
    output = successful
    assert_equal @input.sub(/\.srt\z/, ".m4a"), output
    assert_equal "OLD WAV", File.read(old_wav)
    assert_equal "OLD REPORT", File.read(old_report)
  end

  def test_missing_encoder_fails_before_synthesis
    assert_equal 1, job(ffmpeg: "/not/installed").run
    assert_includes @events.last[:text], "не найден FFmpeg"
    assert_equal [File.basename(@input)], Dir.children(@dir) - ["reports"]
  end

  def test_extension_mismatch_is_rejected
    assert_equal 1, job(format: "m4a", output: File.join(@dir, "wrong.wav")).run
    assert_includes @events.last[:text], "не совпадает"
  end

  def test_failed_encoder_does_not_publish_wav_or_m4a
    assert_equal 1, job(ffmpeg: "/usr/bin/false").run
    assert_equal "error", @events.last[:type]
    assert_equal [File.basename(@input)], Dir.children(@dir) - ["reports"]
  end

  def test_failed_encoder_preserves_approved_replacement
    output = @input.sub(/\.srt\z/, ".m4a")
    File.write(output, "KEEP OLD AUDIO")
    assert_equal 1, job(ffmpeg: "/usr/bin/false", output: output, conflict: "replace").run
    assert_equal "error", @events.last[:type]
    assert_equal "KEEP OLD AUDIO", File.read(output)
    assert_empty Dir.glob(staging_glob)
    report = Dir.glob(File.join(@dir, "reports", "*.report.txt")).fetch(0)
    assert_includes File.read(report), "Статус: failed"
  end

  def test_cancel_at_encoding_or_verification_discards_staging
    ["Сохраняю AAC", "Проверяю AAC"].each do |phase|
      current = job do |event|
        current.cancel if event[:type] == "status" && event[:text].start_with?(phase)
      end
      assert_equal 130, current.run
      assert_equal "cancelled", @events.last[:type]
      assert_equal [File.basename(@input)], Dir.children(@dir) - ["reports"]
    end
  end

  def test_corrupted_encoded_output_is_rejected
    current = job do |event|
      if event[:type] == "status" && event[:text].start_with?("Проверяю AAC")
        File.binwrite(Dir.glob(File.join(staging_glob, "audio.m4a")).fetch(0), "CORRUPT")
      end
    end
    assert_equal 1, current.run
    assert_includes @events.last[:text], "не прошёл проверку"
    assert_equal [File.basename(@input)], Dir.children(@dir) - ["reports"]
  end

  def test_duration_change_is_rejected
    current = job do |event|
      if event[:type] == "status" && event[:text].start_with?("Проверяю AAC")
        current.instance_variable_set(:@expected_duration, 15.0)
      end
    end
    assert_equal 1, current.run
    assert_includes @events.last[:text], "Длительность AAC не совпадает"
    assert_equal [File.basename(@input)], Dir.children(@dir) - ["reports"]
  end
end
