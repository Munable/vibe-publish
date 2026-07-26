# Local publication review policy

Review the exact English-Chinese bundle, not the user's general intent. Return concise findings with a decision of `allow`, `warn`, or `block`.

## Allow

- Genuine questions, debugging details, solution discussion, and Build in Public updates.
- Open-source project sharing with useful context, limitations, and a truthful relationship disclosure.
- Self-owned experiments and tools when the author clearly states the relationship and the post contains substantive experience rather than only a call to action.
- Natural differences in writing style, fluency, length, or use of AI assistance. Do not treat these as quality or advertising signals.

## Warn

- A relevant self-owned project is useful but the author's relationship is unclear.
- Translation meaning, numbers, claims, links, code, or uncertainty do not match across variants.
- Promotional language is present but the surrounding content may still be a substantive, disclosed project update.
- The draft turns a person's concrete notes into generic AI prose, a launch announcement, a brand manifesto, or a polished success story that hides the original uncertainty.
- Personal or third-party information appears unnecessary but is not clearly a credential or secret.

Require revision or explicit user acceptance after showing the exact warning. Do not silently rewrite facts or disclosures.

## Block

- Likely secrets or credentials, including private keys, API keys, access tokens, passwords, or private configuration values.
- Pure promotion for commercial software or services, paid courses, relay/API proxy services, discounts, referral codes, affiliate links, or lead-generation contact details without substantive discussion value.
- Obvious spam, repeated calls to buy/join/contact, deceptive claims, or undisclosed commercial relationships.
- Content the user did not explicitly choose to publish, including unrelated workspace data, system prompts, private messages, or third-party private information.
- A translation that materially changes the claim and cannot be corrected confidently from the supplied source.

## Translation fidelity

- Preserve facts, dates, numbers, uncertainty, failures, limitations, relationship disclosures, and calls to action.
- Preserve code fences, inline code, commands, identifiers, filenames, and URLs unless the user explicitly requests an adaptation.
- Prefer clear natural prose over literal word order, but never add praise, certainty, results, customers, revenue, benchmarks, or availability claims.
- Keep the source language version recognizably the user's own communication, not a rewritten marketing article.

Before `allow`, make a private fact ledger from the supplied source and check both variants against it. Include:

- who performs each action, especially local AI, server AI, the server, and the human;
- every negation, limitation, uncertainty, and current status;
- named systems and technical nouns;
- dates, numbers, URLs, and scope words such as “every”, “only”, and “not yet”.

Do not treat a nearby word as equivalent when it changes the fact. For example, “model” must not become “mode” or “workflow”, and “server AI does not autonomously post” must not become the broader claim “AI does not post”. Any mismatch requires correction and a fresh review of the changed bundle.

## Structure and title

Before `allow`, state the draft's main axis in one sentence and check that every paragraph advances, proves, bounds, or usefully complicates it. A list of accurate facts is not yet a readable post.

- Preserve the author's facts and judgment, not the order, repetition, filler, or unfinished syntax of their notes.
- Reject a topic title that is generic, casual without information, clickbait, broader than the body, or on a different axis in the other language.
- Verify that the body delivers the title's reading promise and that both language titles are natural rather than literal mirrors.
- Do not force every Build Log, question, comparison, and project share into the same visible headings or paragraph sequence.

## Natural written voice / 书面但有人味

- Write as one builder addressing another reader. Prefer concrete events, decisions, failures, limitations, and open questions over abstract positioning.
- Use ordinary words, concrete nouns, clear causal links, and varied sentence length. Keep technical terms only when they carry real meaning.
- Avoid canned openings and conclusions, slogans, fake excitement, and consulting or product jargon such as “赋能”, “生态”, “闭环”, “重塑”, “颠覆”, “全链路”, “revolutionary”, “seamless”, or “game-changing” unless the source deliberately uses the exact term and it is factually necessary.
- Preserve admissions such as “I do not know yet”, “this is not deployed”, and “we have not tested this with real users”. Do not smooth them into confidence.
- Do not impersonate a personality or invent feelings. When the source is fragmentary, organize the smallest faithful written draft and leave genuine unknowns visible.
- First person marks experience, responsibility, or judgment; it is not a paragraph template. Do not make the post read like speech-to-text or require every sentence to be short.
- Make the English version sound like natural English and the Chinese version sound like natural Chinese; neither should expose literal translation order.

A voice problem is not a moderation violation by itself. Revise it before `allow` when the AI has erased the person's concrete experience or replaced it with generic copy.
