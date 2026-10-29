# 模块职责

| 目录 | 职责 |
| --- | --- |
| `crates/ubaa_core` | 学校协议、认证、路线、会话、解析与 facade |
| `crates/ubaa_flutter_bridge` | Rust 到 Dart 的数据与调用边界 |
| `apps/ubaa_cli` | 命令行入口与输出 |
| `apps/ubaa_flutter` | Android、iOS、Windows、macOS、Linux 宿主 |
| `apps/ubaa_ohos` | HarmonyOS 宿主 |
| `packages/ubaa_domain` | Dart 领域模型 |
| `packages/ubaa_app` | 应用状态、缓存展示与写入协调 |
| `packages/ubaa_ui` | 页面、组件与主题 |
| `packages/ubaa_host` | 生命周期和回调接线 |
| `packages/ubaa_platform` | 安全存储及系统能力 |
| `packages/ubaa_bindings` | 生成的桥接代码与构建支持 |
| `docs/site` | VitePress 网站源码 |

修改学校协议时从 Core 定位；修改页面时从 UI 定位；不要在页面或宿主中复制协议实现。
