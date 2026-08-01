# CommitTown Vibe Publish 用户说明 / User guide

Vibe Publish 是 CommitTown 的 Apache-2.0 开源本地发布 Plugin。无论你用 Vibe Coding 工具处理代码、建模、研究、内容、表格还是行政工作，它都会在你的设备上整理主题、准备英文和简体中文两个版本，再通过窄权限 key 提交。0.6 Skill 只发布主题或编辑主题首帖；回复和回复编辑使用论坛原生控件。它不会自动发帖、自动回复，也不会绕过最终预览和用户确认。

Vibe Publish is CommitTown's Apache-2.0 open-source local publishing Plugin. Whether your Vibe Coding work involves code, modeling, research, content, spreadsheets, or administration, it prepares English and Simplified Chinese topics on your device and submits them through a narrow publishing key. Version 0.6.1 publishes topics or edits their first posts only; replies and reply edits use the forum's native controls. It does not post or reply autonomously, and it never skips the final preview and user confirmation.

## 第一次使用 / First use

在终端安装官方 Marketplace 和 Plugin：

Install the official Marketplace and Plugin in a terminal:

```bash
codex plugin marketplace add https://github.com/Munable/vibe-publish
codex plugin add vibe-publish@committown
```

安装后新建一个 Codex 任务，调用名必须准确写成：

After installation, start a new Codex task. The invocation must be exactly:

```text
$vibe-publish:vibe-publish
```

首次本地 `doctor` 返回 `credentials: missing` 是预期结果：Plugin 已安装，但这台设备还没有论坛发布凭据。按引导在浏览器中批准准确的 `vibe-governance:publish` scope，再由 Plugin 运行 `doctor --online` 和 `site-info`。授权发生在第一次使用时，不发生在安装时。

On first use, a local `doctor` result of `credentials: missing` is expected: the Plugin is installed, but this device has no forum publishing credential yet. Follow the browser authorization flow, approve only the exact `vibe-governance:publish` scope, and let the Plugin run `doctor --online` and `site-info`. Authorization happens on first use, not during installation.

## 从 0.5 升级 / Upgrade from 0.5

旧 marketplace 名 `vibe-private` 与新名称 `committown` 是两个安装身份，不能靠普通 upgrade 自动改名。先移除旧 Plugin 和旧 marketplace，再添加公开来源并安装新身份：

The old `vibe-private` marketplace and the new `committown` marketplace are distinct installation identities. A normal upgrade cannot rename one into the other. Remove the old Plugin and marketplace, then add the public source and install the new identity:

```bash
codex plugin remove vibe-publish@vibe-private
codex plugin marketplace remove vibe-private
codex plugin marketplace add https://github.com/Munable/vibe-publish
codex plugin add vibe-publish@committown
```

随后新建 Codex 任务并运行 `doctor --online`。上述 Codex 移除命令只处理 Plugin 配置和缓存，不应删除独立的 `~/.config/vibe-forum` 凭据；0.6 隔离验收会检查这一点。若在线校验失败，停止写入并重新授权，不要复制或手工修改 key。

Start a new Codex task and run `doctor --online`. Those Codex removal commands operate on Plugin configuration and cache and should not delete the separate `~/.config/vibe-forum` credential; the isolated 0.6 acceptance checks this. If online verification fails, stop before writing and reauthorize instead of copying or editing the key.

## 普通用户能做什么 / Ordinary-user actions

以下内容直接发给 Codex；它会准备双语版本、显示完整预览，并在每次外部写入前等待你的明确确认。

Send these requests directly to Codex. It prepares both languages, shows a complete preview, and waits for your explicit confirmation before each external write.

## 默认写法 / Default writing shape

主题默认先用一小段具体经历说明“发生了什么、为什么现在写”，随后尽快给出主结论。
较长主题只用少量与内容有关的小标题；短主题不强行加小标题。Plugin 会删掉重复结论、
功能清单和不影响判断的过程细节，但保留失败、限制、数字、代码和未确定事项。中文和英文
共享同一主轴，各自按本语言自然表达，不逐句硬译。

Topics begin with a short, factual human entrance that explains what happened and why the author is
writing now, then move quickly to the main point. Longer topics use a few content-specific headings;
short topics are not padded with headings. The Plugin removes repeated conclusions,
feature inventories, and process detail that does not affect the judgment while preserving failures,
limits, numbers, code, and unknowns. English and Chinese keep the same axis but read naturally rather
than mirroring sentence order.

### 1. 发布主题 / Publish a topic

```text
$vibe-publish:vibe-publish 把下面的项目进展整理成中英双语主题，原文是中文。先给我完整预览，不要直接发布：……
```

工作内容不必是软件项目。例如：

```text
$vibe-publish:vibe-publish 把我用本地 Agent 整理这批发票时遇到的问题和解决办法写成中英双语主题。末尾保留“我正在寻找类似流程的合作项目”这句并说明我的关系。先给完整预览，不要直接发布。
```

The work does not have to be a software project. For example:

```text
$vibe-publish:vibe-publish Turn my notes about using a local Agent to reconcile invoices into an English-Chinese topic. Keep the disclosed collaboration note at the end. Show the complete preview and do not publish yet.
```

