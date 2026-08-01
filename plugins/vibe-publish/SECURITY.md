# Security Policy

## Supported release

Security fixes target the latest published Vibe Publish 0.6 release. A source snapshot, local build, or passing test suite does not prove that a fix is present in the public Git tag, installed Plugin, or production forum; verify the exact affected version and release hash.

## Report a vulnerability

Use the repository's **Security** tab and **Report a vulnerability** to open a private GitHub Security Advisory when private vulnerability reporting is available. Include the affected Vibe Publish version, file or release hash, impact, and the smallest sanitized reproduction that does not contact the production forum.

If private reporting is unavailable, open a public issue containing only a request for private security coordination. Do not include exploit details, credentials, tokens, private forum content, account data, or a working production target in that issue. Maintainers can then establish an appropriate private channel without publishing the vulnerability.

Do not demonstrate a report by authorizing, uploading, publishing, editing, revoking another user's access, or testing against production data. Use an isolated local environment or a maintainer-approved disposable test target. Never attach `~/.config/vibe-forum/credentials.json` or its contents.

## Scope boundaries

- The Apache-2.0 source and release hashes support auditability; they are not a security attestation or warranty.
- Mode `0600` protects the credential from other POSIX users under normal permissions, not from another process already running as the same OS user.
- `vibe-governance:publish` is a narrow User API scope and does not replace the forum's account, author-ownership, content, or server-policy enforcement.
- Availability of the remote repository, tag, GitHub Security settings, installed bytes, and production behavior requires separate live evidence.
