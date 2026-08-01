# CommitTown Local Publisher

This is the Apache-2.0 narrow development adapter behind the repo-local [`vibe-publish` Agent Skill](../.agents/skills/vibe-publish/SKILL.md). The open-source Plugin under [`codex-plugins/vibe-publish`](../codex-plugins/vibe-publish/) is generated from this canonical tool and Skill; MCP is deferred. Version 0.6.1 creates bilingual topics and edits only their first posts. It directs replies and reply edits to CommitTown's native forum controls. The parser can still read a 0.6.0 reply envelope for local audit evidence, but neither the CLI nor the server advertises or accepts it as a writable operation.

1. asks the forum for a 30-day User API Key with only the exact `vibe-governance:publish` scope and reuses one stable per-installation client ID;
2. uses that same scope's read-only `site-info` endpoint to verify the live key and resolve exactly one internal publication destination, and `edit-info` to retrieve only the current author's exact bilingual post and version; the Skill never asks the user to choose a destination and continues with an edit only for a first post with titles in both language variants;
3. optionally previews one local PNG or JPEG's filename, media type, byte size, and SHA-256, then requires that confirmed digest plus `upload` before sending a private snapshot to the scope's Discourse Upload endpoint;
4. binds a local-AI review report to the SHA-256 of the exact English-Chinese outbound bundle, including the real returned `upload://` reference when present;
5. shows both saved language versions, or the current-to-proposed edit values, and requires the human to type `publish` before sending them with a retry-safe idempotency key.

The review receipt is workflow evidence, not remote attestation. A hostile client can forge local state, so the server still enforces identity, permissions, limits, watched words, governance, and recorded human emergency moderation. Image preflight validates bytes, type, size, digest, and references; this deterministic CLI does not inspect pixels or EXIF and must not be advertised as visual-content review. The tool never authorizes, uploads, or posts by itself and does not contain an automatic posting loop.

It also exposes lifecycle commands that do not broaden the publishing boundary:

- `--version` or `version` prints the packaged CLI version;
- `doctor` performs a local, no-network check by default; `doctor --online` additionally verifies the real site, current key, server-side exact scope, publishing schema, user, and internal destination metadata;
- `site-info` performs only that authenticated read-only server probe; for a new topic, the publisher requires exactly one internal destination and binds it without exposing it in the confirmation preview;
- `edit-info --post-id <id>` reads the current account's exact bilingual post, image metadata, author-original locale, and expected version; the Skill edits it only when it is a topic first post;
- `logout --revoke` self-revokes the current key and removes the local credential only after the server confirms success.

Remote forum URLs must be a canonical HTTPS origin because the request contains a publishing credential and the exact post body. User info, paths, queries, and fragments are rejected. Plain HTTP is disabled by default even on loopback; local development must opt in explicitly with `--allow-loopback-http`, and that option must never be used for a remote forum.

## Minimal flow

```bash
local-tool/bin/vibe-forum doctor --site https://forum.example.com
local-tool/bin/vibe-forum auth --site https://forum.example.com
local-tool/bin/vibe-forum doctor --online
local-tool/bin/vibe-forum site-info
local-tool/bin/vibe-forum edit-info --post-id <owned-first-post-id> # required before a first-post edit

# Optional single-image branch. `image-info` is read-only; `image-upload`
# requires its own fresh human confirmation.
local-tool/bin/vibe-forum image-info --file /path/to/proof.png
local-tool/bin/vibe-forum image-upload \
  --file /path/to/proof.png \
  --expected-sha256 <sha256-from-image-info>

local-tool/bin/vibe-forum review-request \
  --manifest local-tool/examples/bilingual-topic.json

# Give that JSON to the AI coding agent already running on your machine. It
# returns a vibe-local-review/v1 JSON report without publishing or rewriting.

local-tool/bin/vibe-forum publish \
  --manifest local-tool/examples/bilingual-topic.json \
  --review local-review.json
```

Before first authorization, run `local-tool/bin/vibe-forum doctor --site https://forum.example.com`. A missing credential makes the report unhealthy but does not start authorization. After authorization, run `doctor --online`; unlike the default local check, it makes one authenticated GET request and fails if the site is unreachable, the key is rejected, the server reports another scope/schema, or the canonical site does not match the credential. Every authorized network write—publication, image upload, and key revocation—repeats that authenticated `site-info` preflight immediately before writing. `site-info` returns the same verified server metadata directly. To remove publishing access safely, run `local-tool/bin/vibe-forum logout --revoke`.

An older publisher credential without the stable installation client ID is reported as `reauthorization_required`. The doctor stops before making a network request; authorize once with the current CLI before continuing.

The manifest must include exactly `en` and `zh-CN`; the source locale identifies which version is the author's original. A new topic retains `category_slug` only as an internal wire field. The Skill obtains it from the sole destination in live `site-info`, never asks the user to select it, and never exposes it in the confirmation preview. Zero or multiple destinations, or a mismatched manifest, stop before any write. `site-info` also returns the live body and title `content_limits`; `publish` fetches and checks them before showing the final preview, so a short or long language version stops before any write and must be changed and reviewed again. An optional image object must contain the real server-returned upload ID and short URL, and each language body must render that same image exactly once. Remote, raw HTML, reference-style, and duplicate images are rejected; examples inside code blocks remain ordinary code. A first-post author edit uses `operation: edit_post` plus the exact `post_id` and `expected_version` returned by `edit-info`, with titles in both variants. The server rejects stale versions and edits to another account's content. Version 0.6.1 can read a legacy `operation: reply` or title-free reply edit locally as 0.6.0 audit evidence, but `publish` and the server reject both operations and point the user to the native forum controls. The 0.6.1 release stores the complete narrow User API credential at `~/.config/vibe-forum/credentials.json` with exact owner-only `0600` permissions on macOS and Linux/POSIX. Keychain integration is retired; explicit `--credential-backend keychain` fails before browser authorization or listener startup. The stable client ID is kept separately at `~/.config/vibe-forum/client-id`, also mode `0600`. An intentionally duplicated publication can use a new explicit `--request-id`; ordinary retries reuse the content-bound key and return the original result.

## Source, permission, credential, and proof boundaries

- The complete Apache-2.0 text is in [`LICENSE`](LICENSE). The distributed runtime is readable Ruby source; no opaque executable is substituted at install time.
- `vibe-governance:publish` is a narrow transport scope, not elevated forum authority. Normal account, topic, author-ownership, content-limit, watched-word, and server-policy checks remain authoritative.
- The credential is a complete secret in a mode-`0600` file. This blocks other POSIX users under normal permissions, but not another process already running as the same OS user. Never commit, upload, log, or place it in a prompt or model context.
- Local review receipts and release hashes prove exact local bytes only. They do not attest to visual image contents, truth of claims, remote repository/tag availability, GitHub settings, external installation, forum reachability, or a production write.
- The marketplace builder records every unverified remote/production gate as `false` in `vibe-publish-release.json`; close those gates only with separate public-source and production evidence.
