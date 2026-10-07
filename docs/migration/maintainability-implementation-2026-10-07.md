# 可持续开发性整理实施记录

基线：`1e6935fe`；审查与本轮合同提交：`a7933481`。现行决定见 [ADR 0006](../adr/0006-explicit-dart-modules.md)。本页按阶段记录实际结果，未完成项不继承历史通过。

## P1：可信测试与执行入口

- F2：新增缺失/隐藏入口两项用例，旧辅助函数两项 RED；移除 runtimeType/dynamic State 旁路，改为可命中用户入口或明确失败。完整 UI 352 项 GREEN。
- F3：登记 55 个集成入口，记录领域、平台、证据类型、CI 与巡检模式；清单与实际文件双向校验。6 项清单合同及 7 项既有离线统计合同纳入 `just check`。
- 增加 `just integration-check/integration-list/integration-test`；macOS CI 从仅 app_flow 扩展到应用流程、合成 FFI 缓存和本地网络恢复。真实只读与人工流程由独立命令执行，普通执行器拒绝选择。
- 当前 `just check` 全部通过，包含 Rust、CLI 端到端和 Shell 合同；macOS 登记的三组原生集成共 9 项通过。运行器报告无法前置窗口，因此结果属于原生合成测试，不充当真实鼠标操作证据。

阶段日志位于仓库外私有目录 `UBAA-private-evidence/maintainability-20261007`。不记录账号、会话或学校响应。

## P3-A：UI 独立模块

- 原 77 个 part、17,004 行的 widgets library 已拆为独立领域组件、公共展示函数与局部状态组件；公开 barrel 仍只导出原六个组件类型。
- 公共学业展示行、文本与周标签独立，清除学业卡片/字段和课程网格/详情的循环依赖。跨 library 不再读取另一个 State 的私有成员；导航仅暴露只读当前页面视图。
- 状态扩展只归其实际 State：查询面板 1,960 行、详情列表 1,735 行、Shell 1,238 行；其余领域 library 更小。普通 UI 文件均不超过 1,000 行，库导入图无环。
- 独立成绩卡片测试先因模块不可独立导入而 RED，拆分后包含原 golden 的完整 UI 353 项 GREEN；7 包全量 Flutter 分析与测试、完整 Rust/CLI/Shell 门禁通过。调用顺序、展示文字、输入参数和 golden 未修改。

## P3-B：Bridge 上下文与领域适配

- BridgeBackend 保留原构造/客户端/配置 getter 和业务接口，内部组合 BridgeContext。缓存账号、句柄、代次、串行尾链由 BridgeCacheState 单独拥有；交互挑战由 BridgeAuthenticationState 拥有。
- 领域函数显式接收上下文，投影与本地缓存读取按领域分别组织；读分派和写操作各有独立入口。原 8,250 行 library 拆成无导入循环的模块，最大的学业读取 library 约 653 行。
- 独立查询映射合同先 RED，移动后通过；完整 App 637 项、七包 Flutter 门禁及完整 Rust/CLI/Shell 门禁通过。既有认证顺序测试检出了绕开可覆写策略入口的差异，已改为显式传入公开策略回调，保留全部原断言。
- 原业务函数只进行标识符/模块移动、上下文参数及状态字段路径替换；Core、FRB schema、学校请求和缓存代次规则未改变。
