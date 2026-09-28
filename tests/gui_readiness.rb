#!/usr/bin/ruby
# Opens the real setup-readiness dialog in the exact built app, using the
# isolated Python/model QA environment and synthetic, temporary support paths.
require "tmpdir"
require "fileutils"
require "open3"
require "timeout"

binary = ENV["SRT_TO_SOUND_APP_BINARY"]
qa_home = ENV["SRT_TO_SOUND_QA_SILERO_HOME"]
raise "Set SRT_TO_SOUND_APP_BINARY to the exact built app executable" unless binary && File.executable?(binary)
raise "Set SRT_TO_SOUND_QA_SILERO_HOME to the isolated Python/model QA folder" unless qa_home && File.directory?(qa_home)

source_environment = File.join(qa_home, "support", ".venv-silero-py312")
source_model = File.join(qa_home, "support", "models", "v5_5_ru.pt")
raise "QA Python environment is missing" unless File.executable?(File.join(source_environment, "bin", "python"))
raise "QA model file is missing" unless File.file?(source_model) && File.size(source_model).positive?

Dir.mktmpdir("srttosound-readiness-") do |root|
  support = File.join(root, "support")
  reports = File.join(root, "reports")
  models = File.join(support, "models")
  FileUtils.mkdir_p(models)
  FileUtils.symlink(source_environment, File.join(support, ".venv-silero-py312"))
  # The app deliberately checks that the model path is a regular file, so copy
  # the model rather than symlinking it into this isolated support directory.
  FileUtils.copy_file(source_model, File.join(models, "v5_5_ru.pt"))
  screenshot = ENV["SRT_TO_SOUND_READINESS_SCREENSHOT"] || File.join(root, "readiness.png")
  FileUtils.mkdir_p(File.dirname(screenshot))
  output, status = nil, nil
  Open3.popen2e(binary, "--readiness-smoke-test", screenshot,
    "--test-language", "en", "--data-dir", support, "--reports-dir", reports) do |stdin, stream, wait|
    stdin.close
    Timeout.timeout(30) { output = stream.read; status = wait.value.exitstatus }
  end
  unless status == 0 && File.file?(screenshot) && File.size(screenshot) > 10_000 && output.include?("UI_SNAPSHOT_OK")
    raise "Readiness dialog smoke failed (#{status}): #{output}"
  end
  puts "GUI_READINESS_SMOKE_OK · exact app opened the setup-check dialog"
  puts "READINESS_SCREEN #{screenshot}"
end
