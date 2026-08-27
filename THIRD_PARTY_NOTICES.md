# 第三方声明

UBAA 2 使用采用 MIT 许可证的 `buaa-api` 项目作为冻结协议参考：

- Copyright (c) 2025 Fq
- Source: `https://github.com/fontlos/buaa-api.git`
- Fixed commit: `efb7976bf513f38364b88aeb83d704586cff9b2a`
- 许可证：MIT，位于本地参考目录 `examples/buaa-api/License`

实现使用以下 `buaa-api` 文件获取行为证据：

- `src/api/sso/auth.rs`: Direct/WebVPN SSO entry points, execution form fields, and the one-time password-risk continuation.
- `src/api/user/auth.rs` and `src/api/user/opt.rs`: User Center activation/status endpoints and response intent.
- `src/store/cookies.rs`: host/domain, path, Secure, and replacement concepts; UBAA 2 independently adds expiry and persistence hardening.
- `src/api/class/data.rs`: independent evidence that WebVPN protocol segments distinguish HTTP and HTTPS.

协议行为也会与提交 `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e` 的冻结 UBAA v1 仓库比较，重点参照 `docs/migration/references.md` 列出的认证、WebVPN 编解码、Cookie/会话、DTO 和测试文件。UBAA 2 不复制任一参考项目的源码文本，而是在自身合同后独立实现已获证据支持的行为，并将协议/安全决策记录到 `docs/migration/decision-log.md`。

Rust 依赖的许可证元数据以各依赖公开发布的许可证为准；最终 lockfile 是权威依赖清单。
