require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../srt_voiceover"

class Release122Test < Minitest::Test
  RUNTIME_FILES = %w[
    srt_gui_job.rb srt_voiceover.rb srt_output_policy.rb speech_normalizer.rb
    silero_worker.py requirements-silero.txt VERSION
  ].freeze

  def setup
    @dir = Dir.mktmpdir("srt-v122-")
    @old_data = ENV["SRT_VOICEOVER_DATA_DIR"]
    @old_silero = ENV["SRT_VOICEOVER_SILERO_DIR"]
    @old_model = ENV["SRT_VOICEOVER_MODEL_PATH"]
  end

  def teardown
    ENV["SRT_VOICEOVER_DATA_DIR"] = @old_data
    ENV["SRT_VOICEOVER_SILERO_DIR"] = @old_silero
    ENV["SRT_VOICEOVER_MODEL_PATH"] = @old_model
    FileUtils.remove_entry(@dir)
  end

  def test_application_support_paths_override_runtime_directory
    data = File.join(@dir, "Application Support", "SRTtoSound")
    silero = File.join(data, ".venv-silero-py312")
    ENV["SRT_VOICEOVER_DATA_DIR"] = data
    ENV["SRT_VOICEOVER_SILERO_DIR"] = silero
    assert_equal data, voiceover_data_dir("/Applications")
    assert_equal silero, silero_environment_dir("/Applications")
    assert_equal File.join(data, "models", "v5_5_ru.pt"), silero_model_path("/Applications")
  end

  def test_missing_model_stops_before_python_worker_is_started
    data = File.join(@dir, "separate data")
    environment = File.join(data, ".venv-silero-py312", "bin")
    FileUtils.mkdir_p(environment)
    marker = File.join(@dir, "python-was-started")
    python = File.join(environment, "python")
    File.write(python, "#!/bin/sh\nprintf started > #{marker.inspect}\n")
    File.chmod(0o755, python)
    FileUtils.cp(File.join(__dir__, "../silero_worker.py"), File.join(@dir, "silero_worker.py"))
    ENV["SRT_VOICEOVER_DATA_DIR"] = data
    error = assert_raises(VoiceoverError) { SileroWorker.new(@dir, "kseniya") }
    assert_includes error.message, "Загрузка во время озвучки отключена"
    refute File.exist?(marker)
  end

  def test_direct_command_keeps_backward_compatible_adjacent_paths
    ENV.delete("SRT_VOICEOVER_DATA_DIR")
    ENV.delete("SRT_VOICEOVER_SILERO_DIR")
    assert_equal "/runtime", voiceover_data_dir("/runtime")
    assert_equal "/runtime/.venv-silero-py312", silero_environment_dir("/runtime")
  end

  def test_application_support_pronunciation_overrides_bundled_default
    runtime = File.join(@dir, "Runtime")
    data = File.join(@dir, "Data")
    FileUtils.mkdir_p([runtime, data])
    File.write(File.join(runtime, "произношение.txt"), "Instagram => старое\n")
    File.write(File.join(data, "произношение.txt"), "Instagram => новое\n")
    assert_equal "новое", prepare_for_speech("Instagram", load_replacements(runtime, data))
  end

  def test_build_embeds_every_runtime_file_inside_app_resources
    script = File.read(File.expand_path("../scripts/build.sh", __dir__))
    RUNTIME_FILES.each { |file| assert_includes script, file.gsub("\\ ", " ") }
    assert_includes script, "Contents/Resources/Runtime"
    assert_includes script, "build-sources.sha256"
    refute_includes script, "latest_silero_models.yml"
    gui = File.read(File.expand_path("../GUI/main.swift", __dir__))
    assert_includes gui, "Bundle.main.resourceURL"
    assert_includes gui, "SRT_VOICEOVER_DATA_DIR"
    assert_includes gui, "SRT_VOICEOVER_SILERO_DIR"
  end
end
