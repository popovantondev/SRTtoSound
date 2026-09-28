require "minitest/autorun"
require "timeout"
require "digest"
require_relative "../srt_gui_job"

class Release121Test < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("srt-v121-")
    @input = File.join(@dir, "input.ru.srt")
    @output = File.join(@dir, "output.wav")
    @events = []
    File.write(@input, "1\n00:00:00,000 --> 00:00:04,000\nПроверка.\n")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def job(**options)
    VoiceoverJob.new(input: @input, output: @output, voice: "silero", speaker: "kseniya", rhythm: "strict",
      reports_dir: File.join(@dir, "reports"), engine: File.join(__dir__, "fake_engine.rb"),
      **options) { |event| @events << event }
  end

  def test_overlap_rejected_before_synthesis_and_existing_audio_preserved
    File.write(@input, "1\n00:00:00,000 --> 00:00:05,000\nПервая?\n\n2\n00:00:01,000 --> 00:00:02,000\nВторая?\n")
    original = File.read(@input)
    File.write(@output, "KEEP")
    assert_equal 1, job(conflict: "replace").run
    assert_includes @events.last[:text], "Пересекаются"
    refute @events.any? { |event| event[:type] == "status" }
    assert_equal "KEEP", File.read(@output)
    assert_equal original, File.read(@input)
  end

  def test_tiny_windows_rejected_without_inventing_extra_time
    File.write(@input, "1\n00:00:00,000 --> 00:00:00,100\nПервая?\n\n2\n00:00:00,100 --> 00:00:00,200\nВторая?\n")
    assert_equal 1, job.run
    assert_includes @events.last[:text], "Слишком короткое окно"
    refute File.exist?(@output)
  end

  def test_adjacent_valid_cues_and_borrowed_silence_keep_real_boundaries
    cues = [Cue.new(1, 0, 1000, "Первая?"), Cue.new(2, 1000, 2000, "Вторая?"), Cue.new(3, 5000, 6000, "Третья?")]
    assert_equal [[1000, 1.0], [4955, 3.955], [6000, 1.0]], phrase_windows(group_cues(cues))
  end

  def test_backend_duration_must_match_srt_not_only_its_own_wav_header
    File.write(@input, File.read(@input).sub("Проверка.", "BAD_DURATION"))
    assert_equal 1, job.run
    assert_includes @events.last[:text], "Длительность WAV не совпадает"
    refute File.exist?(@output)
    refute @events.any? { |event| event[:type] == "done" }
  end

  def test_warnings_are_forwarded_and_counted_in_done_event
    File.write(@input, File.read(@input).sub("Проверка.", "WARNING"))
    assert_equal 0, job.run
    assert_equal 1, @events.count { |event| event[:type] == "warning" }
    assert_equal 1, @events.last[:warnings]
    assert_equal "done", @events.last[:type]
  end

  def test_silent_hung_engine_times_out_and_preserves_approved_old_audio
    staging_before = Dir.glob(File.join(File.dirname(@dir), ".srt-voiceover-*")).sort
    File.write(@input, File.read(@input).sub("Проверка.", "QUIET"))
    File.write(@output, "KEEP")
    Timeout.timeout(5) { assert_equal 1, job(idle_timeout: 0.3, conflict: "replace").run }
    assert_includes @events.last[:text], "не отвечает"
    assert_equal "KEEP", File.read(@output)
    assert_equal staging_before, Dir.glob(File.join(File.dirname(@dir), ".srt-voiceover-*")).sort
  end

  def tone(seconds = 1.0)
    Array.new((SAMPLE_RATE * seconds).to_i) { |i| (10000 * Math.sin(2 * Math::PI * 440 * i / SAMPLE_RATE)).round }
  end

  def assert_same_pitch(pcm, max_seconds)
    assert_operator pcm.length, :<=, (SAMPLE_RATE * max_seconds).floor
    seconds = pcm.length.to_f / SAMPLE_RATE
    crossings = pcm.each_cons(2).count { |a, b| a <= 0 && b > 0 }
    assert_in_delta 440, crossings / seconds, 12
  end

  def test_true_atempo_keeps_pitch_and_fits_exact_window
    ffmpeg = find_ffmpeg
    skip "FFmpeg required" unless ffmpeg
    samples = fit_tempo_without_pitch_shift(File.join(@dir, "tone.wav"), tone, 0.5, { ffmpeg: ffmpeg })
    assert_same_pitch(samples, 0.5)
  end

  def test_removed_voice_engine_is_rejected_before_worker_start
    stub(:fit_phrase, [tone(5), 180, false, 5.0]) do
      _out, err = capture_io { assert_equal 1, run_voiceover(["--voice", "Milena", "--rhythm", "strict", "--output", @output, @input]) }
      assert_includes err, "Недоступный движок"
    end
    refute File.exist?(@output)
    refute File.exist?(@output.sub(/\.wav$/, ".report.txt"))
  end
end
