# 可持续开发性审查

日期：2026-10-07（Asia/Shanghai）。源码基线：`1e6935fe3dfd7315f7723afc6a3a3cce76a25516`，分支 `ubaa2`，开始时主工作区干净。本报告为审查与建议，尚未实施生产重构或删除测试。

本文保留审查时的结论与原路径；后续修复、当前入口和验证结果见[实施记录](maintainability-implementation-2026-10-07.md)，现行组织以[架构规范](../architecture/code-organization.md)为准。

## 结论

顶层 `apps / crates / packages / fixtures / scripts / docs` 有清晰分工，Rust Core、facade、FRB、Dart 应用层、UI 和宿主的总体分层值得保留。主要维护成本来自：

1. 文件拆小后仍通过 Dart `part` 共享巨大私有作用域，文件规模合规没有转化为模块解耦。
2. 测试同时按领域、实现类、历史重构阶段和离线专项组织；部分断言约束历史形状，部分辅助函数绕过用户入口。
3. 原生集成测试缺少集中、可执行的分类清单。
4. 当前规范、历史实施流水和证据明细混在日常开发入口中。

应先修复测试可信度和建立回归清单，再按业务领域逐个拆出真正独立的模块。大规模改名和按数量删减测试的收益较低、风险较高。

## 范围与快照

检查了 Git 跟踪文件、Cargo/pubspec 依赖、Dart library 与测试注册、Core 模块入口、脚本、两个 CI workflow 和文档索引。行为测试采用重点抽查，没有逐项审阅全部断言或计算覆盖率。

| 指标 | 当前值 | 统计口径 |
|---|---:|---|
| 结构门禁范围内源码文件 / 行数 | 1,146 / 223,273 | 沿 checker 后缀规则，排除 FRB 输出和 Cargokit；包含测试、runner、本地适配插件 |
| `ubaa_app/lib` 文件 / 行数 | 116 / 17,111 | Dart 生产代码 |
| `ubaa_app/test` 文件 / 行数 | 109 / 27,473 | 包含辅助代码和 `part`，不是用例数量 |
| `ubaa_ui/lib` 文件 / 行数 | 81 / 17,191 | Dart 生产代码 |
| `ubaa_ui/test` 文件 / 行数 | 59 / 14,693 | 包含辅助代码和 `part` |
| `widgets.dart` 聚合规模 | 77 个 `part`，17,004 行 | 入口与直接 `part` 总行数，同一 Dart library |
| `BridgeBackend` 聚合规模 | 45 个 `part`，8,250 行 | 同上，不是单个类的行数 |
| `AppController` 聚合规模 | 37 个 `part`，6,801 行 | 同上 |
| Flutter 宿主集成测试入口 | 55 个 | `integration_test/` 下的 `*_test.dart`，含真实读取与巡检入口 |
| 历史 UI 证据目录 | 4,021 个文件，约 3.20 MB | 其中 3,967 个 JSON；主要是检索噪声 |

统计以 `git ls-files` 为输入，不包含忽略目录、冻结示例、构建缓存和旧工作树。测试行数高于生产代码不能单独证明冗余；并发、账号隔离和写入安全需要充分的边界用例。

## F1 · 高优先级：物理拆分掩盖了逻辑大模块

位置：``widgets.dart``、``app_controller.dart``、``bridge_backend.dart``。

UI 的 77 个部件共同拥有私有名称可见性。AppController 的登录、缓存、重试、查询、课表导入和写后回读通过同一 library 的 extension 访问集中状态。例如 ``offline_startup.dart`` 直接修改 `_phase`、`_localAccount`、恢复状态与生命周期代次；无法仅靠 import 或构造参数判断子文件的状态依赖。

``layout.sh`` 只检查单文件超过 1,000 行、目录直属源码超过 16 个。当前零违例并不证明低耦合；后缀清单也未覆盖 `.py` / `.cjs`，不能视为全部手写逻辑的规模检查。

建议：UI 按领域改成独立 library，显式传入模型与 callback；AppController 保留对外组合入口，内部组合会话、恢复、查询等协作者；BridgeBackend 保留版本/客户端边界，提取领域适配与纯投影。每项可变状态继续只有一个所有者，避免拆出多套账号、路线或写入状态机。

保留行数底线，增加 library 总规模、跨领域依赖和状态所有者审查。不通过机械加目录满足数量限制。

## F2 · 高优先级：筛选测试可能绕过真实交互入口

位置：``test/support/navigation.dart``。

`openQueryPanel` 找不到“搜索与筛选”等按钮时，会按 `runtimeType.toString() == '_FeatureDetailView'` 定位内部 State，并用 `dynamic` 调用 `togglePanel()`。即使没找到用户可操作入口，测试也可能继续完成筛选断言；同时测试依赖私有类名。

``query_panel_test.dart`` 和多处领域查询用例使用它。本次该测试通过，不能据此证明所有调用都经过真实按钮；本次没有证明生产界面已经缺失入口。

