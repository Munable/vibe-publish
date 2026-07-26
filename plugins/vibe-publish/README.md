# Vibe Publish 用户说明 / User guide

Vibe Publish 是邀请制 Vibe Forum 的 Codex Plugin。它使用你本地的 Codex 和模型准备英文、简体中文两个版本，通过窄权限 key 提交到论坛。它不会自动发帖、自动回复，也不会绕过最终预览和用户确认。

Vibe Publish is the Codex Plugin for the invite-only Vibe Forum. It uses your local Codex and model to prepare English and Simplified Chinese versions and submits them through a narrow publishing key. It does not post or reply autonomously, and it never skips the final preview and user confirmation.

## 第一次使用 / First use

在终端安装官方 Marketplace 和 Plugin：

Install the official Marketplace and Plugin in a terminal:

```bash
codex plugin marketplace add https://github.com/Munable/vibe-publish
codex plugin add vibe-publish@vibe-private
```

安装后新建一个 Codex 任务，调用名必须准确写成：

After installation, start a new Codex task. The invocation must be exactly:

```text
$vibe-publish:vibe-publish
```

首次本地 `doctor` 返回 `credentials: missing` 是预期结果：Plugin 已安装，但这台设备还没有论坛发布凭据。按引导在浏览器中批准准确的 `vibe-governance:publish` scope，再由 Plugin 运行 `doctor --online` 和 `site-info`。授权发生在第一次使用时，不发生在安装时。

On first use, a local `doctor` result of `credentials: missing` is expected: the Plugin is installed, but this device has no forum publishing credential yet. Follow the browser authorization flow, approve only the exact `vibe-governance:publish` scope, and let the Plugin run `doctor --online` and `site-info`. Authorization happens on first use, not during installation.

## 普通用户能做什么 / Ordinary-user actions

以下内容直接发给 Codex；它会准备双语版本、显示完整预览，并在每次外部写入前等待你的明确确认。

Send these requests directly to Codex. It prepares both languages, shows a complete preview, and waits for your explicit confirmation before each external write.

### 1. 发布主题 / Publish a topic

```text
$vibe-publish:vibe-publish 把下面的项目进展整理成中英双语主题，原文是中文，发到 Build Logs / 构建记录。先给我完整预览，不要直接发布：……
```

### 2. 回复主题 / Reply to a topic

```text
$vibe-publish:vibe-publish 回复这个论坛主题：<从浏览器复制的真实主题 URL>。原文是英文；准备中英双语版本，先给我完整预览：……
```

### 3. 编辑自己的主题或回复 / Edit my own topic or reply

```text
$vibe-publish:vibe-publish 编辑我自己的 post_id <post-id>，同步修正中英文。先读取当前版本并展示 Current / Proposed 差异；版本冲突时停止，不要覆盖。
```

### 4. 撤销这台设备的发布权限 / Revoke this device's publishing access

```text
$vibe-publish:vibe-publish 撤销这台设备的论坛发布权限，并确认服务端已经撤销。
```

撤销 key **不等于删除帖子**。它只撤销这台设备的 `vibe-governance:publish` 凭据；已有主题和回复保持不变。只有论坛确认撤销成功后，本地凭据才会删除。

Revoking the key **does not delete posts**. It only revokes this device's `vibe-governance:publish` credential; existing topics and replies remain. The local credential is deleted only after the forum confirms revocation.

## 本地边界 / Local boundaries

- 当前 Alpha 在 macOS 和 Linux/POSIX 上都把完整的窄权限凭据保存到 `~/.config/vibe-forum/credentials.json`，并强制仅所有者可读写的 `0600` 权限。Keychain 集成已经停用；显式选择 Keychain 会在打开浏览器授权或本地监听器之前直接失败。不要把密钥粘贴到帖子、聊天、issue 或模型上下文中。
- 需要 Codex CLI 的 Plugin 支持，以及 `PATH` 中可用的 Ruby 2.6 或更新版本。
- 当前已验收平台是 macOS。Linux 仍需真机验收；Windows 不属于本 Alpha 的支持范围。
- 普通用户只能用论坛本身允许的分类和主题，并且只能编辑当前账号自己的帖子。
- 当前单次发布最多一张本地 PNG/JPEG。图片上传和帖子写入分别预览、分别确认。
- `doctor` 默认只检查本地状态，不联网；只有 `doctor --online`、`site-info` 和实际授权/写入会访问论坛。

- This Alpha stores the complete narrow credential at `~/.config/vibe-forum/credentials.json` with exact owner-only (`0600`) permissions on both macOS and Linux/POSIX. Keychain integration is retired; an explicit Keychain choice fails before browser authorization or local listener startup. Never paste the key into posts, chats, issues, or model context.
- Codex CLI Plugin support and Ruby 2.6 or newer on `PATH` are required.
- macOS is the currently accepted platform. Linux still needs device acceptance; Windows is outside this Alpha's support boundary.
- Ordinary users remain limited by normal forum category/topic permissions and may edit only their own posts.
- A publication currently supports at most one local PNG/JPEG. Image upload and post writing have separate previews and confirmations.
- Plain `doctor` checks local state without networking. Only `doctor --online`, `site-info`, authorization, and actual writes contact the forum.

仓库开发、同步生成文件和验证说明见 [`CONTRIBUTING.md`](CONTRIBUTING.md)。

Repository development, generated-file synchronization, and validation instructions are in [`CONTRIBUTING.md`](CONTRIBUTING.md).
