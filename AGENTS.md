# UBAA 2 Agent 指南

## 权威入口

本文件是 agent 的长期规则入口。[goal.md](goal.md) 只记录当前阶段目标，不能覆盖安全边界或提供历史任务授权；[UBAA2.md](UBAA2.md) 是长期路线图。当前事实与验证结果写入[迁移状态](docs/migration/status.md)，长期工程规则见[工程规范](docs/development/engineering-standards.md)，日常约定见[开发约定](docs/development/conventions.md)。

协议事实按真实上游证据、冻结旧版实现与测试、固定 buaa-api 的顺序判断；冻结目录和提交以[冻结参考](docs/migration/references.md)为准。架构文档不能替代协议证据。规则冲突采用更严格的一方，并在[决策记录](docs/migration/decision-log.md)说明依据，不能用当前任务或历史成功放宽规则。

## 安全边界

- `examples/`、`.env.local`、运行时会话、验证码图片和真实响应均为只读敏感输入，不得暂存。
- 不得提交凭据、Cookie、Token、原始真实响应、完整个人数据、验证码图片或签名密钥。本地 `.env.toolchain` 同样不得提交。
- UI 截图、录屏等运行验收媒体保存到仓库外私有目录，不纳入 Git。`docs/design/evidence/` 仅提交原型源文件与脱敏文字摘要，逐图元数据随截图留在仓库外，`UBAA_UI_EVIDENCE_DIR` 必须指向仓库外目录。应用图标、静态地图和 golden 测试基准属于工程资源，继续按既有规则管理。归档与旧提交映射见[证据规则](docs/design/evidence/README.md)。
- 不得关闭 TLS 校验，也不得在缺少证据时推断上游字段或 URL。
- 宿主只能通过 facade 或专用 bridge 使用 Core，不得依赖 `upstream` 内部实现。

## 开发循环

