# Flutter UI 规格

更新：2026-10-30。只维护现行共享界面规则；历史验证与旧版设计补记见[历史记录](../migration/history/2026-10-30-flutter-ui-spec-history.md)。

2026-10-26 操作反馈补充：应用内的短暂提示统一通过 `UbaaFeedback` 显示。使用 Flutter 官方 `SnackBar` 的浮动布局，桌面最大宽度 420，窄屏两侧各留 16。成功／一般提示显示 3 秒，错误／待核实提示显示 6 秒并可关闭；开启辅助导航时，后两类提示保持到用户关闭。新消息替换旧消息，避免排队遮挡。样式跟随明暗主题，以图标和文字区分结果，不用整条红色背景。确认弹窗继续使用共享 Dialog 主题，页面读取错误保留原位置和重试入口。

博雅选退在当前按钮内展示进度，提交、核对和刷新期间保留列表和滚动位置；刷新覆盖已加载页后一次更新。刷新失败保留只读内容并提供重试。成功提示简化为“选课成功／退选成功”；结果未知仍明确要求核对且不能重复提交。协议与验证见[博雅反馈记录](../migration/history/bykc-detail-2026-10-26.md#选退反馈与列表保留)。

界面按首页、学业、课程与作业、校园服务、设置组织，当前实现与未验范围见[迁移状态](../migration/status.md)。[旧版界面基准](../migration/history/2026-09-08-ui-ux-old-baseline.md)只用于追溯历史设计，冲突项以本页和后续已登记决定为准。

2026-09-07 维护补充：错误卡显示本次诊断编号并可主动复制稳定字段；登录失败页和“我的”均可
查看本次运行诊断。诊断默认仅在有界内存保存，不自动上传。错误码、重试标志和失败路线完整
保留，展示模板由 platform 统一拥有，详见[本地排障手册](../runbooks/local-diagnostics.md)。

本规格只描述共享 `ubaa_ui` 的用户可见状态。上游 URL、Cookie、令牌和原始响应不进入
页面模型；页面只消费 `ubaa_app` 映射后的 domain 模型。当前候选、确定性门禁与平台验证分别以
[迁移状态](../migration/status.md) 为准，本文末尾的历史验证记录不代表本轮最终候选已经通过。

## 导航与响应式布局

| 入口 | 当前行为 |
|---|---|
| 启动 | 根据本地账号、材料与恢复状态进入登录或首页，等待与错误保持独立可见。 |
| 登录 | 同一表单适配窄宽窗口，保留密码显隐与验证码；连接方式入口放在设置。 |
| 主导航 | 首页、学业、课程与作业、校园服务、设置；窄屏底部导航，宽屏侧栏。 |
| 领域页 | 领域列表、详情和预约步骤保持可返回；按宽度调整表格、卡片与详情排列。 |
| 设置与资料 | 设置内管理路线、外观、缓存和诊断；侧栏或对应入口打开资料与关于页。 |

首页预览与磁贴见[首页规格](home-layout.md)，浅深色角色见[配色规格](color-system.md)。导航分组以 [destination.dart](../../packages/ubaa_ui/lib/src/app/destination.dart) 为实现入口。

## 外观与设备偏好

主题可选 system、light、dark，由 [ThemePreferenceStore](../../packages/ubaa_platform/lib/src/infrastructure/place_preferences.dart) 通过 PreferenceValues 保存设备偏好，键为 `flutter.ubaa.preferences.theme`。Host 在启动时恢复，读取失败或值无效时跟随系统；迟到的恢复结果不能覆盖本次新选择。主题不随退出或清除账号删除。普通偏好写失败不打断本次选择，因此无法保证失败后的下次启动仍恢复同一主题。账号凭据继续使用独立安全存储。

## 照片与拍照

阳光表单提供照片选择、预览、元信息与清除，拍照入口由当前平台能力决定。照片由系统插件或桌面文件选择器取得，平台层先做 10 MiB 上限和可解码校验，只向 Host 交付内存字节、合法展示名与 MIME。选择与拍照共享等待、取消保原图、失败反馈、退出释放和迟到保护；插件遗失结果只清理，不自动附回新账号。当前实现见[平台照片适配](../../packages/ubaa_platform/lib/src/media.dart)。

实际平台与验收范围见[照片来源对照](../migration/source-parity-ui-photos.md)和[迁移状态](../migration/status.md)，合成相机原生UI测试不代表真实设备拍照通过。

## 功能状态

每张卡片和详情页均支持 `idle`、`loading`、`success`、`empty`、`stale`、`failure`；刷新时
保留上一次的详情模型，新的读取结果按 generation 丢弃过期响应。已有成功数据刷新失败时显示
`stale` 横幅、旧数据和重试按钮；首次失败只展示稳定中文错误，不渲染上游正文。可浏览的结果列表在内容顶部常驻搜索框（带一键清除），关键字始终可见；有用户可调条件的列表在搜索框旁提供“筛选”按钮并以角标显示生效数量。筛选只含状态、学期名称、博雅类别/校区和作业排序等用户可理解的条件，点选即生效，“恢复默认”一次撤销；不提供学期编码、各类 ID、时段编号或手填日期，也不在筛选中切换视图，视图由菜单、卡片、页内选择器和预约流程进入。菜单页、单项详情、课表和预约流程不显示搜索。本地筛选与适用的分页能力均保留。Bykc 课程、图书馆预约、阳光打卡记录和研讨室订单等 typed 查询同时
保留 Core 服务端分页元数据，使用 1-based 上下页控件和总数提示，不把服务端页误切成客户端缓存。
筛选只匹配 bridge 白名单字段并重置到第一页。读取成功或空结果
若包含 Core 的 `resolvedRoute`，顶栏单图标显示当前读取的实际路线，点击查看说明及切换选项；该字段不由登录设置中的
`defaultPolicy` 推导，`stale` 状态沿用上次成功路线。若上次成功结果只有摘要而没有详情项，
详情页仍显示该摘要，同时保留失败横幅和重试按钮，不降级为首次失败错误页。
Core 明确返回空结果后不保留旧数据；此后刷新失败按首次失败显示稳定错误，不伪造成 stale。
课堂、图书馆座位和研讨室日期查询的日期输入严格限定为真实日历日期的 `YYYY-MM-DD` 形状；带时间、时区或不存在日期的字符串在 UI 层拒绝，不进入 typed `FeatureQuery`。

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
| 研讨室预约/取消 | 预约只选择一至两个同站点、日期、空间和空间组的 allowed action，时段 ID/原始序号唯一且序号相邻；取消消费 typed target | 预约成功收据与订单列表核对；取消成功或 unknown 固定原路线读取首页列表与同 ID 详情，仅消费本次严格取消证明 |
| 阳光打卡 | typed 提交、照片选择与回读能力齐备才开放入口；表单消费 Core 签发的分类/项目 target、完整本地时间和内存照片，权限失败或缺照片不进入 prepare | 成功或 unknown 按 intent 原路线各尝试一次概览与记录首页读取，结果不确定仍保持 unknown |
| 教学评教 | 单门或批量选择非空、有序、无重复的 typed targets；完整问卷、题目和答案只留在 Core | 确定结果、部分失败、unknown 或 commit 异常都至多按原路线回读一次，保留逐课程四态结果 |

需要确认的流程显示 `WriteIntent` 的摘要、实际路线、警告与过期时间；直接操作继续经同一 prepare/commit 协调器执行，不因省去弹窗绕过 Core 校验。应用层唯一 `WriteCoordinator` 拥有
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

公共导出继续经 `packages/ubaa_ui/lib/ubaa_ui.dart`；`lib/src/widgets.dart` 显式导出独立 library。维护实现时按下表定位，调用方不直接导入 part 文件。

| 修改内容 | 实际实现 |
|---|---|
| 启动、登录、主页和个人页 | [app/splash.dart](../../packages/ubaa_ui/lib/src/app/splash.dart)、[login.dart](../../packages/ubaa_ui/lib/src/app/login.dart)、[home.dart](../../packages/ubaa_ui/lib/src/app/home.dart)、[profile.dart](../../packages/ubaa_ui/lib/src/app/profile.dart) |
| 页签/详情导航、外部写状态与命令接线 | [app/shell.dart](../../packages/ubaa_ui/lib/src/app/shell.dart) |
| 查询控制器创建/释放、输入校验、FeatureQuery 组装与提交 | [common/filters/feature_filters.dart](../../packages/ubaa_ui/lib/src/common/filters/feature_filters.dart) |
| loading/empty/failure/stale 和查询/详情组合 | [common/feature_detail.dart](../../packages/ubaa_ui/lib/src/common/feature_detail.dart) |
| 本地筛选、详情行组合与选择集合生命周期 | [common/details/detail_list.dart](../../packages/ubaa_ui/lib/src/common/details/detail_list.dart)；字段展示在 [detail_fields.dart](../../packages/ubaa_ui/lib/src/common/detail_fields.dart) |
| 服务端/本地翻页控件与错误卡 | [common/paged_results.dart](../../packages/ubaa_ui/lib/src/common/paged_results.dart)、[error_card.dart](../../packages/ubaa_ui/lib/src/common/error_card.dart) |
| 课表、考试、成绩、空教室查询控件 | [features/academic/](../../packages/ubaa_ui/lib/src/features/academic/) |
| SPOC/Judge 作业与 Signin 课堂签到查询、签到按钮 | [features/coursework/](../../packages/ubaa_ui/lib/src/features/coursework/) |
| 博雅、图书馆的领域查询与 typed 写按钮 | [features/bykc/](../../packages/ubaa_ui/lib/src/features/bykc/)、[libbook/](../../packages/ubaa_ui/lib/src/features/libbook/) |
| 研讨室、阳光打卡、评教的领域查询、typed action 与选择控件 | [features/cgyy/](../../packages/ubaa_ui/lib/src/features/cgyy/)、[ygdk/](../../packages/ubaa_ui/lib/src/features/ygdk/)、[evaluation_actions.dart](../../packages/ubaa_ui/lib/src/common/details/evaluation_actions.dart) |
| 研讨室预约与阳光打卡输入表单 | [common/details/cgyy_form.dart](../../packages/ubaa_ui/lib/src/common/details/cgyy_form.dart)、[ygdk_form.dart](../../packages/ubaa_ui/lib/src/common/details/ygdk_form.dart) |
| 意图摘要、错误、取消与提交按钮 | [write/confirmation.dart](../../packages/ubaa_ui/lib/src/write/confirmation.dart)；回调类型在 [write_callbacks.dart](../../packages/ubaa_ui/lib/src/write_callbacks.dart) |

普通回归按领域位于 [UI tests](../../packages/ubaa_ui/test/)、[App write](../../packages/ubaa_app/test/write/) 和[宿主 tests](../../apps/ubaa_flutter/test/)；导航、查询、焦点、状态连续性与写入协调由这些测试分层保护。原生只保留 `platform/*` 和 `synthetic/cache/*`，逐项删除能力、保留理由与无自动化覆盖项见[范围登记](../migration/history/2026-10-30-decisions-through-quality-phase3.md#2026-10-29原生集成只保留真实原生能力)。

生产状态机见[write](../../packages/ubaa_app/lib/src/write/) 和 [controller/write](../../packages/ubaa_app/lib/src/controller/write/)，生命周期与协议语义见[Bridge 合同](../contracts/flutter-bridge.md#2-生命周期与并发)。历史协调器计划归入[实施记录](../migration/history/2026-09-05-write-coordinator.md)，不作为现行实现入口。
