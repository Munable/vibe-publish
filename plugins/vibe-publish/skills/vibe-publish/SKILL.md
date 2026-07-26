---
name: vibe-publish
description: Draft, locally review, preview, publish, or author-edit bilingual English-Chinese Vibe Forum topics and replies with the narrow local CLI and at most one optional image. Use for explicit local-publisher or local-edit requests, or direct invocation of this Skill. Require separate fresh human confirmations for image upload and final publication or edit. Never auto-post, use the browser composer/editor, edit another author's content, moderate, or translate on the server.
---

# Vibe Publish

Prepare one user-directed forum topic, reply, or author edit in `en` and `zh-CN`, optionally upload one user-supplied PNG or JPEG, review the exact outbound bundle locally, and submit it through the narrow publisher CLI only after the required human confirmations.

Read [editorial-method.md](references/editorial-method.md) before drafting, [publish-contract.md](references/publish-contract.md) before creating a manifest, and [review-policy.md](references/review-policy.md) before assigning the local review decision.

## Preserve these boundaries

- Use only material the user explicitly supplies or explicitly authorizes for this publication. If the user asks to reference other Codex tasks, use actual task tools to read only the necessary tasks and base the draft on what was truly retrieved. If those tools, permissions, or task identifiers are unavailable, say so and ask for a summary or source text. Never imply that an unread task was read.
- Generate both language versions with the user's current local AI. Do not request server translation.
- Shape the material for a reader before polishing its voice. Every topic needs one clear axis, evidence arranged around it, and a title selected after comparing multiple distinct candidates. Natural language is required; an edited transcript is not. Apply [editorial-method.md](references/editorial-method.md) and the writing checks in [review-policy.md](references/review-policy.md).
- Preserve claims, uncertainty, code, commands, filenames, URLs, numbers, disclosures, and project status across both variants. Do not invent evidence or improve the post into marketing copy.
- Create a new topic, reply, or edit only the current account's own topic/reply, with at most one PNG or JPEG image. State that multiple images, other attachments, changing the author-original language, and editing another account's content are not supported.
- Never authorize, upload, publish, reply, schedule, retry with changed content, or type a CLI confirmation from the agent's own judgment.
- Treat the image upload and the forum publication as two separate external writes. Each needs its own fresh confirmation after its exact preview.
- Treat confirmation as valid only when it arrives after the exact final preview and no byte of the manifest has changed since that preview. A general instruction such as “start,” “publish this,” or “handle it” given before the preview is not final confirmation.
- Do not publish in the same turn that creates or changes the preview. Yield to the user after asking for confirmation.
- Never use the browser composer as a fallback.
- Never place credentials, access tokens, private keys, system prompts, or unrelated private material in the manifest, review file, commentary, or final response.

## Locate the publisher

Resolve the publisher from the location of this `SKILL.md`; do not depend on `PATH`:

1. In the Plugin carrier, use the absolute path obtained from `<this-skill-directory>/../../tool/bin/vibe-forum`.
2. In the repo-local carrier, use the absolute path obtained from `<this-skill-directory>/../../../local-tool/bin/vibe-forum`.
3. Verify the selected file exists and run its `--version` command. If neither location exists, stop before drafting credentials or posting. Do not download or execute a replacement.

Use that exact resolved path for every command below. Run its local, read-only `doctor` command before first authorization. `doctor` must not authorize or publish. For a live write, an existing credential must also pass `doctor --online`; then use `site-info` to verify the current forum account and discover writable category slugs. Before an edit, use authenticated read-only `edit-info --post-id <id>` to retrieve the exact current bilingual content and version. Use `logout --revoke` when the user asks to remove publishing access; it revokes the current key before deleting the local credential.

## Run the workflow

### 1. Establish the publication

