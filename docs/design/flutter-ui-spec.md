# Flutter UI 规格（无签名执行目标已完成；正式发布后置）

更新：2026-09-05

本规格只描述共享 `ubaa_ui` 的用户可见状态。上游 URL、Cookie、令牌和原始响应不进入
页面模型；页面只消费 `ubaa_app` 映射后的 domain 模型。当前候选、确定性门禁与平台验证分别以
[迁移状态](../migration/status.md) 为准，本文末尾的历史验证记录不代表本轮最终候选已经通过。

## 导航与响应式布局

| 来源 | 目标 | 窄屏 | 宽屏 |
|---|---|---|---|
| Splash/会话恢复 | 登录或主页 | 全屏居中 | 全屏居中 |
| 登录页 | 主页 | 底部表单、顶部路线菜单 | 最大宽度 460 的居中表单 |
| 主页 | 普通功能卡片 | `NavigationBar` | `NavigationRail` |
| 普通功能 | 课表、考试、成绩、博雅、空教室、SPOC、希冀、图书馆 | 网格列表 | 最大宽度自适应网格 |
| 高级功能 | 课堂签到、场馆预约、阳光打卡、教学评教 | 网格列表 | 最大宽度自适应网格 |
| 功能卡片 | 详情列表 | 返回按钮 + 可滚动详情 | 同一布局，支持键盘焦点 |
| 我的 | 资料、默认路线、已认证路线、匿名统计、注销 | 列表 | 侧栏后的列表 |

## 功能状态

每张卡片和详情页均支持 `idle`、`loading`、`success`、`empty`、`stale`、`failure`；刷新时
保留上一次的详情模型，新的读取结果按 generation 丢弃过期响应。已有成功数据刷新失败时显示
`stale` 横幅、旧数据和重试按钮；首次失败只展示稳定中文错误，不渲染上游正文。详情列表提供
本地筛选和每页 20 项分页；Bykc 课程、图书馆预约、阳光打卡记录和场馆订单等 typed 查询同时
保留 Core 服务端分页元数据，使用 1-based 上下页控件和总数提示，不把服务端页误切成客户端缓存。
筛选只匹配 bridge 白名单字段并重置到第一页。读取成功或空结果
若包含 Core 的 `resolvedRoute`，卡片和详情页显示“实际路线”；该字段不由登录设置中的
`defaultPolicy` 推导，`stale` 状态沿用上次成功路线。若上次成功结果只有摘要而没有详情项，
详情页仍显示该摘要，同时保留失败横幅和重试按钮，不降级为首次失败错误页。
Core 明确返回空结果后不保留旧数据；此后刷新失败按首次失败显示稳定错误，不伪造成 stale。
课堂、图书馆座位和场馆日期查询的日期输入严格限定为真实日历日期的 `YYYY-MM-DD` 形状；带时间、时区或不存在日期的字符串在 UI 层拒绝，不进入 typed `FeatureQuery`。

写入口只消费 Core 派生、经 bridge/app 校验的 typed action。只有 `allowed`、完整且一致的稳定目标、
领域 prepare 能力和共享 prepare/cancel/confirm 三个命令全部具备时才开放入口；缺失、未知或冲突默认关闭。
中文标签、展示状态、合成 ID、默认值及 UI 时间计算都不能产生写资格。Core 在 prepare/commit 重新读取
authority，仍是最终业务权威。

| 领域 | 页面输入与资格边界 | 提交后的只读核对 |
|---|---|---|
| 博雅选课/退选 | 消费对应 typed action；退选目标使用课程 ID，不能使用外层选择记录 ID | 成功或 `outcome_unknown` 时刷新关联课程/已选视图 |
| 博雅签到/签退 | 消费 typed 签到 action；位置由平台能力提供，时间窗和签到点由 Core 重读校验，展示层不恢复 `canSign/canSignOut` | 成功或 `outcome_unknown` 时刷新关联考勤信息 |
| 课堂签到 | 消费 `SigninPerformAction`；公开编号本身不能放行 | 成功或 `outcome_unknown` 时刷新今日课程 |
| 图书馆预约/取消 | 预约消费完整座位/日期/时段 action；取消 action 固定 `id/page/limit`，状态文本只展示 | 刷新对应预约页；取消 prepare、commit 和回读保持同页 |
| 场馆预约/取消 | 预约只选择一至两个同站点、日期、空间和空间组的 allowed action，时段 ID/原始序号唯一且序号相邻；取消消费 typed target | 预约成功收据与订单列表核对；取消成功或 unknown 固定原路线读取首页列表与同 ID 详情，仅消费本次严格取消证明 |
| 阳光打卡 | typed 提交、照片选择与回读能力齐备才开放入口；表单消费 Core 签发的分类/项目 target、完整本地时间和内存照片，权限失败或缺照片不进入 prepare | 成功或 unknown 按 intent 原路线各尝试一次概览与记录首页读取，结果不确定仍保持 unknown |
| 教学评教 | 单门或批量选择非空、有序、无重复的 typed targets；完整问卷、题目和答案只留在 Core | 确定结果、部分失败、unknown 或 commit 异常都至多按原路线回读一次，保留逐课程四态结果 |

