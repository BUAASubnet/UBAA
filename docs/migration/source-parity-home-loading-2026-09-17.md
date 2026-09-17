# 首页加载性能修复：来源对照与验证

## 范围与实施前事实

本轮只处理用户反馈的首页加载慢；`goal.md` 中暂停的完整 UI/UX 计划不恢复。
起始分支 `ubaa2`，保留既有 UI 与引用管理未提交修改。
`just refs` 通过：旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`，
`buaa-api` 为 `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。

确认的代码原因：

- `AppController._refreshHome` 默认遍历十二个 `FeatureId`。考试、成绩默认页、博雅可选课程、空教室、图书馆楼馆、研讨室站点和评教并非首页展示数据，却在启动和下拉刷新时读取。
- Bridge `api/read/methods.rs::execute_read` 持有同一个 `inner` 互斥锁直到网络返回。Dart 的 `Future.wait` 不能使这些请求真正并行；枚举顺序将签到排在第九项，无关慢请求和失败超时会阻塞后续首页来源。
- 首页另有博雅已选、研讨室订单、当前学期/周次及成绩变化检查；默认成绩读取还会重复查询学期和成绩。

## 冻结来源核对（生产代码修改前）

已读旧版 `composeApp/.../ui/navigation/HomeBootstrapCoordinator.kt`、同名测试及
`MainAppScreen.kt::startHomeBootstrap`：首页仅调度今日课表、签到、SPOC、希冀、博雅已选、
研讨室订单、阳光提醒、成绩变化检查，不遍历所有功能；测试确认各来源独立启动和失败隔离。

`buaa-api/src/context.rs`、`src/api/{class,spoc,boya}/`、请求、存储与错误模块没有等价首页聚合器；
其共享上下文不构成删除 UBAA Core 互斥保护的依据。
与旧矩阵固定提交只读比较：旧版相关本地 API 仅课表和签到有变化，SPOC、希冀、博雅、场馆、阳光未变；
示例相关差异在课堂 API 与上下文网络刷新。已读课表/签到差异及当前函数：研究生课表回退不在本轮范围；
签到严格 sessionId 与示例 loginName 的分歧继续以[签到专项](source-parity-signin-2026-09-17.md)为准。

以下逐操作列明九个协议维度。本次仅调整应用层触发范围和顺序；原协议依据为
[基础矩阵](source-parity.md)和[首页六来源投影](source-parity-ui-home.md)，不借本轮调度变更补猜协议。

| 操作 | CAS/bootstrap 与 service | 重定向/最终 URL | Cookie/会话 | HTTP 与参数 | 请求头/编码 | 加密/签名 | DTO/解析 | 缓存/并发 | 错误语义 |
|---|---|---|---|---|---|---|---|---|---|
| 今日课表 | 原课表矩阵；示例无等价本科门户 | 原 Core 校验 | 原路线会话 | 原 today、rq/lxdm | 原教务头 | 无新增 | 原 TodayCourse | 仍为第一项 | 原分类/stale |
| 今日签到 | 签到专项；不借示例分歧 | 原跳转限制 | 原业务 sessionId | 原 today、id/dateStr | 原 sessionId 头 | 无新增 | 原 DTO/action | 第九项提前至第二项 | 原鉴权与资格 |
| SPOC 作业 | 原 SPOC 认证矩阵 | 原 Core 校验 | 原 SPOC 会话 | 原 assignments | 原编码 | 原实现 | 原作业投影 | 保留默认读取 | 原分类/stale |
| 希冀作业 | 原 Judge 矩阵；示例不等价 | 原 Core 校验 | 原 Judge 会话 | 原 assignments | 原编码 | 原实现 | 原作业投影 | 保留批量与缓存 | 原分类/stale |
| 阳光概览 | 原阳光矩阵；示例无对应 | 原 Core 校验 | 原阳光会话 | 原 overview，不读记录 | 原编码 | 原实现 | 原 YgdkOverview | 保留默认读取与固定路线回读隔离 | 原分类/stale |
| 博雅已选 | 原博雅矩阵；示例不完整等价 | 原 Core 校验 | 原博雅会话 | 原 chosen | 原编码 | 原实现 | 原已选 DTO | 保留补充缓存；取消可选课程预载 | 原局部错误 |
| 研讨室订单 | 原场馆矩阵；示例无对应 | 原 Core 校验 | 原场馆会话 | orders，page=0/size=20 | 原编码 | 原签名 | 原订单 DTO | 保留补充缓存；取消站点预载 | 原局部错误 |
| 当前学期/周次 | 原课表矩阵 | 原 Core 校验 | 原教务会话 | terms→weeks(term) | 原教务头 | 无新增 | 唯一 selected/current | 保留同代合并 | 原缺失/失败 |
| 成绩变化检查 | 原成绩矩阵 | 原 Core 校验 | 原教务会话 | 原当前学期成绩 | 原教务头 | 无新增 | 原成绩/变化投影 | 保留专用检查，取消默认成绩页重复预载 | 原检查/通知 |
| 考试、空教室、图书馆楼馆、评教及上述默认页 | 各自原矩阵 | 原 Core 校验 | 原路线隔离 | 原默认查询 | 原编码 | 原实现 | 原 DTO | 首次打开经已有 idle 加载，保留显式重试 | 未访问为 idle，不伪造空结果 |

