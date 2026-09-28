require "minitest/autorun"
require "timeout"
require_relative "../srt_gui_job"

class Release12Test < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("srt-v12-")
    @input = File.join(@dir, "01.ru.srt")
    @output = File.join(@dir, "01.ru.silero.voice.wav")
    @reports = File.join(@dir, "reports")
    File.write(@input, "1\n00:00:00,000 --> 00:00:04,000\nПроверка.\n")
    @events = []
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def job(**options, &callback)
    VoiceoverJob.new(input: @input, output: @output, voice: "silero", rhythm: "strict", reports_dir: @reports,
      engine: File.join(__dir__, "fake_engine.rb"), **options) do |event|
        @events << event
        callback.call(event) if callback
      end
  end

  def test_ask_skip_does_not_start_engine
    File.write(@output, "OLD")
    asked = []
    assert_equal 0, job(conflict: "ask", decision: proc { |*args| asked << args; "skip" }).run
    assert_equal [[@output, true]], asked
    assert_equal "OLD", File.read(@output)
    assert_equal "skipped", @events.last[:type]
    assert_empty @events.select { |event| %w[progress status].include?(event[:type]) }
    report = Dir.glob(File.join(@reports, "*.report.txt")).first
    assert report
    assert_includes File.read(report), "Статус: skipped"
  end

  def test_explicit_replace_preserves_old_inode_until_new_audio_is_complete
    File.write(@output, "OLD")
    File.link(@output, File.join(@dir, "old-backup.wav"))
    current = job(conflict: "ask", decision: proc { "replace" }) do |event|
      assert_equal "OLD", File.read(@output) if event[:type] == "progress"
    end
    assert_equal 0, current.run
    assert_equal "RIFF", File.binread(@output, 4)
    assert_equal "OLD", File.read(File.join(@dir, "old-backup.wav"))
    assert_equal @output, @events.last[:output]
  end

  def test_cancel_and_failure_leave_approved_replacement_untouched
    File.write(@output, "OLD")
    current = job(conflict: "replace") { |event| current.cancel if event[:type] == "progress" }
    assert_equal 130, current.run, @events.inspect
    assert_equal "OLD", File.read(@output)
    File.write(@input, File.read(@input).sub("Проверка.", "FAIL"))
    assert_equal 1, job(conflict: "replace").run
    assert_equal "OLD", File.read(@output)
    outcomes = Dir.glob(File.join(@reports, "*.report.txt")).map { |path| File.read(path) }
    assert_equal 2, outcomes.length
    assert outcomes.any? { |report| report.include?("Статус: cancelled") }
    assert outcomes.any? { |report| report.include?("Статус: failed") }
  end

  def test_changed_target_is_asked_again_and_can_be_skipped
    File.write(@output, "OLD")
    answers = %w[replace skip]
    current = job(conflict: "ask", decision: proc { answers.shift }) do |event|
      File.write(@output, "CHANGED ELSEWHERE") if event[:type] == "progress"
    end
    assert_equal 0, current.run
    assert_equal "CHANGED ELSEWHERE", File.read(@output)
    assert_equal "skipped", @events.last[:type]
    assert_empty answers
  end

  def test_changed_target_without_interactive_confirmation_fails_safely
    File.write(@output, "OLD")
    current = job(conflict: "replace") do |event|
      File.write(@output, "CHANGED") if event[:type] == "progress"
    end
    assert_equal 1, current.run
    assert_equal "CHANGED", File.read(@output)
  end

  def test_file_appearing_during_synthesis_prompts_at_publication
    asked = 0
    current = job(conflict: "ask", decision: proc { asked += 1; "copy" }) do |event|
      File.write(@output, "OTHER JOB") if event[:type] == "progress"
    end
    assert_equal 0, current.run
    assert_equal 1, asked
    assert_equal "OTHER JOB", File.read(@output)
    assert_equal @output.sub(/\.wav\z/, " (2).wav"), @events.last[:output]
  end

  def test_symlinks_and_directories_can_only_copy_or_skip
    File.symlink(File.join(@dir, "does-not-exist"), @output)
    assert_equal 1, job(conflict: "replace").run
    assert File.symlink?(@output)
    assert_equal 0, job(conflict: "ask", decision: proc { |_path, allowed| refute allowed; "copy" }).run
    assert File.symlink?(@output)
    File.unlink(@output)
    Dir.mkdir(@output)
    assert_equal 1, job(conflict: "replace").run
    assert File.directory?(@output)
  end

  def test_no_overwrite_if_destination_is_source_via_hardlink
    File.link(@input, @output)
    assert_equal 1, job(conflict: "replace").run
    assert_includes @events.last[:text], "совпадает с исходным"
    assert_includes File.read(@input), "Проверка."
  end

  def test_report_cleanup_only_own_completed_regular_files_older_than_72_hours
    store = VoiceoverReports.new(@reports)
    source = File.join(@dir, "report-source")
    File.write(source, "details")
    old = store.publish(source, input: @input, output: @output)
    fresh = store.publish(source, input: @input, output: @output)
    foreign = File.join(@reports, "foreign.txt")
    fake = File.join(@reports, "voiceover-20000101T000000Z-#{SecureRandom.uuid}.report.txt")
    File.write(foreign, "keep")
    File.write(fake, "not ours")
    link = File.join(@reports, "voiceover-20000101T000000Z-#{SecureRandom.uuid}.report.txt")
    File.symlink(source, link)
    folder = File.join(@reports, "voiceover-20000101T000000Z-#{SecureRandom.uuid}.report.txt")
    Dir.mkdir(folder)
    past = Time.now - 73 * 60 * 60
    [old, foreign, fake, folder].each { |path| File.utime(past, past, path) }
    assert_equal 1, store.cleanup
    refute File.exist?(old)
    [fresh, foreign, fake, folder, source].each { |path| assert File.exist?(path) }
    assert File.symlink?(link)
    assert_equal 0, store.cleanup
  end

  def test_report_root_symlink_is_rejected
    File.symlink(@dir, @reports)
    assert_raises(VoiceoverError) { VoiceoverReports.new(@reports).cleanup }
    assert File.exist?(@input)
  end

  def test_disk_space_failure_happens_before_speech
    result = ["Filesystem 1024-blocks Used Available Capacity Mounted\n/dev/test 99 99 0 100% /\n", "", Struct.new(:success?).new(true)]
    Open3.stub(:capture3, result) { assert_equal 1, job.run }
    assert_includes @events.last[:text], "Недостаточно места"
    refute File.exist?(@output)
  end

  def test_missing_output_directory_is_not_silently_created
    @output = File.join(@dir, "missing", "audio.wav")
    assert_equal 1, job.run
    assert_includes @events.last[:text], "недоступна"
    refute File.exist?(File.dirname(@output))
  end

  def test_eta_uses_measured_phrases_not_startup_time
    current = job
    current.instance_variable_set(:@first_progress, [Process.clock_gettime(Process::CLOCK_MONOTONIC) - 10, 1])
    current.consume(JSON.generate(protocol_version: 1, type: "progress", stage: "speech",
      current: 3, total: 6, percent: 50) + "\n")
    assert_in_delta 15, @events.last[:eta_seconds], 1
  end

  def test_low_level_engine_refuses_existing_audio_before_silero
    File.write(@output, "OLD")
    _out, err = capture_io { assert_equal 1, run_voiceover(["--output", @output, @input]) }
    assert_includes err, "уже существует"
    assert_equal "OLD", File.read(@output)
  end

  def test_waiting_for_gui_answer_is_cancellable
    File.write(@output, "OLD")
    reader, writer = IO.pipe
    original_stdin = $stdin
    $stdin = reader
    current = job(conflict: "ask")
    worker = Thread.new { current.run }
    Timeout.timeout(4) do
      sleep 0.02 until @events.any? { |event| event[:type] == "conflict" }
      current.cancel
      assert_equal 130, worker.value
    end
    assert_equal "OLD", File.read(@output)
  ensure
    current&.cancel
    worker&.join(2)
    $stdin = original_stdin
    reader&.close
    writer&.close
  end

  def test_json_decision_protocol_and_eof_are_safe
    File.write(@output, "OLD")
    original_stdin = $stdin
    reader, writer = IO.pipe
    $stdin = reader
    current = job(conflict: "ask") do |event|
      if event[:type] == "conflict"
        writer.puts JSON.generate(request_id: "wrong", action: "replace")
        writer.puts JSON.generate(request_id: event[:request_id], action: "skip")
      end
    end
    assert_equal 0, current.run
    assert_equal "skipped", @events.last[:type]
    writer.close
    assert_equal 1, job(conflict: "ask").run
    assert_equal "OLD", File.read(@output)
  ensure
    $stdin = original_stdin
    reader&.close
    writer.close unless writer.closed?
  end
end