确认页显示 `WriteIntent` 的摘要、实际路线、警告与过期时间。应用层唯一 `WriteCoordinator` 拥有
prepare、待确认、取消、提交、回读与失效状态；共享 Host 将 domain `WriteState` 和三个命令注入 UI，
UI 只负责表单、确认展示和安全提示，不保存另一份待确认意图。提交或取消期间禁止重复操作；取消失败保留
原意图供再次取消，过期意图不得提交。注销、重登录、路线切换或 backend 重建使旧操作失效，晚到结果不能
恢复旧确认页或触发新会话回读。

`WriteReceiptVerifier` 统一编排既有领域读取与提示。读取失败不重发写请求，不把 unknown 升级为成功；
普通 commit 错误不自动推断请求已发送，只有明确的 `outcome_unknown` 或 Evaluation 既定规则进入相应回读。
任何确定性确认或读取核对都不能替代真实账号写入证据。

取消入口状态门禁：图书馆和场馆详情都只在 Core 返回 typed `allowed` 资格与完整且一致的
`cancelTarget` 时显示取消准备按钮。状态码、状态说明与场馆开始/结束时间只供展示，共享 UI 不解析
中文文案、状态值或四小时截止点；缺失、未知或目标不一致默认关闭。Core prepare/commit 才是状态、时区和
截止时间的最终权威；入口只展示公开 ID，不显示上游令牌或内部字段。

## 无障碍与交互约束

- 所有图标按钮提供中文 `tooltip`，路线菜单和返回按钮可用键盘聚焦。
- 状态同时使用文字、图标和颜色表达；错误不只依赖颜色。
- 卡片详情使用语义化标题和标签/值两列，支持动态字体和窄屏滚动。
- 登录页密码输入不进入日志；记住密码选项仅在 `CredentialVault.isAvailable` 时可用。
- “退出登录”只清理 Core Session；“退出并清除本机账号”必须先经二次确认，再同时清理
  Core Session 与用户主动保存的凭据，明确说明不会删除学校服务器数据。
- “我的”页分别展示 Core 持久化的默认路线策略和不含 Session 内容的已认证路线槽位；两者
  不替代各项读取结果中的实际路线。

## 实现定位与验证边界

公共导出继续经 `packages/ubaa_ui/lib/ubaa_ui.dart`；`lib/src/widgets.dart` 只组装同一 library 的 imports 与
parts。维护实现时按下表定位，调用方不直接导入 part 文件。

| 修改内容 | 实际实现 |
|---|---|
| 启动、登录、主页和个人页 | [app/splash.dart](../../packages/ubaa_ui/lib/src/app/splash.dart)、[login.dart](../../packages/ubaa_ui/lib/src/app/login.dart)、[home.dart](../../packages/ubaa_ui/lib/src/app/home.dart)、[profile.dart](../../packages/ubaa_ui/lib/src/app/profile.dart) |
| 页签/详情导航、外部写状态与命令接线 | [app/shell.dart](../../packages/ubaa_ui/lib/src/app/shell.dart) |
| 查询控制器创建/释放、输入校验、FeatureQuery 组装与提交 | [common/query_controls.dart](../../packages/ubaa_ui/lib/src/common/query_controls.dart) |
| loading/empty/failure/stale 和查询/详情组合 | [common/feature_detail.dart](../../packages/ubaa_ui/lib/src/common/feature_detail.dart) |
| 本地筛选、详情行组合与选择集合生命周期 | [common/detail_list.dart](../../packages/ubaa_ui/lib/src/common/detail_list.dart)；字段展示在 [detail_fields.dart](../../packages/ubaa_ui/lib/src/common/detail_fields.dart) |
| 服务端/本地翻页控件与错误卡 | [common/pagination.dart](../../packages/ubaa_ui/lib/src/common/pagination.dart)、[error_card.dart](../../packages/ubaa_ui/lib/src/common/error_card.dart) |
| 课表、考试、成绩、空教室查询控件 | [features/academic.dart](../../packages/ubaa_ui/lib/src/features/academic.dart) |
| SPOC/Judge 作业与 Signin 课堂签到查询、签到按钮 | [features/assignments.dart](../../packages/ubaa_ui/lib/src/features/assignments.dart) |
| 博雅、图书馆的领域查询与 typed 写按钮 | [features/bykc.dart](../../packages/ubaa_ui/lib/src/features/bykc.dart)、[libbook.dart](../../packages/ubaa_ui/lib/src/features/libbook.dart) |
| 场馆、阳光打卡、评教的领域查询、typed action 与选择控件 | [features/cgyy.dart](../../packages/ubaa_ui/lib/src/features/cgyy.dart)、[ygdk.dart](../../packages/ubaa_ui/lib/src/features/ygdk.dart)、[evaluation.dart](../../packages/ubaa_ui/lib/src/features/evaluation.dart) |
| 场馆预约与阳光打卡输入表单 | [write/cgyy_form.dart](../../packages/ubaa_ui/lib/src/write/cgyy_form.dart)、[ygdk_form.dart](../../packages/ubaa_ui/lib/src/write/ygdk_form.dart) |
| 意图摘要、错误、取消与提交按钮 | [write/confirmation.dart](../../packages/ubaa_ui/lib/src/write/confirmation.dart)；回调类型在 [write_callbacks.dart](../../packages/ubaa_ui/lib/src/write_callbacks.dart) |