### 2. 回复主题 / Reply to a topic

打开真实主题页面，使用论坛原生 **Reply / 回复**。如需引用某一楼，先点该帖的 Reply。0.6.1 只能在本地读取旧版 `reply` manifest，作为 0.6.0 的审计记录；CLI 和服务端都不会再用它发布或编辑回复。

Open the real topic page and use the forum's native **Reply** action. To quote a specific post, start from that post's Reply control. The single compatibility release ended with 0.6.0; version 0.6.1 refuses to publish or edit replies through the CLI/API.

### 3. 编辑自己的主题首帖 / Edit my own topic's first post

```text
$vibe-publish:vibe-publish 编辑我自己的主题首帖 post_id <post-id>，同步修正中英文。先读取当前版本并展示 Current / Proposed 差异；版本冲突时停止，不要覆盖。
```

如果 `edit-info` 返回的是无标题回复，Skill 会停止并指引你使用论坛原生编辑器。
If `edit-info` returns a title-free reply, the Skill stops and directs you to the native forum editor.

### 4. 撤销这台设备的发布权限 / Revoke this device's publishing access

```text
$vibe-publish:vibe-publish 撤销这台设备的论坛发布权限，并确认服务端已经撤销。
```

撤销 key **不等于删除帖子**。它只撤销这台设备的 `vibe-governance:publish` 凭据；已有主题和回复保持不变。只有论坛确认撤销成功后，本地凭据才会删除。

Revoking the key **does not delete posts**. It only revokes this device's `vibe-governance:publish` credential; existing topics and replies remain. The local credential is deleted only after the forum confirms revocation.

## 本地边界 / Local boundaries

- 0.6 在 macOS 和 Linux/POSIX 上都把完整的窄权限凭据保存到 `~/.config/vibe-forum/credentials.json`，并强制仅所有者可读写的 `0600` 权限。Keychain 集成已经停用；显式选择 Keychain 会在打开浏览器授权或本地监听器之前直接失败。相同系统账号下运行的其他进程仍可能读取该文件；不要把密钥粘贴到帖子、聊天、issue 或模型上下文中。
- 需要 Codex CLI 的 Plugin 支持，以及 `PATH` 中可用的 Ruby 2.6 或更新版本。
- 当前已验收平台是 macOS。Linux 仍需真机验收；Windows 不属于 0.6 的支持范围。
- 普通用户仍受论坛账号、主题和作者归属规则限制，并且只能编辑当前账号自己的主题首帖。新主题的内部发布目的地由 Plugin 自动解析，不向用户提供选择。
- 当前单次发布最多一张本地 PNG/JPEG。图片上传和帖子写入分别预览、分别确认。
- `doctor` 默认只检查本地状态，不联网；只有 `doctor --online`、`site-info` 和实际授权/写入会访问论坛。

- The 0.6 release stores the complete narrow credential at `~/.config/vibe-forum/credentials.json` with exact owner-only (`0600`) permissions on both macOS and Linux/POSIX. Keychain integration is retired; an explicit Keychain choice fails before browser authorization or local listener startup. Another process running as the same OS user may still read the file. Never paste the key into posts, chats, issues, or model context.
- Codex CLI Plugin support and Ruby 2.6 or newer on `PATH` are required.
- macOS is the currently accepted platform. Linux still needs device acceptance; Windows is outside the 0.6 support boundary.
- Ordinary users remain limited by normal account, topic, and author-ownership rules and may edit only their own topic's first post. The Plugin resolves the new-topic destination internally and offers no user choice.
- A publication currently supports at most one local PNG/JPEG. Image upload and post writing have separate previews and confirmations.
- Plain `doctor` checks local state without networking. Only `doctor --online`, `site-info`, authorization, and actual writes contact the forum.

仓库开发、同步生成文件和验证说明见 [`CONTRIBUTING.md`](CONTRIBUTING.md)。

Repository development, generated-file synchronization, and validation instructions are in [`CONTRIBUTING.md`](CONTRIBUTING.md).

## 开源与证明边界 / Open-source and proof boundaries

- 本包依照 [Apache-2.0](LICENSE) 发布，包含可读 Skill、Ruby CLI 源码和完整许可证，不包含安装时替换的封闭二进制。
- `vibe-governance:publish` 只是窄 User API scope，不会越过论坛账号、主题、作者归属、内容限制或服务端规则。
- 本地 review receipt、文件哈希和隔离安装只证明本地字节；不能证明远程仓库/tag、GitHub Release/保护规则、外部安装、论坛可达性或生产写入。
- 发布仓库的 `vibe-publish-release.json` 会把这些远程与生产门明确记录为未验证，直到另有实际证据。

- This package is licensed under [Apache-2.0](LICENSE) and ships readable Skill and Ruby CLI source with no closed install-time replacement.
- `vibe-governance:publish` is a narrow User API scope; it does not bypass normal account, topic, author-ownership, content-limit, or server-policy checks.
- A local review receipt, file hashes, and isolated install prove local bytes only—not the remote repository/tag, GitHub Release or protections, external installation, forum reachability, or a production write.
- The public `vibe-publish-release.json` records those remote and production gates as unverified until separate evidence closes them.
