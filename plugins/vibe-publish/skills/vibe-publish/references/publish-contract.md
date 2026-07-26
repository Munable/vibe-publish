# Vibe Publish contract

## Command resolution

Resolve the executable relative to this Skill, never from `PATH`:

```text
Plugin:     <skill-directory>/../../tool/bin/vibe-forum
Repo-local: <skill-directory>/../../../local-tool/bin/vibe-forum
```

Resolve that location to an absolute path and verify it with `--version`. The CLI supports `auth`, `doctor`, `site-info`, `edit-info`, `logout --revoke`, `image-info`, `image-upload`, `review-request`, and `publish`. Plain `doctor` and `image-info` are local, read-only checks with no network request. `doctor --online`, `site-info`, and `edit-info --post-id <id>` are authenticated read-only requests; `edit-info` returns only the current account's exact bilingual post, author-original locale, optional image, and current version. `image-upload` and `publish` are separate external writes with separate exact confirmations. `logout --revoke` removes the local credential only after the server confirms self-revocation. Keep manifests and review reports in a unique directory under the operating system's temporary directory, never in the user's repository. This Alpha stores the complete narrow User API credential at `~/.config/vibe-forum/credentials.json` with exact owner-only `0600` permissions on both macOS and Linux/POSIX. Keychain integration is retired; explicit `--credential-backend keychain` fails before browser authorization or listener startup. Never place the key in a project `.env`, Skill, prompt, or manifest.

## New topic manifest

Use exactly the two variant keys `en` and `zh-CN`:

```json
{
  "schema": "vibe-publish/v3",
  "operation": "create_topic",
  "source_locale": "zh-CN",
  "target": {
    "category_slug": "build-logs"
  },
  "variants": {
    "en": {
      "title": "What I learned from a failed migration",
      "body_markdown": "The rollback looked valid, but the data backfill was irreversible."
    },
    "zh-CN": {
      "title": "一次迁移失败后，我真正学到了什么",
      "body_markdown": "回滚语法看起来没有问题，但数据回填实际上不可逆。"
    }
  }
}
```

Both topic variants require a non-empty title and body.

### Optional featured-shelf request

An ordinary topic omits `feature_request` and creates no server-AI call. Only a new topic that passed the local policy review may include the following exact object:

```json
{
  "feature_request": {
    "schema": "vibe-feature-request/v1",
    "requested": true,
    "candidate_kind": "build_log",
    "local_skill_version": "vibe-publish/0.5.3",
    "precheck_result": "passed",
    "public_disclosure_accepted": true,
    "third_party_ai_processing_accepted": true
  }
}
```

`candidate_kind` must be one of `build_log`, `problem_solution`, `open_source`, `tool_method`, or `failure_lesson`. The two acceptance fields may be true only after the exact final preview explains the credit use, the sanitized original-language content sent for one third-party model decision, the operational fields made public, and the author/content fields withheld. A failure, timeout, invalid result, or exhausted budget leaves the topic public as ordinary and must not trigger deletion, hiding, replying, or penalties.

## Optional single image

Only one local PNG or JPEG up to 10 MiB is supported. First run the read-only metadata check and show its exact result to the user:

```text
vibe-forum image-info --file /path/to/proof.png
```

After the user confirms that filename, media type, byte size, and SHA-256, run `image-upload`. The upload endpoint reuses Discourse `Upload`, accepts no remote URL or second file, and is covered by the same exact `vibe-governance:publish` User API scope as publication:

This deterministic path does not claim to inspect image pixels or EXIF. A capable local agent may separately view the explicit file and warn about visible credentials or private information, but the text review report and forum server must never be described as visual-content attestation.

```text
vibe-forum image-upload --file /path/to/proof.png --expected-sha256 <sha256-from-image-info>
```

Use the real `id` and `short_url` returned by that command. Add exactly this object to the manifest and reference the same short URL in both bodies:

```json
{
  "image": {
    "upload_id": 42,
    "short_url": "upload://qUm0DGR49PAZshIi7HxMd3cAlzn.png"
  },
  "variants": {
    "en": {
      "body_markdown": "Here is the result.\n\n![Result](upload://qUm0DGR49PAZshIi7HxMd3cAlzn.png)"
    },
    "zh-CN": {
      "body_markdown": "这是运行结果。\n\n![运行结果](upload://qUm0DGR49PAZshIi7HxMd3cAlzn.png)"
    }
  }
}
```

