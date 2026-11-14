# UBAA 2 Agent 指南

本文件是在本仓库工作的 agent 必须遵守的长期规则，也是安全边界、来源对照门禁、真实账号授权和工具链规则的权威出处。人类贡献者的上手流程见 [CONTRIBUTING.md](CONTRIBUTING.md)，开发者文档入口见 [docs/README.md](docs/README.md)。

## 权威入口

| 想知道 | 看哪里 |
|---|---|
| 当前阶段要做什么 | [当前目标](docs/project/goal.md)。它不能覆盖本文件的安全边界，也不提供任何授权 |
| 长期方向 | [路线图](docs/project/roadmap.md) |
| 现在实现和验证到哪一步 | [项目现状](docs/project/status.md) |
| 工程规则和日常约定 | [工程规范](docs/development/engineering-standards.md)、[开发约定](docs/development/conventions.md)、[术语表](docs/development/glossary.md) |
| 协议依据 | [协议依据目录](docs/protocol/README.md)、[冻结参考](docs/protocol/references.md)、[决策记录](docs/protocol/decision-log.md) |

判断协议事实时，按以下顺序采信：真实上游证据 → 冻结旧版的实现与测试 → 固定版本的 buaa-api。架构文档不能代替协议证据。

规则冲突时采用更严格的一方，并在决策记录中写明依据。不能因为当前任务需要或以前成功过就放宽规则。

## 安全边界

- **只读敏感输入**：`examples/`、根目录 `.env`、废弃的本地配置、运行时会话、验证码图片和真实响应只能读取，不得暂存。
- **禁止提交**：凭据、Cookie、Token、原始真实响应、完整个人数据、验证码图片、签名密钥。
- **运行媒体放在本地**：UI 截图、录屏和逐图元数据保存在被忽略的 `.ubaa_local/` 任务子目录，不纳入 Git。`UBAA_UI_EVIDENCE_DIR` 指向本次运行的子目录。`docs/design/evidence/` 只提交原型源文件和脱敏文字摘要，归档规则见[证据规则](docs/design/evidence/README.md)。应用图标、静态地图和 golden 测试基准属于工程资源，照常管理。
- **TLS 与证据**：不得关闭 TLS 校验；缺少证据时不得推断上游字段或 URL。
- **分层**：宿主只能通过 facade 或专用 Bridge 使用 Core，不得依赖 `upstream` 内部实现。

## 开发循环

