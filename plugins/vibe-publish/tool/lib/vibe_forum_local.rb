# frozen_string_literal: true

require "base64"
require "digest"
require "fileutils"
require "json"
require "net/http"
require "openssl"
require "securerandom"
require "socket"
require "tempfile"
require "time"
require "uri"

module VibeForumLocal
  VERSION_FILE = File.expand_path("../VERSION", __dir__)
  VERSION = File.read(VERSION_FILE, encoding: "UTF-8").strip
  SCOPE = "vibe-governance:publish"
  REVIEW_SCHEMA = "vibe-local-review/v1"
  DEFAULT_CREDENTIALS = File.expand_path("~/.config/vibe-forum/credentials.json")
  DEFAULT_CLIENT_ID = File.expand_path("~/.config/vibe-forum/client-id")

  class Error < StandardError
  end

  class SiteMismatchError < Error
  end

  module SiteAddress
    LOOPBACK_HOSTS = ["localhost", "127.0.0.1", "::1"].freeze

    module_function

    def canonical(value, allow_loopback_http: false)
      uri = parse(value, allow_loopback_http: allow_loopback_http)
      host = uri.hostname.downcase
      rendered_host = host.include?(":") ? "[#{host}]" : host
      default_port = uri.scheme == "https" ? 443 : 80
      rendered_port = uri.port == default_port ? "" : ":#{uri.port}"
      "#{uri.scheme}://#{rendered_host}#{rendered_port}"
    end

    def equivalent?(left, right, allow_loopback_http: false)
      identity(left, allow_loopback_http: allow_loopback_http) ==
        identity(right, allow_loopback_http: allow_loopback_http)
    rescue Error
      false
    end

    def parse(value, allow_loopback_http: false)
      raise Error, "Site URL is required" if value.to_s.empty?

      uri = URI(value.to_s)
      raise Error, "Site URL must include a hostname" if uri.hostname.to_s.empty?
      raise Error, "Site URL must not contain user credentials" unless uri.userinfo.nil?
      raise Error, "Site URL must not contain a query or fragment" unless uri.query.nil? && uri.fragment.nil?
      unless uri.path.to_s.empty? || uri.path == "/"
        raise Error, "Site URL must be the canonical forum origin without a path"
      end

      host = uri.hostname.downcase
      if uri.scheme == "https"
        return uri
      elsif uri.scheme == "http" && LOOPBACK_HOSTS.include?(host)
        unless allow_loopback_http
          raise Error,
                "Loopback HTTP requires the explicit --allow-loopback-http development option"
        end

        return uri
      end

      raise Error, "Remote forum URLs must use HTTPS"
    rescue URI::InvalidURIError, URI::InvalidComponentError => e
      raise Error, "Site URL is invalid: #{e.message}"
    end

    def identity(value, allow_loopback_http: false)
      uri = parse(value, allow_loopback_http: allow_loopback_http)
      host = uri.hostname.downcase
      host = "loopback" if LOOPBACK_HOSTS.include?(host)
      [uri.scheme, host, uri.port]
    end
  end

  module Envelope
    SCHEMA = "vibe-publish/v3"
    LEGACY_SCHEMA = "vibe-publish/v2"
    SCHEMAS = [LEGACY_SCHEMA, SCHEMA].freeze
    FEATURE_REQUEST_SCHEMA = "vibe-feature-request/v1"
    FEATURE_CANDIDATE_KINDS = %w[
      build_log
      problem_solution
      open_source
      tool_method
      failure_lesson
    ].freeze
    FEATURE_REQUEST_KEYS = %w[
      candidate_kind
      local_skill_version
      precheck_result
      public_disclosure_accepted
      requested
      schema
      third_party_ai_processing_accepted
    ].freeze
    OPERATIONS = %w[create_topic reply edit_post].freeze
    LOCALES = %w[en zh-CN].freeze
    UPLOAD_REFERENCE_PATTERN = %r{upload://[^\s<>"'\)\]]+}
    MARKDOWN_IMAGE_PATTERN = /!\[[^\]\n]*\]\(\s*<?([^>\s\)]+)>?(?:\s+["'][^"'\n]*["'])?\s*\)/
    REFERENCE_IMAGE_PATTERN = /!\[[^\]\n]*\]\s*\[[^\]\n]*\]/
    HTML_MEDIA_PATTERN = /<\s*(?:img|picture|source)\b/i
    FENCED_CODE_PATTERN = /(?:\A|\n)[ \t]{0,3}(?:`{3,}|~{3,})[^\n]*\n.*?(?:(?:\n)[ \t]{0,3}(?:`{3,}|~{3,})[ \t]*(?=\n|\z)|\z)/m
    INLINE_CODE_PATTERN = /(`+)[^`\n]*\1/

    module_function

    def validate!(payload)
      raise Error, "Publication manifest must be a JSON object" if !payload.is_a?(Hash)
      raise Error, "Publication manifest must use #{SCHEMA}" if payload["schema"] != SCHEMA
      unless OPERATIONS.include?(payload["operation"])
        raise Error, "Operation must be create_topic, reply, or edit_post"
      end
      raise Error, "source_locale must be en or zh-CN" if !LOCALES.include?(payload["source_locale"])

      variants = payload["variants"]
      if !variants.is_a?(Hash) || variants.keys.sort != LOCALES.sort
        raise Error, "variants must contain exactly en and zh-CN"
      end

      title_mode = title_mode(variants, operation: payload["operation"])
      variants.each_value do |variant|
        if !variant.is_a?(Hash) || variant["body_markdown"].to_s.strip.empty?
          raise Error, "Every language variant needs body_markdown"
        end

        if title_mode == :required && variant["title"].to_s.strip.empty?
          raise Error, "Every topic language variant needs a title"
        elsif title_mode == :forbidden && variant.key?("title")
          raise Error, "Reply language variants and reply edits must omit title"
        end
      end

      validate_image!(payload["image"], variants)
      validate_feature_request!(payload["feature_request"], operation: payload["operation"])

      target = payload["target"]
      raise Error, "Publication manifest needs a target" if !target.is_a?(Hash)
      if payload["operation"] == "create_topic"
        has_category_id = target.key?("category_id") && !target["category_id"].nil?
        category_slug = target["category_slug"].to_s.strip
        if has_category_id == !category_slug.empty?
          raise Error, "create_topic target needs exactly one of category_id or category_slug"
        end
        if has_category_id && target["category_id"].to_i <= 0
          raise Error, "create_topic category_id must be positive"
        end
        if !category_slug.empty? && (category_slug.length > 200 || category_slug.include?("/"))
          raise Error, "create_topic category_slug must be one category slug"
        end
      elsif payload["operation"] == "reply"
        raise Error, "reply target needs topic_id" if target["topic_id"].to_i <= 0
        if target.key?("reply_to_post_number") && target["reply_to_post_number"].to_i <= 0
          raise Error, "reply_to_post_number must be positive"
        end
      else
        unless target.keys.sort == %w[expected_version post_id]
          raise Error, "edit_post target must contain exactly post_id and expected_version"
        end
        raise Error, "edit_post post_id must be positive" if target["post_id"].to_i <= 0
        if target["expected_version"].to_i <= 0
          raise Error, "edit_post expected_version must be positive"
        end
      end

      payload
    end

    def validate_live_limits!(payload, limits)
      title_requirement = title_mode(payload.fetch("variants"), operation: payload.fetch("operation"))
      body_minimum_key =
        title_requirement == :required ? "min_first_post_length" : "min_post_length"
      body_context = title_requirement == :required ? "topic body" : "reply body"

      payload.fetch("variants").each do |locale, variant|
        validate_live_field_length!(
          variant.fetch("body_markdown").to_s.strip,
          locale: locale,
          field: "body_markdown",
          context: body_context,
          minimum: limits.fetch(body_minimum_key),
          maximum: limits.fetch("max_post_length"),
        )

        next unless title_requirement == :required

        validate_live_field_length!(
          variant.fetch("title").to_s.strip,
          locale: locale,
          field: "title",
          context: "topic title",
          minimum: limits.fetch("min_topic_title_length"),
          maximum: limits.fetch("max_topic_title_length"),
        )
      end

      payload
    end

    def validate_live_field_length!(value, locale:, field:, context:, minimum:, maximum:)
      return if value.length.between?(minimum, maximum)

      raise Error,
            "#{locale} #{field} is #{value.length} characters; the live forum requires " \
              "#{minimum}..#{maximum} for a #{context}. Update that language version, " \
              "regenerate its local review, and try again; no publication was sent"
    end

    def title_mode(variants, operation:)
      return :required if operation == "create_topic"
      return :forbidden if operation == "reply"

      title_presence =
        LOCALES.map do |locale|
          variant = variants.fetch(locale)
          variant.is_a?(Hash) && variant.key?("title") && !variant["title"].to_s.strip.empty?
        end
      unless title_presence.uniq.length == 1
        raise Error, "edit_post must include titles in both variants or omit them from both"
      end

      title_presence.first ? :required : :forbidden
    end

    def validate_image!(image, variants)
      visible_variants = variants.transform_values do |variant|
        visible_media_markup(variant.fetch("body_markdown"))
      end
      references = visible_variants.transform_values do |raw|
        raw.scan(UPLOAD_REFERENCE_PATTERN)
      end
      markdown_images = visible_variants.transform_values do |raw|
        raw.scan(MARKDOWN_IMAGE_PATTERN).flatten
      end

      if image.nil?
        if references.values.any?(&:any?) || markdown_images.values.any?(&:any?) ||
             visible_variants.values.any? { |raw| raw.match?(REFERENCE_IMAGE_PATTERN) || raw.match?(HTML_MEDIA_PATTERN) }
          raise Error, "Rendered images require the manifest image object"
        end
        return
      end

      unless image.is_a?(Hash) && image.keys.sort == %w[short_url upload_id]
        raise Error, "image must contain exactly upload_id and short_url"
      end
      raise Error, "image upload_id must be positive" if image["upload_id"].to_i <= 0

      short_url = image["short_url"].to_s
      unless short_url.match?(%r{\Aupload://[A-Za-z0-9]+\.(?:png|jpe?g)\z}i)
        raise Error, "image short_url must be the PNG or JPEG upload:// URL returned by the forum"
      end

      unless references.values.all? { |locale_references| locale_references == [short_url] } &&
               markdown_images.values.all? { |targets| targets == [short_url] } &&
               visible_variants.values.none? do |raw|
                 raw.match?(REFERENCE_IMAGE_PATTERN) || raw.match?(HTML_MEDIA_PATTERN)
               end
        raise Error, "Every language variant must reference exactly the same manifest image"
      end
    end

    def validate_feature_request!(request, operation:)
      return if request.nil?

      unless operation == "create_topic"
        raise Error, "feature_request is supported only for a new topic"
      end
      unless request.is_a?(Hash) && request.keys.sort == FEATURE_REQUEST_KEYS.sort
        raise Error, "feature_request must contain exactly the v1 consent and precheck fields"
      end
      unless request["schema"] == FEATURE_REQUEST_SCHEMA && request["requested"] == true
        raise Error, "feature_request must be an explicit #{FEATURE_REQUEST_SCHEMA} request"
      end
      unless FEATURE_CANDIDATE_KINDS.include?(request["candidate_kind"])
        raise Error, "feature_request candidate_kind is unsupported"
      end

      skill_version = request["local_skill_version"].to_s.strip
      if skill_version.empty? || skill_version.length > 64
        raise Error, "feature_request local_skill_version must contain 1..64 characters"
      end
      unless request["precheck_result"] == "passed"
        raise Error, "feature_request requires a passed local precheck"
      end
      unless request["public_disclosure_accepted"] == true &&
               request["third_party_ai_processing_accepted"] == true
        raise Error, "feature_request requires explicit public-disclosure and third-party AI consent"
      end
    end

    def visible_media_markup(raw)
      raw.to_s.gsub(FENCED_CODE_PATTERN, "\n").gsub(INLINE_CODE_PATTERN, "")
    end
  end

  class HttpClient
    LOOPBACK_HOSTS = SiteAddress::LOOPBACK_HOSTS

    def initialize(site, allow_loopback_http: false)
      @site = URI(SiteAddress.canonical(site, allow_loopback_http: allow_loopback_http))
    end

    def post(path, payload, headers = {})
      uri = URI.join(normalized_site, path)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/json"
      headers.each { |name, value| request[name] = value }
      request.body = JSON.generate(payload)

      perform(uri, request)
    end

    def get(path, headers = {})
      uri = URI.join(normalized_site, path)
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"
      headers.each { |name, value| request[name] = value }

      perform(uri, request)
    end

    def post_multipart(path, file_io:, filename:, content_type:, headers: {})
      uri = URI.join(normalized_site, path)
      request = Net::HTTP::Post.new(uri)
      request["Accept"] = "application/json"
      headers.each { |name, value| request[name] = value }

      file_io.rewind
      request.set_form(
        [["file", file_io, { filename: filename, content_type: content_type }]],
        "multipart/form-data",
      )
      perform(uri, request)
    end

    private

    def perform(uri, request)

      response =
        Net::HTTP.start(
          uri.hostname,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: 10,
          read_timeout: 30,
        ) { |http| http.request(request) }

      body = response.body.to_s.empty? ? {} : JSON.parse(response.body)
      return body if response.is_a?(Net::HTTPSuccess)

      detail = body["errors"] || body["error"] || response.message
      raise Error,
            "Forum returned HTTP #{response.code}: #{redact(Array(detail).join('; '), request)}"
    rescue JSON::ParserError
      raise Error, "Forum returned invalid JSON"
    rescue SystemCallError, SocketError, Net::OpenTimeout, Net::ReadTimeout,
           OpenSSL::SSL::SSLError => e
      raise Error, "Could not reach forum: #{e.message}"
    end

    def normalized_site
      value = @site.to_s
      value.end_with?("/") ? value : "#{value}/"
    end

    def redact(value, request)
      redacted = value.to_s.dup
      [request["User-Api-Key"]].compact.each do |secret|
        redacted.gsub!(secret, "[REDACTED]") unless secret.empty?
      end
      redacted.gsub!(/\bsk-[A-Za-z0-9_-]{20,}\b/, "[REDACTED]")
      redacted.gsub!(/\bgh[pousr]_[A-Za-z0-9]{20,}\b/, "[REDACTED]")
      redacted
    end
  end

  module Image
    SCHEMA = "vibe-local-image/v1"
    MAX_BYTES = 10 * 1024 * 1024
    EXTENSION_TYPES = {
      ".png" => "image/png",
      ".jpg" => "image/jpeg",
      ".jpeg" => "image/jpeg",
    }.freeze

    module_function

    def inspect_file(path)
      expanded = File.expand_path(path.to_s)
      raise Error, "Image file does not exist: #{path}" unless File.file?(expanded)
      raise Error, "Image file is not readable: #{path}" unless File.readable?(expanded)

      filename = File.basename(expanded)
      extension = File.extname(filename).downcase
      expected_type = EXTENSION_TYPES[extension]
      raise Error, "Only .png, .jpg, or .jpeg files are supported" unless expected_type

      size = File.size(expanded)
      raise Error, "Image file is empty" if size <= 0
      raise Error, "Image exceeds the 10 MiB publishing limit" if size > MAX_BYTES

      media_type = sniff_media_type(expanded)
      raise Error, "File content is not a PNG or JPEG image" unless media_type
      raise Error, "Image filename extension does not match its content" unless media_type == expected_type

      {
        "schema" => SCHEMA,
        "filename" => filename,
        "media_type" => media_type,
        "size_bytes" => size,
        "sha256" => Digest::SHA256.file(expanded).hexdigest,
      }
    end

    def sniff_media_type(path)
      bytes = File.binread(path, 12)
      return "image/png" if bytes.start_with?("\x89PNG\r\n\x1a\n".b)
      return "image/jpeg" if bytes.start_with?("\xFF\xD8\xFF".b)

      nil
    end

    def with_private_snapshot(path)
      source_path = File.expand_path(path.to_s)
      source_info = inspect_file(source_path)
      snapshot = Tempfile.new(["vibe-forum-image-", File.extname(source_info.fetch("filename"))])
      snapshot.binmode
      snapshot.chmod(0o600)

      File.open(source_path, "rb") do |source|
        IO.copy_stream(source, snapshot)
      end
      snapshot.flush
      snapshot.rewind

      snapshot_info = inspect_file(snapshot.path)
      snapshot_info["filename"] = source_info.fetch("filename")
      snapshot.rewind
      yield snapshot, snapshot_info
    rescue SystemCallError => e
      raise Error, "Could not create a private image snapshot: #{e.message}"
    ensure
      snapshot&.close!
    end
  end

  class Credentials
    BACKEND_KEYCHAIN = "macos-keychain"
    BACKEND_FILE = "posix-file"
    KEYCHAIN_UNSUPPORTED_MESSAGE =
      "Keychain credential storage is not supported in this alpha; use auto or file"

    def self.load(
      path = DEFAULT_CREDENTIALS,
      now: Time.now,
      allow_loopback_http: false
    )
      metadata = JSON.parse(read_secure(path))
      reject_keychain_metadata!(metadata)
      validate_data!(metadata, now: now, allow_loopback_http: allow_loopback_http)
    rescue Errno::ENOENT
      raise Error, "No credentials at #{path}; run `vibe-forum auth --site URL` first"
    rescue JSON::ParserError
      raise Error, "Credential file is invalid JSON"
    rescue SystemCallError => e
      raise Error, "Could not securely read credential file #{path}: #{e.class}"
    end

    def self.validate_data!(data, now: Time.now, allow_loopback_http: false)
      raise Error, "Credential data must be a JSON object" unless data.is_a?(Hash)
      raise Error, "Credential file has no site" if data["site"].to_s.empty?
      raise Error, "Credential file has no User API Key" if data["user_api_key"].to_s.empty?
      unless data["client_id"].to_s.match?(/\A[0-9a-f]{32}\z/)
        raise Error, "Credential file has no valid installation client ID"
      end
      unless data["scope"] == SCOPE
        raise Error, "Credential scope must be exactly #{SCOPE}"
      end

      expires_at = data["expires_at"].to_s
      raise Error, "Credential file has no expiration" if expires_at.empty?

      expiration = Time.iso8601(expires_at)
      raise Error, "Publishing credential has expired" if expiration <= now

      canonical_site =
        SiteAddress.canonical(
          data.fetch("site"),
          allow_loopback_http: allow_loopback_http,
        )
      unless data.fetch("site") == canonical_site
        raise Error, "Credential site must use the canonical URL #{canonical_site}"
      end

      data.merge(
        "site" => canonical_site,
        "expires_at" => expiration.iso8601,
      )
    rescue ArgumentError
      raise Error, "Credential expiration is not a valid ISO-8601 timestamp"
    end

    def self.file_security(path)
      stat = File.lstat(path)
      mode = stat.mode & 0o7777
      {
        "regular_file" => stat.file?,
        "symlink" => stat.symlink?,
        "owner_current_user" => stat.uid == Process.uid,
        "permissions" => format("%04o", mode),
        "permissions_exact" => mode == 0o600,
        "device" => stat.dev,
        "inode" => stat.ino,
      }
    end

    def self.read_secure(path)
      before = file_security(path)
      validate_file_security!(before)

      flags = File::RDONLY
      flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
      File.open(path, flags) do |file|
        current = file.stat
        after = {
          "regular_file" => current.file?,
          "symlink" => false,
          "owner_current_user" => current.uid == Process.uid,
          "permissions" => format("%04o", current.mode & 0o7777),
          "permissions_exact" => (current.mode & 0o7777) == 0o600,
          "device" => current.dev,
          "inode" => current.ino,
        }
        validate_file_security!(after)
        unless before.values_at("device", "inode") == after.values_at("device", "inode")
          raise Error, "Credential file changed while it was being opened"
        end

        file.read
      end
    rescue Errno::ELOOP
      raise Error, "Credential path must not be a symbolic link"
    end

    def self.validate_file_security!(security)
      raise Error, "Credential path must not be a symbolic link" if security["symlink"]
      raise Error, "Credential path must be a regular file" unless security["regular_file"]
      unless security["owner_current_user"]
        raise Error, "Credential file must be owned by the current user"
      end
      unless security["permissions_exact"]
        raise Error, "Credential file permissions must be exactly 0600"
      end

      security
    end

    def self.validate_existing_path!(path)
      validate_file_security!(file_security(path))
    rescue Errno::ENOENT
      true
    end

    def self.save(
      data,
      path = DEFAULT_CREDENTIALS,
      now: Time.now,
      allow_loopback_http: false,
      backend: nil
    )
      selected_backend = resolve_backend(backend)
      validated = validate_data!(data, now: now, allow_loopback_http: allow_loopback_http)
      metadata = validated.merge("credential_backend" => selected_backend)
      write_metadata(metadata, path)
      path
    end

    def self.write_metadata(data, path)
      directory = File.dirname(path)
      directory_created = !Dir.exist?(directory)
      FileUtils.mkdir_p(directory, mode: 0o700)
      File.chmod(0o700, directory) if directory_created

      temporary = "#{path}.tmp-#{SecureRandom.hex(4)}"
      File.write(temporary, JSON.pretty_generate(data) + "\n", mode: "w", perm: 0o600)
      File.rename(temporary, path)
      File.chmod(0o600, path)
      validate_file_security!(file_security(path))
      path
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary
    end

    def self.delete(path = DEFAULT_CREDENTIALS)
      metadata = JSON.parse(read_secure(path))
      reject_keychain_metadata!(metadata)
      File.delete(path)
      path
    rescue Errno::ENOENT
      raise Error, "Credential file disappeared before it could be removed: #{path}"
    rescue JSON::ParserError
      raise Error, "Credential file is invalid JSON"
    rescue SystemCallError => e
      raise Error, "Could not remove credential file #{path}: #{e.class}"
    end

    def self.reject_keychain_metadata!(metadata)
      return metadata unless metadata["credential_backend"] == BACKEND_KEYCHAIN

      raise Error,
            "This credential uses retired Keychain storage; authorize again with auto or file"
    end

    def self.resolve_backend(value)
      case value.to_s
      when "", "auto", "file", BACKEND_FILE
        BACKEND_FILE
      when "keychain", BACKEND_KEYCHAIN
        raise Error, KEYCHAIN_UNSUPPORTED_MESSAGE
      else
        raise Error, "Credential backend must be auto or file"
      end
    end
  end

  class InstallationIdentity
    VALUE_PATTERN = /\A[0-9a-f]{32}\z/

    def self.path_for(credentials_path)
      return DEFAULT_CLIENT_ID if File.expand_path(credentials_path) == DEFAULT_CREDENTIALS

      File.join(File.dirname(File.expand_path(credentials_path)), "client-id")
    end

    def self.load_or_create(path, random: SecureRandom)
      begin
        value = Credentials.read_secure(path).strip
        raise Error, "Installation client ID is invalid" unless value.match?(VALUE_PATTERN)

        return value
      rescue Errno::ENOENT
        # Create it below.
      end

      directory = File.dirname(path)
      directory_created = !Dir.exist?(directory)
      FileUtils.mkdir_p(directory, mode: 0o700)
      File.chmod(0o700, directory) if directory_created
      value = random.hex(16)
      temporary = "#{path}.tmp-#{SecureRandom.hex(4)}"
      File.write(temporary, "#{value}\n", mode: "w", perm: 0o600)
      File.rename(temporary, path)
      File.chmod(0o600, path)
      Credentials.validate_file_security!(Credentials.file_security(path))
      value
    rescue SystemCallError => e
      raise Error, "Could not securely persist the installation client ID: #{e.class}"
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary
    end
  end

  module UserApiHeaders
    module_function

    def for(credentials)
      {
        "User-Api-Key" => credentials.fetch("user_api_key"),
        "User-Api-Client-Id" => credentials.fetch("client_id"),
      }
    end
  end

  class SiteInfo
    SCHEMA = "vibe-site-info/v1"
    CONTENT_LIMIT_KEYS = %w[
      min_post_length
      min_first_post_length
      max_post_length
      min_topic_title_length
      max_topic_title_length
    ].freeze

    def initialize(
      credentials:,
      client: nil,
      now: Time.now,
      allow_loopback_http: false
    )
      @allow_loopback_http = allow_loopback_http
      @credentials =
        Credentials.validate_data!(
          credentials,
          now: now,
          allow_loopback_http: allow_loopback_http,
        )
      @client =
        client || HttpClient.new(
          @credentials.fetch("site"),
          allow_loopback_http: allow_loopback_http,
        )
    end

    def fetch
      response =
        @client.get(
          "/vibe-governance/site-info.json",
          UserApiHeaders.for(@credentials),
        )
      validate!(response)
    end

    private

    def validate!(response)
      raise Error, "Forum site-info response must be a JSON object" if !response.is_a?(Hash)
      raise Error, "Forum does not expose #{SCHEMA}" if response["schema"] != SCHEMA
      raise Error, "Forum site-info identified an unexpected plugin" if response["plugin"] != "vibe-governance"
      raise Error, "Forum site-info returned the wrong publishing scope" if response["scope"] != SCOPE
      if response["publish_schema"] != Envelope::SCHEMA
        raise Error, "Forum site-info returned an unsupported publishing schema"
      end
      unless response["accepted_publish_schemas"].is_a?(Array) &&
               response["accepted_publish_schemas"].sort == Envelope::SCHEMAS.sort
        raise Error, "Forum site-info returned an unexpected publishing compatibility set"
      end
      unless response["publish_operations"].is_a?(Array) &&
               response["publish_operations"].sort == Envelope::OPERATIONS.sort
        raise Error, "Forum site-info does not support every required publishing operation"
      end
      if response["edit_info_schema"] != EditInfo::SCHEMA
        raise Error, "Forum site-info returned an unsupported edit-info schema"
      end
      raise Error, "Forum site-info has no canonical site URL" if response["site_url"].to_s.empty?
      canonical_server_site =
        SiteAddress.canonical(
          response["site_url"],
          allow_loopback_http: @allow_loopback_http,
        )
      unless response["site_url"] == canonical_server_site
        raise Error, "Forum site-info returned a non-canonical site URL"
      end
      unless SiteAddress.equivalent?(
               canonical_server_site,
               @credentials.fetch("site"),
               allow_loopback_http: @allow_loopback_http,
             )
        raise SiteMismatchError, "Forum site-info canonical site does not match the credential site"
      end
      unless response["locales"].is_a?(Array) &&
               response["locales"].sort == Envelope::LOCALES.sort
        raise Error, "Forum site-info returned unsupported publishing locales"
      end
      feature = response["feature_request"]
      unless feature.is_a?(Hash) && [true, false].include?(feature["enabled"]) &&
               feature["schema"] == Envelope::FEATURE_REQUEST_SCHEMA &&
               feature["candidate_kinds"].is_a?(Array) &&
               feature["candidate_kinds"].sort == Envelope::FEATURE_CANDIDATE_KINDS.sort &&
               feature["credits"].is_a?(Hash) &&
               feature["public_disclosure"].is_a?(Hash) &&
               feature["third_party_ai_processing"].is_a?(Hash)
        raise Error, "Forum site-info returned invalid feature-request metadata"
      end
      user = response["user"]
      if !user.is_a?(Hash) || user["id"].to_i <= 0 || user["username"].to_s.empty?
        raise Error, "Forum site-info did not identify the authorized user"
      end

      categories = response["categories"]
      unless categories.is_a?(Array) && categories.all? do |category|
               category.is_a?(Hash) && category["id"].to_i.positive? &&
                 !category["slug"].to_s.empty? && !category["name"].to_s.empty?
             end
        raise Error, "Forum site-info returned invalid category metadata"
      end

      limits = response["content_limits"]
      unless limits.is_a?(Hash) && CONTENT_LIMIT_KEYS.all? do |key|
               limits[key].is_a?(Integer) && limits[key].positive?
             end &&
               limits["min_post_length"] <= limits["max_post_length"] &&
               limits["min_first_post_length"] <= limits["max_post_length"] &&
               limits["min_topic_title_length"] <= limits["max_topic_title_length"]
        raise Error, "Forum site-info returned invalid content length limits"
      end

      response
    end
  end

  class EditInfo
    SCHEMA = "vibe-edit-info/v1"

    def initialize(
      credentials:,
      client: nil,
      now: Time.now,
      allow_loopback_http: false
    )
      @credentials =
        Credentials.validate_data!(
          credentials,
          now: now,
          allow_loopback_http: allow_loopback_http,
        )
      @client =
        client || HttpClient.new(
          @credentials.fetch("site"),
          allow_loopback_http: allow_loopback_http,
        )
    end

    def fetch(post_id:)
      numeric_post_id = post_id.to_i
      raise Error, "post_id must be positive" if numeric_post_id <= 0

      response =
        @client.get(
          "/vibe-governance/edit-info/#{numeric_post_id}.json",
          UserApiHeaders.for(@credentials),
        )
      validate!(response, requested_post_id: numeric_post_id)
    end

    private

    def validate!(response, requested_post_id:)
      raise Error, "Forum edit-info response must be a JSON object" unless response.is_a?(Hash)
      raise Error, "Forum does not expose #{SCHEMA}" unless response["schema"] == SCHEMA

      target = response["target"]
      unless target.is_a?(Hash) && target["post_id"].to_i == requested_post_id &&
               target["expected_version"].to_i.positive?
        raise Error, "Forum edit-info returned invalid edit target metadata"
      end

      post = response["post"]
      unless post.is_a?(Hash) && post["topic_id"].to_i.positive? &&
               post["post_number"].to_i.positive?
        raise Error, "Forum edit-info returned invalid post metadata"
      end

      manifest = {
        "schema" => Envelope::SCHEMA,
        "operation" => "edit_post",
        "source_locale" => response["source_locale"],
        "target" => target,
        "variants" => response["variants"],
      }
      manifest["image"] = response["image"] if response.key?("image")
      Envelope.validate!(manifest)

      titles_present = manifest.fetch("variants").values.all? { |variant| variant.key?("title") }
      if titles_present != (post.fetch("post_number").to_i == 1)
        raise Error, "Forum edit-info returned titles for the wrong post type"
      end

      response
    end
  end

  module WritePreflight
    module_function

    def verify!(credentials:, client:, now: Time.now, allow_loopback_http: false)
      validated =
        Credentials.validate_data!(
          credentials,
          now: now,
          allow_loopback_http: allow_loopback_http,
        )
      SiteInfo.new(
        credentials: validated,
        client: client,
        now: now,
        allow_loopback_http: allow_loopback_http,
      ).fetch
    end
  end

  class Doctor
    MINIMUM_RUBY = [2, 6].freeze

    def initialize(
      credentials_path: DEFAULT_CREDENTIALS,
      now: Time.now,
      site_info_client: nil,
      allow_loopback_http: false
    )
      @credentials_path = credentials_path
      @now = now
      @site_info_client = site_info_client
      @allow_loopback_http = allow_loopback_http
    end

    def run(site: nil, online: false)
      credential_report, credentials = credential_status
      requested_site = site.to_s.empty? ? credentials&.fetch("site", nil) : site
      site_report = site_status(requested_site)
      site_matches_credentials =
        if site.to_s.empty? || credentials.nil? || credentials["site"].to_s.empty?
          nil
        else
          same_site?(site, credentials["site"])
        end

      checks = {
        "ruby_supported" => ruby_supported?,
        "site_transport_safe" => site_report.fetch("transport_safe"),
        "credentials_present" => credential_report.fetch("state") == "present",
        "credentials_permissions_safe" => credential_report.fetch("permissions_safe", false),
        "credential_client_id_present" =>
          credential_report.fetch("installation_client_id_present", false),
        "credential_scope_exact" => credential_report.fetch("scope_exact", false),
        "credential_not_expired" => credential_report.fetch("expiration") == "valid",
        "credential_site_canonical" => credential_report.fetch("site_canonical", false),
      }
      checks["site_matches_credentials"] = site_matches_credentials unless site_matches_credentials.nil?

      online_report = nil
      network_requests_made = false
      if online
        online_report, online_checks, network_requests_made = online_status(credentials)
        checks.merge!(online_checks)
      end

      report = {
        "schema" => "vibe-forum-doctor/v1",
        "ok" => checks.values.all?,
        "version" => VERSION,
        "environment" => {
          "ruby_version" => RUBY_VERSION,
          "ruby_supported" => ruby_supported?,
        },
        "site" => site_report,
        "credentials" => credential_report,
        "checks" => checks,
        "network_requests_made" => network_requests_made,
      }
      report["online"] = online_report if online
      report
    end

    private

    def ruby_supported?
      parts = RUBY_VERSION.split(".").first(2).map(&:to_i)
      (parts <=> MINIMUM_RUBY) >= 0
    end

    def credential_status
      security = Credentials.file_security(@credentials_path)
      Credentials.validate_file_security!(security)
      metadata = JSON.parse(Credentials.read_secure(@credentials_path))
      if metadata["credential_backend"] == Credentials::BACKEND_KEYCHAIN
        report = empty_credential_report(
          "reauthorization_required",
          "This credential uses retired Keychain storage; authorize again with auto or file",
        )
        report.merge!(
          "permissions" => security.fetch("permissions"),
          "permissions_safe" => security.fetch("permissions_exact"),
          "regular_file" => security.fetch("regular_file"),
          "symlink" => security.fetch("symlink"),
          "owner_current_user" => security.fetch("owner_current_user"),
          "storage" => Credentials::BACKEND_KEYCHAIN,
        )
        return [report, nil]
      end
      data = metadata
      expiration, expires_at = expiration_status(data["expires_at"])
      canonical_site =
        begin
          SiteAddress.canonical(
            data["site"],
            allow_loopback_http: @allow_loopback_http,
          )
        rescue Error
          nil
        end
      report = {
        "path" => @credentials_path,
        "state" => "present",
        "permissions" => security.fetch("permissions"),
        "permissions_safe" => security.fetch("permissions_exact"),
        "regular_file" => security.fetch("regular_file"),
        "symlink" => security.fetch("symlink"),
        "owner_current_user" => security.fetch("owner_current_user"),
        "scope" => data["scope"],
        "storage" => metadata["credential_backend"] || "legacy-file",
        "scope_exact" => data["scope"] == SCOPE,
        "site_canonical" => !canonical_site.nil? && data["site"] == canonical_site,
        "expires_at" => expires_at,
        "expiration" => expiration,
        "installation_client_id_present" => valid_client_id?(data["client_id"]),
      }
      report["site"] = data["site"] unless data["site"].to_s.empty?
      report["user_api_key_present"] = !data["user_api_key"].to_s.empty?
      if !report["user_api_key_present"]
        report["state"] = "invalid"
      elsif !report["installation_client_id_present"]
        report["state"] = "reauthorization_required"
        report["error"] =
          "This credential was created by an older publisher and must be authorized again"
      end
      [report, data]
    rescue Errno::ENOENT
      [empty_credential_report("missing"), nil]
    rescue JSON::ParserError
      [empty_credential_report("invalid", "Credential file is invalid JSON"), nil]
    rescue Error, SystemCallError => e
      [empty_credential_report("unreadable", e.message), nil]
    end

    def empty_credential_report(state, error = nil)
      report = {
        "path" => @credentials_path,
        "state" => state,
        "permissions" => nil,
        "permissions_safe" => false,
        "regular_file" => false,
        "symlink" => nil,
        "owner_current_user" => false,
        "scope" => nil,
        "storage" => nil,
        "scope_exact" => false,
        "site_canonical" => false,
        "expires_at" => nil,
        "expiration" => "unknown",
        "user_api_key_present" => false,
        "installation_client_id_present" => false,
      }
      report["error"] = error if error
      report
    end

    def expiration_status(value)
      return ["unknown", nil] if value.to_s.empty?

      parsed = Time.iso8601(value)
      [parsed <= @now ? "expired" : "valid", parsed.iso8601]
    rescue ArgumentError
      ["invalid", value]
    end

    def site_status(value)
      return { "value" => nil, "transport" => "missing", "transport_safe" => false } if value.to_s.empty?

      uri = SiteAddress.parse(value, allow_loopback_http: @allow_loopback_http)

      transport =
        if uri.scheme == "https"
          "https"
        elsif uri.scheme == "http" && HttpClient::LOOPBACK_HOSTS.include?(uri.hostname.downcase)
          "loopback-http"
        else
          "unsafe"
        end

      {
        "value" => value,
        "transport" => transport,
        "transport_safe" => %w[https loopback-http].include?(transport),
      }
    rescue Error => e
      { "value" => value, "transport" => "invalid", "transport_safe" => false, "error" => e.message }
    end

    def same_site?(left, right)
      SiteAddress.equivalent?(
        left,
        right,
        allow_loopback_http: @allow_loopback_http,
      )
    end

    def valid_client_id?(value)
      value.to_s.match?(/\A[0-9a-f]{32}\z/)
    end

    def online_status(credentials)
      if credentials.is_a?(Hash) && !valid_client_id?(credentials["client_id"])
        return [
          {
            "requested" => true,
            "state" => "reauthorization_required",
            "error" =>
              "This credential was created by an older publisher and must be authorized again",
          },
          {
            "site_reachable" => false,
            "key_accepted" => false,
            "server_scope_exact" => false,
            "server_site_matches_credentials" => false,
          },
          false,
        ]
      end

      if !credentials.is_a?(Hash) || credentials["site"].to_s.empty? ||
           credentials["user_api_key"].to_s.empty?
        return [
          {
            "requested" => true,
            "state" => "not_attempted",
            "error" => "Valid local credentials are required for an online check",
          },
          {
            "site_reachable" => false,
            "key_accepted" => false,
            "server_scope_exact" => false,
            "server_site_matches_credentials" => false,
          },
          false,
        ]
      end

      validated =
        Credentials.validate_data!(
          credentials,
          now: @now,
          allow_loopback_http: @allow_loopback_http,
        )
      info = SiteInfo.new(
        credentials: validated,
        client: @site_info_client,
        now: @now,
        allow_loopback_http: @allow_loopback_http,
      ).fetch
      site_matches = same_site?(info.fetch("site_url"), credentials.fetch("site"))
      [
        {
          "requested" => true,
          "state" => site_matches ? "verified" : "site_mismatch",
          "site_info" => info,
        },
        {
          "site_reachable" => true,
          "key_accepted" => true,
          "server_scope_exact" => info.fetch("scope") == SCOPE,
          "server_site_matches_credentials" => site_matches,
        },
        true,
      ]
    rescue SiteMismatchError => e
      [
        {
          "requested" => true,
          "state" => "site_mismatch",
          "error" => e.message,
        },
        {
          "site_reachable" => true,
          "key_accepted" => true,
          "server_scope_exact" => true,
          "server_site_matches_credentials" => false,
        },
        true,
      ]
    rescue Error => e
      [
        {
          "requested" => true,
          "state" => "failed",
          "error" => e.message,
        },
        {
          "site_reachable" => false,
          "key_accepted" => false,
          "server_scope_exact" => false,
          "server_site_matches_credentials" => false,
        },
        true,
      ]
    end
  end

  class CredentialRevoker
    def initialize(
      credentials_path: DEFAULT_CREDENTIALS,
      client: nil,
      now: nil,
      allow_loopback_http: false
    )
      @credentials_path = credentials_path
      @client = client
      @now = now
      @allow_loopback_http = allow_loopback_http
    end

    def revoke!
      revoked = false
      current_time = @now || Time.now
      credentials =
        Credentials.load(
          @credentials_path,
          now: current_time,
          allow_loopback_http: @allow_loopback_http,
        )
      client =
        @client || HttpClient.new(
          credentials.fetch("site"),
          allow_loopback_http: @allow_loopback_http,
        )
      WritePreflight.verify!(
        credentials: credentials,
        client: client,
        now: @now || Time.now,
        allow_loopback_http: @allow_loopback_http,
      )
      client.post(
        "/user-api-key/revoke.json",
        {},
        UserApiHeaders.for(credentials),
      )
      revoked = true

      Credentials.delete(@credentials_path)
      {
        "revoked" => true,
        "credentials_removed" => true,
        "site" => credentials.fetch("site"),
      }
    rescue StandardError => e
      if revoked
        raise Error, "Publishing permission was revoked, but the local credential could not be removed: #{e.message}"
      end

      raise Error, "Could not revoke publishing permission; local credentials were kept: #{e.message}"
    end
  end

  class DeviceAuthorization
    EXPIRY_SECONDS = 30 * 24 * 60 * 60
    CALLBACK_HOST = "127.0.0.1"
    CALLBACK_PORT = 53_682
    CALLBACK_PATH = "/vibe-forum-auth"

    def initialize(
      site:,
      credentials_path:,
      client_id_path: nil,
      output: $stdout,
      sleeper: Kernel,
      credential_backend: nil,
      allow_loopback_http: false
    )
      @credential_backend = Credentials.resolve_backend(credential_backend)
      @allow_loopback_http = allow_loopback_http
      @site = SiteAddress.canonical(site, allow_loopback_http: allow_loopback_http)
      @credentials_path = credentials_path
      @client_id_path = client_id_path || InstallationIdentity.path_for(credentials_path)
      @output = output
      @sleeper = sleeper
      @client = HttpClient.new(@site, allow_loopback_http: allow_loopback_http)
    end

    def run(max_wait_seconds: 600)
      Credentials.validate_existing_path!(@credentials_path)
      private_key = OpenSSL::PKey::RSA.new(2048)
      nonce = SecureRandom.hex(8)
      server = TCPServer.new(CALLBACK_HOST, CALLBACK_PORT)
      public_key = private_key.public_key
      client_id = InstallationIdentity.load_or_create(@client_id_path)
      callback = "http://#{CALLBACK_HOST}:#{CALLBACK_PORT}#{CALLBACK_PATH}"
      authorization_url =
        build_authorization_url(
          nonce: nonce,
          client_id: client_id,
          public_key: public_key,
          callback: callback,
        )

      @output.puts "Open this page, sign in, and approve only the publishing permission:"
      @output.puts authorization_url

      payload =
        wait_for_callback(
          server,
          max_wait_seconds: max_wait_seconds,
          private_key: private_key,
          nonce: nonce,
        )

      credentials = {
        "site" => @site,
        "user_api_key" => payload.fetch("key"),
        "client_id" => client_id,
        "scope" => SCOPE,
        "expires_at" => (Time.now + EXPIRY_SECONDS).utc.iso8601,
      }
      validated =
        Credentials.validate_data!(
          credentials,
          allow_loopback_http: @allow_loopback_http,
        )
      WritePreflight.verify!(
        credentials: validated,
        client: @client,
        allow_loopback_http: @allow_loopback_http,
      )
      saved =
        Credentials.save(
          validated,
          @credentials_path,
          backend: @credential_backend,
          allow_loopback_http: @allow_loopback_http,
        )
      @output.puts "Publishing permission saved to #{saved}"
      payload
    rescue Errno::EADDRINUSE
      raise Error,
            "Local authorization port #{CALLBACK_PORT} is already in use; close the other authorization attempt and retry"
    ensure
      server&.close
    end

    private

    def build_authorization_url(nonce:, client_id:, public_key:, callback:)
      "#{@site}/user-api-key/new?#{URI.encode_www_form(
        nonce: nonce,
        scopes: SCOPE,
        client_id: client_id,
        application_name: "Vibe Forum Local Publisher",
        public_key: public_key.to_pem,
        padding: "oaep",
        auth_redirect: callback,
      )}"
    end

    def wait_for_callback(server, max_wait_seconds:, private_key:, nonce:)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + max_wait_seconds

      loop do
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raise Error, "Authorization timed out; run auth again" if remaining <= 0
        next unless IO.select([server], nil, nil, [remaining, 1].min)

        socket = server.accept
        request_line = socket.gets.to_s
        100.times do
          line = socket.gets
          break if line.nil? || line == "\r\n"
        end
        method, request_target, = request_line.split(" ", 3)
        uri = URI(request_target.to_s)
        params = URI.decode_www_form(uri.query.to_s).to_h
        if method == "GET" && uri.path == CALLBACK_PATH && params["payload"].to_s != ""
          begin
            payload = decrypt_payload(params.fetch("payload"), private_key)
            validate_authorization_payload!(payload, nonce: nonce)
            respond_to_callback(socket, status: "200 OK", message: "Publishing permission approved. You can close this tab and return to your local AI tool.")
            return payload
          rescue Error
            respond_to_callback(socket, status: "400 Bad Request", message: "This authorization response was not valid. Return to the forum and try again.")
            next
          end
        end

        respond_to_callback(socket, status: "400 Bad Request", message: "This authorization response was not valid. Return to the forum and try again.")
      rescue URI::InvalidURIError, ArgumentError
        respond_to_callback(socket, status: "400 Bad Request", message: "This authorization response was not valid. Return to the forum and try again.") if socket
      ensure
        socket&.close
      end
    end

    def respond_to_callback(socket, status:, message:)
      body = "<!doctype html><meta charset=\"utf-8\"><title>Vibe Forum</title><p>#{message}</p>"
      socket.write "HTTP/1.1 #{status}\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
    rescue SystemCallError
      nil
    end

    def decrypt_payload(encoded, private_key)
      plaintext =
        private_key.private_decrypt(
          Base64.decode64(encoded),
          OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING,
        )
      JSON.parse(plaintext)
    rescue OpenSSL::PKey::RSAError, JSON::ParserError
      raise Error, "Could not verify the encrypted authorization response"
    end

    def validate_authorization_payload!(payload, nonce:)
      raise Error, "Authorization response must be a JSON object" unless payload.is_a?(Hash)
      raise Error, "Authorization nonce did not match" unless payload["nonce"] == nonce
      raise Error, "Forum returned an unsupported User API version" unless payload["api"] == 4
      raise Error, "Forum returned an empty User API Key" if payload["key"].to_s.empty?

      payload
    end
  end

  module Review
    SECRET_PATTERNS = {
      "private key" => /-----BEGIN [A-Z ]*PRIVATE KEY-----/i,
      "OpenAI-style API key" => /\bsk-[A-Za-z0-9_-]{20,}\b/,
      "AWS access key" => /\bAKIA[0-9A-Z]{16}\b/,
      "GitHub token" => /\bgh[pousr]_[A-Za-z0-9]{20,}\b/,
      "Slack token" => /\bxox[baprs]-[A-Za-z0-9-]{16,}\b/,
      "password assignment" => /\bpassword\s*[:=]\s*\S+/i,
    }.freeze
    PROMOTION_PATTERN = /(限时|优惠|折扣|购买|扫码加群|邀请码|返佣|中转站|limited offer|discount|coupon|affiliate|referral)/i

    module_function

    def request(payload)
      reject_secrets!(payload)

      {
        "schema" => REVIEW_SCHEMA,
        "content_sha256" => content_digest(payload),
        "instruction" =>
          "Review for accidental secrets, pure promotion, obvious spam, and bilingual readability. Do not rewrite or publish. Return decision allow, warn, or block with findings.",
        "content" => payload,
      }
    end

    def validate!(report, payload)
      raise Error, "Local AI review uses an unsupported schema" unless report["schema"] == REVIEW_SCHEMA
      unless report["content_sha256"] == content_digest(payload)
        raise Error, "Local AI review does not match the exact content being sent"
      end
      raise Error, "Local AI review must identify itself" if report["reviewer"].to_s.empty?

      decision = report["decision"]
      raise Error, "Local AI review decision must be allow, warn, or block" unless %w[allow warn block].include?(decision)
      raise Error, "Local AI review blocked this publication" if decision == "block"

      report
    end

    def static_findings(payload)
      text = text_content(payload).join("\n")
      findings =
        SECRET_PATTERNS.each_with_object([]) do |(label, pattern), matches|
          matches << label if text.match?(pattern)
        end
      findings << "promotion language needs human attention" if text.match?(PROMOTION_PATTERN)
      findings
    end

    def reject_secrets!(payload)
      secrets = static_findings(payload) & SECRET_PATTERNS.keys
      return if secrets.empty?

      raise Error, "Possible secret detected locally: #{secrets.join(', ')}"
    end

    def reject_exact_secret!(payload, secret, label: "active credential")
      return if secret.to_s.empty?
      return unless JSON.generate(payload).include?(secret)

      raise Error, "Possible secret detected locally: #{label}"
    end

    def content_digest(payload)
      Digest::SHA256.hexdigest(JSON.generate(canonical_payload(payload)))
    end

    def idempotency_key(payload)
      "vibe-#{content_digest(payload)[0, 48]}"
    end

    def canonical_payload(payload)
      canonicalize(payload)
    end

    def canonicalize(value)
      case value
      when Hash
        value.keys.sort_by(&:to_s).to_h { |key| [key.to_s, canonicalize(value.fetch(key))] }
      when Array
        value.map { |item| canonicalize(item) }
      else
        value
      end
    end

    def text_content(value)
      case value
      when Hash
        value.flat_map { |key, item| %w[title body_markdown].include?(key.to_s) ? [item.to_s] : text_content(item) }
      when Array
        value.flat_map { |item| text_content(item) }
      else
        []
      end
    end
  end

  class Publisher
    def initialize(
      credentials:,
      input: $stdin,
      output: $stdout,
      client: nil,
      now: nil,
      allow_loopback_http: false
    )
      @now = now
      @allow_loopback_http = allow_loopback_http
      @credentials =
        Credentials.validate_data!(
          credentials,
          now: current_time,
          allow_loopback_http: allow_loopback_http,
        )
      @input = input
      @output = output
      @client =
        client || HttpClient.new(
          @credentials.fetch("site"),
          allow_loopback_http: allow_loopback_http,
        )
    end

    def publish(payload:, review_report:, request_id: nil)
      Envelope.validate!(payload)
      Review.reject_secrets!(payload)
      Review.reject_exact_secret!(
        payload,
        @credentials.fetch("user_api_key"),
        label: "forum publishing key",
      )
      report = Review.validate!(review_report, payload)
      site_info = SiteInfo.new(
        credentials: @credentials,
        client: @client,
        now: current_time,
        allow_loopback_http: @allow_loopback_http,
      ).fetch
      Envelope.validate_live_limits!(payload, site_info.fetch("content_limits"))
      current = current_edit_info(payload)
      preview(payload, report, current: current)

      @output.print "Type `publish` to send exactly this content: "
      raise Error, "Publication cancelled" unless @input.gets&.strip == "publish"

      WritePreflight.verify!(
        credentials: @credentials,
        client: @client,
        now: current_time,
        allow_loopback_http: @allow_loopback_http,
      )
      @client.post(
        "/vibe-governance/publish.json",
        payload,
        UserApiHeaders.for(@credentials).merge(
          "Idempotency-Key" => request_id || Review.idempotency_key(payload),
        ),
      )
    end

    private

    def current_time
      @now.respond_to?(:call) ? @now.call : (@now || Time.now)
    end

    def current_edit_info(payload)
      return unless payload.fetch("operation") == "edit_post"

      current =
        EditInfo.new(
          credentials: @credentials,
          client: @client,
          now: current_time,
          allow_loopback_http: @allow_loopback_http,
        ).fetch(
          post_id: payload.dig("target", "post_id"),
        )
      expected_version = payload.dig("target", "expected_version").to_i
      current_version = current.dig("target", "expected_version").to_i
      if current_version != expected_version
        raise Error,
              "Post changed from expected version #{expected_version} to #{current_version}; run edit-info again"
      end
      if current.fetch("source_locale") != payload.fetch("source_locale")
        raise Error, "edit_post cannot change which language is the author original"
      end

      current
    end

    def preview(payload, report, current: nil)
      @output.puts "\n--- Exact outbound content ---"
      if payload.fetch("operation") == "reply"
        @output.puts "Reply to topic: #{payload.dig("target", "topic_id")}"
      elsif payload.fetch("operation") == "edit_post"
        @output.puts "Edit post: #{payload.dig("target", "post_id")}"
        @output.puts "Expected version: #{payload.dig("target", "expected_version")}"
      else
        category = payload.dig("target", "category_slug") || payload.dig("target", "category_id")
        @output.puts "Create topic in category: #{category}"
      end

      preview_edit_changes(payload, current) if current
      @output.puts "Source locale: #{payload.fetch("source_locale")}"
      if payload["image"]
        @output.puts "Image upload: ##{payload.dig("image", "upload_id")} #{payload.dig("image", "short_url")}"
      end
      if payload["feature_request"]
        request = payload.fetch("feature_request")
        @output.puts "Featured shelf request: yes (#{request.fetch("candidate_kind")})"
        @output.puts "Server AI: one requested curation decision; ordinary publication continues if it fails"
        @output.puts "Public transparency: scoped request ID, minute timestamp, category, result, policy/model, token cost, and duration"
        @output.puts "Not public: account, title, body, link, image, or evidence excerpt"
        @output.puts "Third-party AI input: sanitized original-language title and body only"
      else
        @output.puts "Featured shelf request: no; this publication triggers no server AI"
      end
      payload.fetch("variants").sort.each do |locale, variant|
        @output.puts "\n[#{locale}]"
        @output.puts "Title: #{variant.fetch("title")}" if variant["title"]
        @output.puts variant.fetch("body_markdown")
      end
      @output.puts "--- End outbound content ---"
      @output.puts "Local AI review: #{report.fetch('decision')} by #{report.fetch('reviewer')}"
      Array(report["findings"]).each { |finding| @output.puts "- #{finding}" }
      Review.static_findings(payload).each { |finding| @output.puts "- local check: #{finding}" }
    end

    def preview_edit_changes(payload, current)
      @output.puts "\n--- Changes from current version ---"
      changes = 0
      if current["image"] != payload["image"]
        changes += 1
        @output.puts "[image]"
        @output.puts "Current: #{current["image"] ? JSON.generate(current["image"]) : "none"}"
        @output.puts "Proposed: #{payload["image"] ? JSON.generate(payload["image"]) : "none"}"
      end
      payload.fetch("variants").sort.each do |locale, proposed|
        existing = current.fetch("variants").fetch(locale)
        %w[title body_markdown].each do |field|
          before = existing[field]
          after = proposed[field]
          next if before == after

          changes += 1
          @output.puts "[#{locale}] #{field}"
          @output.puts "Current:"
          @output.puts before.to_s
          @output.puts "Proposed:"
          @output.puts after.to_s
        end
      end
      @output.puts "No text changes; the server will only reconcile stale language records." if changes.zero?
      @output.puts "--- End changes ---\n"
    end
  end

  class ImageUploader
    def initialize(
      credentials:,
      input: $stdin,
      output: $stdout,
      client: nil,
      now: nil,
      allow_loopback_http: false
    )
      @now = now
      @allow_loopback_http = allow_loopback_http
      @credentials =
        Credentials.validate_data!(
          credentials,
          now: @now || Time.now,
          allow_loopback_http: allow_loopback_http,
        )
      @input = input
      @output = output
      @client =
        client || HttpClient.new(
          @credentials.fetch("site"),
          allow_loopback_http: allow_loopback_http,
        )
    end

    def upload(file_path:, expected_sha256:)
      unless expected_sha256.to_s.match?(/\A[0-9a-f]{64}\z/i)
        raise Error, "Expected image SHA-256 must contain exactly 64 hexadecimal characters"
      end

      Image.with_private_snapshot(file_path) do |snapshot, info|
        unless info.fetch("sha256") == expected_sha256.downcase
          raise Error, "Image no longer matches the SHA-256 confirmed from image-info"
        end

        preview(info)

        @output.print "Type `upload` to send exactly this image: "
        raise Error, "Image upload cancelled" unless @input.gets&.strip == "upload"

        WritePreflight.verify!(
          credentials: @credentials,
          client: @client,
          now: @now || Time.now,
          allow_loopback_http: @allow_loopback_http,
        )
        response =
          @client.post_multipart(
            "/vibe-governance/image-upload.json",
            file_io: snapshot,
            filename: info.fetch("filename"),
            content_type: info.fetch("media_type"),
            headers: UserApiHeaders.for(@credentials),
          )

        unless response["id"].to_i.positive? &&
               response["short_url"].to_s.match?(%r{\Aupload://[A-Za-z0-9]+\.(?:png|jpe?g)\z}i)
          raise Error, "Forum did not return a valid PNG/JPEG upload reference"
        end
        unless response["source_sha256"] == info.fetch("sha256")
          raise Error, "Forum upload receipt does not match the confirmed local image"
        end

        response
      end
    end

    private

    def preview(info)
      @output.puts "\n--- Exact local image ---"
      @output.puts "Filename: #{info.fetch("filename")}"
      @output.puts "Media type: #{info.fetch("media_type")}"
      @output.puts "Size: #{info.fetch("size_bytes")} bytes"
      @output.puts "SHA-256: #{info.fetch("sha256")}"
      @output.puts "--- End local image ---"
    end
  end
end