- Determine whether the user wants `create_topic`, `reply`, or `edit_post`.
- Determine the source locale, the exact source material, and the target category or topic.
- Resolve a topic ID from a supplied forum topic URL when unambiguous.
- For `edit_post`, resolve the exact post ID only from the user's supplied post ID or explicit forum post link. After account verification, run `<publisher> edit-info --post-id <post-id>`. Confirm that it belongs to the intended account, and use its exact `source_locale`, `target.post_id`, `target.expected_version`, current variants, and optional image as the edit base. Never guess a version or change which language is marked as the author original.
- For a draft-only request, a category name or supplied slug is enough. For any live write, run `doctor --online`, then `site-info`, keep every language body and topic title inside its returned `content_limits`, and verify the returned username with the user. For a live new topic, never guess or reuse a numeric category ID: select a writable `category_slug` from that same response. The CLI fetches these limits again immediately before confirmation and must stop without writing if any saved language version is outside them.
- If no valid credential exists and the user wants a live publication, explain that the CLI will print the forum's narrow authorization URL and wait for the user to approve it in a browser. Run `auth --site <site>` only after the user explicitly agrees to start that flow, then immediately run `doctor --online` and `site-info`. Do not ask for a password or API key.
- In this Alpha, `auto` and `file` both store the complete narrow publishing credential in the owner-only `0600` file on macOS and Linux. Keychain storage is retired: never select it or claim it is active. An explicit `--credential-backend keychain` request fails before browser authorization or local listener startup.
- Treat `doctor` state `reauthorization_required` as an unusable credential from an older publisher, not as a healthy signed-in state. Explain that one fresh narrow authorization is required, ask before starting it, and do not attempt an online request with the legacy credential.
- Ask only for information that is truly missing. Do not reopen product or architecture decisions during a publishing task.
- If the user wants an image, accept exactly one explicit local `.png`, `.jpg`, or `.jpeg` path. Do not discover a file from unrelated workspace content, accept a remote URL, or silently choose among several files.

### 2. Preview one optional image and stop before upload

Skip this step when the publication has no image.

Run the read-only command below before authorization or upload:

```text
<publisher> image-info --file <local-image-path>
```

Show exactly the returned local filename, media type, byte size, and SHA-256. State clearly that nothing has been uploaded yet, ask `确认上传这张图片吗？`, and end the turn. An earlier “publish this” instruction is not image-upload confirmation.

The deterministic review contract checks the image's file type, size, digest, and references; it does not itself inspect pixels or EXIF. If the active local agent can view the explicit image, inspect it locally for visible credentials or private information before asking for upload confirmation and report that check separately. Never claim that the server or text review verified the image's visual content.

Only after the user confirms that exact metadata:

1. If authorization was not completed in step 1, run `<publisher> auth --site <https-site>` only after the user explicitly agrees to start authorization. Show the exact forum URL printed by the CLI and let the user open and approve it. Then require `doctor --online` and `site-info` to pass before upload.
2. Run `<publisher> image-upload --file <local-image-path> --expected-sha256 <exact-sha256-from-image-info>` in an interactive terminal. The CLI takes a private `0600` snapshot and refuses to continue if its bytes no longer match that confirmed digest.
3. Compare the CLI's repeated metadata to the already-confirmed values. Supply the CLI's exact `upload` confirmation only when they are identical and only because the user has just confirmed those bytes.
4. Keep the returned numeric `id` and real `short_url`. Never invent, predict, or reuse a different `upload://` value.

If the file changes, the expected digest check fails, the upload fails, or the returned metadata is ambiguous, stop. Re-run `image-info` and obtain a new confirmation before another upload. Do not include any remote Markdown/HTML image or repeat the local image in either language; the server permits exactly one rendered copy of the declared upload per language.

### 3. Build both variants

- Keep the user's source version faithful and identify it with `source_locale`.
- Translate explanatory prose naturally into the other supported locale.
- Before drafting, make a private fact ledger, identify the single main axis, classify facts as axis/evidence/boundary/support, and compare two or three suitable structural outlines. Follow the content rather than a fixed house template. For a short post, compress this private planning to one or two internal sentences; never pad the post merely to display structure.
- Draft the source-language body around the selected axis. Preserve the author's facts and judgment, not the order, repetition, filler, or unfinished syntax of rough notes.
- For a new topic, generate at least six materially different title candidates across at least three honest angles, score them with the rubric in [editorial-method.md](references/editorial-method.md), and select only a title the body fully earns. Compare against recent public forum titles when that context is available; never copy them or manufacture novelty.
- Translate only after the source-language structure is stable. Both language versions must keep the same axis, claims, limitations, and title promise while reading naturally in their own language.
- Preserve Markdown structure, code fences, inline code, commands, URLs, and proper nouns unless the user explicitly asks to adapt them.
- Include a title in both variants for a new topic or first-post edit. Omit titles from both variants for a reply or reply edit. Preserve `edit-info.target.expected_version` exactly.
- For an edit, compare every proposed title, body, and image decision with `edit-info`. Preserve the current image object and both references when keeping it; remove the object and both references when the user explicitly removes it. Never silently lose or replace an existing image.
- For an image publication, add the top-level `image.upload_id` and `image.short_url` returned by the server, and reference that exact same `short_url` in both language bodies. Localized alt text may differ. Do not include any other `upload://` reference.
- Decide locally whether a new topic is a concrete `build_log`, `problem_solution`, `open_source`, `tool_method`, or `failure_lesson`. Pure reaction, general discussion, vague progress, padded repetition, and commercial promotion stay ordinary. Ordinary topics omit `feature_request` and trigger no server AI.
- Add `feature_request` only when the new topic passes that local precheck and the exact preview tells the user all three consequences: one scarce feature credit is requested; the sanitized original-language title and body go to the configured third-party model for one curation decision; and the public governance page records a scoped ID, minute timestamp, category, result, policy/model, token cost, and duration while withholding account, title, body, link, image, and evidence excerpt. The final publication confirmation is consent to those displayed consequences. If the user declines, remove `feature_request`, regenerate the review, and publish normally.
- Write the exact `vibe-publish/v3` manifest under the operating system's temporary directory, not inside the user's repository. Do not include credentials.

