# Vibe Publish contract

## Command resolution

Resolve the executable relative to this Skill, never from `PATH`:

```text
Plugin:     <skill-directory>/../../tool/bin/vibe-forum
Repo-local: <skill-directory>/../../../local-tool/bin/vibe-forum
```

Resolve that location to an absolute path and verify it with `--version`. The CLI supports `auth`, `doctor`, `site-info`, `edit-info`, `logout --revoke`, `image-info`, `image-upload`, `review-request`, and `publish`. Plain `doctor` and `image-info` are local, read-only checks with no network request. `doctor --online`, `site-info`, and `edit-info --post-id <id>` are authenticated read-only requests; `edit-info` returns only the current account's exact bilingual post, author-original locale, optional image, and current version. The Skill continues only when that post is a topic first post with titles in both variants. `image-upload` and `publish` are separate external writes with separate exact confirmations. `logout --revoke` removes the local credential only after the server confirms self-revocation. Keep manifests and review reports in a unique directory under the operating system's temporary directory, never in the user's repository. The 0.6 release stores the complete narrow User API credential at `~/.config/vibe-forum/credentials.json` with exact owner-only `0600` permissions on both macOS and Linux/POSIX. This is a plain file, not a secret enclave: another process running as the same OS user may read it. Keychain integration is retired; explicit `--credential-backend keychain` fails before browser authorization or listener startup. Never place the key in a project `.env`, Skill, prompt, manifest, issue, or model context.

## New topic manifest

Use exactly the two variant keys `en` and `zh-CN`:

```json
{
  "schema": "vibe-publish/v3",
  "operation": "create_topic",
  "source_locale": "zh-CN",
  "target": {
    "category_slug": "uncategorized"
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

`category_slug` remains a wire field for protocol compatibility. It is not a user choice or visible information-architecture label. For a live write, populate it only from the single internal publication destination returned by the current `site-info`; never ask the user for it or show it in the final preview. If `site-info` returns zero or more than one destination, or the manifest does not match the sole returned destination, fail closed and rebuild only after the forum configuration is corrected. A draft made without live `site-info` is not publish-ready and must be rebound, reviewed, and confirmed before writing.

### Optional temporary marker in Latest

This request can only add a temporary marker to the topic in its existing position in Latest. It never creates a second stream, moves the topic, pins it, or changes Latest ordering.

An ordinary topic omits `feature_request` and creates no server-AI call. Only a new topic that passed the local policy review may include the following exact object:

```json
{
  "feature_request": {
    "schema": "vibe-feature-request/v1",
    "requested": true,
    "candidate_kind": "build_log",
    "local_skill_version": "vibe-publish/0.6.1",
    "precheck_result": "passed",
    "public_disclosure_accepted": true,
    "third_party_ai_processing_accepted": true
  }
}
```

`candidate_kind` must be one of `build_log`, `problem_solution`, `open_source`, `tool_method`, or `failure_lesson`. `open_source` is a legacy wire label retained for rolling compatibility; for a project share, it does **not** require the work to be open source. Open-source, closed-source, self-owned, and commercial projects can all use that value when the post contains concrete project work. The two acceptance fields may be true only after the exact final preview explains the credit use, the sanitized original-language content sent for one third-party model decision, the operational fields made public, and the author/content fields withheld. A legacy transparency response may retain an internal `category` audit field; it represents compatibility metadata, not a user-selectable board or current information architecture, and must not be highlighted in the preview. A failure, timeout, invalid result, or exhausted budget leaves the topic public as ordinary and must not trigger deletion, hiding, replying, or penalties.

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

## Retired reply envelope (read-only evidence)

The current Skill never creates or submits this manifest. For a new reply or reply edit, direct the user to CommitTown's native **Reply / 回复** or edit action. Version 0.6.0 completed the single rolling-compatibility release. In 0.6.1, `review-request` can still read the old envelope for audit evidence, but `publish` and the server endpoint reject it and point the user to the native forum controls.

The following shape is documented only to identify historical evidence. Legacy reply variants omitted titles, and `reply_to_post_number` was optional:

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

## First-post author edit manifest

Fetch the current owned post before drafting an edit:

```text
vibe-forum edit-info --post-id 42
```

Continue only when the returned `en` and `zh-CN` variants both contain titles, proving the target is the topic's first post. Otherwise stop and direct the user to the forum's native reply editor. Use the returned `target.post_id`, `target.expected_version`, `source_locale`, variants, and optional `image` as the base. The author-original locale cannot change.

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

## Live account and internal destination resolution

After authorization, run `doctor --online` and `site-info`. Verify the returned username is the account the user intends to publish as. For a new topic, require exactly one internal publication destination and bind its returned slug to the wire manifest. Never ask the user to select it, expose its name/slug in the preview, or copy an ID from a local demo, document, another account, or another forum. Zero or multiple destinations stop the workflow without writing.

The same live `site-info` response includes `content_limits` for bodies and topic titles. For the Skill's supported topic operations, check both `en` and `zh-CN` against the first-post and title values before requesting publication confirmation. Reply-related limits may remain in this general Discourse metadata, but they do not advertise a writable reply operation. The CLI fetches and enforces the first-post and title limits again immediately before preview and write; when one version is too short or too long, update that version and regenerate the content-bound local review before retrying.

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
