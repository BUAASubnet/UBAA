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

## 2026-10-30：认证重定向安全收紧与复核更正

逐操作来源、反例和测试见[认证安全复核](source-parity-auth-review-2026-10-30.md)。认证目标拒绝用户信息与未声明端口，WebVPN 外壳只接受 HTTPS 默认端口。SSO 不借用 iClass 的 8346/8347 许可。通用 codec 保留冻结业务自定义端口与网关原生路径，仅在加密主机可识别后严格解析 wrapper 端口，防止畸形端口降为默认端口。

BYKC final URL 与 Location 先解析实际目标，再校验精确主机、协议、端口，token 仅取已证 `/cas-login`。Signin、LibBook 同样先解析根相对/协议相对网关包装，普通相对路径继续沿用解包后的业务基址。Direct 接受合法 wrapper 并请求解包上游的行为有冻结测试支持；路线测试确认其实际请求不发往 d，不能把这种解包误判为路线越界。

Ygdk 冻结代码与 BackendTest 证明 app→ygdk 回调，buaa-api 无等价模块。当前只请求 HTTPS 默认端口 app/ygdk，WebVPN 解包后主机同样验证，未知目标失败关闭。code 仅取 ygdk 根路径 query 或 `/home` fragment query，并按冻结 Ktor 语义单次百分号解码，保留字面 `+` 和 `&`。没有推测新的中间主机；完整真实跳转链兼容性仍需双路线证据。

复核撤回了把 Signin/LibBook 写后认证判定改为严格安全 authority 的做法。写已发送后，异常 SSO 地址或认证路径必须继续归为 OutcomeUnknown，严格发送前校验不能缩小未知结果范围。恶意 final URL 加成功 JSON 的 Mock 反例证明分类回归，但生产 Reqwest 禁止自动跳转，不能据此声称普通 Location 已能远程制造该 final。用户/课表等读取认证判定保留解析后的精确主机与路径。

## 2026-10-30：发布材料、集成执行器与宿主 smoke 复核

根 Pub workspace 的成员和锁文件作为检查输入，独立 OHOS 与 Cargokit 锁文件继续保留。读取 workspace 成员时跳过空行和注释，不因顶格注释提前截断。第三方 Git 包不得沿父目录继承本项目许可证。发布默认严格模式在材料不完整时保留报告并返回状态 3；源码 CI 显式使用报告模式，保留缺口清单，同时继续阻断解析、工具或 schema 错误。报告模式不作为发布完成条件。

集成执行器先校验所有选中入口，再启动 Flutter，避免先运行部分测试才发现后续配置缺失。环境变量与 Dart defines 使用环境副本和参数数组传递。清单和参数失败均有离线合同测试；不通过跳过入口或删除前提获得通过。

独立运行 CLI 二进制测试时，编译器报告缺少 `ubaa_core::facade::testing`。全 workspace 测试原先借用了其他成员启用的 `test-contract` feature，掩盖了 CLI 的测试依赖遗漏。CLI 现在显式依赖 `ubaa-test-support` 开发包，并从该包导入测试会话类型，由统一测试支持层启用 feature。生产依赖保持默认关闭，原有 CLI 单包测试命令可以独立执行。

原生 smoke 包含两种证据：DemoBackend 驱动真实宿主登录交互，RustLib/BridgeBackend/Core 验证本地首页、缺会话错误和缓存读取。后者不请求学校，因此保留真实 FFI 接线覆盖，同时明确不覆盖成功的学校登录或业务写入。宿主在首页首帧后合并待处理恢复，并保留异步后端初始化期间的前后台状态；退出再登录时重置首帧标记，避免恢复过早或重复执行。

Bridge 保留 rand 0.10 系列，由锁文件固定为 0.10.3，避免精确钉住 0.10.2 导致其他依赖降级。Core/RSA 仍依赖 0.8，两组接口不能机械合并；cargo-deny 的重复版本记录按实际依赖树说明原因。Cargo 重算还将 cssparser-macros 的 syn 解析从 3.0.9 改为已有的 2.0.119，该上游接受两个系列；完整编译与测试验证当前锁文件，未手改依赖解析结果。

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

## 2026-10-30：阶段 6b 低风险清理

本轮补做阶段 6 顺延的低风险项目，提交前以 `git grep -w` 检查正式名称、测试替身和 OHOS 宿主的全部使用方。删除 `Credentials`、`StoredCredential`、`TelemetryEventName`、`TelemetryRecord.fields`、`WriteFlowController` 以及 `ubaa_host` 的 `network_monitor` re-export；测试改用 `Credential`、`TelemetryEvents` 和 `WriteCoordinator`。`DemoBackend` 迁入 `ubaa_test_support`，生产包不再导出，使用它的官方测试改从 support 包导入；OHOS 宿主登录页测试继续使用 `UnavailableBackend`，避免让独立 OHOS fork 依赖官方测试包。上述变化只移除无人使用的兼容入口或测试替身位置，未改变生产协议、UI 文案、交互或 Bridge 调用。