首次缺少冻结引用时，运行 `just refs-bootstrap` 建立引用（会联网）。之后的开发、验证和发布只运行 `just refs`，它只做校验，不联网，也不改写冻结目录。各命令的联网和写入行为见[网络与写入边界](docs/development/commands.md#网络与写入边界)。

1. **开工**：运行 `git status --short --branch` 和 `just refs`，保留工作区已有改动。
2. **记录**：只有当前事实变化时才更新[项目现状](docs/project/status.md)；只有会影响后续判断的取舍才写决策记录。不为单轮任务新建报告文件，验证过程写进提交说明，临时材料按下文存放。协议相关的来源对照仍按[来源对照门禁](#来源对照门禁)记录。
3. **先证明问题**：行为变更和缺陷修复先写一个能失败的、有意义的反例。纯文案、样式、文档和可逆的机械改动复用已有覆盖，不添加验证语言本身、固定文案缺席或 Widget 数量的断言。整理测试时，登记被删测试的覆盖由哪里保留。
4. **实现与检查**：做最小改动，先跑聚焦检查，再按[检查选择与完成条件](docs/development/commands.md#检查选择与完成条件)执行按改动检查。比较已提交的分支时，传入阶段开始时的 Git 基线。
   - 普通的文档、脚本、Rust、Dart 改动按提交级别检查，较重的检查由推送前或 CI 承担，共用检查不重复执行。
   - 安全、协议、并发、存储和跨语言边界的修改，提交前必须完成完整验收。影响不明时按全量处理；路径无法识别的高风险改动显式使用 `mode=full`。
5. **提交**：用明确的 pathspec 暂存，禁止 `git add .`。提交前人工检查暂存的文件和内容，并运行 `just check-sensitive`。根目录 `.env` 不得暂存，只提交不含真实值的 `.env.example`。每个阶段独立提交；机械移动、行为修改、生成刷新和证据文档按主题拆成可审查的提交，行为实现和对应测试可以放在同一提交。

## 任务粒度

按能独立使用和验收的功能组织任务，通常只有“产品目标 → 执行任务”两层，用直接的中文命名。一个任务包含交付所需的实现、接线、测试、文档、缺陷修复和复审。增加修复轮次、涉及多个技术层或换了聊天，都不新增阶段编号。

实现步骤写成任务内的清单。一个任务可以有多次按主题拆分的提交，也可以交接后继续，提交次数和聊天次数不决定任务数量。只有两部分能各自交付、各自验收，并且拆开确实减少依赖或工作量时，才建立独立任务。历史阶段编号只用于追溯已有记录。

## 本地调试与临时文件

- Agent 创建的调试脚本、合成探测源码、脱敏日志、临时配置和验证中间产物，统一放在仓库内被忽略的 `.ubaa_local/<任务名>/`，优先复用已有目录。不要用系统临时目录或全局 agent 目录（如 `~/.codex/tmp/`）代替。
- UI 截图、录屏、逐图元数据、原始设备日志和必须保留的敏感调试材料，也放在 `.ubaa_local/` 的任务子目录，并设置私有访问权限。这些原始材料不得暂存、提交或复制到共享文档；需要共享时只提取必要的脱敏摘要。

## 项目工具链入口

- Dart/Flutter 命令一律用 `just dart`、`just flutter`，OHOS 用 `just flutter-ohos`。命令中不写 SDK 绝对路径，也不依赖 PATH 中的 Dart/Flutter。
- 首次使用时按 `.env.example` 创建本地私有的 `.env` 并填写 SDK 位置，然后运行 `just setup` 安装锁定工具。`just doctor` 只读核对本机版本。
- just 入口和直接执行的项目脚本，通过 `scripts/lib/toolchain.py` 按白名单加载根目录 `.env`；已导出的同名环境变量优先。
- 签名参数按平台和构建模式整组从进程环境或 `.env` 中选一个来源，缺项不得从另一来源补齐。
- 机密只交给需要它的入口：普通命令只加载非机密键；Android/OHOS 签名只交给对应平台的 SDK 构建命令；学校账号只交给显式的真实验证入口；SSH 部署密钥只交给受保护环境中的部署和分发步骤；云盘发布账号仅由服务器发布程序读取，不能进入 CI。

配置示例与安装步骤见[开发环境](docs/development/setup.md)。其他开发文档提到工具链规则时链接本节。

## 来源对照门禁

任何认证、读取或写入功能的变更，在改生产代码之前，都必须逐个操作比较两个冻结来源的行为：

- `examples/ubaa_old/`：对应的 API 接口、DTO、本地实现和测试。
- `examples/buaa-api/`：最接近的 API 模块、请求与重定向代码、数据模型、加密、Cookie/凭据存储和错误处理。

两者的提交固定为[冻结参考](docs/protocol/references.md)中的值。对照记录写进[协议依据目录](docs/protocol/README.md)中对应的功能文件，或该目录链接的决策记录。

每个操作都要分别覆盖以下各列，认证成功或端点相似都不能代替缺失的列：

1. 业务 CAS/引导 URL 与 service
2. 重定向与最终 URL
3. Cookie、Session、Token 的作用域
4. HTTP 方法与精确参数
5. 请求头与正文编码
6. 加密与签名常量
7. DTO 与解析的字段、类型
8. 缓存、并发、重试
9. 错误、退出与产品语义

**某个来源没有相同的上游协议**：明确记录“不适用”，不得类比借用它的 URL、字段、加密或错误。

**来源冲突**：在冲突的边界停止实现，把具体文件、提交和脱敏的实时观察记入决策记录，再选择有真实证据或适用的冻结本地实现支持的行为。不得凭记忆补齐没有证据的字段或参数。

**TDD 顺序**：先增加脱敏的 Fixture/Mock 请求或解析测试并保留实际失败的证据，再做最小且有来源支持的修复，复跑聚焦测试，完成[来源对照验收](docs/development/commands.md#来源对照与真实验证)后提交。记录过程中不得暂存冻结目录、凭据、原始响应、Cookie、Token、验证码或个人数据。

## 真实账号与验收范围

- **读取授权**：用真实账号做认证或只读验证，必须有当前会话中用户给出的功能和连接方式授权。同一会话中仍然适用的授权继续有效，不重复索取。仓库里的 goal、历史报告、凭据文件的存在、以往的授权记录，都不能扩大授权。
- **不触发学校请求的工作**：普通工程整改、纯 UI 文案、测试整理不因此请求学校。
- **CI**：检查类 CI 永远不接收真实凭据，也不执行真实业务写入。应用服务部署作业只在受保护的 GitHub Environment 中接收专用 SSH 部署密钥，永远不接收学校凭据。
- **双路线**：认证、读取、写入协议变更的 CLI 端到端和 Direct/WebVPN 双路线要求见[来源对照验收](docs/development/commands.md#来源对照与真实验证)。某条路线不可达或未获授权时，登记阻塞原因和重跑条件；另一条路线、Fixture/Mock 或历史成功都不能算作该路线通过。
- **写入授权**：每次真实写入都必须获得具体操作、目标、路线和时间的授权。CLI 确认参数、Flutter 确认按钮、Mock 通过或读取授权都不能代替。
- **写入不自动重试**：写请求可能已到达上游后，禁止自动重试；结果未知时先只读核对。

## 完成条件

检查清单只在[开发命令](docs/development/commands.md#检查选择与完成条件)维护。

- 普通提交按改动级别验收。
- 修改测试框架或门禁时，执行脚本自测、失败反例和实际受影响的入口。完整的确定性验收由显式模式或同一候选提交的 CI 承担。
- 公共合同、安全、协议、并发、存储、跨语言边界和影响不明的改动，提交前必须完成完整的相关验收。
- PR/CI 不用选择性检查代替最终验收；完整入口不再叠加默认的按改动检查。
- 原生集成测试只保留真实原生能力、FFI 和最小宿主 smoke，保留的覆盖和自动化缺口见[测试策略](docs/development/testing.md)。
- 代码实现、静态分析、设备、真实账号、远端 CI 和发布的证据分别报告。Fixture/Mock 通过不能代替真实协议通过。

## 目录与项目地图

自有目录统一使用下划线，例外见[目录命名](docs/development/directories.md)。文件命名与语言约定见[开发约定](docs/development/conventions.md)。

| 位置 | 职责 |
|---|---|
| `crates/ubaa_core` | 领域、认证、会话、路线、上游协议、解析、缓存与 facade |
| `crates/ubaa_flutter_bridge` | facade 到 FRB 的稳定 typed 投影 |
| `crates/ubaa_test_support`、`fixtures/auth`、`fixtures/readonly` | 脱敏夹具与确定性 transport 支持 |
| `crates/ubaa_command`、`tools/core_live` | 公共命令定义、执行与输出；独立的只读协议开发工具 |
| `apps/ubaa_flutter`、`apps/ubaa_ohos` | 官方五平台宿主与 OHOS 宿主 |
| `packages/ubaa_domain`、`packages/ubaa_app`、`packages/ubaa_host` | Dart 模型、应用状态与写协调、共享宿主接线 |
| `packages/ubaa_platform`、`packages/ubaa_ui`、`packages/ubaa_bindings` | 平台能力、共享界面、FRB/Cargokit |
| `packages/*_ohos` | 有上游声明的 OHOS 插件适配 |
| `services/app_service` | Node.js 应用服务与 PostgreSQL |
| `scripts` | 准备、检查、构建、真实验证、发布与脚本自测入口，副作用见[脚本说明](scripts/README.md) |
| `docs/` | 文档，按读者划分，见[文档首页](docs/README.md) |
