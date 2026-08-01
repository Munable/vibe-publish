# frozen_string_literal: true

require "digest"
require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"

class VibePublishMarketplaceBuilderTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  BUILDER = File.join(ROOT, "scripts", "build-vibe-publish-marketplace")
  FORUM_URL = "http://127.0.0.1:3000"
  SOURCE_URL = "https://github.com/Munable/vibe-publish"

  def run_builder(output, source_url: SOURCE_URL)
    command = [
      BUILDER,
      "--output",
      output,
      "--forum-url",
      FORUM_URL,
      "--source-url",
      source_url,
    ]
    Open3.capture3(*command, chdir: ROOT)
  end

  def test_build_records_open_source_snapshot_and_remote_proof_boundaries
    Dir.mktmpdir("vibe-marketplace-builder-") do |directory|
      output = File.join(directory, "marketplace")
      stdout, stderr, status = run_builder(output)

      assert status.success?, stderr
      result = JSON.parse(stdout)
      assert_equal SOURCE_URL, result.fetch("source_url")
      assert_equal "vibe-publish@committown", result.fetch("plugin_id")
      assert_equal false, result.fetch("remote_ref_verified")

      release = JSON.parse(File.read(File.join(output, "vibe-publish-release.json"), encoding: "UTF-8"))
      assert_equal "vibe-codex-plugin-release/v2", release.fetch("schema")
      assert_equal SOURCE_URL, release.fetch("source_url")
      assert_equal FORUM_URL, release.fetch("forum_url")
      assert_equal SOURCE_URL, release.dig("source", "url")
      assert_equal "v0.6.0", release.dig("source", "declared_ref")
      assert_equal false, release.dig("source", "remote_repository_fetched")
      assert_equal false, release.dig("source", "remote_ref_verified")
      assert_equal "Apache-2.0", release.dig("license", "spdx_id")
      assert_equal "SECURITY.md", release.dig("security", "path")
      assert_equal false, release.dig("verification", "external_install_verified")
      assert_equal false, release.dig("verification", "forum_reachability_verified")
      assert_equal false, release.dig("verification", "production_write_verified")
      source_paths = release.dig("source_snapshot", "files").map { |file| file.fetch("path") }
      assert_includes source_paths, ".agents/skills/vibe-publish/SKILL.md"
      assert_includes source_paths, "local-tool/lib/vibe_forum_local.rb"
      assert_includes source_paths, "local-tool/test/vibe_forum_local_test.rb"
      assert_includes source_paths, "scripts/build-vibe-publish-plugin"
      assert File.file?(File.join(output, "LICENSE"))
      assert File.file?(File.join(output, "CONTRIBUTING.md"))
      assert File.file?(File.join(output, "SECURITY.md"))
      assert_equal(
        Digest::SHA256.file(File.join(output, "LICENSE")).hexdigest,
        release.dig("license", "sha256"),
      )
      assert_equal(
        Digest::SHA256.file(File.join(output, "SECURITY.md")).hexdigest,
        release.dig("security", "sha256"),
      )
      assert_includes File.read(File.join(output, "CONTRIBUTING.md")), "Developer Certificate of Origin 1.1"
      assert_includes File.read(File.join(output, "SECURITY.md")), "private GitHub Security Advisory"

      readme = File.read(File.join(output, "README.md"), encoding: "UTF-8")
      assert_includes readme, "codex plugin marketplace add #{SOURCE_URL}"
      assert_includes readme, "codex plugin add vibe-publish@committown"
      assert_includes readme, "codex plugin remove vibe-publish@vibe-private"
      assert_includes readme, "codex plugin marketplace remove vibe-private"
      assert_includes readme, "论坛原生 **Reply / 回复**"
      assert_includes readme, "does not fetch the remote repository"
      refute_includes readme, "Build Logs / 构建记录"
      refute_includes readme, "$PWD"

      marketplace = JSON.parse(
        File.read(File.join(output, ".agents", "plugins", "marketplace.json"), encoding: "UTF-8"),
      )
      assert_equal "committown", marketplace.fetch("name")
      plugin = marketplace.fetch("plugins").find { |entry| entry.fetch("name") == "vibe-publish" }
      assert_equal({ "source" => "local", "path" => "./plugins/vibe-publish" }, plugin.fetch("source"))
      assert_equal "ON_USE", plugin.dig("policy", "authentication")
    end
  end

  def test_source_url_trailing_slash_is_normalized
    Dir.mktmpdir("vibe-marketplace-builder-") do |directory|
      output = File.join(directory, "marketplace")
      _stdout, stderr, status = run_builder(output, source_url: "#{SOURCE_URL}/")

      assert status.success?, stderr
      release = JSON.parse(File.read(File.join(output, "vibe-publish-release.json"), encoding: "UTF-8"))
      assert_equal SOURCE_URL, release.fetch("source_url")
    end
  end

  def test_rejects_non_public_or_non_repository_source_urls
    invalid_sources = {
      "http://github.com/Munable/vibe-publish" => "absolute HTTPS URL",
      "https://user:secret@github.com/Munable/vibe-publish" => "must not contain credentials",
      "https://github.com/Munable/vibe-publish?ref=main" => "must not contain a query or fragment",
      "https://localhost/Munable/vibe-publish" => "real public Git URL",
      "https://example.com/Munable/vibe-publish" => "real public Git URL",
      "https://github.com/Munable" => "identify a Git repository path",
    }

    Dir.mktmpdir("vibe-marketplace-builder-") do |directory|
      invalid_sources.each_with_index do |(source_url, expected_error), index|
        output = File.join(directory, "marketplace-#{index}")
        _stdout, stderr, status = run_builder(output, source_url: source_url)

        refute status.success?, source_url
        assert_includes stderr, expected_error
        refute Dir.exist?(output)
      end
    end
  end

  def test_source_url_is_required
    Dir.mktmpdir("vibe-marketplace-builder-") do |directory|
      output = File.join(directory, "marketplace")
      _stdout, stderr, status =
        Open3.capture3(
          BUILDER,
          "--output",
          output,
          "--forum-url",
          FORUM_URL,
          chdir: ROOT,
        )

      refute status.success?
      assert_includes stderr, "--source-url is required"
      refute Dir.exist?(output)
    end
  end
end
