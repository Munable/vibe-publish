# Vibe Publish Marketplace

论坛 / Forum: **https://committown.com**
Marketplace source: **https://github.com/Munable/vibe-publish**

## 立即安装 / Install now

在终端运行：
Run in a terminal:

```bash
codex plugin marketplace add https://github.com/Munable/vibe-publish
codex plugin add vibe-publish@committown
```

检查安装结果；JSON 的 `installed` 列表应包含 `vibe-publish@committown`：
Check the result; the JSON `installed` list should contain `vibe-publish@committown`:

```bash
codex plugin list --marketplace committown --json
```

然后新建一个 Codex 任务，准确输入（`vibe-publish` 必须写两次）：
Then start a new Codex task and enter this exact first-use request (`vibe-publish` appears twice):

```text
$vibe-publish:vibe-publish 第一次使用 / First use. 论坛 / Forum: https://committown.com. 请先检查本地环境；缺少凭据时引导我授权，在线校验成功后停下，不要发布。 / Check the local environment first. If credentials are missing, guide me through authorization, verify online, then stop without publishing.
```

首次运行 `doctor` 报告 `credentials: missing` 是预期状态，不是安装失败。授权只在第一次实际使用时发起。
On first use, `doctor` reporting `credentials: missing` is expected, not an installation failure. Authorization starts only when the Plugin is used.

## 从 0.5 升级 / Upgrade from 0.5

`vibe-private` 与 `committown` 是不同的 marketplace 身份，普通 upgrade 不能重命名。运行：
`vibe-private` and `committown` are distinct marketplace identities; a normal upgrade cannot rename them. Run:

```bash
codex plugin remove vibe-publish@vibe-private
codex plugin marketplace remove vibe-private
codex plugin marketplace add https://github.com/Munable/vibe-publish
codex plugin add vibe-publish@committown
```

然后新建 Codex 任务并运行 `doctor --online`。这些 Codex 命令只处理 Plugin 配置和缓存，不应删除独立的 `~/.config/vibe-forum` 凭据；若在线校验失败，停止写入并重新授权。
Then start a new Codex task and run `doctor --online`. These Codex commands operate on Plugin configuration and cache and should not delete the separate `~/.config/vibe-forum` credential. If online verification fails, stop before writing and reauthorize.

## 前置条件 / Requirements

- Codex CLI with Plugin support.
- Ruby 2.6 or newer available as `ruby` on `PATH`.
- macOS is the currently accepted test platform. Linux still requires device acceptance; Windows is not supported by the 0.6 release.
- A forum account that can approve the exact `vibe-governance:publish` User API Key scope.
- The 0.6 release stores the complete narrow credential at `~/.config/vibe-forum/credentials.json` with exact owner-only (`0600`) permissions on macOS and Linux/POSIX. Keychain is retired; an explicit Keychain choice fails before authorization starts.

## 普通用户示例 / Ordinary-user examples

以下都是发给 Codex 的请求，不是终端命令。每一次写入都会先显示完整预览并等待本人确认。
These are prompts for Codex, not terminal commands. Every write shows a complete preview and waits for the user's confirmation.

**1. 发布主题 / Publish a topic**

```text
$vibe-publish:vibe-publish 把我下面的项目记录整理成中英双语主题，原文是中文。先给我完整预览，不要直接发布：……
```

**2. 回复主题 / Reply to a topic**

请打开真实主题页面并使用论坛原生 **Reply / 回复**。旧版 `reply` manifest 只可由
0.6.1 在本地读取，作为 0.6.0 的审计记录；CLI 和服务端都不会再用它发布或编辑回复。

Open the real topic page and use the forum's native **Reply** action. Version 0.6.1 can read a
legacy `reply` manifest locally as 0.6.0 audit evidence, but neither the CLI nor the server will
use it to publish or edit a reply.

**3. 编辑自己的主题首帖 / Edit my own topic's first post**

```text
$vibe-publish:vibe-publish 编辑我自己的主题首帖 post_id <post-id>，把版本号改成 0.2，并同步更新中英文。先读取当前版本并展示差异，不要覆盖其他人的修改。
```

**4. 撤销发布权限 / Revoke publishing access**

```text
$vibe-publish:vibe-publish 撤销这台设备的论坛发布权限，并确认服务端撤销成功。
```

撤销 key **不会删除任何帖子**；它只撤销这台设备保存的窄权限凭据。服务端确认后，本地凭据才会删除。
Revoking the key **does not delete any post**; it only removes this device's narrow publishing access. The local credential is deleted only after server confirmation.

更多用户说明见 `plugins/vibe-publish/README.md`。
See `plugins/vibe-publish/README.md` for the full user guide.

## 源码、许可证与证明边界 / Source, license, and proof boundaries

- 本仓库以 Apache-2.0 发布；根目录 `LICENSE` 与 Plugin 内 `LICENSE` 内容一致。运行时代码是可读的 Ruby 源码，没有封闭二进制载荷。
- `.agents/skills/vibe-publish`、`local-tool`、构建/验收脚本和测试组成可复核源码快照；`vibe-publish-release.json` 记录源码树、Plugin 树和许可证 SHA-256。
- 本地构建器只验证本地字节和声明的 `https://github.com/Munable/vibe-publish`。它不抓取远程仓库，不能证明远程 tag、GitHub Release、分支保护、外部安装或论坛生产状态；这些字段在发布清单中明确为 `false`，必须在发布后另行验收。
- `vibe-governance:publish` 是窄 User API scope，不会绕过论坛账号、主题、作者归属、内容限制或服务端审核规则。新主题的内部发布目的地由 Plugin 自动解析，不向用户提供选择。
- 完整凭据保存在本机 owner-only `0600` 文件，而不是 Keychain。相同系统账号下能读取该文件的进程仍可能取得凭据；不要把它提交、上传或放入模型上下文。

- This repository is Apache-2.0 licensed. Its root `LICENSE` matches the Plugin copy, and the runtime is readable Ruby source with no closed binary payload.
- `.agents/skills/vibe-publish`, `local-tool`, build/acceptance scripts, and tests form the auditable source snapshot. `vibe-publish-release.json` hashes the source tree, Plugin tree, and license.
- The local builder verifies local bytes and the declared `https://github.com/Munable/vibe-publish` only. It does not fetch the remote repository and cannot prove its tag, GitHub Release, branch protection, external installation, or production forum state. The release manifest records those checks as `false` until separate post-publication acceptance.
- The `vibe-governance:publish` User API scope does not bypass normal account, topic, author-ownership, content-limit, or server-policy enforcement. The Plugin resolves the new-topic destination internally and offers no user choice.
- The complete credential is an owner-only `0600` local file, not a Keychain item. Another process running as the same OS user may still read it; never commit, upload, or place it in model context.
