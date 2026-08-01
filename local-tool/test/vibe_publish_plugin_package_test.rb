# frozen_string_literal: true

require "fileutils"
require "digest"
require "json"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"

class VibePublishPluginPackageTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  PLUGIN_ROOT =
    [File.join(ROOT, "codex-plugins", "vibe-publish"), File.join(ROOT, "plugins", "vibe-publish")]
      .find { |path| Dir.exist?(path) } || File.join(ROOT, "codex-plugins", "vibe-publish")
  MARKETPLACE_PLUGIN_PATH =
    PLUGIN_ROOT == File.join(ROOT, "plugins", "vibe-publish") ?
      "./plugins/vibe-publish" : "./codex-plugins/vibe-publish"
  BUILDER = File.join(ROOT, "scripts", "build-vibe-publish-plugin")
  CLI = File.join(PLUGIN_ROOT, "tool", "bin", "vibe-forum")

  def test_plugin_manifest_and_repo_marketplace_are_installable
    manifest = JSON.parse(
      File.read(File.join(PLUGIN_ROOT, ".codex-plugin", "plugin.json")),
    )
    assert_operator manifest.dig("interface", "defaultPrompt").length, :<=, 128
    assert_equal "0.6.1", manifest.fetch("version")
    assert_equal "Apache-2.0", manifest.fetch("license")
    assert_equal "https://github.com/Munable/vibe-publish", manifest.fetch("repository")
    assert_equal "https://committown.com", manifest.fetch("homepage")
    assert_equal File.binread(File.join(ROOT, "local-tool", "LICENSE")), File.binread(File.join(PLUGIN_ROOT, "LICENSE"))
    contributing = File.read(File.join(PLUGIN_ROOT, "CONTRIBUTING.md"), encoding: "UTF-8")
    assert_includes contributing, "Developer Certificate of Origin 1.1"
    assert_includes contributing, "git commit -s"
    security = File.read(File.join(PLUGIN_ROOT, "SECURITY.md"), encoding: "UTF-8")
    assert_includes security, "private GitHub Security Advisory"
    assert_includes security, "Do not include exploit details"

    marketplace = JSON.parse(File.read(File.join(ROOT, ".agents", "plugins", "marketplace.json")))
    assert_equal "committown", marketplace.fetch("name")
    plugin = marketplace.fetch("plugins").find { |entry| entry.fetch("name") == "vibe-publish" }
    refute_nil plugin
    assert_equal({ "source" => "local", "path" => MARKETPLACE_PLUGIN_PATH }, plugin.fetch("source"))
  end

  def test_packaged_cli_runs_from_a_clean_home_without_install_or_network
    Dir.mktmpdir("vibe-publish-clean-home") do |directory|
      home = File.join(directory, "home")
      elsewhere = File.join(directory, "elsewhere")
      FileUtils.mkdir_p([home, elsewhere])
      environment = { "HOME" => home, "PATH" => "/usr/bin:/bin" }

      stdout, stderr, status = Open3.capture3(environment, CLI, "--version", chdir: elsewhere)
      assert status.success?, stderr
      assert_equal "vibe-forum 0.6.1\n", stdout

      stdout, stderr, status = Open3.capture3(environment, CLI, "--help", chdir: elsewhere)
      assert status.success?, stderr
      assert_includes stdout, "site-info"
      assert_includes stdout, "edit-info"
      assert_includes stdout, "--online"
      assert_includes stdout, "--allow-loopback-http"
      assert_includes stdout, "keychain is unsupported in Vibe Publish 0.6"
      assert_includes stdout, "reply and reply-edit publishing retired after 0.6.0"
      assert_includes stdout, "native forum Reply/Edit controls"

      stdout, stderr, status =
        Open3.capture3(
          environment,
          CLI,
          "auth",
          "--site",
          "http://127.0.0.1:3000",
          "--allow-loopback-http",
          "--credential-backend",
          "keychain",
          chdir: elsewhere,
        )
      refute status.success?
      assert_empty stdout
      assert_includes stderr, "Keychain credential storage is not supported in Vibe Publish 0.6"
      refute File.exist?(File.join(home, ".config", "vibe-forum", "credentials.json"))
      refute File.exist?(File.join(home, ".config", "vibe-forum", "client-id"))

      image_path = File.join(directory, "proof.png")
      File.binwrite(image_path, "\x89PNG\r\n\x1a\nprivate-alpha-check".b)
      stdout, stderr, status =
        Open3.capture3(environment, CLI, "image-info", "--file", image_path, chdir: elsewhere)
      assert status.success?, stderr
      image_info = JSON.parse(stdout)
      assert_equal "vibe-local-image/v1", image_info.fetch("schema")
      assert_equal "proof.png", image_info.fetch("filename")
      assert_equal "image/png", image_info.fetch("media_type")
      assert_equal Digest::SHA256.file(image_path).hexdigest, image_info.fetch("sha256")

      stdout, stderr, status =
        Open3.capture3(
          environment,
          CLI,
          "doctor",
          "--site",
          "http://127.0.0.1:3000",
          "--allow-loopback-http",
          chdir: elsewhere,
        )
      refute status.success?, stderr
      first_use_report = JSON.parse(stdout)
      assert_equal false, first_use_report.fetch("ok")
      assert_equal "missing", first_use_report.dig("credentials", "state")
      assert_equal "loopback-http", first_use_report.dig("site", "transport")
      assert_equal false, first_use_report.fetch("network_requests_made")

      credentials = File.join(home, ".config", "vibe-forum", "credentials.json")
      FileUtils.mkdir_p(File.dirname(credentials))
      File.write(
        credentials,
        JSON.pretty_generate(
          {
            "site" => "https://forum.example.invalid",
            "user_api_key" => "offline-test-key",
            "client_id" => "0123456789abcdef0123456789abcdef",
            "scope" => "vibe-governance:publish",
            "expires_at" => "2099-01-01T00:00:00Z",
          },
        ) + "\n",
      )
      File.chmod(0o600, credentials)

      stdout, stderr, status = Open3.capture3(environment, CLI, "doctor", chdir: elsewhere)
      assert status.success?, stderr
      report = JSON.parse(stdout)
      assert_equal true, report.fetch("ok")
      assert_equal false, report.fetch("network_requests_made")
      refute_includes stdout, "offline-test-key"

      manifest = File.join(directory, "manifest.json")
      File.write(
        manifest,
        JSON.generate(
          {
            "schema" => "vibe-publish/v3",
            "operation" => "reply",
            "source_locale" => "en",
            "target" => { "topic_id" => 11 },
            "variants" => {
              "en" => { "body_markdown" => "Offline package check." },
              "zh-CN" => { "body_markdown" => "离线包检查。" },
            },
          },
        ),
      )
      stdout, stderr, status =
        Open3.capture3(environment, CLI, "review-request", "--manifest", manifest, chdir: elsewhere)
      assert status.success?, stderr
      review_request = JSON.parse(stdout)
      assert_equal "vibe-local-review/v1", review_request.fetch("schema")
      assert_includes review_request.fetch("compatibility_notice"), "last release that could publish"
      assert_includes review_request.fetch("compatibility_notice"), "readable only as local audit evidence"
      assert_includes review_request.fetch("compatibility_notice"), "native forum controls"

      refute Dir.exist?(File.join(home, ".codex"))
      refute Dir.exist?(File.join(home, ".agents"))
    end
  end

  def test_packaged_skill_keeps_reader_considerate_and_disclosed_relationship_rules
    skill = File.read(File.join(PLUGIN_ROOT, "skills", "vibe-publish", "SKILL.md"), encoding: "UTF-8")
    editorial =
      File.read(
        File.join(PLUGIN_ROOT, "skills", "vibe-publish", "references", "editorial-method.md"),
        encoding: "UTF-8",
      )
    review =
      File.read(
        File.join(PLUGIN_ROOT, "skills", "vibe-publish", "references", "review-policy.md"),
        encoding: "UTF-8",
      )

    assert_includes skill, "brief human entrance grounded in the supplied experience"
    assert_includes skill, "genuine Vibe Coding work from any field"
    assert_includes skill, "Commercial interest alone is never a moderation or featuring failure"
    assert_includes skill, "CommitTown's native **Reply / 回复**"
    assert_includes skill, "Do not create a legacy `reply` manifest"
    assert_includes skill, "both current variants contain titles, proving this is the topic's first post"
    assert_includes skill, "Never ask for, accept, or display a category, board, or destination choice"
    assert_includes skill, "exactly one internal publication destination"
    refute_includes skill, "Determine whether the user wants `create_topic`, `reply`, or `edit_post`"
    assert_includes editorial, "Give the reader a human entrance"
    assert_includes editorial, "private twenty-second scan"
    assert_includes editorial, "A short post may need no headings"
    assert_includes review, "multiple competing axes"
    assert_includes review, "different post types must not share a mandatory visible template"
    assert_includes review, "Job-seeking, hiring, consulting, and collaboration posts"
    assert_includes review, "Commercial interest or a call to action alone is never a reason to block"
    assert_includes review, "Reader consideration is editorial guidance, not a moderation ideology"
  end

  def test_package_check_rejects_unknown_files_and_symlinks
    unknown = File.join(PLUGIN_ROOT, "unexpected-release-file.txt")
    symlink = File.join(PLUGIN_ROOT, "unexpected-release-link")

    begin
      File.write(unknown, "must not ship\n")
      _stdout, stderr, status = Open3.capture3(RbConfig.ruby, BUILDER, "--check", chdir: ROOT)
      refute status.success?
      assert_includes stderr, "unexpected file: unexpected-release-file.txt"
    ensure
      FileUtils.rm_f(unknown)
    end

    begin
      File.symlink("README.md", symlink)
      _stdout, stderr, status = Open3.capture3(RbConfig.ruby, BUILDER, "--check", chdir: ROOT)
      refute status.success?
      assert_includes stderr, "contains a symlink: unexpected-release-link"
    ensure
      FileUtils.rm_f(symlink)
    end

    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, BUILDER, "--check", chdir: ROOT)
    assert status.success?, stderr
  end
end
