#!/usr/bin/ruby
# Exercises the real run-ready decision path over a mixed 59-file GUI queue.
# Synthesis uses the deterministic test worker, never the Silero model.
require "tmpdir"
require "fileutils"
require "open3"
require "timeout"
require "digest"

binary = ENV["SRT_TO_SOUND_APP_BINARY"]
raise "Set SRT_TO_SOUND_APP_BINARY to the exact built app executable" unless binary && File.executable?(binary)
engine = File.expand_path("fake_engine.rb", __dir__)

root = Dir.mktmpdir("srttosound-59-gui-run-ready-")
begin
  lectures = File.join(root, "lectures")
  support = File.join(root, "support-without-model")
  reports = File.join(root, "reports")
  FileUtils.mkdir_p([lectures, support])
  56.times do |index|
    File.write(File.join(lectures, format("good-%02d.ru.srt", index + 1)),
      "1\n00:00:00,000 --> 00:00:04,000\nРомашка и календула.\n")
  end
  File.write(File.join(lectures, "bad-timestamps.ru.srt"),
    "1\n00:00:XX,000 --> 00:00:04,000\nПроверка.\n")
  File.write(File.join(lectures, "bad-symbol.ru.srt"),
    "1\n00:00:00,000 --> 00:00:04,000\nДоза × два.\n")
  File.write(File.join(lectures, "bad-number.ru.srt"),
    "1\n00:00:00,000 --> 00:00:04,000\nПринимать 1/2/3.\n")
  choice = File.join(root, "choice.png")
  result = File.join(root, "result.png")
  args = [binary, "--data-dir", support, "--reports-dir", reports,
    "--integration-test", lectures, "--test-engine", engine,
    "--test-preflight-choice", "run-ready", "--preflight-choice-snapshot", choice,
    "--result-snapshot", result]

  output = ""
  code = nil
  Open3.popen2e(*args, pgroup: true) do |stdin, stream, wait|
    stdin.close
    begin
      Timeout.timeout(180) { output = stream.read; code = wait.value.exitstatus }
    ensure
      if wait.alive?
        Process.kill("TERM", -wait.pid) rescue nil
        sleep 0.3
        Process.kill("KILL", -wait.pid) rescue nil
      end
    end
  end
  raise "Expected 56 ready files to run: #{code}: #{output}" unless code == 0 && output.include?("GUI_QUEUE_TEST OK jobs=56")
  raise "The real decision sheet was not captured" unless File.file?(choice) && File.size(choice) > 10_000
  raise "No final queue state was captured" unless File.file?(result) && File.size(result) > 10_000
  audio = Dir.glob(File.join(lectures, "**/*.m4a"))
  raise "Expected exactly 56 ready outputs, found #{audio.length}" unless audio.length == 56
  reports_found = Dir.glob(File.join(reports, "voiceover-*.report.txt"))
  raise "Expected completion/failure reports for all 59 files" unless reports_found.length == 59
  bodies = reports_found.map { |path| File.read(path) }
  raise "Three preflight failures should remain visible" unless bodies.count { |body| body.include?("Статус: failed") } == 3
  raise "Test must not load Silero" if File.exist?(File.join(support, "models", "v5_5_ru.pt"))
  puts "GUI_PREFLIGHT_RUN_READY_OK · 59 inspected, 56 synthesized with fake worker, 3 retained as failed; Silero not loaded"
ensure
  if ENV["SRT_TO_SOUND_KEEP_GUI_QA"] == "1"
    warn "QA_DIRECTORY_RETAINED #{root}"
  else
    FileUtils.remove_entry(root) if File.exist?(root)
  end
end