This fragment illustrates only the image fields; the complete manifest still needs schema, operation, source locale, target, and topic titles when applicable. A manifest without `image` must render no image. With `image`, each language body must render exactly one copy of that same server-returned value and no remote, HTML, reference-style, duplicate, or additional image. Image syntax inside a code block remains ordinary code. The server verifies the upload ID, exact short URL, owner, media type, size, both language reference lists, and the rendered image structure. `image-upload` copies the explicit file into a private `0600` snapshot, binds it to the SHA-256 the user confirmed from `image-info`, and uploads only that snapshot.

## Reply manifest

Omit titles from reply variants. Include `reply_to_post_number` only when the user explicitly targets a particular reply:

```json
{
  "schema": "vibe-publish/v3",
  "operation": "reply",
  "source_locale": "en",
  "target": {
    "topic_id": 11,
    "reply_to_post_number": 1
  },
  "variants": {
    "en": {
      "body_markdown": "The smaller change list would solve my mobile use case."
    },
    "zh-CN": {
      "body_markdown": "更短的改动列表可以解决我的移动端使用场景。"
    }
  }
}
```

## Author edit manifest

Fetch the current owned post before drafting an edit:

```text
vibe-forum edit-info --post-id 42
```

Use the returned `target.post_id`, `target.expected_version`, `source_locale`, variants, and optional `image` as the base. A topic's first-post edit requires both titles; a reply edit omits both titles. The author-original locale cannot change.

```json
{
  "schema": "vibe-publish/v3",
  "operation": "edit_post",
  "source_locale": "en",
  "target": {
    "post_id": 42,
    "expected_version": 3
  },
  "variants": {
    "en": {
      "title": "What the migration failure actually taught me",
      "body_markdown": "The irreversible backfill was the real failure mode."
    },
    "zh-CN": {
      "title": "这次迁移失败真正教会我的事",
      "body_markdown": "真正的失败模式是不可逆的数据回填。"
    }
  }
}
```

Before asking for confirmation, `publish` reads `edit-info` again, refuses a stale expected version, and prints the current and proposed values for every changed title, body, or image. The server then locks the post, checks author ownership and the same expected version, updates source and translated records in one database transaction, removes stale language rows, and returns the new version. An unchanged retry must reuse the same content-bound idempotency key. A version conflict requires a fresh `edit-info`, review report, diff preview, and human confirmation; never overwrite it with a new request ID.

## Review report

First run `review-request` for the final manifest. Copy its returned `content_sha256` into the report; do not derive a digest from a visually similar draft.

```json
{
  "schema": "vibe-local-review/v1",
  "reviewer": "local-agent-name",
  "decision": "allow",
  "content_sha256": "digest returned by review-request",
  "findings": []
}
```

Allowed decisions are `allow`, `warn`, and `block`. The CLI refuses `block` and refuses a digest that does not match the exact outbound manifest.

## Live account and category discovery

After authorization, run `doctor --online` and `site-info`. Verify the returned username is the account the user intends to publish as. For a new topic, select a `category_slug` from the writable categories returned for that account. Category IDs are deployment-specific compatibility inputs; never copy an ID from a local demo, document, another account, or another forum.

The same live `site-info` response includes `content_limits` for reply bodies, first-post bodies, and topic titles. Check both `en` and `zh-CN` against those values before requesting publication confirmation. The CLI fetches and enforces the limits again immediately before preview and write; when one version is too short or too long, update that version and regenerate the content-bound local review before retrying.

## Submission sequence

```text
vibe-forum image-info --file <image.png>        # optional, read-only
vibe-forum auth --site <https://forum.example.com>
vibe-forum doctor --online
vibe-forum site-info
vibe-forum edit-info --post-id <post-id>         # required before an edit
vibe-forum image-upload --file <image.png> --expected-sha256 <confirmed-sha256>
vibe-forum review-request --manifest <manifest.json>
vibe-forum publish --manifest <manifest.json> --review <review.json>
```

Authorization may need to occur before `image-upload` when credentials are absent; it is never automatic. For local development, `http://127.0.0.1:3000` is allowed. Remote sites must use HTTPS. Ordinary publication retries must reuse the unchanged manifest and omit `--request-id`, so an uncertain retry returns the original post instead of creating a duplicate.
