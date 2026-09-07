# 可维护性治理实施计划

> 执行者使用 `superpowers:subagent-driven-development`；任务按边界实现和独立复审，用户已授权连续完成，无需逐阶段确认。

**目标：** 关闭错误传播、可诊断性、门禁和交接四类缺陷，保留已验证协议。

**架构：** Core 保留请求与写入语义。Dart 单一错误映射与有界本地诊断共享既有模型；宿主只负责展示和复制。各阶段用行为回归和确定性门禁验收。

**技术栈：** Rust 1.95.0、Flutter 3.41.9、FRB 2.13.0、Bash、ShellCheck 0.11.0。

**设计：** [可维护性治理设计](../specs/2026-09-07-maintainability-design.md)。

## 全局约束

- CLI v10 / Bridge v9 / Session v2 / config v1；不改变上游请求、TLS、写入次数或重试策略。
- 真实 App/Core-live 继续暂停；仅本地确定性验证，无凭据和用户会话读取。
- 所有新文档、注释和测试说明使用中文。手写文件不超过 1000 行，目录直属源码不超过 16 个，不增加结构例外。
- 当前 checkout 是干净的非主线开发分支 ubaa2；沿用本地冻结输入和已配置 SDK，在当前工作区按文件所有权协作，避免复制真实运行数据。阶段提交由主执行者串行完成。
- 每个实现阶段保留 RED/GREEN 证据。先来源对照，再生产修改；最终日志使用仓库外目录，仓库仅保存安全摘要。

## 任务 1：错误模型和单一映射

文件：domain/common/error.dart、platform/ui_error.dart、app/contracts/backend.dart、app/bridge/common.dart、app/controller/error_mapper.dart，及 app/controller、write、host 的错误消费点；新增 app/test/error_propagation_test.dart。

接口：BackendException 增加可选 kind/retryable/resolvedRoute；UiError 增加可选 kind/resolvedRoute；`UbaaErrorMapper.fromException(BackendException)` 委托 platform mapper。旧 `fromCode` 保留。

- [ ] 添加真实 BridgeBackend fake-client 测试：读取抛出 `BridgeError(code: parseError, kind: parse, retryable: false, resolvedRoute: webVpn)`；经 AppController 后断言 code=parseError、retryable=false、route=webvpn。
- [ ] 添加两个映射入口对所有 UbaaErrorCode 的一致性测试，以及非重试上传错误、登录失败路线和未知字符串的回归。
- [ ] 执行 `flutter test test/error_propagation_test.dart`，保留预期失败。
- [ ] 实现穷尽 typed 转换、保留可选元数据、统一模板和全部异常消费路径；更新明确依赖旧错误文案的测试。
- [ ] 运行 focused、platform/app/host 相关测试和敏感检查，记录结果。

## 任务 2：Dart 本地诊断与故障隔离

文件：新增 platform/src/diagnostics.dart 和对应测试；app/controller 的独立诊断 part；WriteCoordinator/ReceiptVerifier；UI error_card、profile、shell 和 host 接线；新增诊断传播与 widget 测试。

接口：`LocalDiagnostics` 提供有界记录、不可变快照和 `exportText()`；输入只接受 typed 操作、UiError、领域、时延、异常分类和经筛选源码位置，不收集原始对象字符串。AppController 可注入记录器，默认本地内存；UI 通过回调读取安全报告。

- [ ] 测试错误内嵌模拟凭据/URL/正文不会进入诊断，超限记录淘汰旧项，编号唯一，快照不可变。
- [ ] 测试非预期异常保留关联编号/阶段，失败遥测 sink 不把成功读取或认证改成失败，过期请求不污染当前状态。
- [ ] 测试 UI 只显示稳定代码/编号并能主动复制安全信息；个人页读取本轮诊断，默认不上传。
- [ ] 运行对应新增测试，保留失败；实现记录与阶段接线，隔离可选诊断/遥测副作用。
- [ ] 运行 platform/app/UI/host 测试，核对结果未知、写入单次调用和回读竞态。

## 任务 3：Rust 传输安全诊断

文件：ports/reqwest_transport.rs 及私有 diagnostic 子模块和测试；独立 `docs/migration/source-parity-maintainability-transport.md`。

接口：不改变 HttpTransport 或 UbaaError；私有安全分类记录发送/收包阶段、原因类别和耗时。错误链遍历有界，不格式化原始原因。

- [ ] 核对冻结参考 error/request 与旧版 NetworkUtils/UserFacingErrors，记录九列不变约束和日志不等价项。
- [ ] 通过真实回环 TCP 服务验证 GET/POST 状态、正文和既有传输合同；通过断开的本地端口触发错误，捕获 tracing 并断言字段和敏感内容缺席。
- [ ] 先运行新增诊断测试，确认缺少事件导致失败；实现分类与事件，保持现有公开代码和重试标志。
- [ ] focused tests、Core 和 Mock tests 通过，记录 RED/GREEN 和不改协议证据。

## 任务 4：严格门禁与 macOS 产物权限

文件：justfile、scripts/check 或 release 的独立检查器、对应 scripts/tests；脚本说明与开发命令文档。

接口：提供明确的严格 Shell/Rust 入口；现有 artifact checker 在 macOS 上读取实际签名 entitlements 验证 Sandbox 与 network.client，不能写产物或重签。

- [ ] 添加隔离命令夹具：缺 ShellCheck 的严格入口非零退出；现有宽松入口仍显示 SKIP。
- [ ] 添加 macOS checker 夹具：合法产物权限通过，移除客户端权限、关闭沙箱、无效签名权限读取均拒绝。
- [ ] 先运行失败测试；实现检查并接入既有稳定命令和 CI 合适入口。
- [ ] 执行 Shell 合同、ShellCheck 和真实已有/新构建 macOS 产物检查，不启动或登录 App。

## 任务 5：当前文档与可共享证据

文件：goal.md、docs/migration/status.md、history 两份归档、新 evidence 摘要、docs/index.md；主执行者负责诊断手册和本轮结果摘要。

- [ ] 原样归档旧 goal 和 status，保留此前 macOS 修复、用户确认和真实测试暂停事实。
- [ ] goal 切换本轮治理并链接设计与计划；status 只列当前事实、历史 verified 源码 SHA 和尚未验收范围。
- [ ] 从已存在脱敏报告提取历史安全计数、CI URL 和证据日期到仓库内摘要，明确历史未重新在线验证。
- [ ] 更新索引与当前架构入口，消除当前导航对个人绝对路径的必要依赖；历史原文不批量改写。
- [ ] 检查链接、版本合同、敏感材料与 diff；不为纯文档制造测试。

## 任务 6：整合、复审和阶段提交

- [ ] 每个独立任务完成后检查差异与 focused 证据；复审发现由原实现者修复并定向复验。
- [ ] 运行 `just refs`、`just layout-check`、`just check-sensitive`、严格 `just check`、完整 Flutter、FRB 零漂移；CLI E2E 包含在 Rust 工作区检查中。
- [ ] 运行 macOS Debug 构建、实际产物门禁及脱敏宿主 integration。其它平台按变更和工具可用性执行并明确范围。
- [ ] 独立全量审查本轮 diff，关闭高/中风险问题；不为评分添加无实际收益的抽象。
- [ ] 分阶段检查 staged 文件并提交；最终源码提交验证结果与后续文档记录分开标记。
- [ ] 交付计划、修复摘要、具体测试结果、提交与剩余真实验证边界。
