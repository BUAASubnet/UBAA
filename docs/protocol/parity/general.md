# 来源对照总则与跨领域基线

本文件收录来源对照的总规则、冻结版本声明、逐操作历史矩阵的取证说明，以及 Flutter bridge 等跨领域投影的来源边界。

## 当前规则

### 当前规则与冻结版本

适用范围为所有认证、读取或写入功能变更；双来源读取范围、逐操作列、冲突停止、禁止类比与 TDD 要求只由 [AGENTS 来源对照门禁](../../../AGENTS.md#来源对照门禁)定义。真实只读验证不能证明真实写入成功，历史记录也不能提供当前授权。

2026-10-30 Rust Core 精简的本轮方案、凭据与日志比较见[总记录](core-engineering.md#rust-core-精简与缺陷修复)，操作明细分别见[缓存](core-engineering.md#rust-core-缓存刷新精简)、[协议解析](core-engineering.md#core-读取实现精简的来源对照)和[路线/会话边界](core-engineering.md#rust-core-路线边界精简)。本轮按当前冻结引用重新核对，不把旧矩阵作为当前来源读取的替代。

当前物理路径与固定提交以 [references.md](../references.md)为准，2026-10-29 `just refs` 已确认：

| 来源 | 固定提交 |
|---|---|
| `examples/ubaa_old/` | `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` |
| `examples/buaa-api/` | `a63712fa2ae0a6c8066197063ddee98e3a6b5b81` |

2026-10-30 认证安全修改及复核见[逐操作来源比较、失败反例和验证边界](auth-session.md#认证安全修复复核)。该记录明确网关原生路径、Direct 解包路线、BYKC 精确回调、Ygdk 已证主机与编码，以及写入结果分类的更正。

这两个来源已在 2026-09-17 的 `f63e6d060059beaa68a4b9372c393ea56e3a4c61` 换钉；经过见[决策记录](../../archive/history/2026-10-30-decisions-through-quality-phase3.md#2026-10-29阶段-2-统一权威来源与规范)。本轮仅校正声明，未修改冻结目录或脚本固定值。下方与专项中的旧 SHA、旧候选、当时不适用项及来源例外均保留历史含义，不自动成为当前实现依据；引用前必须按当前来源重新核对所改操作。

路径前缀统一写为 `examples/ubaa_old/` 与 `examples/buaa-api/`。旧来源内部的相对文件名仍相对该来源根目录，行号对应原记录版本。补充旧源例外仍须有明确决策，不能扩展为任意本机来源。

## 逐操作基线矩阵

### 逐操作历史矩阵

更新日期：2026-09-04

以下 2026-09-04 及更早的矩阵原始取证版本为旧版
`6e75e120a26b0eefb3ab4a6f8251d1230db4a62e` 和示例
`efb7976bf513f38364b88aeb83d704586cff9b2a`。这些 SHA 保留历史取证含义，不是当前冻结声明。
后续专项按各自日期和提交记录；本轮未重新逐列验证历史矩阵，不将历史结果改称当前冻结版本已通过。

2026-09-03 的复杂业务模块目录化另见
[`source-parity-code-organization.md`](core-engineering.md#复杂业务模块目录化来源对照)。该记录只授权在现有逐操作
九列矩阵内移动 Cgyy、Judge、SPOC、Bykc、LibBook 与 Ygdk 符号；任一协议列变化仍须回到本文件
重新取证和执行 TDD，不得以结构整理为由推断行为。

历史记录（2026-08-29）：当时的 `verify-live` 曾按独立 CLI 子操作执行，并有一笔单独授权的
Cgyy Direct 写探针。本记录仅保留来源证据，不属于当前执行合同；现行脚本化只读验证由 `core-live` 执行，真实 App 验收单独记录。当前授权规则见 [AGENTS](../../../AGENTS.md#真实账号与验收范围)，此历史探针不授权任何新的真实操作。

生产代码变更前，所有认证、读取或写入功能都遵守 [AGENTS 来源对照门禁](../../../AGENTS.md#来源对照门禁)，不能用历史矩阵代替本次逐操作核对。

### Flutter bridge 产品投影

P1 的 `docs/contracts/flutter-bridge.md` 只把本文件已审计的 facade 方法映射为 typed FRB
DTO，不修改任何 URL、service、跳转、Cookie/Session、HTTP 参数、Header、正文、加密、
缓存、并发、重试或 Core 错误语义。逐操作仍使用下列已有九列证据：

| bridge 领域 | 本文件权威段落 | Flutter 仅新增的产品语义 |
|---|---|---|
| 认证、用户、路线 | 网关探测；双路线加载/保存/退出；准备/登录；用户资料；CLI 与配置 | opaque client、资料白名单、typed error、策略切换后重开 |
| 课表、考试、成绩、空教室 | 未改变的课表/考试证据；未改变的成绩证据；空教室会话同步/查询 | typed DTO 与 `RouteDecision`；考试“已安排/未安排”仅投影同一 `examArrangement(term)` 信封的冻结两列表；成绩“已出/待出”仅按冻结 `score` 字段非空性本地投影；空教室楼层按 `floorid`/分组名、节次按冻结逗号分隔 `kxsds` 令牌本地精确过滤，均不新增请求 |
| SPOC、Judge | SPOC 认证/列表/详情；Judge 列表/详情/批量与缓存 | 不生成诊断入口，只生成列表/详情 DTO；Judge 列表的“包含已过期”仅传递冻结 `includeExpired` 本地截止时间筛选参数；批量键仅为公开课程/作业编号，按冻结 Core 语义保持去重后的输入顺序 |
| Signin、Ygdk、LibBook | 课堂签到今日查询；阳光打卡只读查询；图书馆座位只读查询；直接写操作表 | Signin 的“未签到/已签到”只按 Core 输出的 typed `signinEligibility` 派生；LibBook 座位只消费可空整数 `status`、typed `reserveEligibility/reserveTarget` 和完整查询上下文组成预约 action；UI 仅在稳定 target 存在且资格为 `allowed` 时开放操作，不读取展示字段反推协议状态；其余 typed prepare、一次性 intent、commit 后读取核对 |
| Bykc、Cgyy、Evaluation | 博雅课程只读查询；场馆预约只读查询；直接写操作表 | Cgyy 用途来源明示；待评由 `is_evaluated=false` 派生；原始评教 payload 不暴露 |

`set_default_route_policy` 是本地配置/facade 能力，不是上游协议：它只能原子保存已存在的
`RoutePolicy`，清空 App 不开放的 feature override，使 bridge intent 失效并从同一应用私有
目录重开 `UbaaClient`；不得触发登录、业务请求、Cookie 复制或透明路线回退。每个 opaque intent ID
只在当前 client 内绑定已审计的 typed facade 请求、过期时间、prepare 路线和冲突键；commit 只接收该 ID，
不接收任意 JSON。`requestDigest` 只是返回给宿主的非秘密请求指纹，不是 commit 入参或写入授权依据，bridge
不保存 Session 修订，也不承诺摘要回传比对。外部 Session 修订冲突由 Core 在最终发送前拒绝；login 成功、
logout、`authStatus`、策略保存后重开 client 和 dispose 都会使旧 intent 失效。若实现需要改变上述任一协议列，
必须先停止并回到对应操作的来源对照与失败测试，不得以 bridge 需要为由推断字段。

冻结 WebVPN 编解码使用网关 `d.buaa.edu.cn`、密钥/初始向量文本
`wrdvpnisthebest!`、无填充 AES-128-CFB，以及 `scheme[-port]/encrypted-host/path` 布局，UBAA 2
与这些线路值一致。为保持边界行为，空查询和片段分隔符按冻结 Kotlin 实现省略；Rust URL/运行时
路径表示保留显式根斜杠，因此路线请求和最终 URL 语义不变。Cookie 匹配仍针对网关 URL。两项
选择均有脱敏连接测试覆盖，本对照不会新增重定向主机，当前白名单仍以实时观察为依据。

### Flutter bridge 实现对照记录（2026-09-01）

本轮生产代码只调用已在本文件逐操作固定的 `ubaa-core` facade 方法；`2faa753` 的
`crates/ubaa_flutter_bridge/src/api/client.rs`、`read.rs`、`write.rs` 仅做 typed 字段白名单、
路线结果投影和一次性意图保存，不复制 URL、Cookie、Header、加密、重试或解析逻辑。认证、读取
和写入的 URL、参数、常量、DTO 缺失值、缓存/并发及错误语义分别沿用本文件对应表格，并由
`docs/contracts/flutter-bridge.md` 的方法/字段表约束；`examples/buaa-api` 无等价协议的行继续
标记为“不适用”，没有类比借用字段。

桥接新增的失败测试先验证相对配置目录、销毁后调用、重复意图和随机摘要在网络前拒绝，再实现
最小投影。真实账号、Cookie、挑战材料和上游响应没有进入 bridge、fixture 或生成绑定。

2026-09-01 评教批量确认补充：本轮只在共享 Flutter UI 增加待评课程的显式勾选、顺序保持和批量
`prepareEvaluationSubmitCourses` 调用，仍复用上表已固定的单一冻结评教提交协议、答案构造和一次性
`WriteIntent`；没有新增 URL、参数、Header、DTO、答案策略或重试语义，因此不引入新的上游协议假设。

2026-09-01 阳光打卡表单补充：本轮只在共享 Flutter UI 增加公开项目编号的表单、内存照片 picker 边界
和一次性 `prepareYgdkSubmit` 调用，仍复用冻结 Ygdk 表中已固定的上传/提交 URL、字段、照片校验和错误
语义；没有新增上游 URL、参数、Header、DTO、权限协议或自动重试行为。原生 picker 尚未接入，未执行
真实照片上传或账号写入。

2026-09-01 bridge 输入前置补充：`prepareYgdkSubmit` 现于路线解析前复用冻结的照片非空、开始/结束时间
成对校验；失败返回 `InvalidInput` 且不保存 intent。该边界不改变 Ygdk 上传/提交协议或错误映射，
并以禁止网络的 bridge 回归证明无效请求不会进入认证或路线请求。

2026-09-01 Cgyy bridge DTO 敏感字段补充：冻结 `ubaa_old` 的 `Cgyy.kt` 订单对象同时包含交易号、
手机号、参与人、活动正文及审核内部字段，`examples/buaa-api` 没有等价 Cgyy 协议；这些字段只
属于 Core 解析/写入所需的内部来源，不是 Flutter 产品合同。此前生成的 `BridgeCgyyOrder` 将
上述字段逐一暴露到 Dart，虽然后续 mapping 未展示，仍违反 bridge 最小白名单边界。先以失败的
生成 schema 测试固定禁曝字段，再将 Rust `BridgeCgyyOrder` 和 `map_cgyy_order` 收窄为订单编号、
站点/日期/空间/校区、时间、状态、主题、用途名称和参与人数等页面白名单，并重新生成 FRB；该
调整不改变冻结 URL、参数、Cookie、签名、缓存、并发或错误语义，写入结果仍只从白名单投影非敏感
收据。`just flutter-codegen-check` 与 bridge/Dart 回归负责防止后续生成漂移或敏感字段回流。

2026-09-02 bridge 只读内部字段补充：冻结 `ubaa_old` 的 `BykcChosenCourse` 原始 DTO 还包含作业正文、附件名称/路径和签到附注，`CgyySlotStatus` 还包含交易号、订单号、占用数量/标记及内部说明；`examples/buaa-api` 均无等价协议。这些字段未被 Flutter 页面消费，且附件路径、交易号和占用审核信息不属于稳定产品合同。先在生成 Dart schema 快照中加入两类 DTO 的失败禁曝断言，再将 Rust bridge 结构及映射收窄为课程/签到公开字段和时段可预约状态字段，并重新生成 FRB。该收窄只影响 FFI 投影，不改变 Core 解析、上游 URL/参数、Cookie、签名、缓存、并发或错误语义；冻结 Core DTO 仍保留其内部字段供协议和业务逻辑使用，不能据此把它们暴露给宿主。

2026-09-02 Ygdk bridge 图片字段补充：冻结 `ubaa_old` 的打卡记录解析会保留 `images_fmt` 中的图片地址，`examples/buaa-api` 没有等价 Ygdk 协议；图片地址可能携带业务令牌，且 Flutter 页面只展示图片数量，不需要原始地址。先在生成 Dart schema 快照中加入 `BridgeYgdkRecord` 禁曝 `images` 的失败断言，再将 Rust bridge 结构和映射改为只投影 `imageCount`（对 Core 内部地址列表做有界计数），重新生成 FRB。Core 解析仍保留冻结图片字段供上传/读取逻辑使用；该收窄不改变 Ygdk 上游 URL、参数、令牌生命周期、缓存、并发或错误语义，也不影响真实写入协议。

## 历史专项

### UBAA 旧版完整功能迁移矩阵

本文记录冻结 `ubaa_old` 的公开业务能力与 UBAA 2 当前 Core/CLI/Flutter 交付边界。所有协议字段、请求地址、
加密常量和错误语义必须来自安全实时证据或固定冻结来源，不能凭经验补全。

当前“无签名执行目标已完成”表示生产 Core/bridge/app/UI、确定性测试、无签名构建和发布准备已闭合；它不表示
真实写入、签名、实体设备、原生安全存储或正式发布完成。实时验收默认只运行 Core-live Direct/WebVPN 只读
矩阵；任何真实写入仍需逐操作、逐目标、逐路线、逐时间单独授权。

#### 读取与用户功能

| 功能 | Core/CLI | Flutter/FRB | 当前证据边界 |
|---|---|---|---|
| 认证、用户与路线设置 | `auth`、`user show`、双路线 Session、Auto/Direct/WebVPN | Splash、登录、会话恢复、我的、设置、路线切换与注销 | Core Direct/WebVPN 实时只读已验证；真实 App 账号链路/设备未验证 |
| 课表与考试 | `schedule`、`exam` | 学期/周次 typed 查询与详情页面 | 两路线 Core-live 与确定性 UI/宿主测试 |
| 成绩 | `grades` | 学期与已出成绩 typed 查询 | 两路线 Core-live 与确定性 UI 测试 |
| 空闲教室 | `classroom search` | 日期、校区、楼层、节次 typed 查询 | 两路线 Core-live 与确定性 UI 测试 |
| SPOC 作业 | `spoc` 列表、详情与安全诊断 | 列表/详情 typed 页面 | 两路线 Core-live；详情仅在父列表有 ID 时必需 |
| 希冀作业 | `judge` 列表、详情、批量与安全诊断 | 当前/过期/单项/批量 typed 查询 | 两路线 Core-live 与并发/缓存确定性测试 |
| 课堂签到查询 | `signin today` | 今日课程与签到状态 | 两路线 Core-live、业务会话 Mock 和 UI 状态测试 |
| 阳光打卡查询 | `ygdk overview`、`ygdk records` | 概览、记录分页、图片数量白名单 | 两路线 Core-live；图片 URL 不跨 FFI |
| 图书馆查询 | `libbook` 楼馆、分区、详情、座位、预约记录 | 分区/时段/座位/记录 typed 查询 | 两路线 Core-live；分区详情只在每日 08:30–23:00 营业窗口判定 |
| 博雅课程查询 | `bykc` 资料、课程、详情、已选、统计 | 课程/详情/已选/统计 typed 页面 | 两路线 Core-live；空父列表详情可带依据 N/A |
| 研讨室预约查询 | `cgyy` 站点、用途、日期、订单、详情、锁码 | 场地/时段/订单 typed 页面 | 两路线逐操作 Core-live；用途 `static_fallback` 不冒充上游成功 |
| 教学评教查询 | `evaluation all/pending` | 全部/待评本地派生视图 | 两路线 Core-live 与 schema/UI 测试 |

#### 写入能力

以下十项用户可见写入已经按 Phase 11A–J 落实来源对照、typed 资格、最终权威重读、未知结果保护和
确定性读取核对。共享应用层统一拥有 prepare→确认→单次 commit 流程，UI 只消费 typed action 与状态。
阶段提交和最终候选验证分别见[当前迁移状态](../../project/status.md)；本表不把阶段实现等同于当前真实写入成功。
CLI 默认拒绝并要求 `--confirm-write`；Flutter 必须由用户主动进入确认流程。

| 领域 | 用户操作 | 确定性实现 | 真实边界 |
|---|---|---|---|
| 博雅 | 选课、退选、签到/签退 | Core typed eligibility/action、fresh authority、冻结加密/请求向量、一次性确认与读取刷新；未知资格默认拒绝 | 当前周期未真实执行；中文展示字段不再决定写资格 |
| 研讨室 | 预约、取消 | typed 时段/取消目标、fresh authority、单次最终发送、安全收据及原路线取消证明；验证码重试只在最终写入前 | 2026-08-29 有一次独立授权的历史 Direct 预约/取消证据；不自动证明当前提交或后续授权 |
| 教学评教 | 提交待评课程 | typed targets、Core 内部 fresh 问卷链、批量四态结果、unknown 后停止与 caller-pinned 回读 | 当前周期仅 Fixture/Mock/宿主 fake |
| 图书馆 | 预约、取消 | typed 座位/时段/取消目标、fresh authority、单次发送、取消同页记录刷新 | 当前周期仅 Fixture/Mock/宿主 fake |
| 课堂签到 | 执行签到 | 可空状态、typed 安排目标、当天唯一 authority、冻结表单、严格结果与状态刷新 | 当前周期仅 Fixture/Mock/宿主 fake |
| 阳光打卡 | 上传照片并提交 | typed 分类/项目 authority、完整照片请求、expected-route 原子链、单次 upload/final 与原路线双回读 | 当前周期仅 Fixture/Mock/宿主 fake；无真实照片上传 |

任何写请求一旦可能到达上游都不得自动重试。`outcome_unknown`、transport 异常、收据缺失或读取刷新失败
必须提示先核对，不得把 UI 成功文案当作上游最终状态。

#### 能力变更闭环

后续新增或修改每个操作时独立完成：

1. 记录 `ubaa_old` 与 `examples/buaa-api` 的接口、DTO、实现、测试及“不适用”项；
2. 固定 URL/service、重定向、Cookie/Token、方法/参数/Header/Body、加密、DTO、缓存/重试和错误语义；
3. 添加脱敏 Fixture/Mock 的失败测试并确认失败原因；
4. 在 Core facade 提供稳定能力，CLI/FRB/Flutter 只消费 facade/bridge typed 合同；
5. 运行 focused、敏感扫描、Rust、Flutter/codegen 与适用平台门禁；
6. 认证或只读行为变化最终串行运行 Direct/WebVPN；真实写入另行申请具体授权。

只有 Fixture/Mock 的操作标记为“确定性验证”，不能标记“真实上游已验证”；只有无签名构建的宿主不能标记
“实体设备/正式发布”。

#### 课堂签到协议 parity

冻结 `SigninApi` 的查询不是普通教务接口复用：先访问 iClass 8346 的跳转入口，从最终 URL 或重定向取得
`loginName`；再调用 8347 的业务登录取得 `id` 与 `sessionId`；最后按 `yyyyMMdd` 日期读取课程。业务会话按
学生标识缓存，失效后最多重试一次。

UBAA 2 已完成基础响应 DTO/解析器、独立业务会话、路线转换、facade/CLI/FRB/Flutter 接入，并有脱敏 Fixture、
Mock 与 Direct/WebVPN 只读证据。固定 `examples/buaa-api/src/api/class` 提供部分等价 iClass 实现，但其查询方法、
会话头身份、端口和参数载体与冻结本地实现冲突，只能交叉证明一致字段，不能拼接协议。2026-09-03 审查发现的
今日状态字段、form 用户 ID 和嵌套提交结果缺口已由 Phase 11D 的 `b988ae1` 完成本地确定性修复：未知状态
显式可空、资格与目标由 Core 派生，prepare/commit 重读当天唯一安排，最终写入只发送一次并严格区分业务
拒绝与结果未知。该阶段证据没有执行真实签到，不替代当前候选或真实写后核对。
