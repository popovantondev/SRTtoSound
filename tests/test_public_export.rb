require "minitest/autorun"
require "uri"

class PublicExportTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  MANIFEST = File.join(ROOT, "PUBLIC_EXPORT_FILES.txt")

  def public_files
    paths = []
    File.foreach(MANIFEST) do |line|
      path = line.sub(/#.*/, "").strip
      paths << path unless path.empty?
    end
    paths
  end

  def test_allowlist_is_explicit_unique_and_resolves_to_files
    paths = public_files
    refute_empty paths
    assert_equal paths.uniq, paths
    paths.each do |relative|
      refute relative.start_with?("/"), relative
      refute_includes relative.split("/"), ".."
      assert File.file?(File.join(ROOT, relative)), "Missing allowlisted file: #{relative}"
    end
  end

  def test_private_and_legacy_assets_are_not_exported
    paths = public_files
    forbidden = /(?:\A|\/)(?:\.ai-dev|legacy|translation-work|worktrees)(?:\/|\z)|(?:siri|milena|voice_dictionary|pronunciation\.txt)/i
    assert_empty paths.grep(forbidden)
    refute_includes paths, "docs/CONTINUITY.md"
    refute_includes paths, "docs/RELEASE_PLAN.md"
    refute_includes paths, "термины.txt"
    refute_includes paths, "произношение.txt"
  end

  def test_allowlisted_text_has_no_user_paths_emails_or_credential_markers
    patterns = [
      %r{/Users/(?!example(?:/|"|\s|\z))[A-Za-z0-9._-]+},
      Regexp.new("anton" + "popov", Regexp::IGNORECASE),
      /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/,
      /(?:gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9_-]{20,}|BEGIN (?:RSA |OPENSSH )?PRIVATE KEY)/
    ]
    text_files = public_files.reject { |path| path.match?(/\.(?:png|icns)\z/i) }
    text_files.each do |relative|
      content = File.read(File.join(ROOT, relative))
      patterns.each do |pattern|
        refute_match pattern, content, "Sensitive marker in #{relative}"
      end
    end
  end

  def test_required_public_docs_and_build_inputs_are_included
    paths = public_files
    %w[
      README.md README.en.md README.de.md README.ru.md RIGHTS.md THIRD_PARTY.md .gitignore
      CHANGELOG.md VERSION requirements-silero.txt GUI/main.swift
      GUI/QueueSupport.swift GUI/Assets/SRTVoiceover.icns scripts/build.sh
      scripts/test.sh srt_gui_job.rb srt_voiceover.rb speech_normalizer.rb
    ].each { |path| assert_includes paths, path }
  end

  def test_public_documentation_is_available_in_all_three_languages
    paths = public_files
    %w[
      README.en.md README.de.md README.ru.md
      docs/INSTALLATION.en.md docs/INSTALLATION.de.md docs/INSTALLATION.md
      docs/BUILD.en.md docs/BUILD.de.md docs/BUILD.md
      CHANGELOG.en.md CHANGELOG.de.md CHANGELOG.md
      RIGHTS.en.md RIGHTS.de.md RIGHTS.ru.md
      THIRD_PARTY.en.md THIRD_PARTY.de.md THIRD_PARTY.ru.md
      .github/ISSUE_TEMPLATE/bug_report.yml
      .github/ISSUE_TEMPLATE/bug_report_de.yml
      .github/ISSUE_TEMPLATE/bug_report_ru.yml
      .github/ISSUE_TEMPLATE/feature_request.yml
      .github/ISSUE_TEMPLATE/feature_request_de.yml
      .github/ISSUE_TEMPLATE/feature_request_ru.yml
    ].each { |path| assert_includes paths, path }
  end

  def test_each_language_guide_embeds_its_matching_interface_screenshot
    localized_guides = {
      "README.md" => "interface-en.png",
      "README.en.md" => "interface-en.png",
      "README.de.md" => "interface-de-dark.png",
      "README.ru.md" => "interface-ru.png",
      "docs/INSTALLATION.en.md" => "interface-en.png",
      "docs/INSTALLATION.de.md" => "interface-de-dark.png",
      "docs/INSTALLATION.md" => "interface-ru.png",
      "docs/BUILD.en.md" => "interface-en.png",
      "docs/BUILD.de.md" => "interface-de-dark.png",
      "docs/BUILD.md" => "interface-ru.png"
    }

    localized_guides.each do |guide, screenshot|
      content = File.read(File.join(ROOT, guide))
      assert_includes content, "screenshots/#{screenshot}", guide
    end
  end

  def test_legacy_silero_model_registry_is_not_published_or_bundled
    refute_includes public_files, "latest_silero_models.yml"
    refute_includes File.read(File.join(ROOT, "scripts/build.sh")), "latest_silero_models.yml"
    refute_includes File.read(File.join(ROOT, "scripts/package_release.rb")), "latest_silero_models.yml"
  end

  def test_local_markdown_links_resolve_inside_public_tree
    included = public_files
    included.grep(/\.md\z/).each do |relative|
      text = File.read(File.join(ROOT, relative))
      text.scan(/\[[^\]]*\]\(([^)]+)\)/).flatten.each do |target|
        target = target.split("#", 2).first
        next if target.empty? || target.match?(/\A[a-z][a-z0-9+.-]*:/i)

        decoded = URI::DEFAULT_PARSER.unescape(target)
        resolved = File.expand_path(decoded, File.dirname(File.join(ROOT, relative)))
        assert File.file?(resolved), "Broken local Markdown link: #{relative} -> #{target}"
        public_relative = resolved.delete_prefix("#{ROOT}/")
        assert_includes included, public_relative, "Link target not allowlisted: #{relative} -> #{target}"
      end
    end
  end
end