建议辅助函数只点击明确可见、可命中的语义按钮或稳定 key，缺失时立即失败。面板内部状态测试直接挂载组件，与用户导航测试分开。实施时先用“无可用入口”的合成场景证明辅助函数会失败，再更新调用者。

## F3 · 高优先级：集成入口缺少持续执行分类

位置：``flutter-workspace.sh``、``flutter-platforms.yml``、``integration_test``。

工作区门禁对 `integration_test` 做格式检查和分析，但实际运行的是无路径参数的 `flutter test`。原生 CI 只明确调用 `integration_test/app_flow_test.dart`；它注册自己的 9 个部件，没有汇入其他 54 个入口。

其他入口包含离线恢复、系统安全材料、平台插件、合成 UI、真实只读和人工巡检。本地专项可能执行过，当前统一门禁却没有持续运行它们。统计测试 ``analyze_test.py`` 本次 7 项通过，但没有接入 `justfile` 或 CI。OHOS 原生合成测试已接入 `scripts/build/ohos.sh`，不是完全遗漏，只是与 SDK/构建入口绑定。

建议建立可执行清单，逐项记录领域、证据类型、所需平台、账号/设备需求、命令和 CI 归属。普通确定性测试提供按包/领域的快速入口；原生合成流程进入匹配 runner；设备能力、真实只读、人工巡检分别提供显式入口。不要对当前 `integration_test/` 盲目执行通配全量命令。

## F4 · 中优先级：部分断言约束历史形状，维护价值偏低

| 位置 | 问题 | 建议 |
|---|---|---|
| ``public_api_contract_test.dart:6``、第 54 行 | 手写 `_publicNames` 清单断言长度和去重长度为 33，没有从实际导出生成；导出变化不一定影响计数 | 删除清单计数，保留真实 import 与静态类型签名合同 |
| ``bridge_backend_characterization/signatures.dart:3`` 与公共 API 合同 | 重复维护部分构造器/接口/tear-off；`hasLength(17)` 只核对局部列表 | 合并重复签名，保留独有的“构造不触发原生调用”断言 |
| ``internal_architecture.rs:29`` | 永久锁定迁移后的具体文件名，合法重组也会失败 | 保留禁止 `internal → features` 的依赖测试；路径清单改为必要入口/边界规则或归档迁移检查 |
| ``write_controller_test.dart`` 与 ``write_coordinator/flow.dart`` | 旧名字已是同一实现的 typedef，测试仍按旧/新名字分组 | 统一放入 `write/`；保留少量兼容合同，逐断言对照后合并交叉用例 |

最后一项不能直接整文件删除：旧入口与 UI 入口的抛错、返回值、销毁和释放断言存在差异。本次没有完成全仓等价断言证明，不承诺删掉某个比例的测试。

应保留非幂等请求最多一次、unknown 禁止重发、账号/路线代次、注销后迟到结果、缓存密钥及错误传播、精确协议请求、schema/FRB 和关键原生接线。不同层的输入/输出边界检查通常有独立价值。

## F5 · 中优先级：领域、技术动作、历史阶段混作目录主轴

位置：[`ubaa_app/test`](../../packages/ubaa_app/test/)、[`controller/app_controller`](../../packages/ubaa_app/lib/src/controller/app_controller/)、[`UI features`](../../packages/ubaa_ui/lib/src/features/)。

一个领域的测试散布于 `app_controller/`、`bridge_backend/`、`bridge_backend_characterization/`、`offline/`；UI 并存 `academic.dart`、`academic_content.dart`、`academic/`。Controller 并存 `grades.dart`、`grades/baseline_store.dart`、`offline/grades.dart`。定位时需要知道开发背景，而非只知道功能。

`app_controller_test.dart` 注册 16 个 `part`、合计 4,865 行；`widgets_test.dart` 注册 15 个 `part`、合计 6,620 行。子文件不能直接作为独立测试入口，按文件运行需要回到聚合入口或依赖名称过滤。

建议按“包职责 → 业务领域 → 必要子职责”组织，横切生命周期独立。测试镜像职责，使用独立 `*_test.dart`，共享 harness 放 `test/support/`。`regression/characterization/old` 可以出现在说明或历史链接里，不继续作为新测试的主要分类。

命名无需全仓统一连接符：Rust package 的 `ubaa-core`、Dart package 的 `ubaa_app` 符合各自生态。保留既有 `bykc/cgyy/ygdk/libbook` 等领域标识并补中文映射，避免继续增加 `rooms/cgyy`、`boya/bykc` 等别名。runner、FRB、Cargokit 路径保持工具链约定。本地 OHOS 插件保留上游包名和许可证，用统一清单管理来源、本地差异与退出条件。

## F6 · 中优先级：当前文档入口仍依赖历史设计

位置：``README.md:25``、``code-organization.md:3``、``engineering-standards.md:3``、[`testing.md`](../development/testing.md)、[`status.md`](status.md)。

README 称旧组织设计为“当前权威”，目标文档却声明主体是 2026-09-05 历史记录。测试指南包含大量旧候选 SHA、schema 演进和修复流水；状态页前部仍写依赖审计“生产实现与依赖未修改”，末尾已经记录同日实施完成。工程规范顶部产品状态未跟随近期安全存储和整体未完成边界更新。

