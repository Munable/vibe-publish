# Contributing to Vibe Publish

Vibe Publish 0.6.1 is distributed under Apache-2.0. The public marketplace repository contains the auditable source snapshot (`.agents/skills/vibe-publish`, `local-tool`, release scripts, and tests) plus the generated install carrier at `plugins/vibe-publish`. In the CommitTown product repository, the equivalent carrier is `codex-plugins/vibe-publish`.

The Skill creates bilingual topics and edits only their first posts. Replies and reply edits use CommitTown's native forum controls. Version 0.6.0 completed the one-release compatibility window; 0.6.1 keeps the old envelope readable for local review evidence but refuses to publish it.

## Developer Certificate of Origin

Contributions use the [Developer Certificate of Origin 1.1](https://developercertificate.org/), not a CLA. Sign off every contribution commit with your real authorship identity:

```bash
git commit -s
```

The resulting commit must contain `Signed-off-by: Name <email>` and certify that you have the right to submit the contribution under Apache-2.0. Do not add a sign-off for another person or submit reconstructed/private code whose redistribution rights are unclear. Maintainers must resolve provenance before release; a passing test or public commit is not rights evidence by itself.

## Change the canonical source

Do not edit generated files under `skills/` or `tool/` directly. Update `.agents/skills/vibe-publish` or `local-tool`, then synchronize and check the carrier:

```bash
scripts/build-vibe-publish-plugin
scripts/build-vibe-publish-plugin --check
```

The builder automatically targets `codex-plugins/vibe-publish` in the product repository or `plugins/vibe-publish` in the public marketplace repository. It rejects unknown files and symlinks. The packaged Skill resolves `tool/bin/vibe-forum` relative to its own installed location and must never search `PATH` for a replacement.

## Build a controlled marketplace

Use a new output directory, the exact forum origin, and the intended public HTTPS Git source:

```bash
scripts/build-vibe-publish-marketplace \
  --output /absolute/private/path/committown-marketplace \
  --forum-url "$COMMITTOWN_FORUM_URL" \
  --source-url https://github.com/Munable/vibe-publish
```

The output includes root and packaged Apache-2.0 licenses, canonical source/tests, the generated Plugin, install instructions, and `vibe-publish-release.json`. The manifest hashes the source snapshot, package, marketplace, onboarding, contributing guide, and license.

The builder validates only local bytes and URL syntax. It does not fetch the declared repository and cannot prove that its `v0.6.1` tag, GitHub Release, branch protections, external installation, forum reachability, or production write exists. Those values remain explicitly `false` in the release manifest until separate post-publication acceptance closes them.

## Run the release checks

```bash
ruby local-tool/test/vibe_forum_local_test.rb
ruby local-tool/test/vibe_publish_plugin_package_test.rb
ruby scripts/test/vibe_publish_marketplace_builder_test.rb
ruby scripts/build-vibe-publish-plugin --check
scripts/accept-vibe-publish-plugin-install \
  --forum-url http://127.0.0.1:3000 \
  --source-url https://github.com/Munable/vibe-publish
```

The isolated acceptance installs the controlled local marketplace under a temporary `CODEX_HOME`; it does not alter the developer's real Codex configuration, contact GitHub, authorize a forum account, or publish. A later public-source acceptance must install `vibe-publish@committown` from the real remote repository.

## Credential and server boundaries

The CLI requests only `vibe-governance:publish`. This scope does not bypass ordinary account, category, topic, author-ownership, content-limit, watched-word, or server-policy checks. The complete key is stored in an owner-only mode-`0600` file, not Keychain; another process running as the same OS user may still read it. Never add a credential to source, tests, issue reports, logs, prompts, or release artifacts.

`logout --revoke` revokes the current key and removes the local credential only after server confirmation. It never deletes forum posts.
