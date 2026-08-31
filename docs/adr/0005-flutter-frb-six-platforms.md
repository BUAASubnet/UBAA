# ADR 0005：Flutter + FRB 六平台宿主

状态：接受
日期：2026-09-01

## 背景

UBAA 2 已把认证、Direct/WebVPN 路由、Cookie/session 和业务协议集中到 Rust Core facade。新 GUI 需要覆盖 Windows、macOS、Linux、Android、iOS 和 HarmonyOS，同时避免六套宿主复制协议逻辑。

## 决定

1. Windows、macOS、Linux、Android、iOS 使用官方 Flutter；HarmonyOS 使用 CPF-Flutter 的 OpenHarmony fork。
2. 六个平台共享 `ubaa_domain`、`ubaa_app` 和 `ubaa_ui`；官方 Flutter 与 OHOS 各自保留薄宿主，平台能力通过 `ubaa_platform` 注入。
3. Dart 通过 `flutter_rust_bridge` 调用 `crates/ubaa-flutter-bridge`，bridge 只能依赖 `ubaa-core::facade`。正式版覆盖活动执行合同列出的认证、路线、全部读取和 typed 写业务。
4. bridge 使用 opaque client 串行保护现有 `UbaaClient`；不会把 raw URL、Cookie、业务 token、内部 DTO 或任意写 payload 暴露给 Dart。写操作只经一次性 `WriteIntent` 准备与确认入口提交。
5. FRB Dart package、Rust crate、codegen 和 macros 锁定完全相同版本。首个候选为 2.13.0；升级必须重新生成并完成六平台 smoke。
6. 官方 Flutter 与 OHOS fork 独立锁定完整工具链；不能只锁 Dart pub 版本或只写一个语义版本范围。

## 后果

- 业务和路由正确性只有一份 Rust 实现，Flutter UI 可以高度共享。
- OHOS fork、DevEco、OpenHarmony SDK 和插件生态构成独立发布风险，需要独立宿主和测试矩阵。
- bridge DTO 是新稳定边界；Core 类型变更不能未经映射直接传播到 Dart。
- 全部写操作需要独立 typed DTO、一次性确认、结果核对和不确定结果语义；真实账号验证仍需逐项授权。

## 被否决的方案

- 六个平台分别使用 Swift/Kotlin/WinUI/GTK/ArkUI：维护成本和行为漂移过高。
- 在 Dart 重写协议：会复制 CAS、WebVPN、Cookie 和加密逻辑，违反 Core 边界。
- 只用 `flutter_secure_storage`：其标准包不覆盖 OHOS，无法满足六平台一致的安全降级合同。
- 单一宿主目录强行兼容所有插件：OHOS 工具链和插件声明与官方 Flutter 有差异，风险会扩散到五个标准平台。
