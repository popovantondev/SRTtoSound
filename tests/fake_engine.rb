#!/usr/bin/ruby
# Test fixture only: writes a tiny WAV, fails, or waits for cancellation.
require "optparse"
require_relative "../srt_voiceover"
options = {}
OptionParser.new do |p|
  p.on("--voice NAME") { |v| options[:voice] = v }
  p.on("--rhythm NAME") { |v| options[:rhythm] = v }
  p.on("--output PATH") { |v| options[:output] = v }
  p.on("--expected-sha256 HASH") { |_v| }
  p.on("--expected-preparation-fingerprint HASH") { |_v| }
  p.on("--machine-events") { options[:machine_events] = true }
end.parse!
text = File.read(ARGV.fetch(0))
$stdout.sync = true
Process.kill("KILL", Process.pid) if ENV["SRT_TEST_FAKE_ENGINE_CRASH"] == "1"
sleep 10 if text.include?("QUIET")
if text.include?("CANCEL")
  # A descendant must be stopped too, even if it ignores TERM.
  child = fork { Signal.trap("TERM", "IGNORE"); loop { sleep 0.1 } }
  Signal.trap("TERM", "IGNORE")
  puts "CHILD #{child}"
  loop { sleep 0.1 }
end
if text.include?("FAIL")
  warn "Ошибка тестового голоса"
  exit 1
end
pcm = if text.include?("SIGNAL")
        # Known bursts at the start, middle and end expose timing regressions.
        Array.new(SAMPLE_RATE * 4) do |sample|
          time = sample.to_f / SAMPLE_RATE
          active = [0.5, 2.0, 3.5].any? { |start| time >= start && time < start + 0.2 }
          active ? (10_000 * Math.sin(2 * Math::PI * 440 * time)).round : 0
        end.pack("s<*")
      else
        "\0" * (parse_srt(ARGV.fetch(0)).last.end_ms * SAMPLE_RATE / 1000 * 2)
      end
pcm = "\0" * 480 if text.include?("BAD_DURATION")
File.binwrite(options[:output], wav_header(pcm.bytesize) + pcm)
File.write(options[:output].sub(/\.wav\z/, ".report.txt"), "Тестовый отчёт\n")
if (directory = ENV["SRT_TEST_FAKE_ENGINE_READ_ONLY_DIRECTORY"])
  File.chmod(0o555, directory)
end
if text.include?("WARNING")
  if options[:machine_events]
    puts JSON.generate(protocol_version: 1, type: "warning", code: "tempo_fit",
      phrase: 1, first_cue: 1, last_cue: 1, factor: 1.7, all_words_kept: true)
  else
    puts "ПРЕДУПРЕЖДЕНИЕ: Сильное ускорение; проверьте речь."
  end
end
if options[:machine_events]
  puts JSON.generate(protocol_version: 1, type: "progress", stage: "speech", current: 1, total: 2, percent: 50)
  puts JSON.generate(protocol_version: 1, type: "progress", stage: "speech", current: 2, total: 2, percent: 100)
else
  "50%  Фраза 1/2\r100%  Фраза 2/2\nГотово\n".bytes.each { |b| STDOUT.write(b.chr) }
end
