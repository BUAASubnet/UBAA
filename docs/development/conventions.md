# 开发约定

本文维护命名、语言、提交、依赖、版本、日志及 ADR 的日常约定。[AGENTS.md](../../AGENTS.md)定义安全与来源规则，[工程规范](engineering-standards.md)定义模块所有权，[开发命令](commands.md)是唯一门禁清单。工具链调用规则只在 [AGENTS](../../AGENTS.md#项目工具链入口)维护，环境配置见[setup](setup.md)。

## 命名与格式

自有目录使用下划线，例外沿用[目录命名](directories.md)。文件按语言工具约定：Rust/Python 模块用 snake_case，Dart 文件用 lower_snake_case，Kotlin/Swift 类型文件使用 UpperCamelCase；Shell 入口沿用现有 kebab-case。命令名、Cargo/pub 包名、框架固定路径和第三方文件不随自有目录规则改名。

新增长期文档用小写 ASCII kebab-case，不附日期。普通任务不新建阶段记录；只有跨模块整改需要长期追溯时才新增，命名用 `YYYY-MM-DD-topic.md`，日期放前缀。ADR 用四位顺序编号及主题。既有历史文件本轮不批量改名，后续迁移必须同步链接；不因命名规则删除来源或证据。文档和原型分别按 development/architecture/contracts、migration/history/evidence、design 的实际用途保存，不以本地工具目录充当正式文档入口。

默认 UTF-8、LF、结尾换行和空格缩进；Dart/JSON/YAML/Markdown/TS/Shell/Swift 默认 2 空格，Rust/Python/Kotlin 与 justfile recipe 为 4 空格。以 `.editorconfig` 和对应语言 formatter 为准，不手动格式化第三方或机械生成代码。Markdown 保留有语义的行尾空格，修改时仍须通过差异检查。

## 文档语言

除专业名词、协议字段、公开标识符、命令和上游许可证原文外，对话、文档、注释与提交信息使用中文。先写具体结果、对象和动作，区分当前事实、历史观察、推断和未验证事项。历史提交与计数附上日期或候选，不能把旧日志改称新 HEAD 证据。公共合同定义行为，状态页报告结果，goal 只写当前目标，长期规则不能散落在任务流水中。

## 分支与提交

`main` 是 UBAA v2.0 发布主线，`dev` 用于日常开发，`ubaa1` 保存旧版历史。功能分支从 `dev` 创建，PR 默认提交到 `dev`；准备发布时将已验收的候选合入 `main`。旧版修复单独指向 `ubaa1`，不将旧版提交历史合入新版。

网站和应用服务正式发布均使用 `main`，分别由仓库变量 `DOCS_PUBLISH_BRANCH` 和 `APP_SERVICE_DEPLOY_BRANCH` 控制。变量为空时只执行检查，配置与触发范围见[CI 清单](commands.md#当前-ci-的实际范围)。仓库约定本身不提供合并、推送或发布授权。

提交标题用中文说明意图，必要时正文说明行为、风险和验证。保持单一可审查主题，行为代码与对应测试同提交。机械迁移、生成刷新、golden 更新和证据文档尽量分别审查。每阶段独立提交，使用明确 pathspec 并检查暂存区；不得改写历史、force push 或在未获授权时发布。

## 版本号与依赖

产品展示版本、Cargo/pub 包版本、平台 build number、CLI envelope、Bridge contract、Session/config/cache 磁盘版本各自表达不同含义，不能批量改成相同数字。`docs/contracts` 定义兼容行为；破坏性 CLI DTO/错误变化必须提升 schemaVersion 并更新 Schema、序列化测试和消费者，Bridge 变化同样更新合同及生成物，磁盘格式按迁移规则升级。正式发布需明确展示版本、build number、迁移与回退条件。

产品版本与构建号唯一维护在根目录的 [version.toml](../../version.toml)。例如：

```toml
version = "2.0.0"
build_number = 2003
```

更新版本只需执行一次命令，命令会同时保存配置并同步声明：

```bash
just version 2.0.1 2004
```

也可以编辑 `version.toml`，再执行不带参数的 `just version`。支持 `version=2.0.1 build=2004` 参数写法。产品版本使用三段数字，构建号为 `1` 至 `65535` 的整数，以满足当前 Windows 文件版本格式。Tag 使用 `v<version>`。

| 对象 | 同步规则 |
|---|---|
| Cargo workspace、自有 Dart 包及 Bindings 原生包 | 由配置的 `version` 同步。第三方依赖与带上游版本的 OHOS 适配插件继续采用各自版本。 |
| 官方 Flutter 与 OHOS 应用 | pubspec 由配置同步为 `<version>+<build_number>`，OHOS AppScope 的展示版本与构建号保持一致。 |
| CLI、Bridge、应用服务载荷与磁盘格式 | 沿各自兼容规则维护，与产品版本独立。 |

同一发布候选的各平台共用展示版本和构建号。各宿主 manifest 是构建工具所需的同步结果，日常通过 `just version` 更新。Android、iOS、macOS、Windows 由 Flutter 构建信息提供产品版本。重新分发构建时统一递增构建号；上传商店前核对该渠道已经使用的构建号。

只改构建号时，命令只更新配置与应用声明。产品版本变化时，命令按需调用 Cargo、Flutter pub 和 CocoaPods 刷新自有包的锁定记录，不运行测试、编译或发布。先按[开发环境](setup.md)准备工具及依赖缓存，Apple 锁文件的刷新需要 CocoaPods。工具中途失败后可以重跑同一命令继续同步。

`just version-check` 只读核对配置、各处声明及锁文件中的自有包版本，已纳入脚本与完整检查入口。更新日志、发布说明及渠道下载地址按实际发布内容维护。

新发布采用 SemVer：兼容缺陷修复提升 patch，兼容功能增加提升 minor；稳定版的破坏性变化提升 major。0.x 开发期的破坏性变化至少提升 minor，并在发布说明列出迁移办法。预发布通过分发渠道和 Tag 后缀区分，安装包展示版本保持三段数字。平台 build number 在同一发布序列中单调增加。面向用户的更新记录维护在 `docs/site/changelog/`，包独立发布时维护该包的 CHANGELOG。只有获得发布授权并完成发布验收后才创建 Tag、发布说明或产物，规范本身不提供授权。

引入依赖前说明需要解决的问题、现有实现/标准库是否够用、维护状态、平台/OHOS 兼容性、许可证与体积影响。优先复用仓库已有依赖，按需启用最少 features，不为机械整理顺带升级。

FRB runtime/codegen/macros、Flutter 工具链和依赖兼容边界使用仓库已锁定的精确版本；其他 Rust/Dart 依赖按生态允许兼容区间，但必须审查实际锁文件变化和支持的 SDK 下限。官方七个 Flutter 包与 `ubaa_test_support` 使用根 `pubspec.yaml` 的 Pub workspace，由 `just flutter pub get` 生成唯一根锁文件；OHOS 宿主和三个 OHOS 插件使用 3.41.10-ohos fork，保持独立 manifest 与锁文件，不能由官方 workspace 解析。第三方源码保留许可证、来源提交、逐文件摘要与本地修改说明，不猜缺失的上游版本；普通依赖依据锁文件和发布报告核验。

## 日志与诊断脱敏

这是共享日志与诊断字段清单的唯一维护位置，AGENTS 的禁止提交规则同时适用。允许记录操作名、逻辑路线、稳定状态/错误码、耗时、安全计数和必要的非个人元数据。仅在获得诊断范围授权时记录不含查询值的允许列表主机/路径、参数键及长度、响应长度或不含秘密材料的摘要；不能对密码、Token、签名、验证码或个人资料计算可共享摘要。

不得输出或共享用户名/学号、密码、Cookie/Set-Cookie、Authorization、会话材料、业务 Token、私钥、签名、验证码/图片、表单值、URL 查询值、原始请求/响应或完整个人资料。手机号、证件号等个人字段在产品必要显示时按合同遮盖，共享诊断仍不得记录真实字段值。异常对象、任意 Debug 和原始 stderr 必须先收敛为白名单安全信息，不能只替换某个关键词就归档。

产品遥测不属于日志与诊断。只有[应用服务合同](../contracts/app-service.md#7-用户派生标识与年级)定义的学号派生标识和年级，可以按该合同的白名单上传。日志、诊断报告、测试证据和提交内容仍不得出现学号或任何派生值。例外的依据见[决策记录](../migration/decision-log.md#2026-11-10应用服务的学号派生标识与数据出境)。

本机家目录、设备 UUID、截图/录屏、会话和真实响应按[证据规则](../design/evidence/README.md)处理；共享文字使用明确逻辑占位，调试材料和运行媒体统一保存在被忽略的 `.ubaa_local/` 任务子目录。检查类 CI 不接收真实凭据，普通测试使用合成数据。生产部署 Token 只配置在[应用服务部署环境](../runbooks/app-service.md#配置-github-cd)，所有 GitHub 作业均不接收学校账号。禁止全局 trace，不以关闭 TLS、扩大日志或保存原始正文换取调试便利。

## ADR 模板

涉及长期所有权、模块边界、安全/协议取舍或替代既有设计时新增 ADR。单轮观察和验收结果写提交说明；会影响后续判断的取舍（如换钉、来源冲突裁决）写 decision-log；新决策必须链接受影响合同与来源对照。ADR 状态为“提议”“已接受”“已实施”“已取代”“已废弃”，取代时保留旧文并指向新记录。

```markdown
# ADR NNNN：具体决定

日期：YYYY-MM-DD
状态：提议
取代：无，或旧 ADR 链接
被取代：无，或新 ADR 链接

## 问题与证据

描述可观察的问题、约束和来源。写明哪些信息尚未验证。

## 决定

写清所有者、边界、行为和适用范围。

## 备选与取舍

比较可行方案，说明为何选择当前方案及代价。

## 验证与迁移

链接来源对照、统一门禁及必要专项，写明失败条件、迁移与回退。
```
