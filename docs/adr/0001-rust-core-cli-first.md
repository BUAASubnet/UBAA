# ADR 0001：优先采用 Rust Core 与 CLI

日期：2026-08-17

状态：已接受

适用范围更新：Rust Core 与 facade 边界继续有效。独立 CLI 作为首个宿主的迁移步骤已实施，后续产品入口采用[App 命令模式](../design/desktop-shared-state.md)，最终由 GUI 和命令共用应用服务。当前交付顺序见[路线图](../../UBAA2.md)。以下保留初始决定。

UBAA 2 将协议正确性放在与平台无关的 Rust Core 中，并使用 Rust CLI 作为首个宿主和集成验证器。
KMP 应用和 Ktor 中继仅作为冻结参考，不作为运行时依赖。这样可确保未来各宿主的 Direct/WebVPN
认证、Cookie 处理、重定向、解析和稳定错误保持一致。

Flutter 绑定、MCP、服务器中继和业务 API 延后实现。宿主只消费稳定的 facade DTO，不得深入上游实现模块。
