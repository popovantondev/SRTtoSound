#!/usr/bin/ruby
# Explicit acceptance run: opens only the NEW app and uses real Silero on
# synthetic SRTs. Never reads user lectures or changes system voice settings.
require "tmpdir"
require "fileutils"
require "open3"
require "digest"
require "timeout"
require_relative "../srt_voiceover"
require_relative "../srt_output_policy"

project = File.expand_path("..", __dir__)
name, plist_error, plist_status = Open3.capture3("/usr/libexec/PlistBuddy", "-c", "Print :CFBundleName", File.join(project, "GUI/Info.plist"))
raise plist_error unless plist_status.success?
binary = ENV["SRT_TO_SOUND_APP_BINARY"] || File.join(project, "dist", name.strip + ".app/Contents/MacOS/SRTVoiceover")
raise "Build the new app first" unless File.executable?(binary)
qa = Dir.mktmpdir("srt-v12-acceptance-")
puts "QA_DIRECTORY #{qa}"
$stdout.sync = true
lectures = File.join(qa, "lectures")
downloads = File.join(qa, "Downloads")
reports = File.join(qa, "reports")
support = File.join(qa, "support")
FileUtils.mkdir_p([downloads, support])
if (silero_home = ENV["SRT_TO_SOUND_QA_SILERO_HOME"])
  source_environment = File.join(silero_home, "support", ".venv-silero-py312")
  source_model = File.join(silero_home, "support", "models", "v5_5_ru.pt")
  raise "QA Silero environment is missing: #{source_environment}" unless File.executable?(File.join(source_environment, "bin", "python"))
  raise "QA Silero model is missing: #{source_model}" unless File.file?(source_model) && File.size(source_model).positive?
  FileUtils.mkdir_p(File.join(support, "models"))
  File.symlink(source_environment, File.join(support, ".venv-silero-py312"))
  File.symlink(source_model, File.join(support, "models", "v5_5_ru.pt"))
end
inputs = ["Day A", "Day B"].each_with_index.map do |day, index|
  folder = File.join(lectures, day)
  FileUtils.mkdir_p(folder)
  input = File.join(folder, "01 ' пример.ru.srt")
  text = index.zero? ? "Ромашка и календула." : "Сегодня проверяем новый голос."
  File.write(input, "1\n00:00:00,000 --> 00:00:04,000\n#{text}\n\n2\n00:00:04,500 --> 00:00:08,000\nЭто вторая, другая фраза.\n")
  # Folder loading must ignore German originals and intermediate parts.
  File.write(File.join(folder, "01.srt"), "GERMAN MUST NOT RUN")
  File.write(File.join(folder, "01.part-01.ru.srt"), "PART MUST NOT RUN")
  input
end
originals = inputs.map { |path| Digest::SHA256.file(path).hexdigest }
ffmpeg = find_ffmpeg
raise "FFmpeg not available" unless ffmpeg

run = proc do |name, format, *extra|
  args = [binary, "--data-dir", support, "--integration-test", lectures,
          "--test-voice", "kseniya", "--test-format", format, "--reports-dir", reports,
          "--result-snapshot", File.join(qa, "#{name}.png"), *extra]
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
  puts "#{name}: #{output.strip}"
  expected = extra.include?("stop") ? 1 : 0
  raise "GUI acceptance failed: #{name} (#{code})" unless code == expected && output.include?("jobs=2")
end

# Deterministic visual fixtures for the longest interface language and both
# alternatives. These use synthetic rows and never access user documents.
AppLanguageSmoke = proc do |language|
  snapshot = File.join(qa, "localization-#{language}.png")
  output, status = Open3.capture2e(binary, "--ui-smoke-test", snapshot, "--test-language", language,
                                  "--data-dir", support,
                                  "--reports-dir", reports)
  raise "Localization smoke failed (#{language}): #{output}" unless status.success? && File.file?(snapshot) && File.size(snapshot) > 10_000
  puts "LOCALIZATION_SMOKE_OK #{language} #{snapshot}"
end
%w[ru de en].each { |language| AppLanguageSmoke.call(language) }

run.call("aac-beside", "m4a")
outputs = inputs.map { |path| path.sub(/\.srt\z/, ".m4a") }
outputs.each do |file|
  _out, info, = Open3.capture3(ffmpeg, "-hide_banner", "-i", file)
  raise "Not AAC-LC stereo 48 kHz" unless info.match?(/Audio: aac \(LC\).*48000 Hz, stereo/)
  raw, err, status = Open3.capture3(ffmpeg, "-v", "error", "-i", file, "-ar", "24000", "-ac", "1", "-f", "s16le", "-")
  raise err unless status.success? && (raw.bytesize / 48_000.0 - 8).abs < 0.1