三个 OHOS 插件的 `UPSTREAM.json` 统一为 `repository`、40 位 `commit`、`path` 和逐文件 `sha256`。`flutter_secure_storage_ohos` 的现有材料只有 `Csy_Gitee@f1a8ada0`，没有公开仓库 URL 或完整提交，因此明确保存 `null` 并记录已知短引用，没有猜测提交。Cargokit 增加出处记录，基线对应上游 `969c49a1b15ba8c1036cb6fc8790f40702b734b1`；本地修改逐条注明 `893aa848` 的 OHOS 支持和 `c94dbcd2` 的 Windows 路径修复。

清理平台模板中的 TODO 和占位内容：移除 Android Gradle 的模板 TODO、替换 macOS/Windows 模板展示文本、删除 iOS/macOS 空模板测试方法、删除 OHOS 插件未使用的 `page_show` 资源，并为 OHOS 宿主补齐英文资源回退。官方 Flutter CMake 生成注释保留，因为它们属于工具维护模板而非本项目待办。没有修改 bundle id、application id、版本号或 debug 构建行为；根 `.dart_tool` 等本地生成目录加入忽略规则。

测试替身中可逐字机械合并的 `_tap` helper 收进 `ubaa_test_support.tapVisible`，图书馆导航中带额外滚动语义的变体保留为独立实现。所有原有断言保留，未改变测试覆盖范围。

## 2026-10-30：阶段 7 依赖审计

依赖审计采用两个显式边界。Dependabot 覆盖根 Cargo、官方 Pub workspace、四个独立 OHOS Pub 包、根目录的 docs npm manifest 和 GitHub Actions；Cargo/Pub 每周或每月按生态分组，避免为每个传递依赖单独创建 PR。审计配置使用 `deny.toml`，cargo-deny 版本 `0.20.2` 只在 `scripts/tools/versions.env` 维护，`just dependency-audit` 和 CI 安装/校验同一版本。

许可证白名单根据当前 `cargo metadata --locked` 和 cargo-deny 的实际许可证表达式建立，包含 `0BSD`、Apache-2.0（含 LLVM exception）、BSD-2/3-Clause、CC0-1.0、CDLA-Permissive-2.0、ISC、LGPL-2.1-or-later、MIT/MIT-0、MPL-2.0、Unicode-3.0、Unlicense 和 Zlib。`allo-isolate` 清单缺少 license 字段，但其 LICENSE 被 cargo-deny 识别为 Apache-2.0；该现有上游材料缺口保留 warning，不放宽许可证策略。

本次通过 Cargo 的依赖更新流程修复可直接升级的公告：`h2`、`rustls`、`rustls-webpki`、`tokio`、`webpki-root-certs` 等均由 Cargo 实际更新并写入 `Cargo.lock`；工作区直接依赖统一到 reqwest 0.13.5、rustls-platform-verifier 0.7.1、tokio 1.54.1 和 base64 0.23.1。剩余 `RUSTSEC-2023-0071`（rsa Marvin timing）目前没有安全修复，稳定版本仍受影响；项目只在本地解析固定来源登录材料，不提供可被网络观察的 RSA 私钥解密服务，因此按 cargo-deny 配置逐项豁免并登记，待上游发布修复后删除豁免。该豁免不涵盖其他 advisories，当前检查结果为 advisories、licenses、bans、sources 全部通过。

重复版本检查设为 deny。当前经审计仍因平台目标、时区/解析生态、过程宏和图像/压缩链路的独立约束保留 `core-foundation`、`getrandom`、`hashbrown`、`miniz_oxide`、`phf`、`phf_shared`、`syn` 的重复版本；每项在 `deny.toml` 的 `bans.skip` 中写明原因。workspace path 依赖不代表外部版本漂移，cargo-deny 的 wildcard 检查保持 allow，边界和理由记录在本条。

Advisory 数据库访问只发生在 `just dependency-audit` 或 CI 的对应显式步骤。入口脚本归入 `scripts/release/dependency-audit.sh`，因为它需要联网、由 CI/发布流程显式调用，职责与 `scripts/release/dependency_report.py` 同属发布依赖材料；`scripts/check` 保持 16 个直属源码且不新增布局基线。`just check-strict`、`just release-preflight` 和普通 refs/检查命令不隐式联网。

## 2026-10-30：OHOS 原生材料不再固定判缺

复核发现原报告无条件把四条 OHPM 本地依赖标记为待核对，缺少读取补充证据的路径。本轮增加显式 JSON 输入并校验产物、许可证和使用方声明的摘要，来源仓库只允许无凭据的公开 HTTPS URL 与完整提交。相同名称和产物摘要合并，来源或许可冲突时失败。材料映射只证明文件一致性，来源字段仍是显式声明，不自动证明二进制构建来源。

`libubaa_flutter_bridge.so` 的 OHPM 依赖实际指向受跟踪的类型声明目录，本轮改为收集声明版本、源码摘要和项目许可证，不把该记录当作动态库材料。三个 Flutter 插件的本机 OHPM 锁文件解析到同一份 embedding HAR，SDK 位于固定提交且工作树干净。已从该 SDK 收集许可证正文并生成本地材料映射；历史“四项缺口”由这次实际收集结果替代，不能继续解释成四份文件确实缺失。
