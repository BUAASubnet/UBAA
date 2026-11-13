# 术语表

本页供第一次阅读 UBAA2 工程文档的贡献者查阅，统一解释仓库里反复出现的内部术语。用户网站不使用这些术语，写用户文档时请换成普通说法（例如用“连接方式”代替“路线”）。

## 架构与分层

### Core

`crates/ubaa_core` 中的 Rust 库，负责学校协议、认证、路线、会话与 Cookie、加密、解析、缓存和业务规则。宿主不能直接使用它的内部模块，只能经过 [facade](#facade)。分层见[架构导读](../architecture/overview.md)。

### facade

Core 对外的唯一入口 `ubaa_core::facade`。日常使用聚合客户端 `UbaaClient`，它在内部处理 Direct/WebVPN 两条[路线](#路线directwebvpnauto)；`RouteClient` 固定一条路线，只用于诊断和测试。facade 只返回稳定 DTO 和结构化错误，不暴露上游原始响应、Cookie 或业务 Token。

### Bridge / FRB

FRB 是 [flutter_rust_bridge](https://pub.dev/packages/flutter_rust_bridge)，用来生成 Dart 与 Rust 之间的 FFI 代码，版本锁定为 2.13.0。Bridge 指 `crates/ubaa_flutter_bridge`：它把 facade 转换成 Flutter 可调用的 API，生成的 Dart 代码位于 `packages/ubaa_bindings`，生成文件不能手改。接口规则见 [Flutter Bridge 合同](../contracts/flutter-bridge.md)。

### 宿主（Host）

运行 UI 或命令的应用外壳。`apps/ubaa_flutter`（官方五平台）和 `apps/ubaa_ohos`（HarmonyOS）是“薄宿主”：只负责 SDK 初始化、平台能力注入和启动；共享接线在 `packages/ubaa_host`。宿主不拼接学校 URL，也不处理协议。

### typed

用具名的类型（结构体、枚举）表达数据或错误，而不是字符串、任意 JSON 或 `dynamic`。例如“typed 错误”指带稳定 `code`、`kind` 的错误枚举，“typed 资格”指 Core 返回的结构化[操作资格](#操作资格与目标)对象。

### 投影

把一层的数据转换成另一层或某个视图需要的稳定形状，并且只保留必要字段。常见用法有两种：

- Bridge 把 facade 的 DTO 投影成 Dart 类型，不让 URL、Cookie 等材料越过边界。
- 日程和首页把课表、作业、考试等学校数据投影成统一的待办或日程条目。

### 代次

账号、认证或路线配置每次变化时递增的标识。读取结果返回时会核对代次，代次已变的迟到结果直接丢弃，避免把旧账号或旧路线的数据显示到当前页面。

### 应用服务

UBAA 自有的 Cloudflare Worker 服务，提供启动配置、更新提示、公告和经用户同意的匿名统计。它不接触学校账号。规则见[应用服务合同](../contracts/app-service.md)，部署见[应用服务部署手册](../runbooks/app-service.md)。

## 协议与网络

### 路线（Direct/WebVPN/Auto）

App 访问学校服务的方式，用户界面称为“连接方式”：

| 路线 | 含义 |
|---|---|
| Direct | 直接访问学校站点，通常在校园网内可用 |
| WebVPN | 经学校 WebVPN 网关访问，校外也可用；需要单独认证 |
| Auto | 默认策略。Core 探测是否处于校园网，业务优先直连，某个域名出现网络失败时按域名回退到 WebVPN |

`RoutePolicy` 是用户或宿主选择的策略（auto/direct/webvpn），`ConnectionMode` 是 Core 实际解析出的路线。写入不会因路线回退而重放。详见[路由策略合同](../contracts/route-policy.md)。

### 上游

学校的实际服务（SSO、教务、SPOC 等）。“上游字段”“上游响应”指这些服务返回的内容。

### 合同

`docs/contracts/` 中对外稳定行为的定义，包括 CLI JSON 输出、Flutter Bridge API、离线缓存、日程、云盘和应用服务载荷。合同带版本号，破坏性变化必须升版并同步 Schema、测试和消费者。合同版本只在对应合同和[状态页](../project/status.md)中声明，其他文档链接合同。

### envelope

CLI JSON 输出的外层结构，包含 `schemaVersion`、数据或错误及路线元数据。版本见[认证与用户合同](../contracts/auth-and-user.md)。

### 操作资格与目标

Core 在一次新鲜的在线读取中签发的 typed 字段，例如 `cancelEligibility` 和 `cancelTarget`。资格表示能否执行某个写操作，目标标识要操作的对象。界面只依据资格开放写入口，不从中文文案、状态名或时间自行推断。

### 写协调器

`packages/ubaa_app` 中的 `WriteCoordinator`，是 App 中唯一管理写操作状态的对象。一次写入的流程是：准备（prepare）→ 用户一次性确认 → 单次提交（commit）→ 只读回读核对。提交结果不确定时返回 `outcome_unknown`，不会自动重试，必须先读取核对。

### outcome_unknown

写请求可能已经到达上游、但无法确认结果时的稳定错误。收到后禁止自动重发，只能用读取核对实际状态。

## 来源与验证

### 冻结参考

来源对照使用的两个本地只读参考仓库：`examples/ubaa_old/`（旧版 UBAA）和 `examples/buaa-api/`，各自固定在一个提交。`just refs` 只读校验它们，`just refs-bootstrap` 只在首次缺失时联网建立。固定提交见[冻结参考](../protocol/references.md)。

### 来源对照

修改认证、读取或写入功能前，逐个操作比较两个冻结参考的 URL、重定向、Cookie 作用域、参数、加密、DTO 和错误处理，并把结果记录下来。没有证据的字段或 URL 不能凭推断补齐。规则见 [AGENTS 来源对照门禁](../../AGENTS.md#来源对照门禁)，记录见[来源对照索引](../protocol/README.md)。

### Fixture / Mock

Fixture 是脱敏的协议样本（`fixtures/auth`、`fixtures/readonly`），Mock 是不访问网络的替身 transport（`crates/ubaa_test_support`）。它们让请求、解析和并发测试可重复运行，但不能证明真实学校协议可用。

### golden

Flutter 截图对比测试。基准图使用 macOS 渲染，允许不超过 0.2% 的像素差异；改动基准必须审阅实际差异。

### 真实验证

用真实学校账号向上游发送请求的验证，入口是 `just verify-live mode=direct` 和 `mode=webvpn`，两条路线分别执行，不能用 Auto 代替。每次都需要用户在当前会话中授权；真实写入还需要逐次授权具体操作、目标、路线和时间。见[来源对照与真实验证](commands.md#来源对照与真实验证)。

### Core-live

`tools/core_live` 中的独立只读验证程序，`just verify-live` 通过它执行真实只读请求，只输出安全摘要。操作见[真实只读验证手册](../runbooks/live-readonly-verification.md)。

## 检查与交付

### 门禁

提交、推送、合并或发布前必须通过的自动检查，例如敏感扫描、断链检查、Rust/Flutter 测试和 FRB 生成零漂移。完整清单见[开发命令](commands.md)。

### 按改动检查与完整验收

`just check-changed` 根据改动路径选择需要的门禁：`mode=commit`（默认，提交前）、`mode=push`（推送前）和 `mode=full`（完整确定性验收）。安全、协议、并发、存储和跨语言边界的改动在提交前就要完整验收。见[检查选择与完成条件](commands.md#检查选择与完成条件)。

### 候选

被固定下来接受验收或发布的一个源码提交。验收结果只对这个提交有效；源码、测试、生成文件、锁文件或构建配置变化后，需要对新候选重新验收。

### 生成零漂移

用锁定版本的 FRB 重新生成绑定后，结果与仓库中已提交的生成文件完全一致。入口是 `just flutter-codegen-check`。

### `.ubaa_local/`

仓库内被 Git 忽略的本地工作目录，存放调试脚本、截图、日志和其他临时或敏感材料，按任务使用子目录，不提交。
