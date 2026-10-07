# 可持续开发性整理实施记录

基线：`1e6935fe`；审查与本轮合同提交：`a7933481`。现行决定见 [ADR 0006](../adr/0006-explicit-dart-modules.md)。本页按阶段记录实际结果，未完成项不继承历史通过。

## P1：可信测试与执行入口

- F2：新增缺失/隐藏入口两项用例，旧辅助函数两项 RED；移除 runtimeType/dynamic State 旁路，改为可命中用户入口或明确失败。完整 UI 352 项 GREEN。
- F3：登记 55 个集成入口，记录领域、平台、证据类型、CI 与巡检模式；清单与实际文件双向校验。6 项清单合同及 7 项既有离线统计合同纳入 `just check`。
- 增加 `just integration-check/integration-list/integration-test`；macOS CI 从仅 app_flow 扩展到应用流程、合成 FFI 缓存和本地网络恢复。真实只读与人工流程由独立命令执行，普通执行器拒绝选择。
- 当前 `just check` 全部通过，包含 Rust、CLI 端到端和 Shell 合同；macOS 登记的三组原生集成共 9 项通过。运行器报告无法前置窗口，因此结果属于原生合成测试，不充当真实鼠标操作证据。

阶段日志位于仓库外私有目录 `UBAA-private-evidence/maintainability-20261007`。不记录账号、会话或学校响应。
