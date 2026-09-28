#!/usr/bin/ruby
# Verifies that an all-invalid queue finishes preflight without showing a
# run-ready dialog or loading Silero.
require "tmpdir"
require "fileutils"
require "open3"
require "timeout"

binary = ENV["SRT_TO_SOUND_APP_BINARY"]
raise "Set SRT_TO_SOUND_APP_BINARY to the exact built app executable" unless binary && File.executable?(binary)

Dir.mktmpdir("srttosound-all-error-") do |root|
  lectures = File.join(root, "lectures")
  support = File.join(root, "support-without-model")
  reports = File.join(root, "reports")
  FileUtils.mkdir_p([lectures, support])
  {
    "bad-time.ru.srt" => "1\n00:00:XX,000 --> 00:00:04,000\nПроверка времени.\n",
    "bad-symbol.ru.srt" => "1\n00:00:00,000 --> 00:00:04,000\nДоза × два.\n",
    "bad-number.ru.srt" => "1\n00:00:00,000 --> 00:00:04,000\nПринимать 1/2/3.\n"
  }.each { |name, body| File.write(File.join(lectures, name), body) }
  choice = File.join(root, "choice.png")
  result = File.join(root, "result.png")
  args = [binary, "--data-dir", support, "--reports-dir", reports,
    "--integration-test", lectures, "--test-preflight-choice", "run-ready",
    "--preflight-choice-snapshot", choice, "--result-snapshot", result]

  output = ""
  code = nil
  Open3.popen2e(*args, pgroup: true) do |stdin, stream, wait|
    stdin.close
    begin
      Timeout.timeout(60) { output = stream.read; code = wait.value.exitstatus }
    ensure
      if wait.alive?
        Process.kill("TERM", -wait.pid) rescue nil
        sleep 0.3
        Process.kill("KILL", -wait.pid) rescue nil
      end
    end
  end
  raise "Expected all-invalid queue to stop after preflight: #{code}: #{output}" unless code == 1 && output.include?("GUI_QUEUE_TEST FAILED jobs=0")
  raise "No final queue state was captured" unless File.file?(result) && File.size(result) > 10_000
  raise "All-error queue must not present a choice sheet" if File.exist?(choice)
  raise "All three preflight reports should remain" unless Dir.glob(File.join(reports, "voiceover-*.report.txt")).length == 3
  raise "No audio may be created" unless Dir.glob(File.join(lectures, "**/*.{m4a,wav}")).empty?
  raise "The test unexpectedly populated the Silero model directory" if File.exist?(File.join(support, "models", "v5_5_ru.pt"))
  if (artifact_directory = ENV["SRT_TO_SOUND_TEST_ARTIFACTS_DIR"])
    FileUtils.mkdir_p(artifact_directory)
    FileUtils.cp(result, File.join(artifact_directory, "all-error-result.png"))
  end
  puts "GUI_PREFLIGHT_ALL_ERROR_OK · 3 reported, 0 ready, no choice sheet, no audio/model loaded"
end
