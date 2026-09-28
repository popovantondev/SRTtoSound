#!/usr/bin/ruby
# Packages an already reviewed, clean, tagged SRT to Sound release.
require "open3"
require "tmpdir"
require "fileutils"
require "digest"

project = File.expand_path("..", __dir__)
Dir.chdir(project)

def checked(*args)
  out, err, status = Open3.capture3(*args)
  raise "#{args.first}: #{err}\n#{out}" unless status.success?
  out
end

raise "Usage: ruby scripts/package_release.rb /absolute/path/to/releases" unless ARGV.length == 1
parent = File.realpath(ARGV.first)
version = File.read("VERSION").strip
raise "Invalid VERSION" unless version.match?(/\A\d+\.\d+\.\d+\z/)
tag = "v#{version}"
destination = File.join(parent, "v#{version}")
raise "Release already exists; nothing changed: #{destination}" if File.exist?(destination) || File.symlink?(destination)
raise "Commit changes before packaging" unless checked("git", "status", "--porcelain").empty?
revision = checked("git", "rev-parse", "#{tag}^{commit}").strip
raise "Checkout must match #{tag}" unless checked("git", "rev-parse", "HEAD").strip == revision

app_name = checked("/usr/libexec/PlistBuddy", "-c", "Print :CFBundleName", "GUI/Info.plist").strip + ".app"
app = File.join(project, "dist", app_name)
raise "Build first with ./scripts/build.sh: #{app}" unless File.directory?(app)
raise "App version mismatch" unless checked("/usr/libexec/PlistBuddy", "-c", "Print :CFBundleShortVersionString", File.join(app, "Contents/Info.plist")).strip == version
checked("/usr/bin/codesign", "--verify", "--deep", "--strict", app)

runtime_files = %w[
  srt_gui_job.rb srt_voiceover.rb srt_output_policy.rb speech_normalizer.rb
  silero_worker.py requirements-silero.txt VERSION
]
expected = ["GUI/main.swift", "GUI/QueueSupport.swift", "GUI/Info.plist", "GUI/Assets/SRTVoiceover.icns"] + runtime_files
manifest = File.join(app, "Contents/Resources/build-sources.sha256")
listed = File.readlines(manifest).map do |line|
  digest, path = line.strip.split(/\s+/, 2)
  raise "Stale build: #{path}" unless expected.include?(path) && Digest::SHA256.file(path).hexdigest == digest
  path
end
raise "Invalid build manifest" unless listed.sort == expected.sort

release_name = "SRT-to-Sound-#{version}-macOS-arm64.zip"
source_release_name = "SRT-to-Sound-#{version}-source.zip"
Dir.mktmpdir(".srt-to-sound-release-", parent) do |temporary|
  release = File.join(temporary, "v#{version}")
  payload = File.join(release, "SRT to Sound #{version}")
  FileUtils.mkdir_p(payload)

  source_tar = File.join(temporary, "source.tar")
  manifest_text = checked("git", "show", "#{tag}:PUBLIC_EXPORT_FILES.txt")
  public_files = []
  manifest_text.each_line do |line|
    path = line.sub(/#.*/, "").strip
    public_files << path unless path.empty?
  end
  raise "Public export allowlist is empty or duplicated" if public_files.empty? || public_files.uniq != public_files
  unsafe = public_files.reject do |path|
    path.match?(%r{\A[A-Za-z0-9._/-]+\z}) &&
      !path.start_with?("/") &&
      !path.split("/").include?("..") &&
      !path.start_with?(".ai-dev/", "legacy/", "translation-work/")
  end
  raise "Unsafe public export paths: #{unsafe.join(', ')}" unless unsafe.empty?
  tracked = checked("git", "ls-tree", "-r", "--name-only", tag).lines.map(&:chomp)
  missing = public_files - tracked
  raise "Allowlist entries are not present in #{tag}: #{missing.join(', ')}" unless missing.empty?
  required_public = %w[PUBLIC_EXPORT_FILES.txt README.md README.en.md README.de.md README.ru.md RIGHTS.md THIRD_PARTY.md]
  raise "Public allowlist is missing required files: #{(required_public - public_files).join(', ')}" unless (required_public - public_files).empty?
  checked("git", "archive", "--format=tar", "--output=#{source_tar}", tag, "--", *public_files)
  checked("/usr/bin/tar", "-xf", source_tar, "-C", payload)

  source_payload = File.join(temporary, "SRT to Sound #{version} Source")
  FileUtils.mkdir_p(source_payload)
  checked("/usr/bin/tar", "-xf", source_tar, "-C", source_payload)
  source_archive = File.join(release, source_release_name)
  checked("/usr/bin/ditto", "-c", "-k", "--keepParent", "--norsrc", "--noextattr", source_payload, source_archive)
  checked("/usr/bin/unzip", "-t", source_archive)
  source_digest = Digest::SHA256.file(source_archive).hexdigest

  FileUtils.cp_r(app, File.join(payload, app_name), preserve: true)
  File.write(File.join(payload, "RELEASE-NOTICE.txt"), <<~NOTICE)
    SRT to Sound #{version} for macOS 15+ on Apple silicon.

    This application is not notarized by Apple. FFmpeg, the Silero Python environment, and Silero model weights are required separately and are not included. No model weights are bundled. The v5_5_ru model has non-commercial terms; read THIRD_PARTY.md before use.
    The binary is for personal use only under RIGHTS.md. Third-party components retain their own terms.
  NOTICE

  archive = File.join(release, release_name)
  checked("/usr/bin/ditto", "-c", "-k", "--keepParent", "--norsrc", "--noextattr", payload, archive)
  checked("/usr/bin/unzip", "-t", archive)
  digest = Digest::SHA256.file(archive).hexdigest
  File.write(File.join(release, "SHA256SUMS"), "#{digest}  #{release_name}\n#{source_digest}  #{source_release_name}\n")
  File.write(File.join(release, "RELEASE.md"), <<~MARKDOWN)
    # SRT to Sound #{version}

    - macOS 15+ · Apple silicon
    - Tag: `#{tag}`
    - Source commit: `#{revision}`
    - App: `SRT to Sound #{version}/SRT to Sound #{version}.app`
    - Source archive: `#{source_release_name}`
    - Archive checksum: `shasum -a 256 -c SHA256SUMS`

    The app is ad-hoc signed and not notarized. FFmpeg, Python 3.12 ARM64, Silero packages, and model weights are separate required dependencies. Read `RIGHTS.md` and `THIRD_PARTY.md` before use.
  MARKDOWN
  raise "Release appeared during packaging; nothing replaced: #{destination}" if File.exist?(destination) || File.symlink?(destination)
  File.rename(release, destination)
end
puts "RELEASE_READY #{destination}"
puts "SOURCE_COMMIT #{revision}"
