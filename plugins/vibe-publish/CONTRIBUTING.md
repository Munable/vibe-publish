# Contributing to Vibe Publish

This directory is the generated Codex Plugin carrier for the canonical repo-local `vibe-publish` Skill and Ruby CLI. User onboarding belongs in `README.md`; development commands belong here.

The packaged Skill resolves `tool/bin/vibe-forum` relative to its own installed location, so it must not search `PATH` for a replacement or require the product repository. The package retains the `vibe-publish/v3` boundary: English and Simplified Chinese are submitted together, author edits use the current post version, optional feature requests remain explicit and bounded, and every external write requires a fresh human confirmation.

Do not edit generated files under `skills/` or `tool/` directly. From the product repository, update `.agents/skills/vibe-publish` or `local-tool`, then run:

```bash
scripts/build-vibe-publish-plugin
scripts/build-vibe-publish-plugin --check
```

Build a controlled marketplace only with a real forum URL and the public HTTPS Git source:

```bash
scripts/build-vibe-publish-marketplace \
  --output /absolute/private/path/vibe-private-marketplace \
  --forum-url "$VIBE_FORUM_URL" \
  --source-url https://github.com/Munable/vibe-publish
```

The builder rejects reserved/example forum hosts, non-loopback forum HTTP, and non-public or non-HTTPS marketplace sources. It writes the exact forum and marketplace URLs plus first-use instructions into the marketplace root `README.md`, sets authentication timing to `ON_USE`, and signs the onboarding README in `vibe-publish-release.json`. The release manifest also records `source_url`.

The isolated acceptance deliberately installs the freshly built local marketplace root while checking the declared public `source_url`. This proves the package without changing the developer's real Codex configuration or depending on GitHub availability:

```bash
scripts/accept-vibe-publish-plugin-install \
  --forum-url http://127.0.0.1:3000 \
  --source-url https://github.com/Munable/vibe-publish
```

Repository checks:

```bash
ruby scripts/test/vibe_publish_marketplace_builder_test.rb
scripts/check
```

Package-local diagnostic commands, useful during development:

```bash
tool/bin/vibe-forum --version
tool/bin/vibe-forum doctor
tool/bin/vibe-forum doctor --online
tool/bin/vibe-forum site-info
tool/bin/vibe-forum edit-info --post-id <owned-post-id>
tool/bin/vibe-forum image-info --file /path/to/proof.png
tool/bin/vibe-forum image-upload --file /path/to/proof.png --expected-sha256 <confirmed-sha256>
tool/bin/vibe-forum logout --revoke
```

`logout --revoke` revokes the current key; it never deletes forum posts. The local credential is removed only after the server confirms revocation.
