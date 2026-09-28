#!/usr/bin/ruby
# Captures synthetic GUI states in every supported language and appearance.
# Uses an isolated support/reports folder and never touches user documents.
require "tmpdir"
require "fileutils"
require "open3"

project = File.expand_path("..", __dir__)
name, error, status = Open3.capture3("/usr/libexec/PlistBuddy", "-c", "Print :CFBundleName", File.join(project, "GUI/Info.plist"))
raise error unless status.success?
binary = ENV["SRT_TO_SOUND_APP_BINARY"] || File.join(project, "dist", name.strip + ".app/Contents/MacOS/SRTVoiceover")
raise "Build the new app first with ./scripts/build.sh" unless File.executable?(binary)

output_directory = ENV["SRT_TO_SOUND_SCREENSHOT_DIR"]
directory = output_directory || Dir.mktmpdir("srt-to-sound-localization-")
FileUtils.mkdir_p(directory) if output_directory
begin
  support = File.join(directory, "support")
  reports = File.join(directory, "reports")
  FileUtils.mkdir_p([support, reports])
  %w[ru de en].product(%w[light dark]).each do |language, theme|
    snapshot = File.join(directory, "localization-#{language}-#{theme}.png")
    output, result = Open3.capture2e(binary, "--ui-smoke-test", snapshot,
      "--test-language", language, "--test-theme", theme,
      "--data-dir", support, "--reports-dir", reports)
    unless result.success? && File.file?(snapshot) && File.size(snapshot) > 10_000
      raise "Localization smoke failed (#{language}/#{theme}, exit #{result.exitstatus}): #{output}"
    end
    puts "LOCALIZATION_SMOKE_OK #{language}/#{theme} (#{File.size(snapshot)} bytes)"
  end
  puts "Six synthetic screenshots captured in #{directory}."
ensure
  FileUtils.remove_entry(directory) unless output_directory
end
