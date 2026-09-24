# Vibe Publish — experiment notes / 试验项目笔记

Internal test repository outside Marine Mystique's five company products; not a company website entry. / 本仓库为内部试验，不属于蓝色聚合官网展示的五个公司产品。

Reviewed 2026-09-24 against public source `0f1c362`. This document explains the existing 0.6.1 publishing model. It does not change the released Plugin, its manifest or CommitTown's paused operating status.

## The point / 核心

**Your experience. Two languages. Your call to publish.**

Vibe Publish helps turn a person's real work into an English–Chinese CommitTown topic. Their local AI prepares and reviews both versions; the person sees the complete text and decides what leaves their computer.

**你的经历，两种语言，由你发布。**

Vibe Publish 把真实做事的经历整理成 CommitTown 的中英双语主题。用户身边的 AI 协助编辑、翻译和检查，完整内容展示后，由本人决定是否发出。

The central value is carrying one person's experience across a language boundary while keeping authorship and the final decision with that person. Drafting, local review, an exact preview and narrow publishing permission all serve that one goal.

核心价值是让同一段真实经验跨过语言边界，同时保留作者的责任与决定权。编辑、作者自己的 AI 审阅、完整预览和窄权限发布，都服务于这一件事。

## Choices and tradeoffs / 选择与取舍

| Product choice / 产品选择 | Why it matters / 作用 | Cost / 代价 |
| --- | --- | --- |
| Prepare both languages before sending / 发出前准备完整双语 | Readers receive two deliberate versions of the same topic / 读者看到语义对应的两份成稿 | The author reviews more material before publication / 作者发布前需要多检查一份文字 |
| Use the author's local AI workflow / 使用作者本地的 AI 工作流程 | Existing context can become useful writing with explicit source selection / 可在明确选定材料后利用已有上下文 | Requires a compatible local tool and model; “local” does not mean the AI model runs offline / 依赖相应本地工具和模型；“本地”不等于模型离线运行 |
| Bind review and confirmation to exact content / 检查与确认绑定到准确内容 | The author approves what will actually be sent / 作者确认真正要发出的内容 | Changed content needs a fresh review and confirmation / 内容改变后需重新检查和确认 |
| Topic creation and first-post edits only / 聚焦主题及首帖编辑 | Longer contributions get deliberate preparation / 较完整的经验分享获得充分准备 | Replies stay in the forum's native conversation flow / 回复保留在论坛原生交流流程中 |

This test applies the software-to-reality idea to communication: completed work can become experience another person can understand and use.

它把“软件改变现实”的理念落实到交流：让已经发生的工作，变成其他人能够理解和使用的经验。

## Evidence and wording / 证据与表述

- [Canonical Skill](.agents/skills/vibe-publish/SKILL.md): user-selected source material, bilingual drafting, human authorship and explicit publication confirmation.
- [Editorial method](.agents/skills/vibe-publish/references/editorial-method.md): one clear axis, faithful claims and natural English/Chinese versions.
- [Local tool](local-tool/lib/vibe_forum_local.rb): `Envelope.validate!`, content-bound `Review.validate!`, complete preview and the explicit `publish` confirmation before the HTTP write.
- [Tool guide](local-tool/README.md): narrow `vibe-governance:publish` scope, author/version-bound edits and retry-safe publication.
- [Root README](README.md): the public Apache-2.0 source and supported installation boundary. Its release snapshot is unchanged by this document.

Repository category: **Open-source bilingual publishing tool; internal experiment in the company index**. CommitTown is paused; do not imply that this note reopens the community or verifies current forum operation.

仓库分类：**开源双语发布工具；在公司索引中属于内部试验**。CommitTown 仍暂停运营，本次整理不意味着社区重启，也不证明论坛当前可用。

Do not claim perfect translation, automatic fact verification, confidential/offline model processing, spam elimination, autonomous posting or all-platform publishing. The code can enforce envelope shape, exact-content review binding and confirmation; the quality of editing and translation depends on the selected AI and human review.

不宣称完美翻译、自动核实事实、模型处理完全离线保密、消除垃圾内容、无人值守发帖或全平台发布。程序能约束内容结构、检查与正文的绑定和发送确认；编辑、翻译的质量仍取决于所选 AI 和作者审阅。

## Experiment summary / 试验摘要

**Your experience. Two languages. Your call to publish.** An open-source tool that prepares English–Chinese topics for CommitTown with your AI, then puts the complete text in your hands before it is shared.

**你的经历，两种语言，由你发布。** 用你的 AI 为 CommitTown 整理中英双语主题。完整成稿先交到你手里，再由你决定发出。