首次缺少冻结引用时，显式运行 `just refs-bootstrap` 建立引用；普通开发、验证和发布只运行纯校验的 `just refs`。冻结引用验证不得隐式联网或改写冻结目录。依赖源与学校请求的具体区别见[命令的副作用](docs/development/commands.md#网络与写入边界)。

1. 运行 `git status --short --branch` 和 `just refs`，保留已有工作区改动。
2. 只有当前事实变化时才更新 `docs/migration/status.md`，只有会影响后续判断的取舍才写决策记录。不为单轮任务新建报告文件；验证过程写进提交说明，日志放在被忽略的 `.ubaa_local/`。协议相关的来源对照仍按下文门禁记录。
3. 行为变更或缺陷修复先用有意义的失败反例证明问题。纯文案、样式、文档及可逆机械改动复用已有覆盖，不添加语言自证、固定文案缺席或 Widget 数量断言。整理测试时登记删除项对应的保留覆盖。
4. 实现最小变更，先运行聚焦检查，再按[检查选择与完成条件](docs/development/commands.md#检查选择与完成条件)审阅、执行按改动检查。比较已提交分支必须传入阶段开始时的 Git 基线。安全、协议、并发、存储和跨语言边界修改保留完整相关门禁，未知影响保守全量。
5. 使用明确 pathspec 暂存，禁止 `git add .`。提交前人工检查暂存文件与内容、运行敏感扫描，每个阶段独立提交。机械移动、行为修改、生成刷新和证据文档按可审查的主题拆分，行为实现与对应测试可以同一提交。

## 项目工具链入口

Dart/Flutter 命令一律使用 `just dart`、`just flutter`，OHOS 使用 `just flutter-ohos`。不得在命令中写 SDK 绝对路径，也不依赖 PATH 中的 Dart/Flutter。首次复制 `.env.toolchain.example` 为本地 `.env.toolchain` 并填写 SDK 位置，该文件不提交，然后运行 `just setup` 安装锁定工具；`just doctor` 只读核对本机版本。just 只自动加载仓库根的工具配置，直接运行脚本时复用 `scripts/lib/toolchain.py` 的唯一回退解析器。工具入口绝不加载 `.env.local`，已导出的环境变量优先。配置示例与安装步骤见[开发环境](docs/development/setup.md)。本节是工具链调用规则的唯一维护位置，其他开发文档链接本节。

## 来源对照门禁

所有认证、读取或写入功能变更，在改动生产代码前都必须逐操作比较两个冻结来源的行为：

- `examples/ubaa_old/`：读取对应 API 接口、DTO、本地实现和测试。
- `examples/buaa-api/`：读取最接近的 API 模块、请求与重定向代码、数据模型、加密、Cookie/凭据存储和错误处理。

两者提交均使用[冻结参考](docs/migration/references.md)的固定值。对照记录写入[来源对照索引](docs/migration/source-parity.md)或该索引链接的决策记录。每个操作分别覆盖：业务 CAS/引导 URL 与 service、重定向与最终 URL、Cookie/Session/Token 作用域、HTTP 方法与精确参数、请求头与正文编码、加密/签名常量、DTO 与解析字段/类型、缓存/并发/重试、错误/退出与产品语义。认证成功或端点相似均不能证明缺失的列。

某个来源没有相同上游协议时，明确记录“不适用”，不得类比借用其 URL、字段、加密或错误。来源冲突时，在该边界停止实现，将具体文件、提交及脱敏实时观察记入 decision-log，再选择有真实证据或适用冻结本地实现支持的行为。不得从记忆补齐未证明的字段或参数。

来源差异的 TDD 顺序为：增加脱敏 Fixture/Mock 请求或解析测试并保留实际失败证据，实施最小且有来源支持的修复，复跑聚焦测试，然后完成[来源对照验收](docs/development/commands.md#来源对照与真实验证)后再提交。记录过程中不得暂存冻结目录、凭据、原始响应、Cookie、Token、验证码或个人数据。

## 真实账号与验收范围

真实账号认证、只读验证必须具有当前会话中用户任务指令给出的功能和路线授权；同一会话中仍适用的授权继续有效，不重复索取。仓库中的 goal、历史报告、凭据文件存在与历史授权记录均不能自行扩大授权。普通工程整改、纯 UI 文案或测试整理不因此触发学校请求。CI 永不接收真实凭据或执行真实业务写入。

认证、读取、写入协议变更与发布验收的 CLI 端到端、Direct/WebVPN 双路线要求见[来源对照验收](docs/development/commands.md#来源对照与真实验证)。某条路线不可达或未获授权时登记阻塞与重跑条件，不能把另一条路线、Fixture/Mock 或历史成功当作该路线通过。

真实写入每次必须获具体操作、目标、路线和时间授权。CLI 确认参数、Flutter 确认按钮、Mock 通过或读取授权不能代替真实写入授权。写请求可能到达上游后禁止自动重试，结果未知时先只读核对。

## 完成条件

门禁清单只在[开发命令](docs/development/commands.md#检查选择与完成条件)维护。修改测试框架、门禁、公共合同或完成跨模块整理时必须完成其中的完整确定性验收；PR/CI 不以选择性检查替代最终验收。原生集成保留真实原生能力、FFI/启动锁和最小宿主 smoke，保留覆盖与自动化缺口见[测试策略](docs/development/testing.md)。代码实现、静态分析、设备、真实账号、远端 CI 和发布证据分别报告，Fixture/Mock 成功不能代替真实协议成功。

## 目录与项目地图

自有目录统一使用下划线，包名、命令名、框架路径、第三方及历史归档例外见[目录命名](docs/development/directories.md)。文件命名与语言约定见[开发约定](docs/development/conventions.md)。

| 位置 | 职责 |
|---|---|
| `crates/ubaa_core` | 领域、认证、会话、路线、上游协议、解析、缓存与 facade |
| `crates/ubaa_flutter_bridge` | facade 到 FRB 的稳定 typed 投影 |
| `crates/ubaa_test_support`、`fixtures/auth`、`fixtures/readonly` | 脱敏夹具与确定性 transport 支持 |
| `apps/ubaa_cli` | human/JSON CLI 与 Core-live 只读入口 |
| `apps/ubaa_flutter`、`apps/ubaa_ohos` | 官方五平台及 OHOS 薄宿主 |
| `packages/ubaa_domain`、`packages/ubaa_app`、`packages/ubaa_host` | Dart 模型、应用状态/写协调和共享宿主接线 |
| `packages/ubaa_platform`、`packages/ubaa_ui`、`packages/ubaa_bindings` | 平台能力、共享界面及 FRB/Cargokit |
| `packages/connectivity_plus_ohos`、`packages/flutter_secure_storage_ohos`、`packages/package_info_plus_ohos` | 有上游声明的 OHOS 插件适配 |
| `scripts` | bootstrap/check/build/live/release/tests 入口与 lib/tools 支持，副作用见[脚本说明](scripts/README.md) |
| `docs/contracts`、`docs/architecture`、`docs/development` | 稳定合同、架构和开发规则 |
| `docs/migration`、`docs/adr`、`docs/design`、`docs/site` | 来源/状态/历史、长期决策、设计和用户网站 |