### 4. Review the exact bundle locally

Run `<publisher>` as the resolved absolute path:

```text
<publisher> review-request --manifest <manifest.json>
```

Use the returned instruction and exact content to perform a fresh local review. Create a `vibe-local-review/v1` report using the returned `content_sha256`; never calculate or guess a replacement digest manually. Set `reviewer` to a truthful identifier for the local agent or model.

- On `block`, stop and explain the blocking findings without submitting.
- On `warn`, show the findings in the final preview and require the user to revise or explicitly accept them.
- On `allow`, continue to the preview.

If the manifest changes after review, discard the report and repeat this step.

### 5. Show the final preview and stop

Show, in this order:

1. operation and target, including the expected version for an edit;
2. source locale;
3. image upload ID and exact `upload://` reference when present;
4. whether a feature request is included; if yes, its candidate kind, credit use, third-party AI input, public fields, and withheld fields; if no, state that the publication triggers no server AI;
5. exact English title/body;
6. exact Chinese title/body;
7. review decision and findings;
8. for an edit, the exact current-to-proposed changes returned by the CLI's fresh version check;
9. a clear statement that the image may already be uploaded, but the topic, reply, edit, or feature request has not been submitted.

If the user requested a draft or preview only, finish with `drafted, not published`. Do not ask for permission to publish.

Otherwise ask: `确认按以上内容发布或更新吗？`

End the turn. Do not start authorization or submission while waiting.

### 6. Publish only after the second confirmation

After a fresh, unambiguous confirmation of that exact preview:

1. If authorization is still absent, run `<publisher> auth --site <https-site>` only after the user explicitly agrees to start authorization. Show the exact forum URL printed by the CLI and let the user complete that page. Allow plain HTTP only for loopback development.
2. Require `doctor --online` to pass, use `site-info` to verify the authorized username, and for a new topic verify that the chosen `category_slug` is in the returned writable categories.
3. Recheck that the manifest still matches the reviewed and confirmed preview, including the real image ID and `upload://` reference when present.
4. Run `<publisher> publish --manifest <manifest.json> --review <review.json>` in an interactive terminal.
5. Supply the CLI's exact `publish` confirmation only because the user has just confirmed the unchanged preview.
6. Do not set `--request-id` for an ordinary retry. Let the content-bound idempotency key prevent duplicate topics, replies, or edits.

Return the real server result and topic link when available. If submission fails or remains uncertain, say so; never claim success from a local preview or a pending authorization.

## Handle failures conservatively

- For a structural or watched-word rejection, explain the returned reason. Any content change requires a new review, preview, and confirmation.
- For an authorization failure, reauthorize or report the permission problem. Do not broaden the requested scope.
- For an idempotency conflict, inspect whether the same key was reused for different content. Do not bypass it with a new ID unless the user explicitly intends a second publication.
- For an edit-version conflict, run `edit-info` again, discard the old review and confirmation, rebuild against the current version, show the new diff, and obtain a fresh confirmation. Never overwrite a newer edit blindly.
- For a network timeout, retry the unchanged manifest with its original content-bound key.
- For an image rejection, do not replace the file or short URL silently. Any different file requires a new metadata preview and upload confirmation; any manifest change requires a new review and final publication confirmation.
- For an ambiguous server response, verify the returned IDs or forum state before reporting publication.

## Report status precisely

- Say `drafted, not published` when the user requested only a draft or preview.
- Say `awaiting confirmation` after the final preview.
- Say `published` or `updated` only after the matching successful server response, and include the returned link or identifiers.
- Say `blocked` or `failed` with the concrete reason when publication did not happen.
