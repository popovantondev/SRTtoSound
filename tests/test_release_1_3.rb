require "minitest/autorun"
require "tmpdir"
require_relative "../srt_gui_job"

class Release13Test < Minitest::Test
  def run_with_fake_silero_pool(arguments)
    pool = Object.new
    pool.define_singleton_method(:close) { nil }
    pool.define_singleton_method(:synthesize_all) do |jobs, &progress|
      jobs.each_with_index do |(_index, _text, path), index|
        samples = Array.new(SAMPLE_RATE / 2, 100)
        data = samples.pack("s<*")
        header = "RIFF".b + [36 + data.bytesize].pack("V") + "WAVEfmt ".b +
          [16, 1, 1, SAMPLE_RATE, SAMPLE_RATE * 2, 2, 16].pack("VvvVVvv") +
          "data".b + [data.bytesize].pack("V")
        File.binwrite(path, header + data)
        progress.call(index + 1, jobs.length) if progress
      end
    end
    factory = proc { |_program_dir, _speaker, size: nil| pool }
    SileroWorkerPool.stub(:new, factory) { run_voiceover(arguments) }
  end

  def cue(number, start_ms, end_ms, text)
    Cue.new(number, start_ms, end_ms, text)
  end

  def test_continuation_ellipsis_and_large_german_gap_stay_one_sentence
    cues = [
      cue(1, 0, 2_000, "Можно делать и с сахаром,..."),
      cue(2, 5_450, 8_000, "но с мёдом получается лучше.")
    ]
    phrases = smooth_phrases(cues)
    assert_equal 1, phrases.length
    assert_equal "Можно делать и с сахаром, но с мёдом получается лучше.", phrases.first.text
    assert_equal [1, 2], [phrases.first.first_cue, phrases.first.last_cue]
  end

  def test_incomplete_sentence_ignores_six_second_source_gap
    cues = [
      cue(1, 0, 2_000, "Это растение тоже можно использовать,"),
      cue(2, 8_280, 11_000, "чтобы вернуть энергию.")
    ]
    assert_equal 1, smooth_phrases(cues).length
  end

  def test_real_scene_pause_after_completed_sentence_is_preserved
    cues = [
      cue(1, 0, 2_000, "Первая законченная сцена."),
      cue(2, 14_000, 16_000, "Следующая сцена.")
    ]
    phrases = smooth_phrases(cues)
    islands = smooth_islands(phrases, 16_000)
    assert_equal 2, islands.length
    assert_equal 13_700, islands.first.end_ms
    assert_equal 14_000, islands.last.start_ms
  end

  def test_forced_long_sentence_split_uses_tiny_continuation_pause
    cues = [
      cue(1, 0, 2_000, "Очень длинное начало " + "слово " * 28 + ","),
      cue(2, 2_100, 4_000, "которое продолжается " + "дальше " * 24 + ".")
    ]
    phrases = smooth_phrases(cues, preferred_chars: 120, maximum_chars: 220)
    assert_operator phrases.length, :>=, 2
    assert phrases.first.continuation
    assert_equal (SAMPLE_RATE * 0.08).round, smooth_pause_samples(phrases.first)
  end

  def test_punctuation_free_input_gets_a_hard_planning_boundary
    phrases = Array.new(30) do |index|
      SmoothPhrase.new(
        index + 1, index + 1, index * 10_000, (index + 1) * 10_000,
        "продолжение без точки", true
      )
    end

    islands = smooth_islands(phrases, 300_000)

    assert_operator islands.length, :>=, 2
    assert_equal :planning, islands.first.boundary_after
    assert_operator islands.first.end_ms - islands.first.start_ms, :<=, 240_000
    assert_equal :end, islands.last.boundary_after
    assert_equal phrases, islands.flat_map(&:phrases)
  end

  def test_total_pause_between_smooth_phrases_never_exceeds_800_ms
    ffmpeg = find_ffmpeg
    skip "FFmpeg required" unless ffmpeg

    Dir.mktmpdir("srt-v13-pause-") do |dir|
      clips = Array.new(2) do
        Array.new(SAMPLE_RATE / 2) do |index|
          (8_000 * Math.sin(2 * Math::PI * 220 * index / SAMPLE_RATE)).round
        end
      end
      phrases = [
        SmoothPhrase.new(1, 1, 0, 1_000, "Первая фраза.", false),
        SmoothPhrase.new(2, 2, 1_000, 4_000, "Вторая фраза.", false)
      ]
      paths = [File.join(dir, "one.wav"), File.join(dir, "two.wav")]

      _fitted, pauses, = fit_smooth_island(clips, phrases, paths, SAMPLE_RATE * 4, ffmpeg)

      assert_equal 0, pauses.last
      assert_operator pauses.first, :<=, (SAMPLE_RATE * 0.8).round
    end
  end

  def test_dense_island_above_old_quality_limit_is_fitted_without_truncation
    ffmpeg = find_ffmpeg
    skip "FFmpeg required" unless ffmpeg

    Dir.mktmpdir("srt-v2-dense-") do |dir|
      length = (SAMPLE_RATE * 1.70).round
      samples = Array.new(length, 2_000)
      # A distinct tail marker proves that atempo processed the complete clip
      # instead of taking only the beginning of the PCM array.
      (length - SAMPLE_RATE / 10...length).each { |index| samples[index] = 12_000 }
      phrase = SmoothPhrase.new(1, 1, 0, 1_000, "Вся длинная фраза сохранена.", false)

      clips, pauses, factor, = fit_smooth_island(
        [samples], [phrase], [File.join(dir, "clip.wav")], SAMPLE_RATE, ffmpeg
      )

      assert_operator factor, :>, 1.15
      assert_operator factor, :>, 1.60
      assert_equal 0, pauses.sum
      assert_operator clips.first.length, :<=, SAMPLE_RATE
      assert clips.first.last(SAMPLE_RATE / 12).any? { |sample| sample.abs > 8_000 },
             "tail marker was lost, suggesting truncation"
    end
  end

  def test_dense_factor_around_1_7_publishes_full_wav_with_warning_and_tail
    ffmpeg = find_ffmpeg
    skip "FFmpeg required" unless ffmpeg

    Dir.mktmpdir("srt-v2-dense-file-") do |dir|
      input = File.join(dir, "lecture.ru.srt")
      output = File.join(dir, "lecture.wav")
      source = "1\n00:00:00,000 --> 00:00:01,000\nНачало фразы и её слышимый конец.\n"
      File.write(input, source)
      length = (SAMPLE_RATE * 1.70).round
      samples = Array.new(length, 2_000)
      (length - SAMPLE_RATE / 10...length).each { |index| samples[index] = 12_000 }
      spoken = []
      synth = proc do |text, _path, _voice, _rate, _context|
        spoken << text
        samples
      end

      status = nil
      out = err = nil
      stub(:synthesize_natural_phrase, synth) do
        out, err = capture_io do
          status = run_with_fake_silero_pool([
            "--voice", "silero", "--rhythm", "smooth", "--output", output, input
          ])
        end
      end

      assert_equal 0, status, "#{out}\n#{err}"
      report = output.sub(/\.wav\z/, ".report.txt")
      pcm = wav_pcm(output)
      assert_empty err
      assert_equal ["Начало фразы и её слышимый конец."], spoken
      assert_equal source, File.read(input)
      assert File.file?(report)
      assert_equal SAMPLE_RATE, pcm.length
      assert_includes out, "ПРЕДУПРЕЖДЕНИЕ:"
      assert_includes out, "вынужденно ускорен"
      assert_includes out, "Все слова сохранены"
      assert_includes File.read(report), "ПРЕДУПРЕЖДЕНИЕ:"
      assert pcm.last(SAMPLE_RATE / 8).any? { |sample| sample.abs > 8_000 },
             "published WAV lost the audible tail of the dense phrase"
    end
  end

  def test_dense_multi_phrase_island_ruthlessly_compacts_synthetic_pauses
    ffmpeg = find_ffmpeg
    skip "FFmpeg required" unless ffmpeg

    Dir.mktmpdir("srt-v2-pauses-") do |dir|
      clips = Array.new(2) { Array.new((SAMPLE_RATE * 0.72).round, 4_000) }
      phrases = [
        SmoothPhrase.new(1, 1, 0, 700, "Первая фраза.", false),
        SmoothPhrase.new(2, 2, 700, 1_400, "Вторая фраза.", false)
      ]
      paths = [File.join(dir, "one.wav"), File.join(dir, "two.wav")]

      fitted, pauses, factor, = fit_smooth_island(
        clips, phrases, paths, (SAMPLE_RATE * 1.4).round, ffmpeg
      )

      assert_operator factor, :>, 1.0
      assert_operator pauses.first, :>=, compact_smooth_pause_samples(phrases.first)
      assert_operator pauses.first, :<=, smooth_pause_samples(phrases.first)
      assert_equal 0, pauses.last
      assert_operator fitted.sum(&:length) + pauses.sum, :<=, (SAMPLE_RATE * 1.4).round
    end
  end

  def test_artificial_pauses_never_cancel_a_positive_dense_window
    ffmpeg = find_ffmpeg
    skip "FFmpeg required" unless ffmpeg

    Dir.mktmpdir("srt-v2-tiny-window-") do |dir|
      clips = Array.new(2) { Array.new((SAMPLE_RATE * 0.50).round, 4_000) }
      phrases = [
        SmoothPhrase.new(1, 1, 0, 125, "Первая фраза.", false),
        SmoothPhrase.new(2, 2, 125, 250, "Вторая фраза.", false)
      ]
      paths = [File.join(dir, "one.wav"), File.join(dir, "two.wav")]
      available = (SAMPLE_RATE * 0.25).round

      fitted, pauses, factor, = fit_smooth_island(clips, phrases, paths, available, ffmpeg)

      assert_operator factor, :>, 3.0
      assert_operator pauses.sum, :<=, available / 10
      assert_operator fitted.sum(&:length) + pauses.sum, :<=, available
    end
  end

  def test_compacted_pauses_restore_only_to_natural_length_when_room_remains
    ffmpeg = find_ffmpeg
    skip "FFmpeg required" unless ffmpeg

    Dir.mktmpdir("srt-v2-natural-pauses-") do |dir|
      clips = Array.new(4) { Array.new((SAMPLE_RATE * 0.2125).round, 4_000) }
      phrases = Array.new(4) do |index|
        SmoothPhrase.new(index + 1, index + 1, index * 500, (index + 1) * 500,
                         "Вопрос #{index + 1}?", false)
      end
      paths = phrases.each_index.map { |index| File.join(dir, "#{index}.wav") }
      available = SAMPLE_RATE * 2

      fitted, pauses, factor, = fit_smooth_island(clips, phrases, paths, available, ffmpeg)

      compact = compact_smooth_pause_samples(phrases.first)
      natural = smooth_pause_samples(phrases.first)
      assert_operator factor, :<, 1.0
      assert pauses.first(3).all? { |pause| pause >= compact && pause <= natural }
      assert pauses.first(3).any? { |pause| pause > compact }
      assert_operator fitted.sum(&:length) + pauses.sum, :<=, available
    end
  end

  def test_planning_boundary_after_accelerated_island_keeps_compact_pause
    Dir.mktmpdir("srt-v2-boundary-pause-") do |dir|
      input = File.join(dir, "lecture.ru.srt")
      output = File.join(dir, "lecture.wav")
      File.write(input, <<~SRT)
        1
        00:00:00,000 --> 00:00:01,000
        Первая фраза?

        2
        00:00:03,000 --> 00:00:04,000
        Вторая фраза?
      SRT
      island_builder = proc do |phrases, final_end_ms|
        [
          SpeechIsland.new([phrases.fetch(0)], 0, 1_000, :planning),
          SpeechIsland.new([phrases.fetch(1)], 3_000, final_end_ms, :end)
        ]
      end
      first = Array.new(SAMPLE_RATE / 2, 4_000)
      second = Array.new(SAMPLE_RATE / 4, 12_000)
      synth = proc do |text, _path, _voice, _rate, _context|
        text.start_with?("Первая") ? first : second
      end
      fit_count = 0
      fitter = proc do |raw_clips, phrases, _paths, _available, _ffmpeg|
        factor = fit_count.zero? ? 1.70 : 1.0
        fit_count += 1
        [raw_clips, Array.new(phrases.length, 0), factor, raw_clips.sum(&:length).to_f / SAMPLE_RATE]
      end

      status = nil
      out = nil
      stub(:find_ffmpeg, "/usr/bin/true") do
        stub(:smooth_islands, island_builder) do
          stub(:synthesize_natural_phrase, synth) do
            stub(:fit_smooth_island, fitter) do
              out, _err = capture_io do
                status = run_with_fake_silero_pool([
                  "--voice", "silero", "--rhythm", "smooth", "--output", output, input
                ])
              end
            end
          end
        end
      end

      assert_equal 0, status, out
      pcm = wav_pcm(output)
      second_start = pcm.index { |sample| sample.abs > 8_000 }
      expected_pause = compact_smooth_pause_samples(
        SmoothPhrase.new(1, 1, 0, 1_000, "Первая фраза?", false)
      )
      assert_equal first.length + expected_pause, second_start
      assert_operator expected_pause, :<, smooth_pause_samples(
        SmoothPhrase.new(1, 1, 0, 1_000, "Первая фраза?", false)
      )
      assert_includes out, "вынужденно ускорен"
      assert_equal SAMPLE_RATE * 4, pcm.length
    end
  end

  def test_impossible_zero_room_still_fails_instead_of_hiding_bad_timestamps
    phrase = SmoothPhrase.new(1, 1, 0, 0, "Текст.", false)
    error = assert_raises(VoiceoverError) do
      fit_smooth_island([[1] * 100], [phrase], ["unused.wav"], 0, "unused")
    end
    assert_includes error.message, "нет времени"
  end

  def test_broken_timestamps_and_zero_length_cues_still_fail_before_synthesis
    cases = [
      ["broken", "1\nНЕ ТАЙМКОД\nТекст.\n", "Не найден таймкод"],
      ["zero", "1\n00:00:01,000 --> 00:00:01,000\nТекст.\n", "нулевая или отрицательная длительность"]
    ]

    cases.each do |label, source, expected_error|
      Dir.mktmpdir("srt-v2-invalid-#{label}-") do |dir|
        input = File.join(dir, "lecture.ru.srt")
        output = File.join(dir, "lecture.wav")
        File.write(input, source)
        synth_calls = 0
        synth = proc do |*_args|
          synth_calls += 1
          Array.new(SAMPLE_RATE, 1)
        end

        status = nil
        err = nil
        stub(:synthesize_natural_phrase, synth) do
          _out, err = capture_io do
            status = run_with_fake_silero_pool([
              "--voice", "silero", "--rhythm", "smooth", "--output", output, input
            ])
          end
        end

        assert_equal 1, status, label
        assert_includes err, expected_error, label
        assert_equal 0, synth_calls, label
        refute File.exist?(output), label
        refute File.exist?(output.sub(/\.wav\z/, ".report.txt")), label
        assert_equal source, File.read(input), label
      end
    end
  end

  def test_max_segments_keeps_room_until_the_next_unselected_phrase
    Dir.mktmpdir("srt-v13-max-segments-") do |dir|
      input = File.join(dir, "lecture.ru.srt")
      output = File.join(dir, "lecture.wav")
      File.write(input, <<~SRT)
        1
        00:00:00,000 --> 00:00:01,000
        Первая фраза.

        2
        00:00:05,000 --> 00:00:06,000
        Вторая фраза.
      SRT
      available_samples = nil
      fitter = proc do |raw_clips, phrases, _paths, available, _ffmpeg|
        available_samples = available
        [raw_clips, Array.new(phrases.length, 0), 1.0, raw_clips.sum(&:length).to_f / SAMPLE_RATE]
      end
      synth = proc { |_text, _path, _voice, _rate, _context| Array.new(SAMPLE_RATE / 2, 1) }

      status = nil
      out = err = nil
      stub(:find_ffmpeg, "/usr/bin/true") do
        stub(:synthesize_natural_phrase, synth) do
          stub(:fit_smooth_island, fitter) do
            out, err = capture_io do
              status = run_with_fake_silero_pool([
                "--voice", "silero", "--rhythm", "smooth", "--max-segments", "1",
                "--output", output, input
              ])
            end
          end
        end
      end

      assert_equal 0, status, "#{out}\n#{err}"
      assert_operator available_samples, :>=, (SAMPLE_RATE * 4.8).round
      assert_in_delta 4.955, wav_pcm(output).length.to_f / SAMPLE_RATE, 0.002
    end
  end

  def test_strict_silero_starts_only_one_worker
    Dir.mktmpdir("srt-v13-strict-pool-") do |dir|
      input = File.join(dir, "lecture.ru.srt")
      output = File.join(dir, "lecture.wav")
      File.write(input, "1\n00:00:00,000 --> 00:00:01,000\nПроверка.\n")
      requested_size = nil
      fake_pool = Object.new
      fake_pool.define_singleton_method(:close) { nil }
      factory = proc do |_program_dir, _speaker, size: nil|
        requested_size = size
        fake_pool
      end
      fitted = [Array.new(SAMPLE_RATE / 2, 1), "Silero/kseniya", false, 0.5]

      status = nil
      SileroWorkerPool.stub(:new, factory) do
        stub(:find_ffmpeg, "/usr/bin/true") do
          stub(:fit_phrase, fitted) do
            _out, _err = capture_io do
              status = run_voiceover([
                "--voice", "silero", "--silero-speaker", "kseniya", "--rhythm", "strict",
                "--output", output, input
              ])
            end
          end
        end
      end

      assert_equal 0, status
      assert_equal 1, requested_size
    end
  end

  def test_one_oversized_cue_is_split_into_bounded_continuations
    text = (("длинное слово " * 30) + "завершение.").strip
    phrases = smooth_phrases(
      [cue(1, 0, 8_000, text)], preferred_chars: 80, maximum_chars: 120
    )

    assert_operator phrases.length, :>, 1
    assert phrases.all? { |phrase| phrase.text.length <= 120 }
    assert phrases[0...-1].all?(&:continuation)
    refute phrases.last.continuation
    assert_equal text, phrases.map(&:text).join(" ").gsub(/\s+/, " ")
  end

  def test_no_group_still_splits_one_oversized_cue_safely
    text = (("слово " * 80) + "конец.").strip
    phrases = smooth_phrases([cue(1, 0, 8_000, text)], grouping: false, maximum_chars: 120)

    assert_operator phrases.length, :>, 1
    assert phrases.all? { |phrase| phrase.text.length <= 120 }
    assert phrases[0...-1].all?(&:continuation)
    refute phrases.last.continuation
    assert_equal 0, phrases.first.start_ms
    assert_equal 8_000, phrases.last.end_ms
  end

  def test_silero_symbol_check_happens_before_model_loading
    assert_nil validate_silero_text!("Пять миллиграммов, Кратэгус.")
    error = assert_raises(VoiceoverError) { validate_silero_text!("пять миллиграммов/кг × два") }
    assert_includes error.message, "Silero может пропустить"
    assert_includes error.message, "U+002F"
    assert_includes error.message, "U+00D7"
  end

  def test_silero_preflight_reports_unresolved_mark_with_cue_and_time
    Dir.mktmpdir("srt-v13-preflight-") do |dir|
      input = File.join(dir, "synthetic.ru.srt")
      File.write(input, "1\n00:00:02,000 --> 00:00:03,500\nДоза 5 мг × 2.\n")

      error = assert_raises(VoiceoverError) do
        prepare_speech_file(input, rhythm: "strict", voice: "silero")
      end
      assert_includes error.message, "реплики 1–1"
      assert_includes error.message, "00:00:02,000–00:00:03,500"
      assert_includes error.message, "U+00D7"
    end
  end

  def test_silero_parallel_progress_is_monotonic_and_has_two_stages
    Dir.mktmpdir("srt-v13-progress-") do |dir|
      input = File.join(dir, "лекция.ru.srt")
      File.write(input, "1\n00:00:00,000 --> 00:00:01,000\nТест.\n")
      events = []
      job = VoiceoverJob.new(input: input, voice: "silero", rhythm: "smooth") { |event| events << event }
      1.upto(3) do |index|
        job.record(JSON.generate(protocol_version: 1, type: "progress", stage: "synthesis",
          current: index, total: 3))
      end
      [[33, 1], [67, 2], [100, 3]].each do |percent, index|
        job.record(JSON.generate(protocol_version: 1, type: "progress", stage: "assembly",
          current: index, total: 3, percent: percent))
      end

      progress = events.select { |event| event[:type] == "progress" }
      assert_equal %w[synthesis synthesis synthesis assembly assembly assembly], progress.map { |event| event[:stage] }
      assert_equal [21, 42, 63, 72, 81, 90], progress.map { |event| event[:percent] }
      assert_equal progress.map { |event| event[:percent] }.sort, progress.map { |event| event[:percent] }
      assert progress.all? { |event| event[:protocol_version] == 1 && event[:job_id] }
    end
  end

  def test_neutral_default_output_name_does_not_contain_voice
    Dir.mktmpdir("srt-v13-name-") do |dir|
      input = File.join(dir, "лекция.ru.srt")
      File.write(input, "1\n00:00:00,000 --> 00:00:01,000\nТест.\n")
      job = VoiceoverJob.new(input: input, voice: "silero", speaker: "kseniya")
      assert_equal File.join(dir, "лекция.ru.m4a"), job.instance_variable_get(:@output)
    end
  end

  def test_spare_time_uses_gentle_slowdown_instead_of_one_long_pause
    ffmpeg = find_ffmpeg
    skip "FFmpeg required" unless ffmpeg
    Dir.mktmpdir("srt-v13-tempo-") do |dir|
      samples = Array.new(SAMPLE_RATE) { |index| (8_000 * Math.sin(2 * Math::PI * 220 * index / SAMPLE_RATE)).round }
      phrase = SmoothPhrase.new(1, 1, 0, 2_000, "Спокойная фраза.", false)
      clips, _pauses, factor, = fit_smooth_island(
        [samples], [phrase], [File.join(dir, "clip.wav")], SAMPLE_RATE * 2, ffmpeg
      )
      assert_in_delta 0.82, factor, 0.001
      assert_operator clips.first.length, :>, samples.length
      assert_operator clips.first.length, :<=, SAMPLE_RATE * 2
    end
  end

  def test_silero_worker_is_single_threaded_and_rejects_unsafe_symbols
    source = File.read(File.join(__dir__, "..", "silero_worker.py"))
    assert_includes source, "torch.set_num_threads(1)"
    assert_includes source, "torch.set_num_interop_threads(1)"
    assert_includes source, "unsupported = re.sub"
    refute_includes source.downcase, "speech cache"
  end

  def test_build_and_release_manifest_include_normalizer
    build = File.read(File.join(__dir__, "..", "scripts", "build.sh"))
    package = File.read(File.join(__dir__, "..", "scripts", "package_release.rb"))
    assert_includes build, "speech_normalizer.rb"
    assert_includes package, "speech_normalizer.rb"
  end
end