end
hashes = outputs.map { |path| Digest::SHA256.file(path).hexdigest }
run.call("aac-copy", "m4a", "--test-conflict", "copy", "--conflict-snapshot", File.join(qa, "conflict.png"),
         "--test-language", "de")
raise "Old AAC changed" unless hashes == outputs.map { |path| Digest::SHA256.file(path).hexdigest }
outputs.each { |path| raise "Missing copy" unless File.file?(path.sub(/\.m4a\z/, " (2).m4a")) }

run.call("wav-downloads", "wav", "--test-downloads", downloads, "--test-conflict", "copy")
wavs = Dir.glob(File.join(downloads, "*.wav")).sort
raise "Two downloads expected" unless wavs.length == 2 && wavs.all? { |path| File.binread(path, 4) == "RIFF" }
wav_hashes = wavs.map { |path| Digest::SHA256.file(path).hexdigest }
raise "Both input texts produced identical speech" if wav_hashes.uniq.length != 2
run.call("wav-skip", "wav", "--test-downloads", downloads, "--test-conflict", "skip")
raise "Skip changed files" unless wav_hashes == wavs.map { |path| Digest::SHA256.file(path).hexdigest }
run.call("wav-replace", "wav", "--test-downloads", downloads, "--test-conflict", "replace")
raise "Unexpected copies on replace" unless Dir.glob(File.join(downloads, "*.wav")).sort == wavs
after_replace = wavs.map { |path| Digest::SHA256.file(path).hexdigest }
run.call("wav-stop", "wav", "--test-downloads", downloads, "--test-conflict", "stop")
raise "Stop changed files" unless after_replace == wavs.map { |path| Digest::SHA256.file(path).hexdigest }
raise "Input SRT changed" unless originals == inputs.map { |path| Digest::SHA256.file(path).hexdigest }
raise "Reports left beside SRT" unless Dir.glob(File.join(lectures, "**/*.report.txt")).empty?
raise "Reports left in Downloads" unless Dir.glob(File.join(downloads, "*.report.txt")).empty?
report_files = Dir.glob(File.join(reports, "voiceover-*.report.txt"))
report_bodies = report_files.map { |path| File.read(path) }
raise "Expected one report for each completed/skipped/cancelled file" unless report_files.length == 11
raise "Expected two skipped reports" unless report_bodies.count { |body| body.include?("Статус: skipped") } == 2
raise "Expected one cancellation report" unless report_bodies.count { |body| body.include?("Статус: cancelled") } == 1
raise "Unexpected report content" unless report_bodies.all? { |body| body.start_with?(VoiceoverReports::MARKER) }

# Cancel while a deliberately slow preflight child is active. The test-only
# runtime delegates report creation to the real helper after the child stops.
cancel_dir = File.join(qa, "preflight-cancel")
fake_runtime = File.join(cancel_dir, "runtime")
cancel_inputs = File.join(cancel_dir, "inputs")
cancel_reports = File.join(cancel_dir, "reports")
FileUtils.mkdir_p([fake_runtime, cancel_inputs, cancel_reports])
cancel_sources = 2.times.map do |index|
  path = File.join(cancel_inputs, format("cancel-%02d.ru.srt", index + 1))
  File.write(path, "1\n00:00:00,000 --> 00:00:03,000\nОчередь отменяется до начала синтеза.\n")
  [path, Digest::SHA256.file(path).hexdigest]
