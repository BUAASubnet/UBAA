# 决策记录

本页维护现行决策入口与新增记录。阶段 3 及以前的 282 个记录标题已建立[完整索引](history/2026-10-30-decision-index.md)，正文[原样归档](history/2026-10-30-decisions-through-quality-phase3.md)，顺序、文字和既有链接均未改写。更早的历史汇总仍见原记录中的归档入口。历史授权与测试结果只适用于记录时的范围，不能提供当前操作授权。

## 近期决定索引

| 时间与主题 | 记录 |
|---|---|
| 阶段 1：工具链、脱敏、许可证与证据保留 | [2026-10-29 阶段 1](history/2026-10-30-decisions-through-quality-phase3.md#2026-10-29阶段-1-去除个人机器依赖) |
| 阶段 2：权威入口与冻结引用换钉 | [2026-10-29 阶段 2](history/2026-10-30-decisions-through-quality-phase3.md#2026-10-29阶段-2-统一权威来源与规范) |
| 原生集成删减、每项覆盖缺口与保留理由 | [原生能力范围决定](history/2026-10-30-decisions-through-quality-phase3.md#2026-10-29原生集成只保留真实原生能力) |
| 工具版本、配置解析、CI 与文档链接范围 | [门禁与 CI](history/2026-10-30-decisions-through-quality-phase3.md#2026-10-29门禁基础逻辑与-ci-统一) |
| 阶段 3 最终本机验证与未运行事项 | [2026-10-30 验收](history/2026-10-30-decisions-through-quality-phase3.md#2026-10-30阶段-3-验收结果) |
| 主题等设备偏好与文档站 | [2026-10-29 文档站迁移](history/2026-10-30-decisions-through-quality-phase3.md#2026-10-29将-ubaa-v20-文档站迁入开发分支) |

## 2026-10-30：阶段 4 文档分工与历史保留

状态页改为当前快照，旧时间线完整迁入 history。decision-log 原文件通过 git mv 原样归档，以完整标题索引和近期决定表保留每条入口。既有记录不删改，也不把历史成功改写成当前候选结果。

已完成的 superpowers 计划、9 月 UI 设计/审计/执行记录和 macOS 逐按钮记录归入 history，按日期前缀命名。现行 design 只保留维护中的界面、配色与首页规格；migration 保存来源对照、当前结果与历史入口；两类 evidence 保存各自的验证文字和采集元数据，分工见[文档索引](../index.md#文档分工与归档)。

沿用阶段 3 的链接检查范围：history 内部保留原始相对链接和旧路径，便于按原提交与原位置追溯，豁免原因是历史语义与记录完整性。归档内部链接不承诺按当前目录可点击；[历史目录说明](history/README.md)提供当前入口与原位置映射。现行文档指向归档的文件与标题仍必须通过断链检查。不增加逐链接 allow、基线或脚本豁免。现行规格和来源对照中的源码链接已按当前目录修正；补充来源中无法共享的原材料继续明确为不可复现的历史证据。

约 4000 个 UI 证据 JSON 继续保留在 docs/design/evidence，实际受跟踪 JSON 为 3967 个。本阶段不删除、不移动、不改写 JSON，也不重算历史采集摘要。两类 evidence 不合并，以免丢失原批次和提交映射。

主题已由 ThemePreferenceStore 通过 PreferenceValues 保存为设备偏好，键为 `flutter.ubaa.preferences.theme`；Host 在启动时恢复并防止迟到读取覆盖用户新选择。无效值或读取失败回退到 system，普通偏好写失败不打断本次选择。现行规格、配置与隐私说明同步；旧设计中的“仅本次运行”保留为当时方案。

产品代际名 UBAA 2 / UBAA v2.0、SemVer、平台 build number、CLI/Bridge 合同与磁盘格式分别表达不同含义。当前 OHOS 原生版本与 pubspec 不一致，登记到状态页，配置修复留待阶段 6；本阶段不更改生产版本。离线合同的 CLI schema 旧值改为 v12，Bridge 历史版本节保持当时语义。CLI JSON Schema 使用版本化 URN `urn:ubaa:cli:json:schema:12` 标识文档，局部 $ref 与验证规则不变；消费者从受跟踪 Schema 文件加载，URN 不提供下载服务。

GitHub 仓库已启用私有漏洞报告，本轮通过只读 API 确认；SECURITY 写明实际报告入口与脱敏要求，没有修改远端设置或发送报告。README 收敛为概览与合同链接，协议细节集中到现有 Bridge 合同。

## 2026-10-30：阶段 5 Rust 重构与行为等价边界

本阶段按审计附录 A58–A69 的 Rust 条目处理。重构只改变代码组织、错误构造器、共享辅助函数、依赖声明和编译期约束；认证、读取、写入的上游请求与路线语义保持原值。依赖统一由 Cargo 重新生成 `Cargo.lock`，没有手工编辑锁文件。工作区统一声明依赖并设置 `publish = false`，bridge 与 Core 的 `rand` 对齐到 0.8；CLI 中没有源码引用的 `base64` 和 `ubaa-test-support` 已移除。精确版本的现有依赖仍按冻结工具链和平台兼容性保留。

### 已完成的等价重构

- A58：根 `Cargo.toml` 增加 `[workspace.dependencies]`，四个 Rust crate 改用 `.workspace = true`；`cargo check --locked --workspace --all-features` 验证锁文件，`cargo tree --locked -d` 中项目直接依赖不再引入两个 `rand` 主版本。CLI 未使用依赖删除后，CLI 单元、契约和集成测试仍全部通过。
- A59：`UbaaError` 增加 `invalid_input`、`upstream_changed`、`parse_error`、`authentication_required`、`upstream_unavailable`、`outcome_unknown` 等构造器；HTTP 响应增加大小写不敏感的 `header_values` 与 `header_first`。错误代码、错误种类、可重试标记和消息保持原组合；构造器字段单元测试、Core 合同测试和完整工作区测试覆盖。
- A60：SSO 主机与 Location 目标判定收进 `connection`，保留原有大小写、WebVPN 解包、相对 Location 解析和精确主机边界；日志 URL 统一使用只保留 scheme/host 的严格摘要。先增加失败表征测试，再更新实现和 Cgyy 日志断言；connection 合同测试、Cgyy 日志测试、HTTP 响应测试覆盖。日志摘要只作用于日志文本，不改变请求 URL。
- A61：校园时间收进 `time` 模块，统一上海日期、紧凑日期、日期时间和时间戳格式化；对 Unix epoch、跨日边界、时区转换和既有格式增加测试。各功能原有的空值/错误传播方式保留，相关 Cgyy、课程表、签到、阳光打卡、缓存和 facade 测试通过。
- A62：删除 SPOC `_value_type_marker` 死函数以及 Cgyy 验证码实现上已经被生产代码使用的过期 `dead_code` 抑制。仅测试使用的 `bykc::parse_courses` 和对外 re-export 的 `unused_imports` 抑制保留，因为这些符号仍是测试或模块公开边界的一部分；保留理由由严格 Clippy 的实际诊断确认。其余 serde 线协议字段的抑制用于保留冻结字段解析，不能删除。
- A63/A64：删除与默认模块路径重复的 `#[path]`，并将 CLI 两个后端 trait 从 `backend/mod.rs` 移到 `backend/contract.rs`，`mod.rs` 仅声明子模块并导出契约。CLI 全量测试和严格 Clippy 覆盖行为未改变。
- A65：CLI backend trait 删除“不可用”默认实现，所有能力改为编译期必需实现。先加入检查旧实现存在时失败的表征测试，再迁移固定/路由实现及契约 fake；CLI 全部测试通过，漏实现现在在编译期报错。
- A66：facade 的缓存刷新前置流程收进 `offline::begin_refresh`，保留身份代际、`Inactive`/`Superseded`、保存错误和路线选择顺序；facade 测试 117 项通过。Bridge 离线代码未做跨类型泛型化，因为 FRB 导出 DTO 的类型边界和生成稳定性无法在本阶段证明等价。
- A67：验证码图片 URL 常量和编码构造迁入 `upstream`，facade 只调用上游地址构造；上游 URL 编码单元测试和交互认证相关 Core 测试通过。

### 有意的语义变化与未统一边界

日志 URL 脱敏按最严格规则统一：日志只保留协议和主机，路径、查询和片段全部替换为 `<redacted>`。这是阶段要求的 TDD 语义变化，失败测试先于实现；不改变网络协议。

CLI backend trait 删除运行时“不可用”默认实现是第二项 TDD 语义变化。新增的契约测试先验证旧默认实现存在时失败，迁移后通过；该变化把遗漏能力从运行时错误提前为编译错误。

SSO 服务 URL（课程表、空教室、图书馆、iHome 等）的 `service` 查询参数和重定向目标各不相同。本阶段只统一 SSO 主机检测和共享登录/验证码常量，没有把这些带业务参数的 URL 合并成一个模板，避免改变参数编码、重定向或 Cookie 作用域。A68 中其余 feature 专属 endpoint 常量保留在 feature 文件，作为协议边界遗留项；如需继续收拢，应逐 URL 建立来源对照和表征测试后再做。

`mod.rs` 中的协议实现（例如 `upstream`、`auth` 和部分 facade/cache 模块）仍有历史逻辑。阶段 5 只拆分了与本次 CLI 契约改造直接相关且可机械验证的 backend 模块；继续移动这些实现属于扩大结构范围的机械改动，留待监督者决定。

本阶段提交：`19102297`、`00f40e01`、`b616bc53`、`fb73bac4`、`8d761ac9`、`fb8a60d4`、`81c6a0d6`、`bdc4232b`、`edeb41a4`、`db422ebd`、`29104992`、`69141903`、`aa687563`、`cdb65c22`、`a1d654ca`、`3cd9e3e5`、`f89ce2e2`、`80e1d77a`。阶段验证和未运行项目写入 `.ubaa_local/supervision/phase5-report.md`。


## 2026-10-30：阶段 6 Dart/Flutter/OHOS 结构重构

本阶段以 `d1872cafdf2e425c9f4a48c2cce5856f53ad458c` 为基线，只整理 Dart、Flutter、OHOS 工程结构和测试支持，不修改生产 UI 逻辑、文案、交互或 Bridge 调用参数。所有跨包测试夹具迁移保留原测试文件中的断言，迁移前后由官方七包全量测试和 OHOS 宿主测试覆盖。

### Pub workspace 边界

Flutter 3.41.9 / Dart 3.11.5 的临时最小工程已验证 `workspace` 与成员 `resolution: workspace` 语法；本仓库根清单随后由 `just flutter pub get` 实际生成根 `pubspec.lock`，官方七包及新增 `ubaa_test_support` 共用这一锁文件。`just flutter-check` 的根锁定解析、七包 format/analyze/test 均通过。

OHOS 使用锁定的 `3.41.10-ohos-1.0.1` fork，宿主和三个 `*_ohos` 插件继续使用独立 manifest/lock。该 fork 的 Flutter SDK 版本约束与官方 3.41.9 不同，且 OHOS pub/hvigor 工具链不应读取官方根 workspace；本机通过独立 `just ohos-check mode=debug` 验证了这一边界。OHOS 宿主没有加入根 workspace，也没有依赖 `ubaa_test_support`。

### 分析配置与现有提示

根 `analysis_options.yaml` 统一 include `package:flutter_lints/flutter.yaml`，并把 `implementation_imports` 提升为 error；各官方包、OHOS 宿主和三个 OHOS 插件通过本地 include 继承。迁移后没有 analyzer error，也没有新增 ignore。既有 flutter_lints 的 `info` 风格提示仍按包输出，脚本使用 `flutter analyze --no-fatal-infos`，implementation_imports 等 error 仍会阻断门禁；这些提示没有通过 ignore 掩盖，后续可单独清理。

### 共享测试夹具

新增 `packages/ubaa_test_support`，集中 recovery、backend rebuild、grades、write cache、门锁展示和 navigation 夹具。原单元测试的断言逐条保留，跨包 `test/` 直接导入为 0；domain/platform/app/UI/bindings/host/official app 全量测试均通过。support 包本身使用同一分析配置并完成分析检查。没有移动 `docs/design/evidence` 下的 JSON。

### 布局和构建配置

布局门禁调用现有 `module_graph.py` 按 Dart library 聚合 `part` 文件统计；当前 `ubaa_ui/src` 最大 1813/2000，`ubaa_app/src/bridge` 最大 653/1000，`ubaa_app/src/controller` 最大 746/1000，均未超限，因此没有扩大上限或进行无必要拆分。布局合同测试的最小临时仓库没有该脚本时跳过聚合检查，真实仓库仍严格执行。

Android release signing 改为同时接受 Gradle property 或环境变量 `UBAA_RELEASE_STORE_FILE`、`UBAA_RELEASE_STORE_PASSWORD`、`UBAA_RELEASE_KEY_ALIAS`、`UBAA_RELEASE_KEY_PASSWORD`。变量不完整时 release 不绑定签名配置，避免回退到 debug 密钥；debug 构建逻辑不变，仓库没有加入密钥。Android application id、OHOS bundleName 和版本号均未修改，避免影响已安装应用升级；OHOS 的 `1.0.0`/`1000000` 与 Flutter `0.1.0+1` 差异登记为后续决定。

### 明确保留的后续待办

监督者已决定本轮不继续拆分历史 `mod.rs` 中的协议实现，也不把 Bridge 离线流程泛型化；两项保留原实现并登记在状态页，待后续阶段重新评估。feature 专属 SSO URL 同样按阶段 5 决定保留，不在本阶段合并。

本阶段实现提交为 `1b53eb1a`、`8480c23e`、`758e5de1`、`dbc3c847`、`43d9fc0c`、`c8777caa`；其中 `c8777caa` 固定 FRB 2.13.0 重复生成时 `BridgeClient.dispose` 注解的归一化，文档提交单独保留。完整验证结果写入 `.ubaa_local/supervision/phase6-report.md`。
