#!/usr/bin/ruby
# Exercises the built app's mixed-queue choice dialog without loading Silero.
require "tmpdir"
require "fileutils"
require "open3"
require "timeout"

project = File.expand_path("..", __dir__)
binary = ENV["SRT_TO_SOUND_APP_BINARY"]
raise "Set SRT_TO_SOUND_APP_BINARY to the exact built app executable" unless binary && File.executable?(binary)

Dir.mktmpdir("srttosound-59-gui-review-") do |root|
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
  choice = File.join(root, "preflight-choice.png")
  result = File.join(root, "result.png")
  args = [binary, "--data-dir", support, "--reports-dir", reports,
    "--integration-test", lectures, "--test-preflight-choice", "review",
    "--preflight-choice-snapshot", choice, "--result-snapshot", result]

  output = ""
  code = nil
  Open3.popen2e(*args, pgroup: true) do |stdin, stream, wait|
    stdin.close
    begin
      Timeout.timeout(90) { output = stream.read; code = wait.value.exitstatus }
    ensure
      if wait.alive?
        Process.kill("TERM", -wait.pid) rescue nil
        sleep 0.3
        Process.kill("KILL", -wait.pid) rescue nil
      end
    end
  end
  raise "Expected review selection to stop before synthesis; exit=#{code}: #{output}" unless code == 1 && output.include?("GUI_QUEUE_TEST FAILED jobs=59")
  raise "The real preflight-choice alert screenshot was not captured" unless File.file?(choice) && File.size(choice) > 10_000
  raise "No final synthetic GUI state was captured" unless File.file?(result) && File.size(result) > 10_000
  raise "The 56 valid files should not have started synthesis" unless Dir.glob(File.join(lectures, "**/*.{m4a,wav}")).empty?
  raise "The test unexpectedly populated the separate Silero model directory" if File.exist?(File.join(support, "models", "v5_5_ru.pt"))
  raise "All three invalid files should retain reports" unless Dir.glob(File.join(reports, "voiceover-*.report.txt")).length == 3
  if (artifact_directory = ENV["SRT_TO_SOUND_TEST_ARTIFACTS_DIR"])
    FileUtils.mkdir_p(artifact_directory)
    FileUtils.cp(choice, File.join(artifact_directory, "preflight-choice.png"))
    FileUtils.cp(result, File.join(artifact_directory, "preflight-result.png"))
  end
  puts "GUI_PREFLIGHT_REVIEW_OK · 59 inspected, 56 ready, 3 reported; review selected; no audio/model loaded"
  puts "CHOICE_SCREEN #{choice}"
end
