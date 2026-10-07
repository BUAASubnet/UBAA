# 第三方声明

UBAA 2 使用采用 MIT 许可证的 `buaa-api` 项目作为冻结协议参考：

- Copyright (c) 2025 Fq
- Source: `https://github.com/fontlos/buaa-api.git`
- Fixed commit: `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`
- 许可证：MIT，位于本地参考目录 `examples/buaa-api/License`

实现使用以下 `buaa-api` 文件获取行为证据：

- `src/api/sso/auth.rs`: Direct/WebVPN SSO entry points, execution form fields, and the one-time password-risk continuation.
- `src/api/user/auth.rs` and `src/api/user/opt.rs`: User Center activation/status endpoints and response intent.
- `src/store/cookies.rs`: host/domain, path, Secure, and replacement concepts; UBAA 2 independently adds expiry and persistence hardening.
- `src/api/class/data.rs`: independent evidence that WebVPN protocol segments distinguish HTTP and HTTPS.

协议行为也会与提交 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 的冻结 UBAA v1 仓库比较，重点参照 `docs/migration/references.md` 列出的认证、WebVPN 编解码、Cookie/会话、DTO 和测试文件。协议逻辑在自身合同后独立实现已获证据支持的行为，并将协议/安全决策记录到 `docs/migration/decision-log.md`。

Android桌面课表的 `widgets/WidgetRenderer.kt` 及 `schedule_widget` 布局、背景和组件元数据，移植自上述冻结旧版，保留其绘制结构并适配当前只读模型和日期类型。版权为 Copyright (c) 2026 BUAASubnet，MIT许可证全文随仓库保存在 [ubaa-old-MIT.txt](docs/licenses/ubaa-old-MIT.txt)。

Rust 依赖的许可证元数据以各依赖公开发布的许可证为准；最终 lockfile 是权威依赖清单。

OHOS安全存储插件位于 `packages/flutter_secure_storage_ohos/`，基于Csy_Gitee HUKS fork `f1a8ada0a000f3c3d0e2ad51eed3b86b57969652` 和CPF-Flutter工具代码 `67c7b82e85b08a649dfd4f2bb0c455011a9384fa` 修订，使用Apache-2.0并保留上游BSD声明。原版权头、许可证全文、来源指纹及修改说明均保存在插件目录。