页面测试按领域位于 `packages/ubaa_ui/test/widgets/`，写命令接线测试位于
`packages/ubaa_ui/test/write_coordination_test.dart`。应用层 `packages/ubaa_app/test/` 中的
`write_coordinator_test.dart`、`app_write_lifecycle_test.dart` 与 `write_readback_reentry_test.dart`
分别保护单次消费、会话失效和回读重入。宿主 integration 位于
`apps/ubaa_flutter/integration_test/app_flow_test.dart`，只使用脱敏 backend。
生产唯一状态机的实现与接口见[协调器实施记录](../superpowers/plans/2026-09-05-write-coordinator.md)。

## 历史与阶段 UI 验证记录

以下保留当时的实现和验证事实，旧提交中的资格推断、刷新行为与测试数量不再定义现行规则；现行规则以
上文 typed action/协调器边界及稳定合同为准，当前门禁结果以迁移状态页为准。

- `packages/ubaa_ui/test/widgets_test.dart` 已覆盖登录安全提示、详情字段渲染、本地/服务端分页与筛选、
  日期格式/日历校验、摘要-only stale 保留、实际路线展示、手机/平板/桌面明暗主题响应式 golden、
  动态字体、键盘焦点、十二项卡片语义和 1000 条长列表分页；`packages/ubaa_app/test/app_controller_test.dart` 覆盖不可用生产 backend 不
  伪造 Demo 登录、刷新失败后的 `stale` 数据保留、实际路线投影以及未认证固定路线的安全
  回登录。
- `apps/ubaa_flutter/integration_test/app_flow_test.dart` 已覆盖官方 Flutter 宿主从登录、主页、
  课表详情到学期/周次 typed 查询、“我的”页，以及普通 8 项和高级 4 项全部详情入口；另有
  课堂签到的 prepare/confirm/单次提交/只读刷新组合回归。测试仅使用脱敏 fake backend，不能
  代替设备上的真实 FRB/上游读取。
- `BridgeBackend` 已为 12 个只读功能映射白名单详情，并为课表/考试/成绩提供学期（课表另有
  周次）、空教室提供日期/校区及楼层/节次本地过滤的 typed 查询入口；详情页控件只向
  `AppController.refreshFeatureQuery` 传递 `FeatureQuery`，不拼接 URL。上述入口已有 app/widget
  参数传递测试。Judge 另提供批量详情视图，逐行接收公开的 `课程编号/作业编号` 并解析为 typed
  键列表，不接收 raw JSON 或上游正文；课堂签到提供全部/未签到/已签到本地状态视图。
- 博雅已选课程的签到时间窗、位置点数量和签到类型现有 bridge 白名单与 widget 覆盖；位置坐标不跨入
  `FeatureDetail`，不可操作状态的签到/签退按钮会禁用并说明由 Core 判定。
- 课堂签到详情只消费 Core/bridge 输出的 typed action；action 缺失、目标为空或资格为 `unknown/denied`
  时默认拒绝且不调用 prepare。只有稳定目标和 `allowed` 同时成立时才开放入口，prepare/commit 仍由 Core
  重读当天唯一安排做最终校验。
- `777261f` 固定了主页与共享详情页明亮主题 1280×800 golden 基线；随后 `c2fed18` 为十二项
  `FeatureId` 分别固定同一详情渲染器在领域标题、脱敏字段、实际路线和查询控件下的 1280×800
  明亮主题输出（`test/goldens/feature_<id>_light.png`）。这些基线不代表实体设备字体、权限或安全存储能力。
