# 架构总览

UBAA v2.0 使用 Rust Core 处理学校协议，Flutter 提供跨平台界面，Flutter Rust Bridge 连接两端。

```text
Flutter 页面 → 应用状态与操作协调 → Bridge → Rust facade → 学校系统
CLI ─────────────────────────────────→ Rust facade
```

## 职责划分

Rust Core 统一管理认证、直连与 WebVPN、Cookie、会话、解析和业务规则。界面通过稳定的数据模型读取结果，不自行拼接学校请求。

Dart 应用层负责加载、缓存展示、筛选与提交状态。平台层提供安全存储、网络状态和系统能力。CLI 面向开发与诊断，通过同一 facade 调用 Core。

新版不依赖旧版 Kotlin 服务端或 Redis 中转服务，当前没有 Web/Wasm 应用宿主。

## 开发入口

- [模块职责](/tech/modules)
- [配置说明](/tech/configuration)
- [测试与质量](/tech/testing)
- [源码中的工程文档](https://github.com/BUAASubnet/UBAA/tree/ubaa2/docs)

网站提供使用与开发概览。公开合同、迁移证据和阶段验证保留在源码仓库，与对应提交一起阅读。