建议 `goal.md` 只保存当前任务，`architecture/` 保存现行结构，`development/` 保存当前操作，`contracts/` 保存稳定合同。状态页只保留最新结论与欠项；旧计数、阶段与失败尝试归入现有 history/evidence。沿用 ADR 目录记录新独立决策，不继续把所有主题正文追加进 1,837 行的 decision log。

## F7 · 低优先级：历史证据明细挤占日常搜索

位置：[`证据规则`](../design/evidence/README.md)、[`ui-ux`](../design/evidence/ui-ux/)。

4,021 个跟踪文件主要是归档验收 JSON，总计仅约 3.20 MB；截图已经外置。问题是文件树和搜索命中被历史采集阶段占据，不是大媒体未清理。

短期让源码搜索限定 `apps/crates/packages/scripts`。长期按批次提供摘要索引；如进一步归档明细，保留逻辑路径、摘要、提交映射及可恢复性。现有元数据不是无用文件，本次不删除或重写历史。

## 建议的目标组织

保留顶层和包边界，先在包内演进。以下是方向示例，不要求一次创建所有目录；小领域保持平铺，只有职责需要才增加层级。

```text
packages/ubaa_app/lib/src/
  application/                 # AppController 对外组合
  session/                     # 身份与生命周期唯一所有者
  recovery/                    # 离线恢复、重试编排
  features/<领域>/             # 用例、读取适配、展示投影
  bridge/                      # 客户端、版本和共用边界
  write/                       # 唯一写协调器与回读

packages/ubaa_ui/lib/src/
  app/                         # 壳、导航、登录与设置组合
  features/<领域>/             # 独立 library，显式输入/回调
  shared/                      # 无业务状态的通用控件
  write/                       # 公共确认与结果展示

packages/ubaa_app/test/
  session/
  recovery/
  features/<领域>/
  write/
  contracts/
  support/

apps/ubaa_flutter/integration_test/
  synthetic/<领域>/            # 合成 backend 自动流程
  platform/<能力>/             # 原生能力，注明设备条件
  live/<领域>/                 # 显式真实只读
```

人工巡检驱动另设入口，具体路径在核对工具链和脚本后确定。Rust 暂不拆出大量小 crate，沿现有 domain/features/cache/facade 按领域收口，保留 facade 稳定。Core DTO、FRB DTO、展示模型承载不同边界，不合并成万能模型。

## 实施顺序与完成条件

| 阶段 | 工作 | 完成条件 |
|---|---|---|
| 1：可信测试 | 修复内部状态旁路；分类集成入口；接入遗漏的独立确定性脚本测试 | 缺少入口明确失败；每个集成入口有分类和命令；CI 不运行账号测试 |
| 2：测试整理 | 移除自证计数；合并签名重复；领域测试独立入口 | 每条删除断言对应保留用例或明确无行为价值，保留状态机独有分支 |
| 3：领域试点 | 建议先整理成绩的 app/UI/测试，采用显式依赖 | 可单独挂载与运行，不访问其他领域私有状态，公开行为/文案/查询合同不变 |
| 4：横切拆分 | 提取会话、恢复、调度协作者与剩余领域 UI | 状态唯一所有者，账号切换/迟到结果/回读与恢复并发回归持续通过 |
| 5：规范收敛 | 更新现行权威；归档流水；增加按域命令与架构约束 | 可从功能名找到实现、测试、命令和合同，不靠目录数量判断模块质量 |

机械移动、测试组织和行为修复分开提交；不夹带依赖升级、协议修改、无关 golden 或公开 DTO 改动。认证/读取行为变化继续先双来源对照、RED→GREEN。本次只审查，没有改变活动合同及原有验收边界。

持续观察 library 规模、测试独立运行能力、同一缺陷涉及的 fixture 套数、快速回归耗时、CI 分类覆盖及状态所有权。先记录趋势再制定阈值；本次未测全量耗时或覆盖率，不设任意删减比例。

## 本次验证与限制

- 已核对分支、HEAD、工作区和 worktree；旧工作树未改动。
- `just refs` 通过：ubaa_old `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`；buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。
- `just layout-check` 通过，精确 baseline 违例为 0。
- 固定官方 Flutter SDK 下，`ubaa_app` 的 `public_api_contract_test.dart`、`write_controller_test.dart`、`write_coordinator_test.dart` 合计 41 项通过；`ubaa_ui/test/query_panel_test.dart` 1 项通过。命令采用 `flutter test --no-pub --reporter expanded` 加对应文件路径。
- `PYTHONDONTWRITEBYTECODE=1 python3 scripts/live/offline_startup/analyze_test.py`：7 项通过。
- 本轮只新增审查文档及索引/状态/决策记录，未修改生产代码、测试、依赖或合同；未运行全量 Rust/Flutter 门禁、原生构建、设备或真实学校请求。
- F2 是源码确认的测试旁路风险，F3 是静态确认的持续回归缺口，均不表示已证明生产故障。测试合并判断限于明确列出的候选。
