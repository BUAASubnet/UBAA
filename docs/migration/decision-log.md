# 决策记录

## 2026-11-06：SSO 直接验票与域名路线缓存

用户在校外网络确认 UC 无法访问，而 SSO 登录后其他网站仍可使用。本会话在同一环境直接调用 SSO：使用既有教务 service 取得票据，SSO `/serviceValidate` 返回有效账号身份，无需请求 UC 或教务服务器。主登录和会话检查采用此验票链，UC 保留独立资料功能。两份冻结参考没有等价验票实现，以[真实协议对照](source-parity.md#sso-身份核验与-uc-解耦)为依据。302、Cookie 存在或输入账号都不能独立作为已核验身份。

Auto 在校园网只认证和使用 Direct；校外认证两条独立路线，业务默认 Direct。网络不可达或超时才允许在另一条路线重新执行可重放读取。域名的 Direct 失败且 WebVPN 成功后记录 24 小时回退状态，到期再尝试 Direct。认证拒绝、权限、业务和解析错误不触发路线切换，显式路线不回退，业务写入越过发送边界后不自动重放。

同账号、同业务查询共用持久业务缓存，传输路线作为结果来源保留，不作为数据归属。Cookie、业务 Token、会话、提交资格和一次性句柄继续按路线隔离。当前项目处于开发期且没有用户，新的缓存结构不承担旧格式迁移。

## 2026-11-06：SSO 图像验证码按当前准备状态直接提交

冻结旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 的 `LocalConnectionAuth.kt:451-550` 在提交前重新 GET 登录页，却优先使用调用者传入的 execution。固定 buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81` 的 `api/sso/auth.rs` 没有等价图像验证码操作。此前保留 GET 的方案依赖挑战标识稳定，来源尚未证明这一条件。

2026-11-06 同一 Cookie 会话内的只读观察显示，WebVPN 连续两次 GET `/login` 都返回图像验证码，而且 captchaId 与 execution 每次变化；Direct 当时没有图像验证码，execution 同样变化。用户提供的验证码失败 HAR 中，浏览器使用准备页的 execution 直接 POST，中间没有重新 GET 登录页。401 拒绝页同时给出新 captchaId、execution 和统一文案“用户名或密码错误。”。原始材料仅保留在本机私有目录。

依据上述实际协议，图像答案与当前准备页一起提交，提交前只核对本地账号意图、路线、挑战代次、有效期及取消状态，不再重新读取登录页。服务端拒绝后使用拒绝页的新挑战。静默识别使用 ddddocr 默认模型和左右各 5 像素留白，最多尝试三次，随后交给人工输入；未知错误或没有收到响应时不重放凭据。用户已接受统一拒绝也可能来自错误密码，因此本轮限次策略不能用于撤销保存的凭据。

原 `rotated_execution_or_id_returns_new_challenge_without_post` 测试改为服务端拒绝后替换挑战并拒收旧句柄；本地取消、过期、刷新与跨路线句柄的零 POST 覆盖继续保留。新增每次 GET 都轮换页面的反例证明当前图片可以实际提交。[来源索引](source-parity.md#sso-图像验证码静默处理)记录完整操作对照。

## 2026-11-05：希冀作业详情使用独立正文预算

Direct 真实只读返回的一项正常作业详情为 10,875,793 字节，超过 Core 默认 8 MiB 解压正文预算。旧版完整读取 HTML，没有在对应客户端设置应用层响应字节上限。采用[来源对照](source-parity.md#希冀作业详情正文预算)确认的详情端点预算：GET、精确 Judge 主机、`/assignment/index.jsp` 和数字 `assignID` 使用 16 MiB，Direct 与 WebVPN 解包后采用同一规则。其余请求保留 8 MiB，声明长度与解压累计长度均执行预算检查，TLS、重定向和错误分类保持。

Judge 详情需要完整 HTML 进行现有 DOM 解析，因此本次保留完整缓冲，每份详情允许的正文字节数增加 8 MiB，实际内存还包括缓冲容量与 HTML DOM。现有 Direct 批量读取上限仍为四个课程 worker。16 MiB 是本机资源预算，后续若出现更大的正常响应，应按新证据评估解析与内存需求。对象下载继续走现有专用流式端口。

## 2026-11-04：日程界面优先，按产品结果组织交付

下一项主要验收目标确定为 App 日程列表、详情、新建编辑和 `.ics` 导出，复用主线已有的 Core 模型、存储、投影和日程服务。三平台正式命令入口、Linux SSH、共享恢复和旧 CLI 退役不再共同构成日程 GUI 的前置条件。采用尚未合并的共享服务候选时，仍须关闭相关缺陷并完成整合验收。

统一 App 命令模式、共享账号/会话/缓存/日程、Linux SSH、完整北航云盘和日程同步的既定需求保留。同步按所需网盘读写与并发证据安排，不要求先完成全部分享和回收站功能。Core、Bridge、应用服务、平台和 UI 的主要职责保持，客户端替换与关闭的关联状态由现有资源所有者统一管理。

产品计划使用日程界面、统一命令模式、北航云盘、日程同步等可验收结果。旧阶段编号保留为候选和证据索引，具体修复、平台适配与审查归入内部任务。当前目标、长期范围、实现状态分别由 [goal](../../goal.md)、[路线图](../../UBAA2.md)和[状态页](status.md)维护。当前仅调整计划，开发执行保持暂停。

执行任务本身也按完整功能划分。日程列表、详情、编辑、保存和导出作为同一任务交付，测试、修复及复审在任务内完成。跨提交或更换聊天继续时保持任务身份，只有能够独立交付和验收的功能才拆成新任务，规则见 [AGENTS 任务粒度](../../AGENTS.md#任务粒度)。

## 2026-11-01：命令运行时按平台分流，共用无界面服务

H0 按锁定 Flutter `3.41.9`、Dart `3.11.5` 和 FRB `2.13.0` 的实际源码及私有样机，选择 macOS/Windows 的无 view Engine 路线和 Linux 的纯 Dart AOT＋同一生成 FRB 路线。Linux 锁定 public headless API 没有公开启动接口，独立 Dart 路线已经在无显示器、断网 Docker 中实际调用 Rust 日程库。Linux 的安全材料沿用 libsecret/Secret Service，私有 Dart FFI 试验复用锁定插件原生后端，材料服务重开后可读回合成值。生产材料适配和原 item 连续性仍待平台接入验证。

所有原生入口均在窗口及 GUI 单实例逻辑前分流。GUI 只识别 GUI 角色，避免命令运行期间阻止用户启动窗口。命令的输出通道独立于 Engine 日志，保留继承管道和实际退出码。Linux AOT 只改变运行组件，不新增账号索引或业务状态。账号、目录、凭据许可和恢复规则在同一公共服务中维护，旧 alias、CacheKey、业务缓存加密及日程明文继续保留。

H1-a 先在现有 `ubaa_app` 提供纯 Dart 窄入口，提取所需路线恢复服务和最小 Bridge 适配，保留 GUI 的调度、写入等待与展示。跨进程代次、锁和全局退出在 H1-b 单独验证。Windows 本机没有可用运行环境，平台源码核对不计为原生通过。完整路线、样机范围、失败结果与下一单元文件见[实施计划](../design/desktop-shared-state.md#h0-运行路线与样机证据)。本轮只提交文档，继承的旧 CLI worker 与公共身份修复实验保持原样，逐项去向写入私有交接。

## 2026-10-31：缓存预读与博雅首屏分页

本轮冻结参考为旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 和 buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。旧版 `LocalBykcApi.kt::getCourses/queryStudentSemesterCourseByPage`、DTO `Bykc.kt` 和 `LocalBykcApiBackendTest.kt` 将调用方的页码、条数传入上游；旧 UI `BykcViewModel.kt` 默认 20 条。buaa-api `api/boya/opt.rs::query_courses` 同样传入 `pageNumber/pageSize`，并未要求固定 20 条。请求、登录、加密和错误继续遵守[博雅逐操作对照](source-parity.md#博雅课程只读查询)的九列规则。

App 的选课 summary 固定每页 8 条，在线和本机缓存使用同一分页键。选择依据是用户在本轮提供的先前只读耗时观察：1/5/20/50 条分别约 0.6/1.6/5.4–6.4/17.5 秒；本轮没有重新访问学校核验，因此这些数值只作为性能取舍的输入，不是当前候选的实测结果。可见选课列表串行预取到 40 门，之后保留滚动加载。失败、无新增项目、离线缓存、离开当前帧、清缓存、账号变化和写入期间均停止自动追加；筛选与搜索只处理已加载集合，不能据此宣称全量搜索。Core 和 CLI 的可选分页参数保持原约定。

缓存预读仅调整本机投影时机。逐操作的 URL、service、跳转、Cookie/Token、HTTP 参数、请求头、正文、加密和 DTO 沿用[来源索引](source-parity.md)及[离线恢复对照](source-parity-offline-recovery-2026-09-17.md)。旧版按账号保存课表、按账号与路线缓存 Judge；buaa-api 没有等价全功能离线仓库，对此次本机首帧调度不适用。首页最多等待本机缓存 800ms，查询切换最多等待 300ms 后开始在线读取，默认读取与缓存恢复并行。任何缓存结果均须校验账号、路线、查询与读取代次；资料缓存允许在 checkingSession 阶段投影，仍不改变认证身份或恢复状态。待核实提示在进入首页后补读。本轮只运行合成数据与本机门禁，Direct/WebVPN 实测留待有相应任务授权时执行。

## 2026-10-30：桌面宿主改为单实例并删除跨进程启动锁测试

用户决定应用不支持多开：有其他实例运行时禁止启动，跨进程启动锁原生集成测试不再保留。macOS 在 AppDelegate 初始化时按 Bundle ID 查找同用户的其他进程，唤起后退出；Windows 用会话级命名互斥量 `Local\cn.edu.ubaa.single_instance` 判断并唤起已有窗口；Linux 去掉 `G_APPLICATION_NON_UNIQUE`，由 GApplication 把重复启动的 activate 转交主实例并呈现已有窗口。移动端与 OHOS 由系统保证单实例，不改。

Core 会话文件锁和 resourceBusy 提示保留为兜底（例如无会话总线的 Linux、或绕过宿主的进程），由 Rust 合同测试覆盖。删除 `startup_lock_test.dart`、Perl 持锁夹具与其自测、catalog harness 字段；单实例行为暂无自动化覆盖，需各平台手动重复启动验收。

## 2026-10-30：Rust Core 重复实现收敛与开发期缓存格式

用户要求执行 Core 审查中发现的全部修复，并明确当前应用处于全新开发阶段，无需保留缓存格式迁移。本轮删除历史缓存迁移和无效兼容字段，旧数据库返回明确版本错误，用户可显式重建。当前格式的加密、账号/路线隔离、持久失效票据和部分结果保护继续保留。

缓存刷新共用准备/收尾，业务凭据共用私有 typed 槽位，两种客户端共用路线内安全检查与清理。固定路线客户端和双路线客户端的公开返回值、协调范围继续分别处理。SPOC、评教与 LibBook 共用协议读取/解析步骤，博雅移除 JSON 内存往返；Cgyy 删除敏感正文 SHA1 日志。来源、失败反例、测试整理登记及最终验证见[本轮记录](2026-10-30-core-simplification.md)。

## 2026-10-30：延续旧版应用身份与签名配置

用户明确要求 UBAA 2 作为旧版更新。根据用户后续要求，Android applicationId、iOS/macOS Bundle ID、Linux APPLICATION_ID 和 OHOS bundleName 统一为 `cn.edu.ubaa`，Apple 测试 target 同步后缀。Windows 尚无 MSIX 配置，后续非商店包 Identity Name 使用同一标识，Publisher 由证书确定；商店包遵循 Partner Center 分配的身份。Android Kotlin namespace 保持现有值，避免无关源码移动。依据为旧版 androidApp/build.gradle.kts 与 release.yml 的发布身份，以及本机旧版 iOS Profile。当前桌面身份不能从移动端类推，仍需核对旧正式安装包的身份和数据目录。

[应用签名配置](../runbooks/app-signing.md)统一本机私有材料目录、原生工具配置和旧 CI secret 映射，分别说明官方更新与二次开发。当前阶段提供配置方法，不新增自动签名或上传流水线，不生成或替换官方密钥。构建号、签名有效性和旧版数据迁移仍是正式发布前的独立检查项。

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

## 2026-10-30：Android TLS 组件的 Maven 分发迁移

Android Debug 实际构建先失败于缺少 `rustls:rustls-platform-verifier:0.2.0`。锁定的 rustls-platform-verifier 0.7.1 依赖 Android shim 0.2.0，该 Cargo 包不再携带 Maven/AAR。按[上游发行说明](https://github.com/rustls/rustls-platform-verifier/releases/tag/v/0.7.1)及 [0.2.0 POM](https://github.com/rustls/rustls-platform-verifier/blob/maven-archive/android-release-support/maven/org/rustls/rustls-platform-verifier/0.2.0/rustls-platform-verifier-0.2.0.pom)，改用官方 Maven archive 和 `org.rustls` group。上游 README 中仍有旧 group 示例，因此以实际 POM 为准。

Gradle 的 exclusiveContent 仅允许该模块从此仓库解析，版本继续由 `cargo metadata --locked` 取得。没有改动 TLS 校验逻辑、学校请求、Cargo 锁文件或依赖版本。首次失败和逐次构建日志保留在本地忽略目录 `.ubaa_local/signing_android_*.log`。

## 2026-10-30：签名材料默认使用仓库内 .sign 目录

按用户要求，签名手册默认使用根目录 `.sign/`，根 `.gitignore` 排除整个目录。仓库外保存只是先前的建议，长期规则要求的是不提交签名密钥，没有要求所有签名文件必须放在仓库外。原生安全存储继续按平台要求使用，目录约定不新增自动配置加载。共享示例与真实材料分开，说明相对路径基准、目录备份和打包排除要求。

## 2026-10-30：Android 平台签名字段与本机配置入口

Android 自动读取被忽略的 `.sign/android/signing.properties`，使用 ANDROID_STORE_FILE、ANDROID_KEY_ALIAS、ANDROID_KEY_PASSWORD、ANDROID_STORE_PASSWORD。文件中的密钥相对路径以配置文件所在目录为基准；外部 Gradle/环境覆盖值仍沿用原 app 目录基准。

配置按整组选择：ANDROID_ 外部字段优先，其次为兼容旧 CI 的 UBAA_RELEASE_ 外部字段，最后是本地文件。选中组不完整时失败，避免从下一组混入另一个密钥的口令。ANDROID_SIGNING_PROPERTIES 支持指定独立配置文件，显式路径不存在时失败；默认文件缺失且没有外部字段时保持无签名。密码只在构建进程内使用，不打印或加入仓库。

真实 Gradle 配置阶段反例先证实本地字段未被加载，修改后本地读取、相对路径、字段缺失拒绝、平台环境覆盖和旧 CI 兼容均通过。配置反例使用隔离的合成属性文件，另已验证部分外部覆盖不会回退到本地字段、显式缺失路径拒绝和空配置保持无签名。完整按改动检查以 `552edafe` 为基线通过，包含 Rust/脚本检查、八成员 Flutter 检查和 FRB 零漂移，严格 ShellCheck 也通过。日志位于本地忽略目录 `.ubaa_local/android_signing_config/`。

用户完成本地配置后，使用提供的 keystore 构建 Release APK，签名校验及与 keystore 的公开证书摘要对照通过。包名保持 `cn.edu.ubaa`，版本仍为签名试包用的 `0.1.0+1`。首次构建与 Flutter 检查并行时发生插件注册文件引用 `integration_test` 的编译错误；检查结束后源码不变、单独重跑成功。后续同一 checkout 的 Flutter 检查与平台构建应串行运行，避免生成文件互相覆盖。旧正式包证书对照、覆盖升级和设备运行仍未验收。

## 2026-10-30：逐图 UI 元数据移出当前文件树

阶段 4 曾决定 3967 个历史 UI JSON 原位保留。复核后，这些文件只描述已移到仓库外的截图（尺寸、时间、`pngSaved`），
占当前文档行数约四分之三，却没有现行流程读取它们，反而拖慢检索与全仓扫描。本次移除这些 JSON 和 40 份 SHA256SUMS，
只保留批次文字说明、原型、`external-archive.json` 与 `prototype-manifest.json`。原文在 `7348b8b3` 及更早提交中完整可取，
恢复方式写入[批次索引](../design/evidence/batches.md)。新批次的逐图元数据与截图一起留在 `UBAA_UI_EVIDENCE_DIR`，
仓库只提交文字摘要。验收分类、外部归档和提交映射均不变。

## 2026-10-30：记录只跟随事实变化

此前开发循环要求每轮都更新状态页和决策记录，结果近 60 个提交中 `docs/migration` 的改动次数超过 Core，
状态页也变成按日期追加的流水。现在状态页只保留当前实现、未解决事项和最近一次完整验证；单轮验证写提交说明，
日志留在 `.ubaa_local/`，决策记录只收会影响后续判断的取舍。原状态流水原样移入
[历史目录](history/2026-10-30-status-log-through-signing.md)，单轮任务报告同样归档。来源对照门禁、
真实账号授权和完成条件不变。

## 2026-10-30：发布前置只保留许可证材料

`release-preflight` 原先还生成带 CycloneDX schema 校验的 Cargo SBOM、全部跟踪文件的逐文件 SHA-256 清单和
pubspec 锁文件摘要。没有使用方读取 SBOM；Rust 依赖的许可与公告已由 cargo-deny 检查；提交 SHA 已唯一确定
全部跟踪文件和锁文件，逐文件清单不增加保证。现在入口只做干净工作树、refs、敏感扫描和 Dart/OHOS 许可证材料，
材料缺口仍以状态 3 阻止发布。随之删除 CycloneDX schema 副本及 jsonschema 依赖链（六个 Python 包）。
`source_manifest.py` 改名为 `build_record.py`，原生工作流仍把候选 SHA、作业和产物逐文件摘要关联。
日常 CI 不再以报告模式运行发布前置，发布前本地执行。OHOS 补充材料清单格式不变。

## 2026-10-30：本机工具链改为一条命令准备

版本仍只维护在 `scripts/tools/versions.env`，但新机器原先要手敲十余条命令，也没有入口能一次看出本机哪些工具
与锁定版本不符。新增 `just setup`（显式联网，已一致项跳过，不改写已有 SDK 或 `.env.toolchain`）和只读的
`just doctor`。暂不引入 mise：它无法管理 OHOS fork、DevEco 和 Flutter 提交锁定，引入后还需迁移 CI 与
`versions.env` 的全部读取方，收益不足以抵消第二套版本来源的风险。

## 2026-10-30：OHOS 工具链收成一条单链

DevEco 直接构建时没有 just 导出的环境变量，Cargokit 找不到 Dart 和 native SDK。另一轮未提交的修复让 Hvigor
优先读 `FLUTTER_ROOT`/`OHOS_SDK_HOME`、缺项再调用 Python 解析 `.env.toolchain`，同一组 SDK 路径因此分散在
`.env.toolchain`、环境变量、`local.properties`、`ohos-json` 接口和手写材料清单五处，`FLUTTER_ROOT` 还可能
让 OHOS 构建悄悄用上官方 Flutter。

现在只保留一条链：`.env.toolchain` → `just flutter-ohos`（从 `UBAA_DEVECO_HOME` 导出 `DEVECO_SDK_HOME`、
`OHOS_SDK_HOME`）→ OHOS Flutter 生成的 `ohos/local.properties` → `hvigorfile.ts` 读取 `flutter.sdk` 与
`hwsdk.dir`，以 CMake 参数只传给 Cargokit 子进程。Flutter 自己的 hvigor 插件本就读取该文件。OHOS Flutter 的
全局 `ohos-sdk` 设置优先于环境变量写入 `hwsdk.dir`，由 `just doctor` 核对与 `.env.toolchain` 一致。删除手抄的
`local.properties.example`。

发布预检不再读取 `UBAA_OHOS_EVIDENCE` 手写清单：embedding HAR 的许可证从提交等于 `OHOS_FLUTTER_COMMIT` 的
锁定 SDK 收集，来源记为新增的 `OHOS_FLUTTER_REMOTE`。实测仍为 324 条材料、0 项缺口，并多收集了 HAR 附带的
`LICENSE.flutter_har_zip.md`。`packages/ubaa_bindings/ohos/oh-package-lock.json5` 与其他 OHOS 包一致改为忽略，
它只锁定仓库内的类型声明，每次构建都会被写入本机 SDK 路径。OHOS fork 构建时会移走受跟踪的
`buildinfo.json5` 模板，`ohos.sh` 构建后自动恢复。Cargokit 的本地修改登记到 `UPSTREAM.json`。

## 2026-10-30：按改动范围分级，完整验收只执行一次

日常提交区分文档、脚本、普通 Rust、受影响 Dart 包和完整验收，推送模式扩大 Flutter 检查并按原生影响选择集成测试。安全、协议、并发、存储、公共合同和跨语言边界仍在提交前完整验收，未知路径保持保守；路径不能判断的语义由审阅者显式选择 full。门禁改动先验证自身行为与实际入口，PR/CI 继续承担完整确定性检查，不再要求默认按改动检查与完整清单重复执行。FRB 只随生成输入、依赖配置或未知影响检查，显式 full 保留重生成。

文档和脚本使用独立静态 Cargo 命令锁定扫描，保留 CLI 二进制中原扫描，避免分级后漏掉文档里的未锁定命令。共用脚本检查从 Rust 入口抽出，布局中的 Dart 依赖检查不再重复执行。审查后保留 CLI 与 Bridge 各自的默认编译合同：合并两个宿主会统一 Core feature，可能掩盖另一个宿主误用测试注入面。workspace 测试和默认生产构建也继续保留。

布局检查改为批量读取 Git index blob，分别检查 index 与工作树。原有 42 项 Shell 合同保留，另增加空格路径、无尾换行、隐藏源码及 Git 列举/读取失败的六项反例；本机布局耗时从约 78 秒降至约 1.3 秒。不新增布局基线，验证日志保存在本地忽略目录，耗时和最终验收写入提交说明。

## 2026-10-30：构建缓存从源头限制增长

清理约 123 GiB 后一小时内仓库又长回约 31 GiB。实测主要来源：根 `target` 的增量缓存因门禁的多种 feature 组合
（默认、`--no-default-features`、`test-contract`、`--all-features`、doc、clippy）同时存在 24 份 `ubaa_core`
变体；OHOS `.cxx` 是 Cargokit 独立的 Cargo 目录，`flutter clean` 清不到；桥接 crate 同时声明 `cdylib` 与
`staticlib`，各平台都把两种都编出来；Cargokit Gradle 插件在 debug 下无条件追加 `android-x86`/`android-x64`，
指定 `--target-platform android-arm64` 或 `flutter run` 到真机时仍编三份 Rust。

处理：门禁 recipe 用 `[env("CARGO_INCREMENTAL", "0")]` 关闭增量（日常 Rust 与 Flutter 运行不受影响）；
`profile.dev.debug = "line-tables-only"`，保留堆栈行号；Cargokit 改用 Cargo 的 rustc 子命令并传入 `--lib --crate-type`，Apple
只编 `staticlib`、其余只编 `cdylib`，zigbuild 路径不变；删除 Gradle 插件过时的 debug 架构追加，与 Flutter 3.41
的平台列表一致。两处 Cargokit 修改登记到 `UPSTREAM.json`。新增 `just cache`/`just cache-clean`，只删除被忽略、
无受跟踪文件的真实目录，任一目标不安全时整体拒绝；`.ubaa_local` 只显示不清理。

实测（同一机器，清理后重建）：macOS debug 的桥接 `.a` 从 590 MB 降到 325 MB，不再生成 75 MB `.dylib`，
`build/macos` 从 5.0 GiB 降到 3.1 GiB；Android arm64 debug 只编一种目标、不生成 `.a`，桥接 `.so` 146 MB
（改前 OHOS 同类产物 342 MB 外加 844 MB `.a`），整次构建 132 秒。

未处理：Core 集成测试仍是每个 `tests/*.rs` 一个二进制。精简调试信息后 `test-contract` 全部测试目标共 17 个、合计 213 MB（单个最大 45 MB），合并收益有限且会触及测试目标登记合同，因此不合并；
Cargokit 固定使用 `rustup run stable` 而非 `rust-toolchain.toml` 的 1.95.0，目前两者版本相同，属于可复现性问题，
另行处理。仓库外的模拟器、Gradle 旧版本缓存等不在本入口范围内。

## 2026-10-30：项目调试材料统一保存在本地工作目录

用户明确要求项目临时源码、调试脚本、日志、截图和原始调试材料统一放入被忽略的 `.ubaa_local/`，按任务使用独立子目录。本决定更新此前运行媒体必须保存在仓库外的约定，已有历史归档保持原位置。原始材料继续只保留在本地并设置私有访问权限，共享文档仅使用必要的脱敏摘要，不纳入 Git。

截图驱动同步检查真实路径，只允许 `.ubaa_local/` 下的任务子目录，拒绝父目录跳转、仓库其他目录及符号链接越界。关于、照片与方向用例的截图内容和验收范围保持原规则。

## 2026-10-30：完整验收合并原生构建与静态分析

同一台 8 核 macOS 上，冷缓存的完整验收（`just check-changed mode=full`）基线共 1175 秒：Rust 严格检查 434 秒、八包 Flutter 374 秒、原生集成 212 秒、FRB 生成检查 150 秒。只追加一行 Core 改动后重跑，Rust 262 秒、Flutter 235 秒。处理如下，覆盖不减少：

- 原生集成：Flutter 3.41 对每个入口文件各调用一次 `startApp`，一次传多个文件也逐个构建、启动。基线首个文件构建 87 秒，之后每个文件还要 25 至 30 秒重建和启动，测试本体只有 1 至 3 秒。默认集合改为运行时按清单生成被忽略的 `integration_test/.ci_suite/` 聚合入口，各入口在同一应用进程依次运行，Dart define 合并、冲突时拒绝，结束即删除。两个 FFI 入口共用一次 `RustLib.init()`，FRB 不允许重复初始化；`suite=ci-isolated` 保留逐文件运行，用于排查入口间的状态影响。当时五个入口的冷缓存运行连同 macOS 与 Rust 构建一共 184 秒，测试本体 9 秒；启动锁用例随单实例改动删除后剩四个入口，每次仍省去 3 次重建和启动，约 80 秒。
- 删除 `synthetic/app/smoke_test.dart` 的替身登录用例：原生集成绑定不注册测试输入法，应用没能切到前台时文本输入失效。未改动的基线与新版都在“登录按钮可点”处失败过。同样的流程和断言由 `apps/ubaa_flutter/test/app/smoke_test.dart` 覆盖，同文件的真实 FRB/Core 首页用例继续承担宿主 smoke。
- Flutter：在根目录执行一次 `pub get`、一次覆盖八包的 `dart format`，以及一次多目录 `flutter analyze`。基线逐包的这三步合计 59 至 81 秒，合并后约 10 秒，诊断集合与逐包分析逐条一致（674 条）。测试仍逐包执行；三包并行的实测为 199 秒，比串行的 175 秒还慢，因为单个 `flutter test` 已按核数并发，所以默认串行，`UBAA_FLUTTER_TEST_JOBS` 留给核数更多的机器。
- Rust：`cargo tree --locked -e normal,build,features` 显示 `cargo build --locked --workspace` 中的 Core 被 `ubaa_test_support` 统一打开了 `test-contract`，并不是此前记录的默认生产构建。改为分别执行 `cargo build --locked -p ubaa-cli` 与 `cargo build --locked -p ubaa_flutter_bridge`，两个宿主各按默认 feature 链接，Core 默认配置的编译单元与文档测试共用，facade 的 CLI、Bridge 各自 check 保持不变。其余组合各有独立合同，未合并：all-features clippy、默认配置 all-targets check、默认配置下的两条 `compile_fail` 文档测试、`test-contract` 测试。CI 的 `rust-platforms` 仍使用 `cargo build --locked --workspace --all-targets`，留待单独处理。
- 分级：近期 38 次 `Cargo.toml` 改动中 33 次同时改了 `Cargo.lock`，工作区依赖的版本也写在根清单，所以只放宽单个清单作用不大。现在按锁文件求 Bridge 的依赖闭包（含 dev 依赖，偏大即保守），三类改动只执行完整 Rust 严格检查，不运行原生、Flutter 与 FRB 生成：CLI 清单；锁文件改动未触及该闭包；根清单只改了闭包外的工作区依赖。读不到比较起点、解析失败或改动其他字段时，仍执行完整验收。Core、Bridge 与测试辅助 crate 的清单按原边界保持完整验收。
- `CARGO_INCREMENTAL=0` 保持不变。开启增量只对小改动的重复运行有利，却会让每种 feature 组合各自积累一份缓存，这正是上一条记录要解决的问题。FRB 生成检查的 `CARGO_BUILD_JOBS=1` 没有找到原因记录，本次未改动。

改动后的完整验收没有在相同条件下再完整计时一遍：用户要求停止测量，集成测试在本机还偶发上述焦点失败。按上面各阶段的实测估算，冷缓存约省 2.5 分钟（集成约 1.5 分钟、Flutter 约 1 分钟），日常 Core 改动后重跑约省 2.5 分钟。

## 2026-10-30：golden 允许渲染级像素差异，测试时钟固定为校园时区

远端 `ubaa2` 的 flutter-contracts 从 10-28 起持续失败，原因有两个：

- 时区：产品先把当前时刻转成校园时间（UTC+8）再比较，测试却用运行机器的本地时间构造“现在”和替身数据。CI 机器使用 UTC，相差 8 小时，`ubaa_ui` 有 5 个首页用例失败，`ubaa_flutter` 有 2 个首页导航用例失败；本机设 `TZ=UTC` 可以复现。现在固定时钟一律写成带 `+08:00` 的时刻，替身后端先转换为校园时间；在 UTC、Asia/Shanghai、America/Los_Angeles 下均通过。
- golden：6 张基准图在 CI 最近 4 次运行中全部失败，差异稳定在 0.00% 至 0.05%（11 至 178 像素），本机全部通过，属于字体抗锯齿差别。全部删除会失去颜色、间距、暗色模式等外观回归的唯一自动覆盖，所以保留基准。改为在 `ubaa_ui` 包级测试配置中使用带 0.2% 容差的比较器，约为实测最大差异的 4 倍；超出容差时照常写出差异图。自测用合成图片验证：默认比较器拒绝 0.1% 的差异，容差比较器放过 0.1%，仍拒绝 0.5%。


## 2026-10-31：macOS 最低版本统一为 12.0

用户更新至 Xcode 27.2 后，原生构建明确拒绝 Runner、FlutterMacOS 和插件 Pod 的 10.14/10.15 部署目标，当前 SDK 支持的最低构建版本为 12.0。用户明确要求直接修改项目声明，因此将 Runner 的 Debug/Profile/Release、Podfile 平台和自有 bindings Podspec 统一为 macOS 12.0。Podfile 的安装后处理将依赖的较低目标提升到 12.0，同时保留依赖已经声明的更高版本要求。

该决定使应用最低支持版本变为 macOS 12.0，不继续承诺在 10.15/11 安装。已有旧版系统的历史测试和来源记录保留历史含义，不改写第三方 Podspec 或 Flutter SDK。原生验收使用正式项目设置，不依赖本地部署目标覆盖文件。

## 2026-10-31：iOS 最低版本统一为 15.0

Xcode 27.2 的 iOS 模拟器构建拒绝 Runner、Flutter 与插件 Pod 的 12.0/13.0 部署目标，当前 SDK 支持范围从 15.0 开始。[平台说明](../architecture/flutter-platforms.md)已声明 iOS 15+，工程声明此前未同步。用户明确允许直接修改项目文件，因此按 macOS 12.0 的同一方式，将 Runner 全部构建配置、Podfile 平台和自有 bindings Podspec 统一为 iOS 15.0，Podfile 安装后处理把较低依赖目标提升到 15.0 并保留更高要求。不改写第三方 Podspec 或 Flutter SDK。

## 2026-10-31：阳光打卡 OAuth 补齐 SSO 中间跳转

Direct 实测统一认证成功后，阳光 OAuth 依次经过 app 的 `/uc/wap/login`、`/a_buaa/api/cas/index`、SSO 的 `/login`，再回到 app CAS、OAuth 和 ygdk 根路径回调。现有 app/ygdk 双主机检查在 SSO 跳转前返回 `upstream_changed`。冻结旧版 `LocalYgdkApi.fetchOauthCode` 逐跳处理 Location，没有该双主机限制，故支持这条链。依据当前实时证据，只补充 HTTPS 默认端口 `sso.buaa.edu.cn/login`，不开放 SSO 其他路径，不改变授权码提取主机、十跳上限、Cookie 作用域或路线。WebVPN 同样校验解包后的主机和路径。双路线真实读取结果在迁移状态维护。

## 2026-10-31：“我的”页快照保存身份、学院与逐项指标

用户要求“我的”页无感刷新，需要持久快照。资料缓存此前只保存遮罩后的姓名和学号，因为它们能直接辨认账号。门户身份与学院不是账号标识，金额、计数、容量和流量与成绩一样属于账号内业务数据，因此按原值写入账号密文库，不另做遮罩；不保存内部 ID、原始响应或认证材料。

单项指标失败很常见，如果整组只按完整度发布，一项失败就会让其余新值无法保存。因此快照逐项保存最近成功值和各自时间，失败项沿用旧值，从未成功的项保持缺失，绝不以零补齐。页面显示最早一项的时间，不把沿用的旧值说成刚更新。新增载荷沿命名标签追加，不升级 schema v7，避免已有用户缓存失效。

## 2026-10-31：课表节次轴固定采用校历作息

用户提供并确认了学校 2026—2027 学年官方校历作息，要求第 1–14 节的时间标签在切周时保持一致。因此 Dart 展示投影固定使用校历时间，避免课程边界覆盖节次时间，以及多个时间方案冲突后标签消失。课程详情仍显示课程自己的开始、结束时间。校历之外的节次继续使用接口作息，缺项才用课程边界，冲突或未知值保持为空。

`345d1236` 引入的 GSMIS 完整时间轴继续保留。冻结旧版 `1f4b8f84` 的 `GraduateSchedule.kt` 从适用方案的 `skjcList` 提取 `DM/KSSJ/JSSJ` 并去重，周课表保留 `SectionTime`；冻结 buaa-api `a63712fa` 的 `src/api/aas/data.rs` 只有本科课程的开始、结束时间，没有 GSMIS 协议。来源详情见[GSMIS 对照](source-parity-gsmis-2026-10-02.md)。本决定调整第 1–14 节的展示优先级，Core、Bridge DTO、缓存原值和请求协议不变，Android 课表组件导出也使用同一展示规则。

这项选择采用用户确认的当前校历作为统一展示基准。历史学期或具有特殊作息方案的研究生课程可能与节次轴不同，应以课程详情中的原始课程时间判断。以后若支持按学年切换作息，应使用相应官方校历，不能重新从某周课程反推整张节次表。

## 2026-10-31：模拟器构建按 lipo 能力选择架构

Xcode 27.2 的 `lipo /usr/bin/true -verify_arch x86_64 arm64e` 返回参数解析错误，锁定 Flutter 3.41.9 的 `thinFramework` 同样一次传入两个架构，因此把参数错误报告为缺少架构。构建入口只对这个明确诊断设置本机架构，保留显式环境覆盖，不修改 SDK 或跳过真实架构校验。正常工具链和无关错误保持原行为。代价是触发回退时的产物只适用于所选架构，跨架构模拟器仍需分别构建。

## 2026-10-31：启动主题与 Android 应用外观同步

共享 bootstrap 在启动 Flutter 页面前最多等待主题偏好 300ms，读取失败或超时回落系统主题。启动页、初始化失败页和宿主使用同一初值，宿主后续恢复仍用代次检查保护用户的新选择。OHOS 使用现有偏好插件分支，Android 外观通道仅在 Android 启用。

Android 12+ 使用 `setApplicationNightMode` 保存应用外观，使下次系统启动画面采用相同主题。该调用也改变当前 Activity 的 `uiMode`，Flutter 会把配置变化传入 `platformBrightness`；显式深浅主题由 `ThemeMode` 决定，不根据亮度回写偏好。切回系统主题时传入 `MODE_NIGHT_AUTO`，AOSP 在这个应用级 API 中把它映射为 `UI_MODE_NIGHT_UNDEFINED`，清除应用覆盖。该行为与全局 `setNightMode` 的自动昼夜计算不同，依据见 [AOSP 实现](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android15-release/services/core/java/com/android/server/UiModeManagerService.java)。Manifest 已声明处理 `uiMode`，由 Flutter 接收配置变化。

macOS 在首帧前从标准 UserDefaults 读取 `flutter.ubaa.preferences.theme` 并设置窗口和 FlutterViewController 底色。键由 ThemePreferenceStore 完整提供，SharedPreferencesAsync 不追加前缀。iOS 原生启动图仍跟随系统，Flutter 首帧使用应用偏好；Android 12 以下原生背景同样跟随系统资源，应用偏好在 Flutter 页面生效。

## 2026-10-31：日程使用独立账号密文库与标准重复规则

状态：存储方案已被[逐记录明文 SQLite 决定](#2026-10-31日程改为逐记录明文-sqlite)取代。下文保留 1a 的历史依据，重复规则与账号隔离语义继续有效。

[日程设计](../design/agenda.md)的子任务 1a 只实现 Rust Core 本机自建事项与学校事项覆盖层。学校投影和同步均未接入，冻结来源协议对照不适用于这些纯本地操作，本轮不读取冻结来源内容，不执行学校请求。

日程不能随只读缓存淘汰、退出或重建而丢失。现有 `CacheScope` 必须带 Direct/WebVPN 路线，`CachePayload` 是只读投影白名单，缓存重建还会替换账号库。因此选择独立的 `agenda/<随机账号别名>.sqlite`，复用现有私有路径检查、SQLite、`CacheKey` 和 AES-256-GCM 实现，使用独立 `ubaa.agenda.v1` AAD 绑定账号和格式。日程 schema v1 与缓存 v7 独立。将日程加入原缓存表会扩大清理与恢复的影响范围，本期不采用。

一期将账号的事项和覆盖层组成一个加密状态行，内容、UUID、学校来源键、时间、完成记录和未同步标记全部位于密文内。SQLite 的 IMMEDIATE 事务包住读取、修改、加密和写回，跨连接修改不会相互覆盖，错误时整体回滚。优点是没有明文业务索引，系列拆分和覆盖修改天然原子。代价是每次修改需要重封整个账号状态，单行损坏会阻断整个账号的日程读取并保留原文件。暂定密文 16 MiB 上限，达到上限明确报错且保留原数据，绝不淘汰日程。后续规模需要逐条存储时应升级独立 schema，并保持账号和 AAD 隔离。

宿主按已核实的账号索引交付随机别名和安全存储中的密钥，日程密钥随日程数据保留，不受只读缓存密钥轮换影响。退出时调用 `deactivate`，同账号重新登录后调用 `activate`。退出状态持久保存并作用于其他连接，普通打开不会重新激活。显式 `clear_local_data` 清除事项和覆盖层，返回清除前未同步条目数，另提供 `unsynced_count` 供宿主确认前查询。每条本地写入维护 `updated_at` 和 `locally_modified`，删除使用 `deleted_at`。删除标记清理规则于同日子任务 1b 前修正：未同步删除标记一律保留，只有已同步且严格超过 180 天的记录才可显式清理。这样长期离线后的首次同步仍能传递删除意图。同步确认和跨设备合并留给后续任务，本期没有将记录标记为已同步的公开入口。

重复规则采用 [rrule 0.14.0](https://docs.rs/crate/rrule/0.14.0)，2026-10-31 核对 crates.io API 的最新稳定版为 0.14.0，发布于 2025-04-20，未撤回，许可证 MIT OR Apache-2.0。[上游仓库](https://github.com/fmeringdal/rust-rrule)仍开放维护，但发版间隔较长，不能据此假定所有 RFC 边界都已修复。精确锁定版本，禁用可选 CLI/serde_with 功能。该依赖使用 chrono 0.4 与 chrono-tz 0.10，与工作区现有版本统一，没有新增时区实现。标准库无法替代 RFC 5545 的规则解析和展开，不自行实现第二套重复语法。UUID 使用精确锁定的 [uuid 1.29.0](https://docs.rs/crate/uuid/1.29.0)，crates.io 最新稳定版发布于 2026-10-23，许可证 Apache-2.0 OR MIT，仅启用标准 UUID v4 和 serde。随机源复用已有 getrandom 0.4，新增两个包，未升级既有依赖；chrono/chrono-tz 为时间值启用 serde。两者均为 Rust 库，未新增平台原生库；本轮只在本机完整入口验证，OHOS 交叉编译留给宿主接入。`icalendar` 留给导出任务。

时间值保留 RFC 3339 偏移量和 `Asia/Shanghai` 标识，精确到秒。RECURRENCE-ID 使用规范化的原始发生时间字符串，移动单次事项后原键保持不变，无日期待办使用 `undated`。日期查询使用左闭右开区间，时段按相交关系返回，全天结束为不包含的次日零点，无日期待办每次查询均返回。展开达到库内迭代限制或 65,535 次发生时返回 Capacity，不返回部分成功。为避免无界查询，单次日期跨度最多 3,660 天。

仅此次修改保留原 RECURRENCE-ID，单次删除写 EXDATE。「此次及以后」在同一事务中截断旧规则并新建 UUID，原系列首项拆分时旧系列写删除标记。相同规则的 COUNT 按未排除前的发生次数扣减，平移时同步平移 UNTIL、EXDATE、覆盖键和完成键，完成操作的实际时间保持原值。整体替换规则后，已不属于新规则的例外移除。覆盖层采用来源和上游稳定标识的结构化键，避免拼接分隔符碰撞；设计稿只有 `completed_at`，无法区分只加备注和明确取消完成，因此保守补充 `completion_override` 布尔字段。仅在完成覆盖启用且记录未删除时，`completed_at = null` 才表示本地重新挂起；只加备注、隐藏或清除覆盖继续沿用上游完成状态。

公开入口经 facade 显式导出，沿用本地仓库的 `CacheResult/CacheError` 稳定错误类别。此次只增加 Core API，未改变 CLI JSON schema v12、Bridge v43 或其 DTO，也不改 FRB 生成输入。日程本地清除与学校写入无关。公共使用规则见[日程 Core 合同](../contracts/agenda.md)。

## 2026-10-31：学校日程投影沿首页规则并保留完整日程状态

子任务 1b 只迁移已有 Core 公开读结果的本地投影，没有新增上游字段、请求或学校账号操作。行为依据为 Dart `home.dart`、`home_todo_test.dart`、`home_calendar_test.dart`，课程日期依据为 `CachedSemesterSchedule.today` 与 Dart `schedule/home.dart`，节次轴等价移植提交 `690a6800` 的 `scheduleSectionTimes`。前十四节使用官方校历，原课程时间保留在详情状态；第十五节后的接口优先、唯一课程边界后备和冲突未知均保留。源码与公开缓存已提供所需字段，本轮无需冻结来源内容或新的协议对照。

现有首页会过滤已提交和过期事项，如果直接把过滤后列表作为日程，就无法查看历史或对上游已提交作业设置本地重新挂起。因此学校投影保留可定位日期的公开记录，同时用 `home_todo` 保存既有首页过滤结果。合并查询应用完成覆盖后仍保留上游原始状态。首页调用和 Dart 实现本轮保持原样，切换属于 1c。签到按现有首页起止字段表示时段，保留开始时间排序与紧迫判断。签到状态一律按持久读显示“状态待更新”，新类型不包含学校写资格。

课程按已知起止节次逐节展开，键包含学期、课程代码、序号、教学周、星期和该节节次，避免跨学期或连堂不同节次共用覆盖。考试沿首页 task_id/course_no/标题、日期与开始时间组成发生键。脱敏反例证明仅使用学期与 task_id 会丢失同任务的第二场考试，所以不将任务标识当成独立考试标识。时间变化可能断开旧覆盖。阳光提醒没有独立上游记录，使用学期与教学周组成合成键。缺必需业务标识、课程代码或起始节时跳过并返回数量，不以列表位置或猜测字段生成键。完全相同的重复项去重，内容或状态冲突时跳过该键的全部记录并报告数量，防止本地覆盖误套。博雅完成只采用现有 UI 明确的考勤通过值 1，其他考勤值保留原始状态；研讨室缺少可依据的完成枚举，保守不从时间推断完成。

阳光提醒开关、周达标记忆和学期达标记忆属于 Dart 本地状态，Core 显式接收三项参数。当前教学周由同路线的公开周元数据按日期重新匹配，不能沿用失效的 cur_week。完整导入缺失时允许投影已缓存周，同时返回缺导入、缺范围和原取得时间。SPOC、阳光与希冀沿现有首页缓存范围，研讨室读取每页 20 条的已知缓存页，缺页不联网补齐。逐来源读取不保证跨来源原子快照，返回每个范围的观察时间供宿主提示。完整合同及稳定键映射见[日程 Core 合同](../contracts/agenda.md#学校投影与合并查询)。

Dart 考试分支使用 `sortTime: start ?? day`。结束已知、开始未知的考试仍按当天零点排序，不能套用其他时段的结束时间后备。已用等价失败反例确认该差异，因此新增独立 `sort_time`，学校时间端点继续保留未知值。合并查询也使用同一排序字段。

用户已决定下一阶段将日程独立改为明文 SQLite，事项和覆盖各一行，去除日程密钥依赖与整账号 16 MiB 密文上限，保留账号隔离、私有路径保护、事务和退出栅栏。当前没有用户日程数据，不迁移旧格式，但必须拒绝破坏性覆盖未知或旧文件。该决定尚未实施，1b 不改存储架构；只读业务缓存加密保持原合同。

## 2026-10-31：日程改为逐记录明文 SQLite

用户明确决定本机日程改用明文，并再次确认只读缓存加密不修改。日程不再依赖密钥或钥匙串，事项和学校覆盖各一行，便于后续按记录同步。这一决定替代 1a 的整账号密文行方案，保留独立账号库、随机别名、Direct/WebVPN 共用日程、私有路径和权限检查、事务及退出访问栅栏。明文不提供加密存储的保密和完整性保证，拥有私有文件访问权限的本机进程能够读取或修改日程。

schema 升为 2，元数据保存账号别名、版本和 active，事项与覆盖按稳定键保存明文 JSON。复用原内存领域操作，IMMEDIATE 事务读取最新状态，操作后只按差异写入变化行。这样可以保留系列拆分、例外、完成与覆盖的现有规则和原子性。代价是每次操作仍加载账号全部记录，后续若需要缩小读取范围，应逐操作改造，不在本轮重写领域层。

删除整账号 16 MiB 密文上限，改为每条 JSON 16 MiB 的资源界限，已有字段、例外数量和展开限制保留。账号总量超过原界限的多记录回归保持可读，单条超限则整体回滚。未同步删除标记仍一律保留，只清理已同步且严格超过 180 天的记录。

当前没有生产宿主日程数据，旧密文不迁移。只有通过排他创建确认的新文件才初始化；已有文件用只读连接先核对版本、元数据、记录及 SQLite 完整性。版本 0、v1、未知版本和损坏库均拒绝且保留，不能把空文件推断为可重建新库，也不在打开时改变旧库 journal/schema。新建过程失败留下的文件同样不会在后续普通打开时自动覆盖。缓存的密码学、安全存储、schema v7 和维护行为保持原合同。

测试覆盖调整：删除密文专属的 `wrong_key_unknown_version_and_ciphertext_tampering_preserve_database`。无需密钥打开与明文行读取由新存储测试覆盖；未知版本及原文件保留由新旧/WAL/损坏文件矩阵及原活动句柄版本测试保留；密文篡改场景改为损坏 JSON 和账号元数据错配拒绝。原有重复规则、多连接、退出恢复、账号隔离、缓存清理不影响日程、未同步删除标记和 1b 查询回归继续运行。完整行为见[日程合同](../contracts/agenda.md#持久化与修改)。


## 2026-10-31：日程 1c-a 的独立通道与账号保留

Bridge v44 用独立 `BridgeAgendaStore` 直接包装 facade，不持有网络客户端，也不把自建事项纳入业务缓存。Dart 服务将打开、退出、切换和销毁绑定到账号代次，操作前后检查同一代次，迟到的成功与错误均被拒绝。学校来源始终按固定实际路线查询公开缓存。缓存不可读时返回本机日程及独立缓存故障，日程损坏则只返回日程错误，不提供自动缓存重建建议。本阶段保留现有首页构造器，1c-b 再切换界面。

已有安全索引的 `retain` 曾先读取缓存密钥，因此丢失缓存密钥会同时阻断独立明文日程。现在账号身份保存与缓存密钥分开，索引正文 version 2 只为明确登记的新别名延后建立缓存密钥。旧版索引及已建立密钥的别名仍在密钥缺失时拒绝替换。异常索引不被重建，不扫描或认领日程文件，不用账号哈希或新别名绕过旧身份。

清理边界反例表明，缓存密钥缺失时句柄可能从未打开，原 `clearOfflineAccount` 会空操作。继续调用 `removeAccount` 则删除原密钥与别名，使日程失去身份关联，也可能使后续新密钥覆盖旧业务缓存。用户明确选择保留安全存储中的原缓存密钥和账号别名，只清凭据与可确认清除的缓存内容。生产清理不再调用 `removeAccount`，缓存清理要求匹配的已打开句柄，否则返回不可用，同时完成独立日程关闭及其他清理。缺少旧密钥的缓存仍不能自动重建。

测试覆盖调整：宿主“退出并清除后账号为空”断言改为保留同一随机别名且禁止自动恢复；“密钥删除失败导致退出清理失败”场景改为删除接口不可用时仍保留原密钥和别名。缓存、索引、会话、凭据和偏好清理失败的传播覆盖保留。新增已知账号缺密钥、旧版索引缺密钥、异常索引保留、迟到打开/查询、原始与有效状态分列及真实 FFI 日程探测。


收尾回归补充：只在安全索引写入或后端工厂返回后关闭日程，会让已有服务引用在等待期间交付旧结果。四个失败反例分别覆盖退出、已核实账号切换、重建工厂成功和失败。现在退出在首次等待前推进日程代次，换号同步入队旧账号关闭，重建先关闭旧日程再等待工厂。工厂失败时，仅在原账号和原后端仍有效且没有退出/销毁时重新打开同一别名的日程。这样网络客户端重建失败仍保留本地日程能力，旧操作结果保持失效。


2026-11-01 补充退出顺序：日程停用与安全索引禁止恢复独立启动，先同步撤销服务代次，并立即入队索引关闭。日程停用等待不能延后持久禁止自动恢复，两个关闭动作均在退出返回前收尾。新增停用挂起时索引仍先禁止恢复的失败反例，避免用修复迟到结果的等待顺序引入恢复窗口。

## 2026-11-01：日程关闭先收束已交付写入

独立审查发现，1c-a 只将打开和关闭放入串行尾链。业务写入进入 Bridge 的后台队列后，关闭可以先完成，同账号重新激活又把持久 `active` 设为 true。此时旧写入恢复执行仍能提交，Dart 在返回时报告 `superseded` 无法撤销副作用。创建、删除、完成和显式日程清除都受此顺序影响。

修复选择在 Dart 服务收束写操作，不增加磁盘代次或 Bridge 接口。创建、编辑、删除、完成、覆盖设置/清除和显式日程清除与打开、关闭共用尾链。关闭请求同步推进代次并清除当前账号。尚在服务尾链等待的旧写入在调用后端前拒绝；已经调用后端的写入允许在关闭等待期间完成或失败，包括仍在 Bridge 预处理、尚未进入 SQLite 事务的操作。关闭等待该写入返回后才停用持久库，后续打开不得越过关闭。因此关闭完成后没有该服务尚未收尾的旧写入。已经进入 SQLite 事务的写入继续按原事务提交或回滚。失败不会中断尾链。读取不加入尾链，仍在结果返回时检查代次，挂起读取不阻塞关闭。服务记录每次调用时的打开 Future，避免后续打开替换依赖后形成尾链自等待。

退出仍先同步撤销日程访问，并独立启动安全索引禁止自动恢复。等待写入不能延后索引关闭。后端重建先等待旧日程关闭，才创建和打开继任服务。保留原账号别名、缓存密钥、独立日程错误及旧库保护。

本次逐操作来源复核使用 `examples/ubaa_old@1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 与 `examples/buaa-api@a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。旧版最近的实现为 `composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/menu/HomeTodo.kt` 的首页构造、`shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalScheduleApi.kt` 的课表读取与 `api/storage/CredentialStore.kt` 的凭据清理。buaa-api 最近的模块为 `src/api/cloud/{mod,core,opt,data}.rs`，请求与 Cookie 行为在 `src/request.rs` 和 `src/store/cookies.rs`。两个冻结来源均无本机自建日程及其账号生命周期仓库。

| 本机操作 | CAS/service、重定向/最终 URL、Cookie/Session/Token、方法/参数、头/编码、加密/签名 | DTO/字段 | 缓存/并发/重试 | 错误/退出语义 |
|---|---|---|---|---|
| create、edit、delete、complete | 两个来源均不适用，无上游请求 | 沿现有 Agenda 类型，不新增字段 | 本机写入加入生命周期尾链，不重试 | 旧排队调用拒绝，已交付调用在关闭前收尾 |
| setOverlay、clearOverlay、clearLocalData | 两个来源均不适用，无上游请求 | 沿现有覆盖/清除类型 | 同上，清除仅作用于独立日程 | 同上，失败后仍尝试关闭 |
| open、close、dispose、后端重建 | 两个来源均不适用，无相同本机生命周期 | 继续使用已核实随机别名 | 打开不能越过旧写入收尾 | 查询迟到拒绝，安全索引独立关闭 |

来源索引引用本记录；没有借用学校接口或网盘协议实现日程生命周期。

## 2026-11-01：首页复用已取得结果进行 Core 投影

首页现有在线读取能够在缓存未打开、密钥不可用或保存失败时交付结果。`query_with_cache` 只读取持久缓存，因此首页改用 `HomeAgendaRead` 与纯本地 `project_home_agenda`，复制已解析兼容 DTO 的 typed 字段，不增加学校请求、不反解析展示字段，也不伪造缓存时间。在线和缓存快照共用入口，原来源状态与取得时间继续由现有读取链持有。实际考试请求学期在兼容 DTO 中保留，用于与完整日程相同的稳定键。

已打开的同账号日程句柄负责叠加覆盖。打开尚未完成时先显示学校投影，打开完成后重新查询本地覆盖。覆盖故障保留学校结果并单独提示。明确完成和隐藏移除条目，重新挂起已提交作业仍检查原时间条件并保留学校状态，不能简单过滤原 `home_todo = false` 的记录。

签到关联沿用当次在线读取中的唯一 allowed action，并核对课程、独立在线目标、日期、账号、路线和读取代次。缓存不保存目标，跨校园日期的无缓存读取拒绝交付动作。投影与覆盖均不能生成学校写资格。前四项、原位展开、原功能详情及单层返回继续使用既有交互，新日程页面、底栏调整和自建事项首页入口留给界面阶段。

双来源范围见[来源对照](source-parity.md#2026-11-01首页待办迁入-core)，测试迁移及保留覆盖见[测试策略](../development/testing.md#首页投影覆盖的归属)。

## 2026-11-01：日程 CLI 独立安全材料方案 A 已选定

后续决定：本节方案 A 已被[统一 App 命令模式](#2026-11-01统一-app-命令模式与无感恢复)替代。保留本节解释旧实现，不再按独立 CLI 索引和 worker 继续扩展。

本轮检查 `apps/ubaa_cli/src/main.rs`：默认目录由 `ProjectDirs::from("org", "BUAASubnet", "UBAA").config_dir()` 决定，`--config-dir` 可覆盖，所有现有执行路径先构造 `UbaaClient` 或隐藏诊断 `RouteClient`。`UbaaClient::open` 只加载路线配置与双槽会话；公开 `active_routes` 仅返回槽位路线。`facade/auth.rs::auth_status` 会调用各路线的用户中心验证。会话 schema v2 明确不持久化用户名，因此仅凭会话存在不能在离线 CLI 恢复账号身份。

`AgendaStore::open` 要求宿主提供已核实账号的随机别名。`OfflineCache::open` 额外要求已核实 identity 与 CacheKey。Flutter 的别名索引及密钥属于平台安全材料，由 Flutter 自身目录和生命周期管理。两个宿主的默认目录不同，不能称为自动共用。CLI 暂无对应索引、平台材料提供者或公开的离线已核实账号能力。此次只完成可独立的 Core 导出与[命令/模型设计](../contracts/agenda.md#app-日程命令)，保留 CLI 执行停止点，不解析 Core 私有 session，不读取 Flutter 钥匙串或扫描数据库。

主聊天已在用户授权的 CLI 日程开发范围内选定方案 A，实施安排是在本次 Core 导出提交复核后，由新会话为 CLI 增加独立的平台安全材料适配，采用独立命名空间与 `--config-dir` 作用域。在既有显式登录成功后，以 Core 已验证的 profile 身份建立稳定关联，复用同一随机别名，离线日程命令只读这份登记。Core 应提供不可由任意用户名兑换的已核实身份票据/登记入口，并把登录、退出、切号及会话冲突与账号激活代次关联起来。身份字段缺失或冲突时拒绝登记。退出撤销活动选择并保留账号映射及日程，重新登录同账号恢复原库；索引缺失或不可读失败关闭，不能另造别名绕过。缓存密钥单独管理，缺失仅影响学校缓存。此方案需要新增 CLI 安全材料适配及生命周期合同，属于后续实现单元，当前尚未实现。

备选方案 B 是把离线已核实账号登记正式下沉为 Core 的宿主共用能力，持久化版本、完整性、平台密钥所有权与会话 revision 原子关联都需独立设计。该方案能避免宿主重复身份生命周期，但会扩大本期存储与账号安全模型，当前未选用。不能以明文用户名配置、裸别名参数、临时全局库或任意 JSON 导入代替上述身份边界。

方案 A 的后续实现还须满足以下条件：

- 新索引只接受显式成功登录的已核实 profile 与不可由任意参数伪造的 Core 身份能力。账号、路线或会话冲突时拒绝登记，不能接受裸用户名或别名认领。旧 CLI 会话缺少登记时，本地命令明确要求先显式登录建立关联，不自动调用 auth_status。
- 同账号跨 Direct/WebVPN 复用同一别名。退出撤销活动选择并保留映射与明文日程。材料丢失、损坏或不可用时失败关闭且保留旧文件，不创建新别名绕过，也不读取 Flutter 钥匙串或扫描私有库。安全材料只管理核实身份及必要密钥，日程正文继续采用 schema v2 明文 SQLite。
- 本地日程操作、退出/切号及身份登记的关键段必须使用同一配置作用域的跨进程共享锁或等价原子关联。不能只依靠进程内 bool/队列，必须阻止旧 CLI 操作借后来的同账号激活重新生效。具体锁及身份能力由后续任务依据 Core 公开接口确定，不解析私有 session，也不扩大普通公开构造面。
- CLI 新增默认流程保持既有学校请求协议。测试使用合成身份和隔离的安全材料后端，各平台按实际提供者分别验收，不把某一平台通过写成全部平台通过。

## 2026-11-01：日程范围快照与 iCalendar 依赖

采用 [RFC 5545](https://www.rfc-editor.org/rfc/rfc5545) 的 VEVENT/VTODO、DATE 排他结束及 UTC DATE-TIME。只导出选定范围内的展开快照，不同时提供完整重复系列，避免把单次完成映射或仅有 DUE 的重复待办错误表示为带虚构 DTSTART 的系列。未知学校端点与日期占位跳过并计数。UID 保持原始发生身份，使用已有 SHA-256、hex 与 JSON 元组编码，不引入第二套重复展开器。

已在 2026-11-01 核实 [crates.io 的 icalendar 0.17.17](https://crates.io/crates/icalendar/0.17.17) 及该发布包 manifest：2026-10-26 发布，未撤回，最低 Rust 1.88，MIT/Apache-2.0，官方仓库为 [hoodie/icalendar](https://github.com/hoodie/icalendar)。现有 chrono/rrule 负责时刻与展开，尚无 RFC 5545 组件、TEXT 转义及 UTF-8 折行构造器，标准库也不提供这些能力，因此引入精确版本。生产关闭默认 parser/recurrence，测试启用 parser。新增运行时依赖为纯 Rust icalendar、iso8601、nom，测试另有 nom-language，复用已锁定 chrono/uuid。未引入新的原生库、动态加载或平台服务，现有 Rust 1.95 满足版本要求。OHOS 与其他实体平台的本次产物体积尚无实测，不能由 macOS 检查推导。

输出逐组件写入 32 MiB 缓冲预算，超限整体失败。Core 返回正文与计数，后续 CLI 才处理安全路径与文件原子交付。CLI/Bridge/磁盘版本均不变。源码审查、合成回归与完整门禁结果由状态页和提交说明记录。

独立复核后，非重复事项改用已有 UUID 派生导出 UID，重复发生继续使用原始发生键。增加或移除 RRULE 时切换两种身份空间，不补造持久历史。`icalendar 0.17.17` 的长 UTF-8 折行存在反复从头查找的二次增长，因此保留 typed 组件构造，范围快照自行按 RFC 5545 实现流式 TEXT 转义及内容行折行，并在写入过程中检查原 32 MiB 预算。本地内容行写入器属于项目实现，没有修改、复制或维护第三方发布包补丁，也没有改变依赖或许可证清单。序列化继续在原 mutex 和读取事务内执行，避免引入锁外迟到结果及重开代次问题。

## 2026-11-01：日程 CLI 独立账号登记与只读命令

CLI 的认证输出继续表达学校双路线结果，新增 `agendaRegistration` 单独表达本机登记。学校认证成功而身份不足、冲突或安全材料写入失败时，本机登记失败且退出非零。Core 能力只从显式聚合登录的逐路线内部结果产生，要求成功路线 schoolid 一致、与显式输入相符，并且失败路线没有未核实的残留会话槽位。能力绑定客户端、会话所有权、随机 nonce 与五分钟期限，登记后消费。诊断路线登录不登记，状态查询不能兑换能力。

CLI 选择按规范化配置目录建立独立 Keychain 命名空间和排他文件锁。锁覆盖打开会话、登录、登记、撤销、日程读操作及输出，避免旧操作跨退出和重新激活交付。初始化标记与索引相互核对，目录节点身份也必须匹配。登记和撤销先持久化 pending 标记，中断后保留现场并拒绝访问。本阶段没有自动恢复或替代别名路径。生产只有 macOS provider，缺少平台能力时明确不可用。

初始 macOS provider 调用固定的 `/usr/bin/security` 操作 Keychain，所有记录由同一系统工具创建和读取，使 CLI 不同进程可重开。材料正文只经 stdin 交付，完全不通过 shell 或 argv，不输出子进程 stdout/stderr。每次调用有五秒期限，stdout 限 1 MiB、stderr 限 16 KiB，工具缺失、权限拒绝、超时或读回不一致均返回不可用。索引保留 Keychain 的用户访问边界；本机日程正文仍为私有明文文件。没有引入新的第三方包或升级锁定版本，CLI 只增加现有 fs2、sha2、uuid、chrono 和 libc 的直接引用。依赖审计结果写本阶段提交说明。

CLI local envelope 增加新的错误命名空间和本机元数据，因此提升 CLI schema 为 v13。Bridge v45、日程 v2、业务缓存 v7、会话 v2 保持。只读命令不创建网络客户端，显式学校缓存合并只读取同账号既有库。CLI 尚无业务缓存预取流水线，CacheKey 缺失只影响显式学校缓存合并。下一阶段继续全部本机修改、完成、覆盖、原子 compare-and-clear 和 .ics 文件安全交付。


## 2026-11-01：CLI-a 身份代次与原生 Keychain 材料接口

CLI-a 独立审查发现交互式换号和所需路线明确失效后仍可使用旧身份票据，以及非 macOS 原认证被可选日程 provider 阻断的问题。票据现在绑定双路线运行时的认证代次，清会话时更换代次，正常活动刷新不更换。新交互准备独立撤销旧票据，保留当前交互句柄。不支持日程 provider 时，仅无登记痕迹的作用域继续原认证，登记独立报告不可用；已管理或异常作用域继续失败关闭。

材料写入停止使用 `security -i`，因为其交互分词规则会破坏 JSON 引号与反斜杠，4096 字节行缓冲还会将正常多账号索引拆成额外命令。复用锁文件已有的 [security-framework 3.7.0](https://docs.rs/security-framework/3.7.0/security_framework/) 安全 Rust 接口，macOS 条件依赖关闭默认 features，保留 MIT OR Apache-2.0 许可。来源为 [rust-security-framework 上游](https://github.com/kornelski/rust-security-framework)，本地核对发布包 manifest、许可证与源码，Cargo.lock 只增加 CLI 到现有包的依赖边，不新增版本或 registry 节点，不引入自有 unsafe 或修改 registry。

索引通过 SecItemAdd/SecItemUpdate 的 CFData 字节参数和 SecItemCopyMatching 完整往返，避免命令字符串解析。[Apple 的更新接口](https://developer.apple.com/documentation/security/secitemupdate(_:_:))定义查询匹配的条目更新。原生调用放在同一真实 CLI 的短命子进程中，正文仅经管道传递，父进程限时五秒。[禁用 Keychain 交互](https://developer.apple.com/documentation/security/seckeychainsetuserinteractionallowed(_:))只作用于工作进程，拒绝访问返回固定 unavailable。创建沿系统默认 ACL，更新保留已有权限，不给所有应用授权，也不自动修改旧条目权限。旧 security 工具创建的条目若拒绝当前 CLI，保留原材料并报告 unavailable，本轮不自动迁移权限。

既有 1 MiB 读取容量边界现在也在索引过渡前检查，超限不写 pending、不更新材料、不删账号，不改变原 service、scope、alias、CacheKey 或 schema。已进入持久过渡后结果不明仍保留 pending。合成原生测试由同一 CLI 创建、更新、跨进程读取，采用默认 ACL，清理只按本次私有目录派生的专用 scope 删除，本轮未读取或修改真实用户材料。其他平台使用不支持 provider 的确定性模拟，尚无 native 验收。

## 2026-11-01：统一 App 命令模式与无感恢复

用户明确确认同机 CLI 与 App 共享凭据、会话、缓存和日程，进一步选择把命令行并入 App，最终取消独立 Rust CLI 宿主。macOS、Windows 按桌面环境设计，Linux 同时考虑 SSH 服务器；命令登录过期后应与 App 一样无感恢复。执行模型改为 `gpt-6.1-sol / ultra`，主聊天规划审查，每个独立单元使用新上下文。用户允许根据证据自主选择技术接线，包括用 Docker 验证 Linux。

选择提取现有界面之外的应用服务，GUI 和命令入口共用恢复、账号和数据生命周期，通过 facade/Bridge 复用 Rust Core。命令定义、JSON、退出码及测试保留一份；Rust 命令库可以迁移复用，不以删除 Rust 语言代码为目标。`core-live` 先迁出为开发工具，再退役独立 `ubaa` 宿主和专属材料体系。Linux 服务器运行也不得重新建立另一套账号逻辑。

优先复用 App 现有安全材料、原随机别名和缓存密钥。用户反馈 App 钥匙串问题已解决，停止旧 worker 专项，不将其作为共享工作的前置。正常会话过期按保存的自动登录选择恢复，主动退出或关闭自动登录仍有效；可能已到达上游的学校写入不因重新认证自动重放。业务缓存加密、日程明文及网盘同步既定规则保留。

Mac App Store 并非已确认的强制分发渠道，当前沙箱配置不作为跨平台架构前提。是否调整由运行样机与旧数据连续性证据决定，不能隐含签名、发布或真实材料迁移。Linux 需验证无图形会话、进程重开和非交互恢复，可使用私有合成容器。当前仅有架构选择与阶段安排，尚未完成平台接入或退役。

具体阶段、失败用例和接续顺序见[实施计划](../design/desktop-shared-state.md)。旧工作区改动和审查证据私有保留，逐项取舍，不重置未知来源改动，不将旧候选通过结果继承为新架构验收。


## 2026-11-05：北航云盘的认证与分享关联

冻结来源及提交见[北航云盘来源对照](source-parity-bhpan.md)。旧版 `UploadLatestReleaseToBhpanTask.kt:295–327` 使用百分号编码的固定 service、精确 query challenge 和已有 SSO GET 会话，并由同源测试覆盖相对 Location 与 303。buaa-api `cloud/core.rs:50–63` 使用不同的 service 拼接与 query 提取，且包含独立 SSO 表单认证。按协议证据优先级，当前实现采用适用的冻结旧版本地实现和测试，复用现有学校会话。遇到 SSO 登录表单时交回已有认证流程，不在云盘内部增加凭据入口。手动跳转仅接受来源中的云盘认证路径、固定 SSO service、HTTPS 443 和有限跳数，未知分支停止。未执行真实账号观察，Direct 分支与 WebVPN 均保留各自的真实验收条件。

分享更新需要完整目标关联。buaa-api `cloud/data.rs:347–359` 的单项 record 模型跳过 `item.id/type`，不能直接把该模型用于更新。创建结果沿用已发送的完整 item，history 的 `cloud/data.rs:294–343` 显式读取 `doc.id/type` 与权限，两种输入可以形成来源支持的更新正文。当前解析器保留这些显式字段，并分别覆盖创建结果、history 和缺关联 record 的 Mock 请求。缺关联 record 继续支持查看、链接交付与取消，更新入口要求从完整分享历史选择。

对象存储目标与重定向、普通/分片上传、内容下载、WebVPN 和同名条件覆盖继续使用来源对照中的停止条件。上述取舍没有新增服务器字段，也没有将上传 `rev` 解释为 CAS。

## 2026-11-02：共享身份撤销与本进程句柄关闭

Core 不读取宿主安全索引或凭据，只接收平台在材料事务内捕获的固定目录和版本。平台在原索引保存后、材料事务完成标记发布前写入 account-generation.v1。Core 在同一材料锁的共享侧核对完成标记和固定版本，缺失、损坏或中断均拒绝操作。版本记录只撤销已有能力，不单独授予学校身份或自动恢复许可。索引缺少版本记录时，只有持材料独占锁并验证权威索引的调用方可以初始化记录。保留账号索引 v3、随机 alias 和 CacheKey，不迁移业务缓存或日程格式。

锁顺序为 recovery → materials → Core 仓库 → SQLite。实际本地写事务持有材料共享锁，身份变更使用独占锁，因此身份发布与真实提交有明确先后。网络 Future 等待期间释放材料锁，已交付请求后发生撤销仍按原结果未知合同收尾。外层结果交付再次校验原身份，拒绝迟到结果不能用来推断已经提交的事务未发生。

普通服务关闭撤销本进程操作并释放本进程句柄，保留其他消费者及共享持久材料。显式全局退出按原快照取得专用清理票据，票据不能绑定为普通活动权限。受限注销 RPC 在客户端锁内临时使用票据，RAII 保证正常、错误、panic 和 Future 取消均恢复原归属，旧客户端保持已撤销状态。缓存清理直接使用固定清理票据，不将票据装入可继续读取的普通缓存对象。清除凭据后的宿主回调仅处理本机偏好，材料事务内不调用 Core 或网络。

无界面消费者关闭立即停止接受操作，有界等待已经接受的操作、恢复任务和资源释放。超时保留实际收尾 Future，不能因为 dispose 已返回就提前报告全部完成。业务错误沿原 Future 交付，资源错误由 settlement 保留。该接口供后续 H2 消费，本单元不迁入命令运行时。

## 2026-11-01：H2 命令骨架、平台分发与停止规则

用户本日决定及监督裁定已纳入[App 命令模式设计](../design/app-command-mode.md)。H2-common-a 先抽取 Rust 唯一命令实现，H2-common-b 补独立恢复目标及共享运行时，正式共享验收以 H1-b3 放行为前提，完整业务及旧宿主退役分别留给 H3、H4。

- macOS 使用 Developer ID 分发并关闭沙箱。旧容器、旧签名与钥匙串先只读盘点，再选择迁移方式，不预认定 ACL 连续。首期 PATH 使用 `~/.local/bin/ubaa` 符号链接，同时支持 `--command`。
- Linux 强制 Secret Service，提供用户总线、PAM 与 SSH 部署指南。首批 Debian 12 amd64/arm64、Ubuntu 24.04 LTS amd64，最低 glibc 以 Debian 12 为准。公钥 SSH 每次开机后依赖已解锁用户会话或受保护交互解锁一次；未解锁明确失败，不把口令放入 unit、环境、argv 或日志。
- Windows 使用控制台子系统 `ubaa.exe` 加 WIN32 GUI，两者共享安装资源和资料规则。Windows 原生阶段使用已登录桌面的 `ssh windows` 验证。
- 只读命令首次明确认证过期且路线、身份、scope 和许可有效时，释放尝试资源，调用 H1 恢复服务，再从命令起点重跑一次。第二次过期停止。第一轮数据和错误均不提前输出，外部会话更新也共用一次重跑额度。学校写入准备/提交后不自动重新准备或提交，可能发送后只读核对。
- 默认命令总预算 120 秒，起点为原生单调时间，所有阶段共享，停止后最多两秒收尾。保留 schema v13：在线取消 `internal_error/7`、在线期限 `timeout/5`、本机取消或期限 `storage/7`，原因写 stderr 和 JSON message；暂不引入 130。
- macOS Release 目标为本机命令热启动 P95≤0.5 秒、冷启动 P95≤1.5 秒、峰值 RSS≤150 MiB。超出先定位并报告 AOT 评估，超出两倍以上阻塞平台放行。

本单元只迁移命令实现与本地输入/输出边界，不修改学校 URL、参数、重定向、Cookie/Session/Token、请求编码、签名常量、DTO 或 Core 重试。旧材料 worker 和独立索引原样保留为兼容适配，H4 再退役。任意同步输入/存储的强制中断由后续宿主的可取消适配和进程收尾负责，不能把 Rust Mock 结果当作平台证据。

## 2026-11-05：统一 App 命令入口与材料共享

公共 Rust 命令库拥有唯一 parser、输入快照、schema v13 和输出，Dart 调度共享账号、恢复与句柄。学校写入复用 GUI 的一次性 prepare/commit、发送观察、缓存失效和核对提示。恢复发生在写资格准备前，准备、提交和回读期间保持固定归属。

macOS 命令使用无窗口 Engine，GUI 单实例锁只适用于 GUI。为支持终端指定的正常文件路径，桌面 App 关闭 Sandbox；目录解析优先沿用已有容器或非容器资料，两份同时存在时停止，不复制数据库、WAL 或材料。旧签名包与真实材料的访问连续性另行验证。

Linux GUI 与 AOT 使用同一 Secret Service 适配，保留锁定插件的 account、schema、JSON item 和材料键。命令运行包与 GUI 同版本交付，无服务、锁定或需要 Prompt 时明确失败。旧 Rust CLI 宿主与材料 worker 删除，开发工具迁入 `tools/core_live`，保留覆盖登记在测试策略中；Windows 原生运行仍须补验。

## 2026-11-05：北航云盘的动态传输授权

Direct 对象请求以本次、同操作的云盘 API 授权响应为目标与对象请求头的来源。冻结 buaa-api `cloud/opt.rs:508–547、570–661` 和旧版 `UploadLatestReleaseToBhpanTask.kt:397–419、455–549、818–828` 均从响应的动态授权数组取得地址和头，再上传内容、合并分片并完成文件登记。两源没有固定对象主机表。已有认证主机策略限定认证跳转，其适用范围不扩大到对象传输。冻结提交及完整协议列见[来源对照](source-parity-bhpan.md)。

Core 将授权绑定当前账号、Direct 路线、客户端、目标和传输阶段，校验预期方法、结构、合法 HTTPS 地址与头，并通过独立 Cookie 边界发送。请求不附加个人或分享 Bearer，不接受宿主提供的对象 URL 或旧授权。当前拒绝对象端重定向、额外认证和不支持的授权形状；取得对应协议证据后再扩展这些分支。严格 TLS、一次发送、取消与关闭检查、结果未知和日志脱敏继续适用。

buaa-api `cloud/opt.rs:374–387` 从 osdownload 的 QUERY_STRING 授权提取下载地址，`406–423` 从 batchdownload 提取打包地址。旧版无同源正文下载实现，buaa-api 也只交付地址。Core 以标准 GET、成功状态检查和流式落盘消费地址，明确作为客户端实现，用 Mock 验证请求与文件结果，不添加未证明的 Cookie、URL 改写、Range 或续传协议。上传采用旧版的状态码、ETag 和最终登记 error 检查，不继承自动写重试或仅凭同名文件认定成功。

动态目标不阻塞已有 Direct 传输路径的实现。真实读写仍需当前会话的具体授权与对应路线验收。`ondup=1` 和上传 `rev` 尚无条件覆盖含义，日程固定文件并发更新继续等待比较字段与冲突语义；WebVPN 的云盘认证、分享与对象路由同样保留独立证据要求。

## 2026-11-05：日程同步的版本比较与本机快照

[官方接口文档](https://developers.aishutech.com/napi/documents/307)的检索正文补充了 `metadata/osdownload.rev` 和上传开始、初始化、最终登记的 `editedrev`。直接页面读取超时，北航部署尚未验证。两份冻结实现没有完整版本条件，逐操作差异见[来源对照](source-parity-bhpan.md#日程固定文件的版本条件)。同步读取基版 R 的内容，开始与最终登记均以 R 为条件，新上传版本 U 只用于最终登记的 rev 和读回。路径定位区分存在、明确缺失和范围未知，未知列表不证明缺失。首次启用已明确确认创建时，可用 `ondup=1` 尝试创建，冲突后只读重定位，无须为此新增分页；部署能力仍保持未验证。unknown 先只读核对，不删旧文件或自动重发。现有能力状态继续表达“未验证”，文档依据不开放真实自动同步。

Core 持有明文同步文档、按记录合并和 SQLite 事务。记录按修改时间和设备标识排序，同设备同秒的连续修改使用持久递增序号区分。完整版本键相同但内容不同则报告冲突并保留本机记录，不按输入顺序取胜。回执逐记录比较原快照，网络等待期间的新编辑保持待同步，确认不使用内容哈希。设备标识与记录序号保存在同一个账号库，GUI 和命令共用。为现有已知 schema 2 增加同步元数据时采用一次性原子升级，旧版本及损坏库的拒绝规则继续保留，不引入通用迁移框架。

目录与文件步骤在各自第一次可能发送前写入日程 SQLite；文件尝试保存完整快照和已知对象定位。保存失败不发送，确定拒绝结束尝试，unknown 或停止保留记录。目录步骤只核对目录；文件步骤核对当前 metadata 和固定版本正文，只有 U 正文可读不足以证明最终登记。新消费者不重发已登记的尝试。确认时完整比较记录内容和版本，并在同一事务清理匹配的尝试。

## 2026-11-05：OHOS 下载文件交付

OHOS 保存使用 `DocumentSaveOptions.autoCreateEmptyFile=false`，由应用在用户确认位置后创建文件。官方[保存用户文件](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/file-management/save-user-file.md)说明该 URI 同时具备临时读写、创建和删除权限。[FileUri 实现](https://github.com/openharmony/filemanagement_app_file_service/blob/master/interfaces/innerkits/native/file_uri/src/file_uri.cpp)中，本机 `docs` URI 的实际路径与 `FileUri.path` 一致，远端 URI 使用另一份映射路径。

[OpenHarmony 文件打开实现](https://github.com/openharmony/filemanagement_file_api/blob/master/interfaces/kits/js/src/mod_fs/properties/open.cpp)对尚不存在的 `docs` URI 使用 DataShare，创建标志不会传给 DataShare。[ArkTS 标志转换](https://github.com/openharmony/filemanagement_file_api/blob/master/interfaces/kits/js/src/mod_fs/common_func.cpp)也没有独占创建模式。ArkTS 消费一次性选择并返回本机 `docs` 的解码路径。Dart 对该路径调用 `File.create(exclusive: true)`；[Dart 文件实现](https://github.com/dart-lang/sdk/blob/3.11.5/runtime/bin/file_linux.cc)使用 `O_CREAT | O_EXCL`。已有同名文件时保留原文件。成功创建后用文件句柄逐块读写。交付层在关闭句柄后统一清理失败目标，避免系统复制和应用分别按同一个路径删除。清理失败明确提示残留。

ArkTS 源码回归覆盖路径解码、一次性选择和远端 URI 拒绝。平台测试覆盖多块文件交付、同名目标保留、部分复制失败清理、后继同名文件保留和选择过期。设备文件面板与外部文件提供方按平台单独验收。

## 2026-11-05：日程采用设备独立的不可变快照

独立复核的 Direct 证据确认：同一 docid、同一 R 的两次并发最终登记使用不同 U，均返回 HTTP 200 与相同的成功元数据形状，Core 均交付各自 Committed。当前接口不能向调用方提供同 R 至多一方明确成功的保证，因此停止把它作为共同 agenda.json 的条件覆盖前提。该判断不推断服务端内部写入顺序，也不以旧 U 可下载补成发布证明。

同步改为设备 UUID 与持久发布序号命名的新文件，复用普通创建上传、当前版本读取、原记录排序和本机发送事务。官方分页结束与路径编码、新文件在最终登记前后的可见性仍须独立验证；验证前生产能力保持未验证，不复用 conditional_replace 的状态开放新方案。正常路径以明确成功的最终登记回执加当前文件和完整正文核对确认。暂存阶段若已满足全部读取条件，只限制丢失最终回执后的自动确认；unknown 保留 dirty、原发布身份与正文，不自动重传。已收到成功回执但读回中断时是否保存最小回执状态，等待首次可见性事实再确定。旧单文件协议从未启用，无云端迁移或清理任务。

本机库采用一次 schema 4 升级，新增发布序号、自动同步许可与无正文的删除摘要。180 天继续控制已同步的本机完整删除记录，摘要保留以拒绝旧版本。云端不可变快照暂不自动删除，允许历史内容与存储增长；后续若增加清理，另以明确的记录覆盖证明设计，不先增加远端垃圾回收框架。本机清除不改变云端，不把本机缺失发布成删除。

本机清除擦除事项、覆盖、删除摘要和待发送正文，但保留可能已发送发布的无正文身份，继续占用原唯一在途位置，未决前不分配更高发布序号。本机编辑与其他设备只读合并继续，旧作业不能确认清除后的状态。这个限制防止 p7 的删除摘要在最终登记挂起时，被清除后仅从 p6 重建的更高 p8 永久遮蔽，不增加新的代次框架。

CLI 本机命令仍不访问学校。原服务仅由未验证能力提前返回阻止自动网络，未保存 GUI 启用许可；新方案在账号库内保存默认关闭的明确许可，只在原首次确认之后允许 GUI 自动拉取或上传。详细规则、可证伪反例和必要验收见[日程设计](../design/agenda.md#bhpan-同步)与[合同](../contracts/agenda.md#跨设备同步)。

## 2026-11-07：首页主会话与单项目标恢复

首页区分账号主会话恢复与单个功能的目标会话恢复。支持按目标恢复的后端在主会话 ready 后，只更新相应功能的恢复状态，其他首页读取继续调度。每个功能的读取仍先等待自身目标会话，分批读取在下一批前再次检查目标状态。单项网络故障保留在功能状态中，全局恢复为 ready；需要登录、共享身份撤销和恢复中断保留原状态，不能归一成 ready。

纯本地待办投影从过渡计数中只扣除正在执行的会话恢复所占的一次。原地登录、清缓存、写入和路线切换继续阻塞投影。投影交付核对账号、生命周期、读取代次和路线策略；共享后端还在读取前后验证持久身份。账号不符会关闭旧账号并失效读取，已核验的路线登录替换会取消受影响的分批计划并重新准备，旧批次不进入展示。

后端离线读取代次变化产生的 operationConflict 映射为日程 superseded，首页保留当前展示并稍后重新投影。账号或路线过渡清空旧范围待办并显示占位，旧路线签到入口及时撤销。

App 的 HomeCoordinator 统一管理补充来源、展示日期课表、待办投影和刷新完成信号。缓存首屏在原有 800 毫秒预算内等待本地周次和待办投影，先读取已保存的路线策略。待办由来源快照和本地完成标记计算，不再新增派生列表存储。连续输入只保留一个在途投影和一份最新输入，相同结果复用原列表。

主会话已就绪时，单项目标校验不发布新的共享账号代次，也不重绑同一共享后端。主会话恢复、真正重新登录和外部身份变化仍发布或采纳对应代次。共享后端确需重绑时，先通知 Controller 撤销旧读取计划。Core 在显式首页读取批次内复用同实际路线、同认证代次和同路线配置的成功身份校验，每次操作仍检查持久身份。批次结束、认证失败、重新登录及路线改变使复用失效，登录保持串行。

## 2026-11-08：HTML 正文纯文本保留分段并完整解码实体

Core 的 `to_plain_text` 同时服务 SPOC 作业详情 `zynr`，以及 iHome 的公告、诉求正文、回复、评价和处理记录。旧实现只解码 7 个固定实体，并把全部空白压成一行，所以公告会显示 `&ldquo;` 原文，分段也会丢失。现改用已有依赖 `scraper`（html5ever）解析片段，解码全部 HTML5 命名实体和数字实体。块级元素、`<br>`/`<hr>` 和原文换行都转为换行；每行折叠空白、去掉首尾空白并丢弃空行；行内标签不插入空格；`script`、`style` 等内容不输出。

来源对照（纯解析，不改请求协议、字段或 DTO 形状）：冻结旧版 `1f4b8f84` 的 `LocalSpocSupport.toPlainText` 只解码同样 7 个实体，并把空白压成单行；旧版主仓库的 iHome `IhomeProtocol.plain` 直接复用这个函数，因此两处缺陷相同，不作为需要保持的行为。固定 buaa-api `a63712fa` 的 SPOC `HomeworkDetail` 只删除 `<p>`/`</p>`，注明正文含 `\n`，并保留原有换行，这支持保留分段；它没有 iHome，iHome 一列不适用。行为变化仅限展示文本：SPOC 正文由单行改为多行，旧实体残留改为解码后的字符。