end
started_marker = File.join(cancel_dir, "preflight-started")
fake_job = File.join(fake_runtime, "srt_gui_job.rb")
File.write(fake_job, <<~RUBY)
  if ARGV.include?("--preflight")
    File.write(#{started_marker.inspect}, "started")
    sleep 30
  else
    exec("/usr/bin/ruby", #{File.join(project, "srt_gui_job.rb").inspect}, *ARGV)
  end
RUBY
cancel_args = [binary, "--program-dir", fake_runtime, "--data-dir", File.join(cancel_dir, "support"),
  "--reports-dir", cancel_reports, "--integration-test", cancel_inputs,
  "--test-voice", "kseniya", "--test-format", "m4a", "--test-cancel-during-preflight", "enabled"]
cancel_output = ""
cancel_code = nil
Open3.popen2e(*cancel_args, pgroup: true) do |stdin, stream, wait|
  stdin.close
  begin
    Timeout.timeout(20) { cancel_output = stream.read; cancel_code = wait.value.exitstatus }
  ensure
    if wait.alive?
      Process.kill("TERM", -wait.pid) rescue nil
      sleep 0.2
      Process.kill("KILL", -wait.pid) rescue nil
    end
  end
end
raise "Preflight child did not start" unless File.file?(started_marker)
raise "GUI did not stop during preflight: #{cancel_output}" unless cancel_code == 1 && cancel_output.include?("jobs=2")
cancelled_reports = Dir.glob(File.join(cancel_reports, "voiceover-*.report.txt"))
raise "Expected one cancellation report per unprocessed input" unless cancelled_reports.length == 2
cancelled_bodies = cancelled_reports.map { |path| File.read(path) }
raise "Cancellation report is missing its status or reason" unless cancelled_bodies.all? do |body|
  body.start_with?(VoiceoverReports::MARKER) && body.include?("Статус: cancelled") &&
    body.include?("Синтез для этого файла не запускался")
end
raise "Preflight cancellation created an audio result" unless Dir.glob(File.join(cancel_inputs, "*.m4a")).empty?
raise "Preflight cancellation changed an input SRT" unless cancel_sources.all? { |path, digest| Digest::SHA256.file(path).hexdigest == digest }

# Exercise cancellation from the native GUI after real AAC encoding and AAC
# verification have each begun. The wrapper delays only FFmpeg progress jobs,
# leaving preflight capability probes untouched and making the stage observable.
slow_ffmpeg = File.join(qa, "slow-ffmpeg")
File.write(slow_ffmpeg, <<~SH)
  #!/bin/sh
  for arg in "$@"; do
    if [ "$arg" = "-progress" ]; then sleep 1; break; fi
  done
  exec #{ffmpeg.inspect} "$@"
SH
FileUtils.chmod(0o755, slow_ffmpeg)
%w[encode verify].each do |stage|
  3.times do |iteration|
  stage_dir = File.join(qa, "cancel-#{stage}-#{iteration + 1}")
  stage_inputs = File.join(stage_dir, "inputs")
  stage_reports = File.join(stage_dir, "reports")
  stage_support = File.join(stage_dir, "support")
  FileUtils.mkdir_p([stage_inputs, stage_reports, stage_support])
  if silero_home
    FileUtils.mkdir_p(File.join(stage_support, "models"))
    File.symlink(File.join(silero_home, "support", ".venv-silero-py312"),
      File.join(stage_support, ".venv-silero-py312"))
    File.symlink(File.join(silero_home, "support", "models", "v5_5_ru.pt"),
      File.join(stage_support, "models", "v5_5_ru.pt"))
  end
  stage_srt = File.join(stage_inputs, "cancel-#{stage}.ru.srt")
  File.write(stage_srt, "1\n00:00:00,000 --> 00:00:08,000\nПроверяем отмену во время кодирования и проверки.\n")
  stage_output = stage_srt.sub(/\.srt\z/, ".m4a")
  File.binwrite(stage_output, "EXISTING AUDIO MUST SURVIVE")
  old_digest = Digest::SHA256.file(stage_output).hexdigest
  args = [binary, "--data-dir", stage_support, "--reports-dir", stage_reports,
    "--integration-test", stage_inputs, "--test-voice", "kseniya", "--test-format", "m4a",
    "--test-conflict", "replace", "--test-ffmpeg", slow_ffmpeg,
    "--test-cancel-at-stage", stage]
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
  raise "GUI did not cancel at #{stage}: #{output}" unless code == 1 && output.include?("GUI_TEST_CANCEL_STAGE #{stage}")
  raise "Cancelled #{stage} changed the existing audio" unless Digest::SHA256.file(stage_output).hexdigest == old_digest
  raise "Cancelled #{stage} created a duplicate output" unless Dir.glob(File.join(stage_inputs, "* (2).m4a")).empty?
  staging_parent = File.dirname(stage_inputs)
  raise "Cancelled #{stage} left staging data" unless Dir.glob(File.join(staging_parent, ".srt-voiceover-*"), File::FNM_DOTMATCH).empty?
  stage_report = Dir.glob(File.join(stage_reports, "voiceover-*.report.txt")).fetch(0)
  report_body = File.read(stage_report)
  raise "Cancelled #{stage} report is incomplete" unless report_body.start_with?(VoiceoverReports::MARKER) && report_body.include?("Статус: cancelled")
  raise "Cancelled #{stage} changed its input SRT" unless Digest::SHA256.file(stage_srt).hexdigest == Digest::SHA256.hexdigest("1\n00:00:00,000 --> 00:00:08,000\nПроверяем отмену во время кодирования и проверки.\n")
  puts "GUI_CANCEL_STAGE_OK #{stage} run #{iteration + 1}/3 · existing result preserved"
  end
end
puts "GUI_ACCEPTANCE_OK · 6 synthesis scenarios plus preflight, encode and verification cancellation; QA files retained at #{qa}"
