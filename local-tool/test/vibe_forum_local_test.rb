# frozen_string_literal: true

require "minitest/autorun"
require "stringio"
require "tempfile"
require "tmpdir"
require_relative "../lib/vibe_forum_local"

class VibeForumLocalTest < Minitest::Test
  class FakeClient
    attr_reader :calls

    def initialize(
      response = { "post" => { "id" => 42, "topic_id" => 7 } },
      get_response: nil
    )
      @response = response
      @get_response = get_response
      @calls = []
    end

    def post(path, payload, headers = {})
      @calls << { path: path, payload: payload, headers: headers }
      @response
    end

    def get(path, headers = {})
      @calls << { path: path, headers: headers }
      return @get_response.shift if @get_response.is_a?(Array)

      @get_response || @response
    end

    def post_multipart(path, file_io:, filename:, content_type:, headers: {})
      file_io.rewind
      @calls << {
        path: path,
        file_bytes: file_io.read,
        filename: filename,
        content_type: content_type,
        headers: headers,
      }
      @response
    end
  end

  class FailingClient
    def post(*)
      raise VibeForumLocal::Error, "simulated network failure"
    end

    def get(*)
      raise VibeForumLocal::Error, "simulated network failure"
    end
  end

  class EditClient
    attr_reader :calls

    def initialize(edit_info:, publish_response:, site_info:)
      @edit_info = edit_info
      @publish_response = publish_response
      @site_info = site_info
      @calls = []
    end

    def get(path, headers = {})
      @calls << { method: :get, path: path, headers: headers }
      path == "/vibe-governance/site-info.json" ? @site_info : @edit_info
    end

    def post(path, payload, headers = {})
      @calls << { method: :post, path: path, payload: payload, headers: headers }
      @publish_response
    end
  end

  def test_browser_authorization_callback_accepts_only_the_fixed_path
    Dir.mktmpdir do |directory|
      authorization =
        VibeForumLocal::DeviceAuthorization.new(
          site: "http://127.0.0.1:3000",
          credentials_path: File.join(directory, "credentials.json"),
          allow_loopback_http: true,
        )
      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.ip_port
      private_key = OpenSSL::PKey::RSA.new(2048)
      expected = { "key" => "narrow-user-api-key", "nonce" => "nonce-123", "api" => 4 }
      encoded =
        Base64.strict_encode64(
          private_key.public_key.public_encrypt(
            JSON.generate(expected),
            OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING,
          ),
        )
      waiter =
        Thread.new do
          authorization.send(
            :wait_for_callback,
            server,
            max_wait_seconds: 2,
            private_key: private_key,
            nonce: "nonce-123",
          )
        end

      wrong_path = send_callback(port, "/wrong-path?payload=#{URI.encode_www_form_component(encoded)}")
      assert_includes wrong_path, "400 Bad Request"
      assert waiter.alive?

      accepted = send_callback(port, "/vibe-forum-auth?payload=#{URI.encode_www_form_component(encoded)}")
      assert_includes accepted, "200 OK"
      assert_equal expected, waiter.value
    ensure
      server&.close
      waiter&.kill
    end
  end

  def test_browser_authorization_rejects_bad_nonce_and_api_before_showing_success
    Dir.mktmpdir do |directory|
      authorization =
        VibeForumLocal::DeviceAuthorization.new(
          site: "http://127.0.0.1:3000",
          credentials_path: File.join(directory, "credentials.json"),
          allow_loopback_http: true,
        )
      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.ip_port
      private_key = OpenSSL::PKey::RSA.new(2048)
      waiter =
        Thread.new do
          authorization.send(
            :wait_for_callback,
            server,
            max_wait_seconds: 3,
            private_key: private_key,
            nonce: "correct-nonce",
          )
        end

      [
        { "key" => "secret-key", "nonce" => "wrong-nonce", "api" => 4 },
        { "key" => "secret-key", "nonce" => "correct-nonce", "api" => 3 },
      ].each do |invalid|
        response = send_encrypted_callback(port, private_key, invalid)
        assert_includes response, "400 Bad Request"
        assert waiter.alive?
      end

      valid = { "key" => "secret-key", "nonce" => "correct-nonce", "api" => 4 }
      assert_includes send_encrypted_callback(port, private_key, valid), "200 OK"
      assert_equal valid, waiter.value
    ensure
      server&.close
      waiter&.kill
    end
  end

  def test_browser_authorization_decrypts_discourse_oaep_payload
    authorization =
      VibeForumLocal::DeviceAuthorization.new(
        site: "http://127.0.0.1:3000",
        credentials_path: File.join(Dir.tmpdir, "unused-vibe-credentials.json"),
        allow_loopback_http: true,
      )
    private_key = OpenSSL::PKey::RSA.new(2048)
    expected = { "key" => "narrow-user-api-key", "nonce" => "nonce-123", "api" => 4 }
    encrypted =
      private_key.public_key.public_encrypt(
        JSON.generate(expected),
        OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING,
      )

    actual = authorization.send(:decrypt_payload, Base64.strict_encode64(encrypted), private_key)

    assert_equal expected, actual
  end

  def test_installation_client_id_is_stable_and_private
    Dir.mktmpdir do |directory|
      path = File.join(directory, "client-id")
      first = VibeForumLocal::InstallationIdentity.load_or_create(path)
      second = VibeForumLocal::InstallationIdentity.load_or_create(path)

      assert_equal first, second
      assert_match(/\A[0-9a-f]{32}\z/, first)
      assert_equal 0o600, File.stat(path).mode & 0o777
    end
  end

  def test_authorization_url_requests_only_the_narrow_scope
    authorization =
      VibeForumLocal::DeviceAuthorization.new(
        site: "https://forum.example.test",
        credentials_path: File.join(Dir.tmpdir, "unused-vibe-credentials.json"),
      )
    key = OpenSSL::PKey::RSA.new(2048)
    url =
      authorization.send(
        :build_authorization_url,
        nonce: "nonce-123",
        client_id: "0123456789abcdef0123456789abcdef",
        public_key: key.public_key,
        callback: "http://127.0.0.1:53682/vibe-forum-auth",
      )
    uri = URI(url)
    params = URI.decode_www_form(uri.query).to_h

    assert_equal "/user-api-key/new", uri.path
    assert_equal VibeForumLocal::SCOPE, params.fetch("scopes")
    assert_equal "0123456789abcdef0123456789abcdef", params.fetch("client_id")
    assert_equal "oaep", params.fetch("padding")
    assert_equal "http://127.0.0.1:53682/vibe-forum-auth", params.fetch("auth_redirect")
    refute_match(/(?:^|,)(?:read|write)(?:,|$)/, params.fetch("scopes"))
  end

  def topic_payload
    {
      "schema" => "vibe-publish/v3",
      "operation" => "create_topic",
      "source_locale" => "en",
      "target" => { "category_slug" => "uncategorized" },
      "variants" => {
        "en" => {
          "title" => "What I learned building a small migration checker",
          "body_markdown" => "The failure mode was an irreversible backfill, not the prompt.",
        },
        "zh-CN" => {
          "title" => "做一个小型迁移检查器后，我学到了什么",
          "body_markdown" => "真正的问题是不可逆的数据回填，而不是提示词。",
        },
      },
    }
  end

  def review_for(payload, decision: "allow")
    {
      "schema" => VibeForumLocal::REVIEW_SCHEMA,
      "reviewer" => "local-test-agent",
      "decision" => decision,
      "content_sha256" => VibeForumLocal::Review.content_digest(payload),
      "findings" => [],
    }
  end

  def edit_info(version: 3)
    {
      "schema" => "vibe-edit-info/v1",
      "target" => { "post_id" => 42, "expected_version" => version },
      "post" => { "topic_id" => 7, "post_number" => 1 },
      "source_locale" => "en",
      "variants" => {
        "en" => {
          "title" => "Current English title for the topic",
          "body_markdown" => "Current English body before the bilingual edit.",
        },
        "zh-CN" => {
          "title" => "当前主题的中文标题",
          "body_markdown" => "这是进行双语编辑之前保存的当前中文正文内容。",
        },
      },
    }
  end

  def edit_payload(version: 3)
    payload = edit_info(version: version).slice("source_locale", "variants")
    payload["schema"] = "vibe-publish/v3"
    payload["operation"] = "edit_post"
    payload["target"] = { "post_id" => 42, "expected_version" => version }
    payload["variants"] = Marshal.load(Marshal.dump(payload.fetch("variants")))
    payload["variants"]["en"]["body_markdown"] =
      "Updated English body after the bilingual edit."
    payload["variants"]["zh-CN"]["body_markdown"] =
      "作者已经通过本地工具更新了这段双语中文正文内容。"
    payload
  end

  def site_info_response(site_url: "https://forum.test")
    {
      "schema" => "vibe-site-info/v1",
      "site_url" => site_url,
      "plugin" => "vibe-governance",
      "publish_schema" => "vibe-publish/v3",
      "accepted_publish_schemas" => %w[vibe-publish/v2 vibe-publish/v3],
      "publish_operations" => %w[create_topic reply edit_post],
      "edit_info_schema" => "vibe-edit-info/v1",
      "scope" => VibeForumLocal::SCOPE,
      "locales" => %w[en zh-CN],
      "feature_request" => {
        "enabled" => false,
        "schema" => "vibe-feature-request/v1",
        "candidate_kinds" => %w[
          build_log
          problem_solution
          open_source
          tool_method
          failure_lesson
        ],
        "credits" => { "available" => 1, "cap" => 2 },
        "public_disclosure" => { "published" => [], "not_published" => [] },
        "third_party_ai_processing" => { "required_acknowledgement" => true },
      },
      "content_limits" => {
        "min_post_length" => 20,
        "min_first_post_length" => 20,
        "max_post_length" => 32_000,
        "min_topic_title_length" => 5,
        "max_topic_title_length" => 255,
      },
      "user" => { "id" => 7, "username" => "alpha-user" },
      "categories" => [
        { "id" => 1, "slug" => "uncategorized", "name" => "Internal publication destination" },
      ],
    }
  end

  def credentials(
    site: "https://forum.test",
    user_api_key: "key",
    client_id: "0123456789abcdef0123456789abcdef",
    scope: VibeForumLocal::SCOPE,
    expires_at: "2099-01-01T00:00:00Z"
  )
    {
      "site" => site,
      "user_api_key" => user_api_key,
      "client_id" => client_id,
      "scope" => scope,
      "expires_at" => expires_at,
    }
  end

  def write_credentials(path, data, mode: 0o600)
    File.write(path, JSON.pretty_generate(data) + "\n")
    File.chmod(mode, path)
  end

  def send_callback(port, target)
    socket = TCPSocket.new("127.0.0.1", port)
    socket.write "GET #{target} HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
    socket.read
  ensure
    socket&.close
  end

  def send_encrypted_callback(port, private_key, payload)
    encrypted =
      private_key.public_key.public_encrypt(
        JSON.generate(payload),
        OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING,
      )
    encoded = URI.encode_www_form_component(Base64.strict_encode64(encrypted))
    send_callback(port, "/vibe-forum-auth?payload=#{encoded}")
  end

  def with_image(extension: ".png", bytes: "\x89PNG\r\n\x1a\nlocal-test".b)
    file = Tempfile.new(["vibe-image", extension])
    file.binmode
    file.write(bytes)
    file.close
    yield file.path
  ensure
    file&.unlink
  end

  def topic_payload_with_image
    payload = Marshal.load(Marshal.dump(topic_payload))
    short_url = "upload://qUm0DGR49PAZshIi7HxMd3cAlzn.png"
    payload["image"] = { "upload_id" => 42, "short_url" => short_url }
    payload["variants"]["en"]["body_markdown"] += "\n\n![Proof](#{short_url})"
    payload["variants"]["zh-CN"]["body_markdown"] += "\n\n![证明图片](#{short_url})"
    payload
  end

  def topic_payload_with_feature_request
    payload = Marshal.load(Marshal.dump(topic_payload))
    payload["feature_request"] = {
      "schema" => "vibe-feature-request/v1",
      "requested" => true,
      "candidate_kind" => "build_log",
      "local_skill_version" => "vibe-publish/0.6.0",
      "precheck_result" => "passed",
      "public_disclosure_accepted" => true,
      "third_party_ai_processing_accepted" => true,
    }
    payload
  end

  def test_review_is_bound_to_the_exact_outbound_content
    report = review_for(topic_payload)
    changed = Marshal.load(Marshal.dump(topic_payload))
    changed["variants"]["en"]["body_markdown"] = "Changed after review"

    error = assert_raises(VibeForumLocal::Error) do
      VibeForumLocal::Review.validate!(report, changed)
    end

    assert_match(/does not match/, error.message)
  end

  def test_review_request_instructs_the_local_agent_to_apply_reader_considerate_rules
    request = VibeForumLocal::Review.request(topic_payload)
    instruction = request.fetch("instruction")

    assert_includes instruction, "Genuine Vibe Coding work may come from any field"
    assert_includes instruction, "commercial interest alone is never a block or ordinary-post reason"
    assert_includes instruction, "job-seeking, hiring, consulting, and collaboration are allowed"
    assert_includes instruction, "Reader structure, title, length, fluency, and style issues should warn, not block"
    assert_includes instruction, "one main axis"
    assert_includes instruction, "truthful human opening"
    assert_includes instruction, "direct first-sentence response"
    assert_includes instruction, "before technical detail"
    assert_includes instruction, "no repeated conclusions or feature inventory"
    assert_includes instruction, "fact-equivalent English and Chinese"
    assert_equal topic_payload, request.fetch("content")
    refute request.key?("compatibility_notice")
  end

  def test_review_request_keeps_legacy_reply_compatibility_visible_for_0_6
    payload = {
      "schema" => "vibe-publish/v3",
      "operation" => "reply",
      "source_locale" => "en",
      "target" => { "topic_id" => 11 },
      "variants" => {
        "en" => { "body_markdown" => "Legacy reply compatibility check." },
        "zh-CN" => { "body_markdown" => "旧版回复兼容检查。" },
      },
    }

    request = VibeForumLocal::Review.request(payload)

    assert_equal "0.6.0", VibeForumLocal::LEGACY_REPLY_COMPATIBLE_THROUGH
    assert_includes request.fetch("compatibility_notice"), "Legacy reply envelopes"
    assert_includes request.fetch("compatibility_notice"), "native forum controls"
  end

  def test_static_promotion_terms_warn_without_blocking_substantive_disclosed_content
    payload = Marshal.load(Marshal.dump(topic_payload))
    payload["variants"]["zh-CN"]["body_markdown"] =
      "我负责这个闭源工具。下面是复现过程、限制和修复；购买链接只放在文末。"

    assert_equal(
      ["possible promotion terms: verify substantive context, repetition, and relationship disclosure"],
      VibeForumLocal::Review.static_findings(payload),
    )
    assert_nil VibeForumLocal::Review.reject_secrets!(payload)
  end

  def test_static_preflight_blocks_likely_secrets
    payload = Marshal.load(Marshal.dump(topic_payload))
    payload["variants"]["zh-CN"]["body_markdown"] = "password=do-not-publish-this"

    error = assert_raises(VibeForumLocal::Error) do
      VibeForumLocal::Review.reject_secrets!(payload)
    end

    assert_match(/Possible secret/, error.message)
  end

  def test_publish_blocks_the_active_forum_key_before_preview_or_network
    payload = Marshal.load(Marshal.dump(topic_payload))
    active_key = "forum-key-without-a-known-prefix-123456"
    payload["variants"]["en"]["body_markdown"] = "Accidentally pasted #{active_key}"
    client = FakeClient.new(get_response: site_info_response)

    error = assert_raises(VibeForumLocal::Error) do
      VibeForumLocal::Publisher.new(
        credentials: credentials(user_api_key: active_key),
        input: StringIO.new("publish\n"),
        output: StringIO.new,
        client: client,
      ).publish(payload: payload, review_report: review_for(payload))
    end

    assert_match(/forum publishing key/, error.message)
    assert_empty client.calls
    refute_includes error.message, active_key
  end

  def test_http_error_redaction_removes_active_and_common_api_keys
    client = VibeForumLocal::HttpClient.new("https://forum.example.test")
    request = Net::HTTP::Post.new(URI("https://forum.example.test/test"))
    active_key = "forum-key-without-a-known-prefix-123456"
    request["User-Api-Key"] = active_key
    # Assemble a recognisable fake key only at runtime so repository scanners
    # do not mistake this redaction fixture for a committed provider secret.
    common_key = ["sk", "abcdefghijklmnopqrstuvwxyz123456"].join("-")

    redacted = client.send(:redact, "#{active_key} #{common_key}", request)

    assert_equal "[REDACTED] [REDACTED]", redacted
  end

  def test_idempotency_key_is_stable_for_the_same_content_and_target
    first = VibeForumLocal::Review.idempotency_key(topic_payload)
    reordered = topic_payload.to_a.reverse.to_h

    assert_equal first, VibeForumLocal::Review.idempotency_key(reordered)
    changed_target = Marshal.load(Marshal.dump(topic_payload))
    changed_target["target"]["category_id"] = 6
    refute_equal first, VibeForumLocal::Review.idempotency_key(changed_target)
    refute_equal first, VibeForumLocal::Review.idempotency_key(topic_payload_with_feature_request)
  end

  def test_credentials_can_be_saved_under_an_existing_shared_directory
    Dir.mktmpdir do |directory|
      path = File.join(directory, "credentials.json")
      original_directory_mode = File.stat(directory).mode & 0o777

      VibeForumLocal::Credentials.save(
        credentials,
        path,
      )

      assert_equal original_directory_mode, File.stat(directory).mode & 0o777
      assert_equal 0o600, File.stat(path).mode & 0o777
      assert_equal "key", VibeForumLocal::Credentials.load(path).fetch("user_api_key")
    end
  end

  def test_default_backend_uses_the_private_file_on_every_platform
    Dir.mktmpdir do |directory|
      path = File.join(directory, "credentials.json")
      secret = "narrow-file-key"

      assert_equal "posix-file", VibeForumLocal::Credentials.resolve_backend(nil)
      assert_equal "posix-file", VibeForumLocal::Credentials.resolve_backend("auto")

      VibeForumLocal::Credentials.save(
        credentials(user_api_key: secret),
        path,
      )

      metadata = JSON.parse(File.read(path))
      assert_equal 0o600, File.stat(path).mode & 0o777
      assert_equal "posix-file", metadata.fetch("credential_backend")
      assert_equal secret, metadata.fetch("user_api_key")
      refute metadata.key?("credential_ref")
      assert_equal secret, VibeForumLocal::Credentials.load(path).fetch("user_api_key")
      refute VibeForumLocal.const_defined?(:SecretStore, false)
    end
  end

  def test_explicit_keychain_backend_fails_before_authorization_starts
    Dir.mktmpdir do |directory|
      path = File.join(directory, "credentials.json")
      client_id_path = File.join(directory, "client-id")

      error =
        assert_raises(VibeForumLocal::Error) do
          VibeForumLocal::DeviceAuthorization.new(
            site: "https://forum.test",
            credentials_path: path,
            client_id_path: client_id_path,
            credential_backend: "keychain",
            output: StringIO.new,
          )
        end

      assert_equal VibeForumLocal::Credentials::KEYCHAIN_UNSUPPORTED_MESSAGE, error.message
      refute File.exist?(path)
      refute File.exist?(client_id_path)
    end
  end

  def test_explicit_keychain_save_fails_closed_without_writing_a_file
    Dir.mktmpdir do |directory|
      path = File.join(directory, "credentials.json")
      secret = "explicit-keychain-secret"

      error =
        assert_raises(VibeForumLocal::Error) do
          VibeForumLocal::Credentials.save(
            credentials(user_api_key: secret),
            path,
            backend: "keychain",
          )
        end

      refute File.exist?(path)
      refute_includes error.message, secret
      assert_equal VibeForumLocal::Credentials::KEYCHAIN_UNSUPPORTED_MESSAGE, error.message
    end
  end

  def test_doctor_marks_retired_keychain_metadata_for_reauthorization_without_network
    Dir.mktmpdir do |directory|
      path = File.join(directory, "credentials.json")
      retired_reference = "retired-reference-that-must-not-be-reported"
      write_credentials(
        path,
        {
          "site" => "https://forum.test",
          "client_id" => "0123456789abcdef0123456789abcdef",
          "scope" => VibeForumLocal::SCOPE,
          "expires_at" => "2099-01-01T00:00:00Z",
          "credential_backend" => "macos-keychain",
          "credential_ref" => retired_reference,
        },
      )

      report =
        VibeForumLocal::Doctor.new(
          credentials_path: path,
          now: Time.iso8601("2029-01-01T00:00:00Z"),
        ).run(online: true)

      assert_equal false, report.fetch("ok")
      assert_equal "reauthorization_required", report.dig("credentials", "state")
      assert_equal "macos-keychain", report.dig("credentials", "storage")
      assert_equal false, report.fetch("network_requests_made")
      assert_equal "not_attempted", report.dig("online", "state")
      refute_includes JSON.generate(report), retired_reference
    end
  end

  def test_credentials_load_rejects_a_symbolic_link
    Dir.mktmpdir do |directory|
      target = File.join(directory, "real-credentials.json")
      link = File.join(directory, "credentials.json")
      write_credentials(target, credentials)
      File.symlink(target, link)

      error = assert_raises(VibeForumLocal::Error) do
        VibeForumLocal::Credentials.load(link)
      end
      assert_match(/must not be a symbolic link/, error.message)
    end
  end

  def test_credentials_path_must_be_a_regular_file
    Dir.mktmpdir do |directory|
      error = assert_raises(VibeForumLocal::Error) do
        VibeForumLocal::Credentials.load(directory)
      end
      assert_match(/must be a regular file/, error.message)
    end
  end

  def test_credentials_load_requires_exact_0600_permissions
    Dir.mktmpdir do |directory|
      path = File.join(directory, "credentials.json")
      write_credentials(path, credentials, mode: 0o640)

      error = assert_raises(VibeForumLocal::Error) do
        VibeForumLocal::Credentials.load(path)
      end
      assert_match(/exactly 0600/, error.message)
    end
  end

  def test_credentials_load_requires_current_user_ownership
    Dir.mktmpdir do |directory|
      path = File.join(directory, "credentials.json")
      write_credentials(path, credentials)

      error = Process.stub(:uid, Process.uid + 1) do
        assert_raises(VibeForumLocal::Error) { VibeForumLocal::Credentials.load(path) }
      end
      assert_match(/owned by the current user/, error.message)
    end
  end

  def test_credentials_load_rejects_expired_or_wrong_scope_credentials
    Dir.mktmpdir do |directory|
      path = File.join(directory, "credentials.json")
      write_credentials(
        path,
        credentials(expires_at: "2028-01-01T00:00:00Z"),
      )

      error = assert_raises(VibeForumLocal::Error) do
        VibeForumLocal::Credentials.load(
          path,
          now: Time.iso8601("2029-01-01T00:00:00Z"),
        )
      end
      assert_match(/has expired/, error.message)

      write_credentials(path, credentials(scope: "all"))
      error = assert_raises(VibeForumLocal::Error) do
        VibeForumLocal::Credentials.load(path)
      end
      assert_match(/scope must be exactly/, error.message)

      write_credentials(path, credentials(site: "https://forum.test/"))
      error = assert_raises(VibeForumLocal::Error) do
        VibeForumLocal::Credentials.load(path)
      end
      assert_match(/must use the canonical URL/, error.message)
    end
  end

  def test_remote_forum_requires_https
    error = assert_raises(VibeForumLocal::Error) do
      VibeForumLocal::HttpClient.new("http://forum.example.com")
    end

    assert_match(/must use HTTPS/, error.message)
    VibeForumLocal::HttpClient.new("https://forum.example.com")
  end

  def test_forum_site_must_be_a_canonical_origin
    [
      "https://user@forum.example.com",
      "https://forum.example.com/subpath",
      "https://forum.example.com?redirect=elsewhere",
      "https://forum.example.com#fragment",
    ].each do |site|
      assert_raises(VibeForumLocal::Error) { VibeForumLocal::HttpClient.new(site) }
    end

    assert_equal(
      "https://forum.example.com",
      VibeForumLocal::SiteAddress.canonical("https://FORUM.example.com:443/"),
    )
  end

  def test_http_is_allowed_for_loopback_development_only
    error = assert_raises(VibeForumLocal::Error) do
      VibeForumLocal::HttpClient.new("http://127.0.0.1:3000")
    end
    assert_match(/explicit --allow-loopback-http/, error.message)

    VibeForumLocal::HttpClient.new(
      "http://127.0.0.1:3000",
      allow_loopback_http: true,
    )
    VibeForumLocal::HttpClient.new(
      "http://localhost:3000",
      allow_loopback_http: true,
    )
    VibeForumLocal::HttpClient.new(
      "http://[::1]:3000",
      allow_loopback_http: true,
    )
  end

  def test_publish_shows_preview_requires_exact_confirmation_and_uses_narrow_headers
    client = FakeClient.new(get_response: site_info_response)
    output = StringIO.new
    publisher =
      VibeForumLocal::Publisher.new(
        credentials: credentials(user_api_key: "secret-key"),
        input: StringIO.new("publish\n"),
        output: output,
        client: client,
      )

    response = publisher.publish(payload: topic_payload, review_report: review_for(topic_payload))

    assert_equal 42, response.dig("post", "id")
    assert_includes output.string, topic_payload.dig("variants", "en", "body_markdown")
    assert_includes output.string, topic_payload.dig("variants", "zh-CN", "body_markdown")
    assert_includes output.string, "Featured shelf request: no"
    assert_includes output.string, "triggers no server AI"
    assert_equal "/vibe-governance/site-info.json", client.calls.fetch(0).fetch(:path)
    assert_equal "/vibe-governance/site-info.json", client.calls.fetch(1).fetch(:path)
    call = client.calls.fetch(2)
    assert_equal "/vibe-governance/publish.json", call.fetch(:path)
    assert_equal "secret-key", call.dig(:headers, "User-Api-Key")
    assert_equal "0123456789abcdef0123456789abcdef", call.dig(:headers, "User-Api-Client-Id")
    assert_match(/\Avibe-[0-9a-f]{48}\z/, call.dig(:headers, "Idempotency-Key"))
  end

  def test_publish_preview_makes_feature_cost_and_disclosure_explicit
    payload = topic_payload_with_feature_request
    output = StringIO.new
    client = FakeClient.new(get_response: site_info_response)

    VibeForumLocal::Publisher.new(
      credentials: credentials,
      input: StringIO.new("publish\n"),
      output: output,
      client: client,
    ).publish(payload: payload, review_report: review_for(payload))

    assert_includes output.string, "Featured shelf request: yes (build_log)"
    assert_includes output.string, "one requested curation decision"
    assert_includes output.string, "Public transparency: scoped request ID, minute timestamp, result"
    refute_includes output.string.downcase, "category"
    refute_includes output.string, "uncategorized"
    assert_includes output.string, "Not public: account, title, body, link, image, or evidence excerpt"
    assert_equal payload.fetch("feature_request"), client.calls.last.fetch(:payload).fetch("feature_request")
  end

  def test_publish_cancels_without_human_confirmation
    publisher =
      VibeForumLocal::Publisher.new(
        credentials: credentials,
        input: StringIO.new("no\n"),
        output: StringIO.new,
        client: FakeClient.new(get_response: site_info_response),
      )

    assert_raises(VibeForumLocal::Error) do
      publisher.publish(payload: topic_payload, review_report: review_for(topic_payload))
    end
  end

  def test_publish_rejects_a_short_bilingual_reply_using_live_forum_limits_before_write
    payload = {
      "schema" => "vibe-publish/v3",
      "operation" => "reply",
      "source_locale" => "zh-CN",
      "target" => { "topic_id" => 28 },
      "variants" => {
        "en" => {
          "body_markdown" => "Internal novice acceptance: the reply flow is working normally.",
        },
        "zh-CN" => { "body_markdown" => "内部新人验收：回复流程正常。" },
      },
    }
    client = FakeClient.new(get_response: site_info_response)

    error = assert_raises(VibeForumLocal::Error) do
      VibeForumLocal::Publisher.new(
        credentials: credentials,
        input: StringIO.new("publish\n"),
        output: StringIO.new,
        client: client,
      ).publish(payload: payload, review_report: review_for(payload))
    end

    assert_match(/zh-CN body_markdown is 14 characters/, error.message)
    assert_match(/requires 20\.\.32000/, error.message)
    assert_match(/regenerate its local review/, error.message)
    assert_match(/no publication was sent/, error.message)
    assert_equal ["/vibe-governance/site-info.json"], client.calls.map { |call| call.fetch(:path) }
  end

  def test_edit_manifest_requires_version_and_consistent_topic_titles
    assert_equal edit_payload, VibeForumLocal::Envelope.validate!(edit_payload)

    missing_version = Marshal.load(Marshal.dump(edit_payload))
    missing_version["target"].delete("expected_version")
    error = assert_raises(VibeForumLocal::Error) do
      VibeForumLocal::Envelope.validate!(missing_version)
    end
    assert_match(/exactly post_id and expected_version/, error.message)

    one_title = Marshal.load(Marshal.dump(edit_payload))
    one_title["variants"]["zh-CN"].delete("title")
    error = assert_raises(VibeForumLocal::Error) do
      VibeForumLocal::Envelope.validate!(one_title)
    end
    assert_match(/include titles in both/, error.message)
  end

  def test_edit_info_uses_narrow_key_and_validates_exact_current_manifest
    client = FakeClient.new(edit_info)
    response =
      VibeForumLocal::EditInfo.new(
        credentials: credentials(user_api_key: "narrow-key"),
        client: client,
      ).fetch(post_id: 42)

    assert_equal 3, response.dig("target", "expected_version")
    call = client.calls.fetch(0)
    assert_equal "/vibe-governance/edit-info/42.json", call.fetch(:path)
    assert_equal "narrow-key", call.dig(:headers, "User-Api-Key")
    assert_equal "0123456789abcdef0123456789abcdef", call.dig(:headers, "User-Api-Client-Id")
  end

  def test_edit_publish_fetches_current_version_shows_changes_and_then_writes
    payload = edit_payload
    client =
      EditClient.new(
        edit_info: edit_info,
        site_info: site_info_response,
        publish_response: {
          "post" => { "id" => 42, "topic_id" => 7, "version" => 4 },
        },
      )
    output = StringIO.new

    response =
      VibeForumLocal::Publisher.new(
        credentials: credentials(user_api_key: "narrow-key"),
        input: StringIO.new("publish\n"),
        output: output,
        client: client,
      ).publish(payload: payload, review_report: review_for(payload))

    assert_equal 4, response.dig("post", "version")
    assert_includes output.string, "Changes from current version"
    assert_includes output.string, "Current English body before the bilingual edit."
    assert_includes output.string, "Updated English body after the bilingual edit."
    assert_equal %i[get get get post], client.calls.map { |call| call.fetch(:method) }
    assert_equal "/vibe-governance/site-info.json", client.calls.first.fetch(:path)
    assert_equal "/vibe-governance/publish.json", client.calls.last.fetch(:path)
  end

  def test_edit_publish_stops_before_confirmation_or_write_when_version_is_stale
    payload = edit_payload(version: 3)
    client =
      EditClient.new(
        edit_info: edit_info(version: 4),
        site_info: site_info_response,
        publish_response: {},
      )
    publisher =
      VibeForumLocal::Publisher.new(
        credentials: credentials,
        input: StringIO.new("publish\n"),
        output: StringIO.new,
        client: client,
      )

    error = assert_raises(VibeForumLocal::Error) do
      publisher.publish(payload: payload, review_report: review_for(payload))
    end
    assert_match(/changed from expected version 3 to 4/, error.message)
    assert_equal %i[get get], client.calls.map { |call| call.fetch(:method) }
  end

  def test_topic_manifest_uses_the_sole_internal_destination_without_exposing_it_in_preview
    payload = Marshal.load(Marshal.dump(topic_payload))
    payload["target"] = { "category_slug" => "uncategorized" }

    assert_equal payload, VibeForumLocal::Envelope.validate!(payload)

    client = FakeClient.new(get_response: site_info_response)
    output = StringIO.new
    VibeForumLocal::Publisher.new(
      credentials: credentials,
      input: StringIO.new("publish\n"),
      output: output,
      client: client,
    ).publish(payload: payload, review_report: review_for(payload))

    assert_includes output.string, "Create CommitTown topic"
    refute_includes output.string, "uncategorized"
    refute_includes output.string.downcase, "category"
    assert_equal "uncategorized", client.calls.fetch(2).dig(:payload, "target", "category_slug")

    ambiguous = Marshal.load(Marshal.dump(payload))
    ambiguous["target"]["category_id"] = 1
    error = assert_raises(VibeForumLocal::Error) do
      VibeForumLocal::Envelope.validate!(ambiguous)
    end
    assert_match(/exactly one/, error.message)
  end

  def test_topic_publish_fails_closed_for_missing_multiple_or_mismatched_destinations
    missing = site_info_response.merge("categories" => [])
    multiple =
      site_info_response.merge(
        "categories" => [
          { "id" => 1, "slug" => "uncategorized", "name" => "Internal destination" },
          { "id" => 2, "slug" => "other", "name" => "Unexpected destination" },
        ],
      )

    [missing, multiple].each do |site_info|
      client = FakeClient.new(get_response: site_info)
      error = assert_raises(VibeForumLocal::Error) do
        VibeForumLocal::Publisher.new(
          credentials: credentials,
          input: StringIO.new("publish\n"),
          output: StringIO.new,
          client: client,
        ).publish(payload: topic_payload, review_report: review_for(topic_payload))
      end

      assert_match(/exactly one internal publication destination/, error.message)
      assert_match(/No publication was sent/, error.message)
      assert_equal ["/vibe-governance/site-info.json"], client.calls.map { |call| call.fetch(:path) }
    end

    mismatched = Marshal.load(Marshal.dump(topic_payload))
    mismatched["target"] = { "category_slug" => "not-the-internal-destination" }
    client = FakeClient.new(get_response: site_info_response)
    error = assert_raises(VibeForumLocal::Error) do
      VibeForumLocal::Publisher.new(
        credentials: credentials,
        input: StringIO.new("publish\n"),
        output: StringIO.new,
        client: client,
      ).publish(payload: mismatched, review_report: review_for(mismatched))
    end
    assert_match(/sole internal publication destination/, error.message)
    assert_match(/review it again/, error.message)
    assert_equal ["/vibe-governance/site-info.json"], client.calls.map { |call| call.fetch(:path) }
  end

  def test_manifest_binds_one_forum_image_to_both_language_variants
    payload = topic_payload_with_image
    assert_equal payload, VibeForumLocal::Envelope.validate!(payload)

    missing_chinese_reference = Marshal.load(Marshal.dump(payload))
    missing_chinese_reference["variants"]["zh-CN"]["body_markdown"] = "没有图片引用的中文正文。"
    error = assert_raises(VibeForumLocal::Error) do
      VibeForumLocal::Envelope.validate!(missing_chinese_reference)
    end
    assert_match(/same manifest image/, error.message)

    undeclared = Marshal.load(Marshal.dump(topic_payload))
    undeclared["variants"]["en"]["body_markdown"] +=
      "\n\n![Unknown](upload://qUm0DGR49PAZshIi7HxMd3cAlzn.png)"
    error = assert_raises(VibeForumLocal::Error) do
      VibeForumLocal::Envelope.validate!(undeclared)
    end
    assert_match(/require the manifest image/, error.message)
  end

  def test_manifest_rejects_duplicate_remote_or_raw_html_images_but_allows_code_examples
    duplicate = topic_payload_with_image
    duplicate["variants"]["en"]["body_markdown"] +=
      "\n\n![Duplicate](#{duplicate.dig("image", "short_url")})"
    error = assert_raises(VibeForumLocal::Error) do
      VibeForumLocal::Envelope.validate!(duplicate)
    end
    assert_match(/exactly the same manifest image/, error.message)

    [
      "![Remote](https://example.com/remote.png)",
      %q{<img src="https://example.com/remote.png">},
      "![Remote][proof]\n\n[proof]: https://example.com/remote.png",
    ].each do |markup|
      payload = Marshal.load(Marshal.dump(topic_payload))
      payload["variants"]["en"]["body_markdown"] += "\n\n#{markup}"
      error = assert_raises(VibeForumLocal::Error) do
        VibeForumLocal::Envelope.validate!(payload)
      end
      assert_match(/Rendered images require/, error.message)
    end

    code_example = Marshal.load(Marshal.dump(topic_payload))
    code_example["variants"]["en"]["body_markdown"] +=
      "\n\n```md\n![Example](https://example.com/not-rendered.png)\n```"
    assert_equal code_example, VibeForumLocal::Envelope.validate!(code_example)
  end

  def test_local_image_inspection_reports_exact_metadata_without_network
    with_image do |path|
      info = VibeForumLocal::Image.inspect_file(path)

      assert_equal "vibe-local-image/v1", info.fetch("schema")
      assert_equal File.basename(path), info.fetch("filename")
      assert_equal "image/png", info.fetch("media_type")
      assert_equal File.size(path), info.fetch("size_bytes")
      assert_equal Digest::SHA256.file(path).hexdigest, info.fetch("sha256")
    end
  end

  def test_local_image_inspection_rejects_unsupported_or_misleading_files
    with_image(extension: ".gif", bytes: "GIF89a".b) do |path|
      error = assert_raises(VibeForumLocal::Error) { VibeForumLocal::Image.inspect_file(path) }
      assert_match(/Only .png/, error.message)
    end

    with_image(extension: ".jpg") do |path|
      error = assert_raises(VibeForumLocal::Error) { VibeForumLocal::Image.inspect_file(path) }
      assert_match(/does not match/, error.message)
    end
  end

  def test_image_upload_shows_metadata_requires_confirmation_and_uses_the_same_narrow_key
    with_image do |path|
      response = {
        "id" => 77,
        "short_url" => "upload://qUm0DGR49PAZshIi7HxMd3cAlzn.png",
        "source_sha256" => Digest::SHA256.file(path).hexdigest,
      }
      output = StringIO.new
      client = FakeClient.new(response, get_response: site_info_response)
      uploader =
        VibeForumLocal::ImageUploader.new(
          credentials: credentials(user_api_key: "narrow-key"),
          input: StringIO.new("upload\n"),
          output: output,
          client: client,
        )

      assert_equal response,
                   uploader.upload(
                     file_path: path,
                     expected_sha256: Digest::SHA256.file(path).hexdigest,
                   )
      assert_includes output.string, File.basename(path)
      assert_includes output.string, Digest::SHA256.file(path).hexdigest
      assert_equal "/vibe-governance/site-info.json", client.calls.fetch(0).fetch(:path)
      call = client.calls.fetch(1)
      assert_equal "/vibe-governance/image-upload.json", call.fetch(:path)
      assert_equal "image/png", call.fetch(:content_type)
      assert_equal "narrow-key", call.dig(:headers, "User-Api-Key")
      assert_equal "0123456789abcdef0123456789abcdef", call.dig(:headers, "User-Api-Client-Id")
      assert_equal File.binread(path), call.fetch(:file_bytes)
    end
  end

  def test_image_upload_sends_the_confirmed_private_snapshot_if_the_source_path_changes
    with_image do |path|
      confirmed_bytes = File.binread(path)
      input =
        Object.new.tap do |object|
          object.define_singleton_method(:gets) do
            File.binwrite(path, "\x89PNG\r\n\x1a\nafter-confirmation".b)
            "upload\n"
          end
        end
      client =
        FakeClient.new(
          {
            "id" => 77,
            "short_url" => "upload://qUm0DGR49PAZshIi7HxMd3cAlzn.png",
            "source_sha256" => Digest::SHA256.hexdigest(confirmed_bytes),
          },
          get_response: site_info_response,
        )
      uploader =
        VibeForumLocal::ImageUploader.new(
          credentials: credentials,
          input: input,
          output: StringIO.new,
          client: client,
        )

      uploader.upload(
        file_path: path,
        expected_sha256: Digest::SHA256.hexdigest(confirmed_bytes),
      )

      assert_equal confirmed_bytes, client.calls.fetch(1).fetch(:file_bytes)
      refute_equal File.binread(path), client.calls.fetch(1).fetch(:file_bytes)
    end
  end

  def test_image_upload_does_not_write_without_exact_human_confirmation
    with_image do |path|
      client = FakeClient.new
      uploader =
        VibeForumLocal::ImageUploader.new(
          credentials: credentials,
          input: StringIO.new("no\n"),
          output: StringIO.new,
          client: client,
        )

      assert_raises(VibeForumLocal::Error) do
        uploader.upload(file_path: path, expected_sha256: Digest::SHA256.file(path).hexdigest)
      end
      assert_empty client.calls
    end
  end

  def test_image_upload_stops_before_confirmation_or_network_if_the_confirmed_hash_changed
    with_image do |path|
      client = FakeClient.new
      uploader =
        VibeForumLocal::ImageUploader.new(
          credentials: credentials,
          input: StringIO.new("upload\n"),
          output: StringIO.new,
          client: client,
        )

      error = assert_raises(VibeForumLocal::Error) do
        uploader.upload(file_path: path, expected_sha256: "0" * 64)
      end
      assert_match(/no longer matches/, error.message)
      assert_empty client.calls
    end
  end

  def test_image_upload_rejects_a_receipt_for_different_source_bytes
    with_image do |path|
      client =
        FakeClient.new(
          {
            "id" => 77,
            "short_url" => "upload://qUm0DGR49PAZshIi7HxMd3cAlzn.png",
            "source_sha256" => "0" * 64,
          },
          get_response: site_info_response,
        )
      uploader =
        VibeForumLocal::ImageUploader.new(
          credentials: credentials,
          input: StringIO.new("upload\n"),
          output: StringIO.new,
          client: client,
        )

      error = assert_raises(VibeForumLocal::Error) do
        uploader.upload(file_path: path, expected_sha256: Digest::SHA256.file(path).hexdigest)
      end
      assert_match(/does not match/, error.message)
    end
  end

  def test_manifest_requires_both_english_and_chinese
    payload = Marshal.load(Marshal.dump(topic_payload))
    payload["variants"].delete("zh-CN")

    error = assert_raises(VibeForumLocal::Error) do
      VibeForumLocal::Envelope.validate!(payload)
    end

    assert_match(/exactly en and zh-CN/, error.message)
  end

  def test_feature_request_is_optional_but_strict_and_only_for_new_topics
    payload = topic_payload_with_feature_request
    assert_equal payload, VibeForumLocal::Envelope.validate!(payload)

    missing_consent = Marshal.load(Marshal.dump(payload))
    missing_consent["feature_request"]["third_party_ai_processing_accepted"] = false
    error = assert_raises(VibeForumLocal::Error) do
      VibeForumLocal::Envelope.validate!(missing_consent)
    end
    assert_match(/explicit public-disclosure and third-party AI consent/, error.message)

    wrong_candidate = Marshal.load(Marshal.dump(payload))
    wrong_candidate["feature_request"]["candidate_kind"] = "general_chat"
    error = assert_raises(VibeForumLocal::Error) do
      VibeForumLocal::Envelope.validate!(wrong_candidate)
    end
    assert_match(/candidate_kind is unsupported/, error.message)

    reply = {
      "schema" => "vibe-publish/v3",
      "operation" => "reply",
      "source_locale" => "en",
      "target" => { "topic_id" => 11 },
      "variants" => {
        "en" => { "body_markdown" => "A sufficiently detailed English reply." },
        "zh-CN" => { "body_markdown" => "这是一条包含足够具体信息的中文回复。" },
      },
      "feature_request" => payload.fetch("feature_request"),
    }
    error = assert_raises(VibeForumLocal::Error) do
      VibeForumLocal::Envelope.validate!(reply)
    end
    assert_match(/only for a new topic/, error.message)
  end

  def test_reply_manifest_omits_titles_and_validates_reply_target
    payload = {
      "schema" => "vibe-publish/v3",
      "operation" => "reply",
      "source_locale" => "en",
      "target" => { "topic_id" => 11, "reply_to_post_number" => 1 },
      "variants" => {
        "en" => { "body_markdown" => "This fixes the mobile case." },
        "zh-CN" => { "body_markdown" => "这解决了移动端场景。" },
      },
    }

    assert_equal payload, VibeForumLocal::Envelope.validate!(payload)

    with_title = Marshal.load(Marshal.dump(payload))
    with_title["variants"]["en"]["title"] = "Not allowed"
    error = assert_raises(VibeForumLocal::Error) do
      VibeForumLocal::Envelope.validate!(with_title)
    end
    assert_match(/must omit title/, error.message)

    bad_target = Marshal.load(Marshal.dump(payload))
    bad_target["target"]["reply_to_post_number"] = 0
    error = assert_raises(VibeForumLocal::Error) do
      VibeForumLocal::Envelope.validate!(bad_target)
    end
    assert_match(/must be positive/, error.message)
  end

  def test_review_request_rejects_secrets_before_preview
    payload = Marshal.load(Marshal.dump(topic_payload))
    # Keep the detector exercise without committing a token-shaped literal.
    github_token_fixture = ["ghp", "12345678901234567890"].join("_")
    payload["variants"]["en"]["body_markdown"] = "Use token #{github_token_fixture}"

    error = assert_raises(VibeForumLocal::Error) do
      VibeForumLocal::Review.request(payload)
    end

    assert_match(/Possible secret/, error.message)
  end

  def test_doctor_is_read_only_and_reports_safe_https_credentials
    Dir.mktmpdir do |directory|
      path = File.join(directory, "credentials.json")
      VibeForumLocal::Credentials.save(
        {
          "site" => "https://forum.example.invalid",
          "user_api_key" => "secret-key-that-must-not-be-reported",
          "client_id" => "0123456789abcdef0123456789abcdef",
          "scope" => VibeForumLocal::SCOPE,
          "expires_at" => "2030-01-02T03:04:05Z",
        },
        path,
      )

      report =
        VibeForumLocal::Doctor.new(
          credentials_path: path,
          now: Time.iso8601("2029-01-01T00:00:00Z"),
        ).run

      assert_equal true, report.fetch("ok")
      assert_equal "https", report.dig("site", "transport")
      assert_equal true, report.dig("credentials", "scope_exact")
      assert_equal "valid", report.dig("credentials", "expiration")
      assert_equal false, report.fetch("network_requests_made")
      refute_includes JSON.generate(report), "secret-key-that-must-not-be-reported"
    end
  end

  def test_site_info_uses_the_narrow_key_and_validates_category_metadata
    client = FakeClient.new(site_info_response)
    info =
      VibeForumLocal::SiteInfo.new(
        credentials: credentials(user_api_key: "narrow-key"),
        client: client,
      ).fetch

    assert_equal "vibe-site-info/v1", info.fetch("schema")
    assert_equal "uncategorized", info.fetch("categories").first.fetch("slug")
    call = client.calls.fetch(0)
    assert_equal "/vibe-governance/site-info.json", call.fetch(:path)
    assert_equal "narrow-key", call.dig(:headers, "User-Api-Key")
    assert_equal "0123456789abcdef0123456789abcdef", call.dig(:headers, "User-Api-Client-Id")
  end

  def test_site_info_requires_complete_live_content_limits
    response = site_info_response
    response.fetch("content_limits").delete("min_post_length")

    error = assert_raises(VibeForumLocal::Error) do
      VibeForumLocal::SiteInfo.new(
        credentials: credentials(user_api_key: "narrow-key"),
        client: FakeClient.new(response),
      ).fetch
    end

    assert_match(/invalid content length limits/, error.message)
  end

  def test_site_info_requires_exact_schema_scope_and_canonical_site
    failures = {
      "wrong schema" => site_info_response.merge("schema" => "vibe-site-info/v2"),
      "wrong scope" => site_info_response.merge("scope" => "all"),
      "wrong site" => site_info_response(site_url: "https://other-forum.test"),
      "non-canonical site" => site_info_response(site_url: "https://forum.test/"),
    }

    failures.each do |label, response|
      client = FakeClient.new(response)
      assert_raises(VibeForumLocal::Error, label) do
        VibeForumLocal::SiteInfo.new(
          credentials: credentials(user_api_key: "narrow-key"),
          client: client,
        ).fetch
      end
      assert_equal ["/vibe-governance/site-info.json"], client.calls.map { |call| call.fetch(:path) }
    end
  end

  def test_publish_rechecks_server_scope_after_confirmation_and_before_write
    changed = site_info_response.merge("scope" => "all")
    client = FakeClient.new(get_response: [site_info_response, changed])

    error = assert_raises(VibeForumLocal::Error) do
      VibeForumLocal::Publisher.new(
        credentials: credentials,
        input: StringIO.new("publish\n"),
        output: StringIO.new,
        client: client,
      ).publish(payload: topic_payload, review_report: review_for(topic_payload))
    end

    assert_match(/wrong publishing scope/, error.message)
    assert_equal(
      ["/vibe-governance/site-info.json", "/vibe-governance/site-info.json"],
      client.calls.map { |call| call.fetch(:path) },
    )
  end

  def test_publish_rechecks_the_sole_internal_destination_after_confirmation
    changed = site_info_response.merge("categories" => [])
    client = FakeClient.new(get_response: [site_info_response, changed])

    error = assert_raises(VibeForumLocal::Error) do
      VibeForumLocal::Publisher.new(
        credentials: credentials,
        input: StringIO.new("publish\n"),
        output: StringIO.new,
        client: client,
      ).publish(payload: topic_payload, review_report: review_for(topic_payload))
    end

    assert_match(/exactly one internal publication destination/, error.message)
    assert_equal(
      ["/vibe-governance/site-info.json", "/vibe-governance/site-info.json"],
      client.calls.map { |call| call.fetch(:path) },
    )
  end

  def test_publish_rechecks_expiration_after_confirmation_and_before_write
    expired_time = Time.iso8601("2031-01-01T00:00:00Z")
    times = [
      Time.iso8601("2029-01-01T00:00:00Z"),
      Time.iso8601("2029-01-01T00:00:00Z"),
      expired_time,
    ]
    client = FakeClient.new(get_response: site_info_response)

    clock = -> { times.empty? ? expired_time : times.shift }
    error = assert_raises(VibeForumLocal::Error) do
      VibeForumLocal::Publisher.new(
        credentials: credentials(expires_at: "2030-01-01T00:00:00Z"),
        input: StringIO.new("publish\n"),
        output: StringIO.new,
        client: client,
        now: clock,
      ).publish(payload: topic_payload, review_report: review_for(topic_payload))
    end

    assert_match(/has expired/, error.message)
    assert_equal ["/vibe-governance/site-info.json"], client.calls.map { |call| call.fetch(:path) }
  end

  def test_image_upload_fails_closed_before_write_when_server_scope_changes
    with_image do |path|
      response = site_info_response.merge("scope" => "all")
      client = FakeClient.new(get_response: response)
      uploader =
        VibeForumLocal::ImageUploader.new(
          credentials: credentials,
          input: StringIO.new("upload\n"),
          output: StringIO.new,
          client: client,
        )

      assert_raises(VibeForumLocal::Error) do
        uploader.upload(
          file_path: path,
          expected_sha256: Digest::SHA256.file(path).hexdigest,
        )
      end
      assert_equal ["/vibe-governance/site-info.json"], client.calls.map { |call| call.fetch(:path) }
    end
  end

  def test_online_doctor_verifies_the_real_site_key_scope_and_categories
    Dir.mktmpdir do |directory|
      path = File.join(directory, "credentials.json")
      VibeForumLocal::Credentials.save(
        {
          "site" => "https://forum.test",
          "user_api_key" => "secret-key-that-must-not-be-reported",
          "client_id" => "0123456789abcdef0123456789abcdef",
          "scope" => VibeForumLocal::SCOPE,
          "expires_at" => "2030-01-02T03:04:05Z",
        },
        path,
      )

      report =
        VibeForumLocal::Doctor.new(
          credentials_path: path,
          now: Time.iso8601("2029-01-01T00:00:00Z"),
          site_info_client: FakeClient.new(site_info_response),
        ).run(online: true)

      assert_equal true, report.fetch("ok")
      assert_equal true, report.fetch("network_requests_made")
      assert_equal "verified", report.dig("online", "state")
      assert_equal true, report.dig("checks", "site_reachable")
      assert_equal true, report.dig("checks", "key_accepted")
      assert_equal true, report.dig("checks", "server_scope_exact")
      assert_equal "uncategorized", report.dig("online", "site_info", "categories", 0, "slug")
      refute_includes JSON.generate(report), "secret-key-that-must-not-be-reported"
    end
  end

  def test_doctor_marks_legacy_credentials_for_reauthorization_without_network
    Dir.mktmpdir do |directory|
      path = File.join(directory, "credentials.json")
      legacy = credentials(user_api_key: "legacy-secret-key")
      legacy.delete("client_id")
      write_credentials(path, legacy)
      client = FakeClient.new(site_info_response)

      report =
        VibeForumLocal::Doctor.new(
          credentials_path: path,
          now: Time.iso8601("2029-01-01T00:00:00Z"),
          site_info_client: client,
        ).run(online: true)

      assert_equal false, report.fetch("ok")
      assert_equal "reauthorization_required", report.dig("credentials", "state")
      assert_equal false, report.dig("credentials", "installation_client_id_present")
      assert_equal false, report.dig("checks", "credential_client_id_present")
      assert_equal "reauthorization_required", report.dig("online", "state")
      assert_equal false, report.fetch("network_requests_made")
      assert_empty client.calls
      refute_includes JSON.generate(report), "legacy-secret-key"
    end
  end

  def test_online_doctor_accepts_equivalent_loopback_hostnames_on_the_same_port
    Dir.mktmpdir do |directory|
      path = File.join(directory, "credentials.json")
      VibeForumLocal::Credentials.save(
        {
          "site" => "http://127.0.0.1:3000",
          "user_api_key" => "secret-key",
          "client_id" => "0123456789abcdef0123456789abcdef",
          "scope" => VibeForumLocal::SCOPE,
          "expires_at" => "2030-01-02T03:04:05Z",
        },
        path,
        allow_loopback_http: true,
      )
      response = site_info_response.merge("site_url" => "http://localhost:3000")

      report =
        VibeForumLocal::Doctor.new(
          credentials_path: path,
          now: Time.iso8601("2029-01-01T00:00:00Z"),
          site_info_client: FakeClient.new(response),
          allow_loopback_http: true,
        ).run(online: true)

      assert_equal true, report.fetch("ok")
      assert_equal "verified", report.dig("online", "state")
      assert_equal true, report.dig("checks", "server_site_matches_credentials")
    end
  end

  def test_online_doctor_rejects_a_loopback_site_on_a_different_port
    Dir.mktmpdir do |directory|
      path = File.join(directory, "credentials.json")
      VibeForumLocal::Credentials.save(
        {
          "site" => "http://127.0.0.1:3000",
          "user_api_key" => "secret-key",
          "client_id" => "0123456789abcdef0123456789abcdef",
          "scope" => VibeForumLocal::SCOPE,
          "expires_at" => "2030-01-02T03:04:05Z",
        },
        path,
        allow_loopback_http: true,
      )
      response = site_info_response.merge("site_url" => "http://localhost:4000")

      report =
        VibeForumLocal::Doctor.new(
          credentials_path: path,
          now: Time.iso8601("2029-01-01T00:00:00Z"),
          site_info_client: FakeClient.new(response),
          allow_loopback_http: true,
        ).run(online: true)

      assert_equal false, report.fetch("ok")
      assert_equal "site_mismatch", report.dig("online", "state")
      assert_equal false, report.dig("checks", "server_site_matches_credentials")
    end
  end

  def test_online_doctor_is_unhealthy_when_the_authenticated_probe_fails
    Dir.mktmpdir do |directory|
      path = File.join(directory, "credentials.json")
      VibeForumLocal::Credentials.save(
        {
          "site" => "https://forum.test",
          "user_api_key" => "secret-key",
          "client_id" => "0123456789abcdef0123456789abcdef",
          "scope" => VibeForumLocal::SCOPE,
          "expires_at" => "2030-01-02T03:04:05Z",
        },
        path,
      )

      report =
        VibeForumLocal::Doctor.new(
          credentials_path: path,
          now: Time.iso8601("2029-01-01T00:00:00Z"),
          site_info_client: FailingClient.new,
        ).run(online: true)

      assert_equal false, report.fetch("ok")
      assert_equal true, report.fetch("network_requests_made")
      assert_equal "failed", report.dig("online", "state")
      assert_equal false, report.dig("checks", "site_reachable")
      assert_equal false, report.dig("checks", "key_accepted")
    end
  end

  def test_doctor_returns_a_structured_unhealthy_report_before_authorization
    Dir.mktmpdir do |directory|
      path = File.join(directory, "missing-credentials.json")

      report =
        VibeForumLocal::Doctor.new(
          credentials_path: path,
          allow_loopback_http: true,
        ).run(
          site: "http://127.0.0.1:3000",
        )

      assert_equal false, report.fetch("ok")
      assert_equal "loopback-http", report.dig("site", "transport")
      assert_equal "missing", report.dig("credentials", "state")
      assert_equal "unknown", report.dig("credentials", "expiration")
      assert_equal false, report.dig("credentials", "scope_exact")
      assert_equal false, report.fetch("network_requests_made")
    end
  end

  def test_doctor_rejects_expired_wrong_scope_and_remote_http_credentials
    Dir.mktmpdir do |directory|
      path = File.join(directory, "credentials.json")
      write_credentials(
        path,
        credentials(
          site: "http://forum.example.invalid",
          user_api_key: "secret-key",
          scope: "all",
          expires_at: "2028-01-01T00:00:00Z",
        ),
      )

      report =
        VibeForumLocal::Doctor.new(
          credentials_path: path,
          now: Time.iso8601("2029-01-01T00:00:00Z"),
        ).run

      assert_equal false, report.fetch("ok")
      assert_equal "invalid", report.dig("site", "transport")
      assert_equal false, report.dig("credentials", "scope_exact")
      assert_equal "expired", report.dig("credentials", "expiration")
    end
  end

  def test_logout_revokes_current_key_before_removing_local_credentials
    Dir.mktmpdir do |directory|
      path = File.join(directory, "credentials.json")
      VibeForumLocal::Credentials.save(
        credentials(user_api_key: "secret-key"),
        path,
      )
      client = FakeClient.new({ "success" => "OK" }, get_response: site_info_response)

      result =
        VibeForumLocal::CredentialRevoker.new(credentials_path: path, client: client).revoke!

      assert_equal true, result.fetch("revoked")
      refute File.exist?(path)
      assert_equal "/vibe-governance/site-info.json", client.calls.fetch(0).fetch(:path)
      call = client.calls.fetch(1)
      assert_equal "/user-api-key/revoke.json", call.fetch(:path)
      assert_equal "secret-key", call.dig(:headers, "User-Api-Key")
      assert_equal "0123456789abcdef0123456789abcdef", call.dig(:headers, "User-Api-Client-Id")
    end
  end

  def test_logout_keeps_local_credentials_when_revocation_fails
    Dir.mktmpdir do |directory|
      path = File.join(directory, "credentials.json")
      VibeForumLocal::Credentials.save(
        credentials(user_api_key: "secret-key"),
        path,
      )

      error = assert_raises(VibeForumLocal::Error) do
        VibeForumLocal::CredentialRevoker.new(
          credentials_path: path,
          client: FailingClient.new,
        ).revoke!
      end

      assert_match(/local credentials were kept/, error.message)
      assert File.exist?(path)
      assert_equal "secret-key", VibeForumLocal::Credentials.load(path).fetch("user_api_key")
    end
  end

  def test_logout_fails_closed_before_revocation_when_server_scope_changes
    Dir.mktmpdir do |directory|
      path = File.join(directory, "credentials.json")
      VibeForumLocal::Credentials.save(credentials(user_api_key: "secret-key"), path)
      client =
        FakeClient.new(
          { "success" => "OK" },
          get_response: site_info_response.merge("scope" => "all"),
        )

      error = assert_raises(VibeForumLocal::Error) do
        VibeForumLocal::CredentialRevoker.new(
          credentials_path: path,
          client: client,
        ).revoke!
      end

      assert_match(/local credentials were kept/, error.message)
      assert File.exist?(path)
      assert_equal ["/vibe-governance/site-info.json"], client.calls.map { |call| call.fetch(:path) }
    end
  end
end
