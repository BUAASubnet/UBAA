# 可持续开发性整理实施记录

基线：`1e6935fe`；审查与本轮合同提交：`a7933481`。现行决定见 [ADR 0006](../../adr/0006-explicit-dart-modules.md)。本页按阶段记录实际结果，未完成项不继承历史通过。

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

## P3-C：Controller 状态所有权与局部实现

- AppController 保留同一继承实例、构造参数、ChangeNotifier 通知链、公开方法及原公共扩展；共享可变状态集中于 ControllerState，领域、会话、恢复、缓存与写回读由独立 library 的具名 mixin 实现。没有创建第二个状态机或通知代理。
- 跨 library 的内部状态与操作显式标为 @internal，宿主不能依赖这些实现成员；共享操作合同只保留实际跨模块调用，移除 91 个不必要的重复抽象签名。
- 原 6,801 行 library 已解除聚合；包含既有辅助组件的 controller 范围为 46 个无环 library，最大 731 行。State 与操作合同、记录类型分离，领域处理器不反向导入 AppController 组合入口。
- 完整 App 637 项及修正未用 import 后的七包 Flutter 门禁通过；Rust/CLI/Shell 门禁通过。通知重入、注销、账号切换、并发读取、晚到结果和写回读均沿既有断言验证。

## P2 / P4：独立测试、清单与防退化门禁

- 6 个聚合测试入口的 60 个注册函数拆为 54 个独立入口，共享夹具与行为文件分离；原有独有断言保持。随后将离线专项、旧版对齐和宿主测试归入领域/会话/恢复/缓存/写入，保留兼容入口语义。
- 删除 publicNames 手写计数；签名合同保留为真实 import 与静态类型赋值，构造器另保留客户端身份及零原生调用测试。Core 只删除固定历史文件名的迁移断言，依赖方向与 facade 边界门禁保留。
- 分离后发现博雅分页测试在默认窗口下点击屏幕外按钮；保留原分页断言，通过失焦、滚动、命中确认修复。17 项查询文件独立运行 GREEN；完整七包为 1,327 项通过，golden 字节未改变。
- 原生入口按 synthetic/platform/live/manual 归类，16 个巡检模式改为独立 driver，补录照片和启动测量两个旧遗漏入口，清单共 73 项。辅助文件的真实账号标记递归检查，人工/真实入口不得进入 CI；8 项清单合同通过。
- 加入 library/part/无环门禁及 5 项行为合同；Python/CJS 超限回归先 RED 后 GREEN，布局 Shell 合同 42 项通过。快速包测试、源码定位和原生分类入口已进入 justfile。
- 现行架构/测试指南重写，旧正文、状态与决策流水归档；版本门禁改为验证现行声明，不再要求开发指南复述旧升级过程，7 项版本合同先 RED 后 GREEN。
- 历史 UI 材料增加 34 批次索引与默认检索隔离；4,021 个原文件及其字节均保留，不删除媒体归档或改写历史哈希。

## 审查项闭环

| 审查项 | 已落地结果 | 持续检查 |
|---|---|---|
| F1：大型隐式 library | UI 显式输入/回调、BridgeContext、ControllerState 与局部操作合同 | module-check、类型分析、账号/通知/并发行为测试 |
| F2：筛选绕过用户入口 | 删除 State 旁路，缺失/隐藏入口明确失败；修复独立运行的屏外点击 | UI support 与 query 行为用例 |
| F3：原生入口遗漏 | 73 项完整清单、独立人工 driver、默认 3 组原生回归与 CI 接线 | integration-check、8 项清单合同 |
| F4：低价值断言 | 移除名字计数与历史路径锁定，收敛重复签名，保留独有兼容行为 | 编译合同、write/compatibility、Core 依赖边界 |
| F5：目录主轴混杂 | 生产代码按包职责/领域组织，54 个聚合行为文件改为独立测试入口 | 按领域 flutter-test、现行代码地图 |
| F6：规范与流水混合 | 现行架构/测试/状态重写，旧正文进入 history，新决策进入 ADR | 文档索引、合同版本检查 |
| F7：历史证据搜索噪声 | 34 批次摘要索引、默认检索隔离、源码限定命令 | 原 4,021 文件保留，敏感扫描仍覆盖 Git 跟踪内容 |

## 最终验证

生产与测试整理候选为 `d2e3d53f`，最后补齐集成执行器的固定 SDK 校验、纠正迁移后的注释并记录验收；没有新增业务行为。所有日志保存在仓库外私有目录 `<private-evidence>/maintainability-20261007`，不纳入 Git。

| 验证 | 当前结果 | 日志 |
|---|---|---|
| just check-strict | 通过；Rust、CLI 二进制 E2E、Shell/Python、布局、模块、清单、schema、Clippy 与文档门禁 | final-check-strict.log |
| just flutter-check | 通过；七包共 1,327 项：Domain 57、Platform 83、App 636、UI 353、Bindings 31、Host 92、官方宿主 75 | final-flutter-check.log |
| just flutter-codegen-check | 通过；FRB 生成零漂移 | final-codegen.log |
| just integration-test | 通过；迁移后的网络 1、应用流程 7、FFI 缓存 1，共 9 项原生合成/本地测试 | final-integration.log |
| UBAA_OHOS_NO_CODESIGN=1 just ohos-check mode=debug | 通过；分析、2 项宿主测试、安全存储/网络插件合成合同、无签名 HAP 与 arm64 Rust 动态库检查 | final-ohos.log |
| just flutter-build platform=android-apk mode=debug | 通过；APK 及所需 ABI Rust bridge 产物结构检查通过 | final-android.log、final-android-artifact.log |
| just flutter-build platform=ios-simulator mode=debug | 通过；无签名模拟器 App 构建与产物结构检查 | final-ios.log、final-ios-artifact.log |
| just verify-live mode=webvpn | 40 行 PASS；其中 5 行 count=0，1 行 source=static_fallback | final-webvpn.log |

原生测试报告无法前置 macOS 窗口，因此只计入原生合成回归。WebVPN 空结果和 Cgyy 用途静态回退不证明真实业务按钮已验收。OHOS 无签名 HAP 与合成 HUKS 错误传播不替代实体设备 HUKS 成功证据。Direct、真实学校写入、Windows/Linux 运行、实体设备与正式发布未执行，原 B2/C2/C3/D 欠验继续保留。

OHOS 构建产生的本地 HAR 锁文件差异和 buildinfo 删除已恢复；不把 SDK 工作路径或构建副作用提交为源码。最终阶段保留 golden 字节、冻结引用和三个既有独立工作树。

补丁收尾再次通过 20 项 Python 合同、module-check、integration-check、refs、layout-check、check-sensitive 和 git diff --check。现行文档相对链接及执行入口已复查。P1—P5 与 F1—F7 均完成；变更按合同、可信测试、UI、Bridge、Controller、测试/规范、最终验收分为七个本地提交，未推送或发布。