- `35ffb0d` 为功能卡片补充容器级无障碍语义（功能名、状态和点击提示），并以 widget 回归固定语义标签；
  失败/过期卡片的重试按钮仍保持独立 tooltip/语义。该证据覆盖共享卡片壳，不替代逐领域页面和实体设备读屏验证。
- `7bc9c1a` 为统一写入确认结果固定 `outcome_unknown` 文案：“提交结果不确定，请先刷新相关状态，不要重复提交。”；
  widget 回归证明未知结果不会沿用普通后端消息，也不会自动触发重试或写后刷新。该证据覆盖共享确认壳，
  不替代逐领域真实写后核对。
- `1e3c729` 的合同 CI `33589036008` 与五平台 Debug CI `33589036000` 已终态成功；CI 只证明无签名构建和
  确定性门禁，不替代 OHOS 签名、实体设备读屏或真实 App→FRB→Core 链路。当时 HEAD `0a0bb71` 的
  `CARGO_INCREMENTAL=0 CARGO_BUILD_JOBS=1 just flutter-codegen-check` 已完成并报告 FRB 零漂移。
- `7bc9c1a` 的合同 CI `33591063958` 与五平台 Debug CI `33591063833` 已终态成功；Android APK、iOS simulator、
  macOS、Linux、Windows 均上传无签名 Debug 产物。CI 不替代 OHOS 签名、实体设备读屏、真实写后核对或当前本机
  FRB 零漂移重试。
- `f46c65c` 将提交异常与显式 `outcome_unknown` 统一为稳定的“提交结果不确定，请先刷新相关状态，不要重复提交”提示；
  widget 回归证明异常路径不泄露具体业务上下文。该提交的本地 Flutter/根级门禁、无签名 RC 前置与 API26 HAP 复核均通过，
  合同 CI `33592184452` 与五平台 CI `33592184458` 也已终态成功；这些证据仍不替代真实写后核对、实体设备或签名。
- `190f318` 在官方 Flutter macOS 宿主集成中加入 commit 异常场景，4/4 场景通过；异常结果不刷新签到状态、不显示已签到，
  仅保留稳定未知结果提示。集成使用脱敏 typed fake backend，不替代真实 FRB、上游或设备证据。
- 当时官方 Flutter macOS 宿主集成已扩展到 5/5：新增全领域 typed 查询矩阵，逐项覆盖十二个功能的查询视图、公开 ID、日期、学期/周次和分页
  参数，并从页面回到功能列表验证导航状态不丢失；所有输入均为脱敏 fixture，不访问真实账号或上游。
- `WriteFlowController` 测试当时以 `WriteOperation.values` 逐项验证十项写操作的 prepare→confirm 单次提交和重复确认拒绝；该矩阵只证明共享确认
  状态机，不证明任何真实账号副作用或写后上游核对。
- `190f318` 的合同 CI `33593160544` 与五平台 Debug CI `33593160580`，以及后续文档 CI `33593227275` 均终态成功；五平台
  Debug 产物已上传，仍不替代 OHOS 签名、实体设备或真实写后核对。
- 当时 HEAD `0a0bb71` 的 FRB 零漂移重试已完成，`cargo-expand`、生成、格式化和生成目录差异检查均通过；此前无输出后中断的尝试仅作为过程记录保留。
- 最终审计提交 `7e6a4ea` 的引用、敏感扫描、无签名 RC 前置报告和差异检查均通过，且远端同步、工作树清洁；临时 OHOS 无签名产物已移出仓库。
- 平台权限和照片选择器通过 `CallbackPermissionGateway`、`CallbackPhotoPicker` 注入原生回调；回调异常
  归约为稳定不可用/能力错误，`PermissionedPhotoPicker` 可按宿主选择相册或桌面文件权限。当前测试覆盖
  权限拒绝不调用 picker、文件权限选择和图书馆取消确认；这仍不是原生插件或实体设备证据。
- 十二项功能均已通过共享详情页提供正式导航入口，不再使用生产 Demo backend 或“即将接入”占位页。
  `c2fed18` 已补齐十二项详情逐领域 golden；`81dd9d2` 的官方 macOS 宿主十项写入组合回归进一步逐项
  断言提交后刷新关联只读领域，预期失败后聚焦场景 1/1 通过。结合当前 Direct/WebVPN Core-live、五平台
  原生 CI 与 API26 无签名 OHOS 门禁，无签名执行目标的 P3/P4 UI 证据已闭合；原生 handler、实体设备读屏/
  权限/生命周期、签名发布仍为后置 `BLOCKED`，不在本规格中宣称正式发布。