保留 Bridge/Core 锁、会话修订、账号/路线生命周期边界；不复制客户端或 Cookie，不并发改写会话。

## RED 证据

锁定 SDK 下在 `packages/ubaa_app` 执行 `flutter test test/home_loading_test.dart --reporter expanded`，
实际退出 1，三项全部预期失败：启动与刷新读取十二项而非五项；每项一秒的串行合成网络到第二秒时，
签到仍为 loading。虚拟时间仅复现排队，不代表校园网络测速。

## 验收记录

首轮完整 Flutter 回归发现首次从成绩提醒进入时，既有导航器的 idle 帧回调晚于指定学期查询，
会多发默认读取并覆盖查询；既有 `home_grade_notice_test.dart` 第 95 行出现 null query，已保留 RED。
导航器同时检查当前本地帧仍为 idle 且无指定查询才自动加载，避免旧宿主快照覆盖直达操作。
另两项失败是旧测试要求首页刷新隐藏的图书馆楼馆和研讨室站点，按本轮按需加载合同更新断言，
保留首页研讨室订单 page=0/size=20 与隐藏页不扩展子查询的检查。

最终当前工作区验证：

- 新增三项首页加载测试：初始与刷新只读取五来源、未访问功能 idle、显式单项仍可读取、串行队列中签到第二项完成。RED 后 GREEN。
- 新增七项宿主实际点击回归：考试、成绩、博雅、空教室、图书馆、研讨室、评教首次打开自动读取，返回重进不重读。既有首页六来源与成绩提醒测试继续通过。
- `just flutter-check` 退出 0：Domain 54、Platform 59、App 273、UI 249、Bindings 15、Host 30、Flutter 宿主 54，共 734 项，锁定 SDK 分析与格式检查通过。
- `just check` 退出 0，包含 CLI 端到端 16 项；最终 `just refs`、`just layout-check`、`just check-sensitive`、`git diff --check` 通过。
- `just verify-live mode=direct` 与 `mode=webvpn` 均退出 0，各 40 PASS、0 FAIL；日志仅安全状态、路线、数量和耗时。认证通过既有 `.env.local`→stdin 路径，不复制凭据或修改默认运行会话。
- macOS 原生生产入口 `integration_test/ui_home/live_readonly_test.dart`，新建 Sandbox 私有隔离目录（700，配置 600），显式只读开关和预期路线。Direct/WebVPN 各 1 PASS；五个默认来源、三个补充来源与实际路线都成功/明确空，七个未访问领域保持 idle，业务写入 0，不截取真实个人页面。
- 原生只读验证结束后执行 `just flutter-build platform=macos mode=debug`，正常 `lib/main.dart` 入口构建成功，产物为 `apps/ubaa_flutter/build/macos/Build/Products/Debug/ubaa_flutter.app`；不把集成测试入口留作交付应用。

### 原生计时与限制

下表为一次启动样本，从生产 bootstrap 开始用 Stopwatch 计时，`observed_ms` 为测试首次观察到
结果的时间（含轮询间隔），不是单接口精确耗时；不包含构建时间，也不是冷启动统计基准。
Direct 在最后导航时序保护前取得（该保护不改变首页启动读取），WebVPN 在最终生产代码取得。

| 观察点 | Direct / ms | WebVPN / ms |
|---|---:|---:|
| 首页容器显示 | 1267 | 1168 |
| 今日课表完成 | 1272 | 1747 |
| 今日签到完成 | 1891 | 1752 |
| SPOC 完成 | 1892 | 2308 |
| 希冀完成 | 15677 | 28308 |
| 阳光概览完成 | 16749 | 29375 |

可确定减少的是默认加载任务由 12 降至 5，且签到从第 9 项提前至第 2 项。
没有真实旧版本同条件对照，因此不宣称真实整体提速百分比。希冀聚合读取仍为明显长尾；
本次两路线返回数量不同，不能将两组耗时直接当作网络路线性能对比。Bridge 锁与上游协议保持原样，
首页容器/已有来源先行可用不代表全部来源已完成。

本轮提交包含导航器已有的首次访问加载片段及新增直达保护，因为缩减预载依赖该行为；
其余既有 UI、冻结引用管理和文档改动保留在工作区，不混入本轮提交。
