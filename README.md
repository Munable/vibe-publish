# Vibe Publish Marketplace

论坛 / Forum: **https://discourse-production-1690.up.railway.app**
Marketplace source: **https://github.com/Munable/vibe-publish**

## 立即安装 / Install now

在终端运行：
Run in a terminal:

```bash
codex plugin marketplace add https://github.com/Munable/vibe-publish
codex plugin add vibe-publish@vibe-private
```

检查安装结果；JSON 的 `installed` 列表应包含 `vibe-publish@vibe-private`：
Check the result; the JSON `installed` list should contain `vibe-publish@vibe-private`:

```bash
codex plugin list --marketplace vibe-private --json
```

然后新建一个 Codex 任务，准确输入（`vibe-publish` 必须写两次）：
Then start a new Codex task and enter this exact first-use request (`vibe-publish` appears twice):

```text
$vibe-publish:vibe-publish 第一次使用 / First use. 论坛 / Forum: https://discourse-production-1690.up.railway.app. 请先检查本地环境；缺少凭据时引导我授权，在线校验成功后停下，不要发布。 / Check the local environment first. If credentials are missing, guide me through authorization, verify online, then stop without publishing.
```

首次运行 `doctor` 报告 `credentials: missing` 是预期状态，不是安装失败。授权只在第一次实际使用时发起。
On first use, `doctor` reporting `credentials: missing` is expected, not an installation failure. Authorization starts only when the Plugin is used.

## 前置条件 / Requirements

- Codex CLI with Plugin support.
- Ruby 2.6 or newer available as `ruby` on `PATH`.
- macOS is the currently accepted test platform. Linux still requires device acceptance; Windows is not supported by this Alpha package.
- A forum account that can approve the exact `vibe-governance:publish` User API Key scope.
- This Alpha stores the complete narrow credential at `~/.config/vibe-forum/credentials.json` with exact owner-only (`0600`) permissions on macOS and Linux/POSIX. Keychain is retired; an explicit Keychain choice fails before authorization starts.

## 普通用户示例 / Ordinary-user examples

以下都是发给 Codex 的请求，不是终端命令。每一次写入都会先显示完整预览并等待本人确认。
These are prompts for Codex, not terminal commands. Every write shows a complete preview and waits for the user's confirmation.

**1. 发布主题 / Publish a topic**

```text
$vibe-publish:vibe-publish 把我下面的项目记录整理成中英双语主题，原文是中文，发布到 Build Logs / 构建记录。先给我完整预览，不要直接发布：……
```

**2. 回复主题 / Reply to a topic**

```text
$vibe-publish:vibe-publish 回复 https://discourse-production-1690.up.railway.app/t/<topic-slug>/<topic-id>。原文是英文；生成中英双语版本，先给我完整预览：……
```

**3. 编辑自己的帖子 / Edit my own post**

```text
$vibe-publish:vibe-publish 编辑我自己的 post_id <post-id>，把版本号改成 0.2，并同步更新中英文。先读取当前版本并展示差异，不要覆盖其他人的修改。
```

**4. 撤销发布权限 / Revoke publishing access**

```text
$vibe-publish:vibe-publish 撤销这台设备的论坛发布权限，并确认服务端撤销成功。
```

撤销 key **不会删除任何帖子**；它只撤销这台设备保存的窄权限凭据。服务端确认后，本地凭据才会删除。
Revoking the key **does not delete any post**; it only removes this device's narrow publishing access. The local credential is deleted only after server confirmation.

更多用户说明见 `plugins/vibe-publish/README.md`。
See `plugins/vibe-publish/README.md` for the full user guide.
