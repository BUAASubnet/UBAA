# 决策索引

## 2026-10-29：首页传输与首批调度优化

用户随后明确要求优先解除跨业务串行。实施范围扩展为有上限的分组并发和统一认证/写协调；gzip 与首批优化保留。实施前对照见 [并发方案](source-parity-home-concurrency-2026-10-29.md)。

用户要求继续尽可能优化首页加载。代码确认全局串行同时存在于 App 的 ReadScheduler 和 BridgeClient 的 Core 锁，单独增加 Dart 并发不会增加网络吞吐。旧版 HomeBootstrapCoordinator 以协程并发启动来源，但旧版希冀的 WebVPN 课程隔离曾有真实反例，因此不能据此取消当前会话保护。

优先验证不增加并发的传输压缩和首批结果调度。真实 WebVPN 诊断确认希冀 96 份详情支持 gzip，传输量减少约 87%；诊断仅记录分类、数量、字节数和耗时。实施前逐项对照和后续验收见 [首页性能记录](source-parity-home-performance-2026-10-29.md)。

## 2026-10-29：首页解析性能优化

实测希冀持久缓存可正常复用，但逐题解析反复编译相同正则。将解析规则和 CSS 选择器改为静态延迟初始化，保持全部字段、网络请求、缓存期限、取消及 WebVPN 串行边界。96 份合成详情解析从 5208 毫秒降至 240 毫秒。两路线真实只读各 50 项通过，首页完整刷新仍受考试等上游等待影响，不据单次网络样本承诺固定提速。双来源矩阵、基准、隔离检查与现存门禁问题见[性能记录](source-parity-home-performance-2026-10-29.md)。

## 2026-10-29：iOS 首页加载初步排查

用户反馈首页加载偏慢。使用 iPhone 17 Pro（iOS 26.5）模拟器运行当前工作区的 `apps/ubaa_flutter/lib/main.dart`，保留既有六个界面文件的未提交改动。冻结引用检查与 Debug 构建通过，Flutter VM Service 已连接。读取沿应用已有账号和 WebVPN 路线执行，未提交业务写入。

通过仓库外的临时 Dart 观察脚本，每约 300 毫秒读取一次控制器状态，只记录阶段、功能状态、数量、路线及错误分类，不读取凭据或业务正文。一次热重启中，以首次观察到 `AppPhase.home` 为相对零点，缓存约在 0.7 秒后恢复，课表约在 1.0 秒后刷新完成，签到约 6.5 秒、运动约 7.5 秒、考试约 13.6 秒、SPOC 约 18.5 秒、希冀约 38.5 秒完成。六项最终均成功且没有功能错误。完成后截图确认待办区加载指示消失，截图及原始观测保存在仓库外。

代码核对：`controller/read_scheduler.dart` 一次执行一批读取；`controller/reads/progressive.dart` 将首页分批读取的后续批次设为后台优先级；`ubaa_ui/lib/src/app/home.dart` 在待办来源仍为 `loading` 时保留加载指示。观测支持优先调查希冀分批扫描及其排队时间，尚不能将 38.5 秒全部归因于希冀上游网络耗时。

本轮只排查并记录事实，没有修改产品代码或调度规则。上述时间包含轮询误差和 Debug 调试开销，来自单次热重启，未测量进程冷启动、首帧栅格化时间、真机或 Release 性能。下一步应分别记录希冀会话恢复、排队和各读取批次耗时，再决定是否需要调整调度或减少重复读取。

## 2026-10-27：接手修复原生集成测试

接手 `claude/gallant-mcclintock-c3344c` 在 `8079f2ef` 上的 37 个未提交集成测试改动，继续处理当前导航、搜索筛选及 Bridge v42 与旧测试之间的差异。本轮仅调整测试与记录，不改变生产 UI 或上游协议。

测试改走可见导航、卡片和页内选择器，并继续核对读取参数、修订、单次提交与原路线回读。加载场景显式挂起并释放请求，刷新失败在首次成功后主动触发，避免按后台调用次数制造偶发状态。部分登录夹具补齐交互认证与显式继续，未实现的业务读取仍明确失败。旋转专项保留原生方向与同一页面状态检查，适配当前紧凑／展开导航及课程网格的文字对比度。

已删除检查与保留覆盖、失败反例及本轮验证结果集中记录在[集成测试修复](integration-repair-2026-10-27.md)。真实账号入口只做静态检查。macOS 启动锁入口因本机应用容器目录访问权限被拒绝而未通过，不修改 App Sandbox 或将环境限制记为成功。

随后按用户要求先将 `b87408d1` 快进合并到 `ubaa2`，确认与已验证提交的代码树一致，再删除原工作树。工作树无未提交源码，忽略项为构建产物、依赖及干净的冻结引用副本；仓库外私有证据保留。原分支保留，未执行远端推送。

## 2026-10-27：搜索与筛选拆分重做

用户反馈搜索与筛选体验差。真实账号只读巡检确认：原通用面板把本地关键字、即时生效的标签和需点“应用筛选”的服务端视图混在一起，并暴露学期编码、周次、课程/订单/站点/分区 ID、时段编号和手填日期等协议参数；视图下拉与菜单入口重复。成绩页关键字在面板收起后仍生效却没有任何可见提示，切换学期和离开重入后列表依旧为空，用户只会以为数据丢失。

处理：可浏览的结果列表在内容顶部常驻搜索框，带一键清除，关键字始终可见；搜索不再藏在面板中。有用户可调条件的列表在搜索框旁提供“筛选”按钮，角标显示生效数量。筛选面板（`FeatureFilterControls`）只含考试/成绩/评教/签到状态、考试学期名称、博雅状态/类别/校区和作业排序，点选即生效，“恢复默认”一次撤销，博雅保留“状态不限”。删除原 `common/query` 通用查询表单及其全部协议参数输入和视图下拉；视图继续由菜单、卡片、页内校区/日期/楼栋选择器、课表选择器和预约流程进入。博雅资料、用途类型两个只在旧面板可达的调试视图不再在 GUI 提供，CLI 保留。菜单页、单项详情、课表与预约流程不显示搜索；顶栏只保留课表的学期选择。考试学期对话框保留读取代次保护，打开期间连接变化不套用旧学期。

失败反例：新增 3 项行为测试在修改前全部失败（找不到常驻搜索框、找不到筛选按钮、博雅菜单页仍有搜索图标），修改后通过。

测试整理与保留覆盖：
- 删除 `query/panel_test.dart`（未应用草稿跨宽度保留）：草稿概念移除，由新测试与 `navigation/continuity_test.dart` 的搜索重入、跨断点保留覆盖。
- 删除 `features/classroom/selectors_test.dart` 9 项（面板楼层/节次/日期选项与代次）及 `details_test.dart` 3 项、`academic/selectors_test.dart` 教室日期 1 项：对应输入已移除；正文切换校区/日期清除旧楼层节次仍由 `classroom/parity_test.dart` 覆盖。
- 删除 `query/queries_test.dart` 4 项（博雅课程 ID 详情、修读统计视图、博雅与阳光记录第一页）：详情经卡片 typed 课程 ID 进入（`bykc/content_test.dart`），统计与记录经子菜单和阳光首页进入（`landing_parity_test.dart`、`ygdk/content_test.dart`）。
- 删除 `bykc/content_test.dart` 课程 ID 下拉 1 项与 `shell_parity_test.dart` 面板草稿 1 项：分别由卡片 typed ID 断言和新搜索测试覆盖。
- 改写：考试/成绩/评教/签到状态改为点选标签；学期选择改经考试筛选，保留缓存选项、按内容收缩、失败重试、只提交 typed 编码和代次保护；连续性测试改为换账号清空、重入保留、重试沿用已生效条件和领域隔离。

原生集成：默认 CI 集合中的 `synthetic/app/flow_test.dart` 已改写为状态筛选点选矩阵，移除手填周课表步骤。其余按需运行的合成、平台与真实只读入口只机械替换了搜索框、筛选入口和关闭按钮定位，并通过静态分析；其中仍依赖已删除参数的步骤（学期编码草稿、手填日期/周次、视图下拉、各类 ID）需后续改为页面入口。部分步骤在本轮前已引用不存在的旧标签。本轮不执行真实学校请求。

验证：冻结引用、布局、目录、模块和敏感检查与完整 `just check` 通过；`just flutter-check` 七包 1421 项测试与静态分析通过（UI 454、App 676、Host 101、官方 App 83、领域 87、平台 20），收尾样式调整后 `just check-changed` 复验通过。iOS 模拟器正式 Debug 以真实账号只读核对：成绩搜索边输入边过滤、清除按钮、状态筛选即时读取与角标、恢复默认，博雅菜单页无搜索，博雅与考试筛选不含协议参数，未提交任何写入。实际检查中修正了已选标签显示为禁用、生效筛选按钮为深色实心两处样式。默认 CI 原生流程 `synthetic/app/flow_test.dart` 在 macOS 运行 7 项中 6 项失败，失败点均在进入功能页前的旧入口（宽窗口缺少抽屉菜单、分组页结构变化），与 2026-10-26 记录的既有问题一致，本轮未修复，不记为通过。

## 2026-10-26：补齐触摸板滚动并固定导航栏边界

用户反馈触摸板在正文留白处无效，同时左侧导航可以被拉动。上一轮只覆盖 `PointerScrollEvent`；触摸板的 `PointerPanZoomStart/Update/EndEvent` 未接入。宽屏导航的 `ListView` 还会默认采用 `AlwaysScrollableScrollPhysics`，结合 macOS 回弹效果，内容未溢出时仍可被拉出边界。

留白处新增纵向触摸板手势识别，复用当前正文 `ScrollPosition.drag`、平台速度估算与滚动物理参数，保留拖动、惯性和边界行为。手势开始于正文时仍由正文处理；切换页面后终止原手势，避免带动后台页面或新页面。导航独立使用 `ClampingScrollPhysics`，宽屏导航显式关闭隐式主滚动继承；内容放得下时固定，窗口过矮时可滚动到其余入口，设置与关于继续固定在底部。

修改前的失败反例：相同触摸板序列在正文把位置从 500 推进到 660，两侧留白仍停在 500；宽屏导航在无溢出时被拉到约 -72.29。修复后 12 项聚焦测试通过，包含左右手势与正文的拖动／惯性比较、手势中切页、横向／缩放／禁用场景、宽窄导航固定与矮窗口入口访问。触摸板验证使用 Flutter PanZoom 事件序列，与原生实体触摸板人工验收分开记录。

验证：`just check-changed` 通过，包含引用、敏感扫描、布局、模块检查，以及 UI 476、Host 101、官方 App 83 项测试与三包静态分析。macOS Debug 构建与签名权限检查通过，已重启并恢复宽屏首页。当前自动化桌面工具只提供普通滚动操作，因此本轮实体触摸板未人工验收，未将鼠标滚轮操作记为触摸板证据。

## 2026-10-26：正文两侧留白支持滚轮

主容器将正文限制为 1040 逻辑像素，两侧留白原本位于滚动组件之外，鼠标滚轮无法带动正文。新增共享 `ScrollGutters`，保留正文宽度，在留白处找到当前可见页面最外层的纵向滚动位置，并通过 Flutter 的滚轮信号仲裁与 `pointerScroll` 执行滚动。后台页面和导航父帧不接收操作；正文内部继续由原滚动组件处理，横向表格、内嵌列表、反向滚动及禁用滚动规则保持独立。

修改前运行宽屏主容器回归，在左侧留白发送 120 像素滚轮后，预期位置为 120，实际仍为 0。修复后左右留白、正文单次滚动、顶部和底部边界通过，补充页面切换／详情返回、内嵌双向滚动、Shift 修饰键、反向列表和禁用滚动覆盖，共 4 项聚焦测试通过。本轮不涉及读取协议或业务操作规则。范围检查与原生验证结果在状态文件记录。

验证：引用、敏感扫描、布局和模块检查通过；范围门禁首次发现主容器格式差异，格式化后从 Flutter 检查步骤继续，三包静态分析及 652 项测试全部通过。macOS Debug 构建与实际签名权限检查通过，重启后在首页和博雅列表分别完成左侧向下、右侧向上的滚轮核对。未执行真实业务写入，移动端本轮由既有 Widget 回归覆盖。

## 2026-10-26：统一临时提示并保留博雅选退页面

统一使用 Flutter 官方 SnackBar 和 ScaffoldMessenger，提供限宽浮动提示、明暗主题、消息替换及辅助导航支持。已评估 `toastification` 的通知样式和队列能力；当前需求由已有 Flutter 组件覆盖，因此不新增依赖。临时消息入口集中到 `UbaaFeedback`，确认弹窗和页面错误继续承担确认与恢复操作。博雅写后失效不再显示为整页错误，保留列表展示并等待新读结果，旧数据不能提供新写入资格。来源与验证见[反馈记录](bykc-detail-2026-10-26.md#选退反馈与列表保留)，样式规则见[UI 规格](../design/flutter-ui-spec.md)。

方案资料：[Flutter SnackBar](https://api.flutter.dev/flutter/material/SnackBar-class.html)、[ScaffoldMessenger](https://api.flutter.dev/flutter/material/ScaffoldMessenger-class.html) 和 [toastification](https://pub.dev/packages/toastification)。实现同时核对仓库锁定的 Flutter 3.41.9 源码，确认浮动宽度、关闭按钮和 persist 参数可用。

## 2026-10-26：博雅课程卡片紧凑布局

按用户反馈，分类、校区和“自主签到”统一为标签，课程状态增加字号和内边距。宽屏把教师／地点与时间安排分成两列，窄屏按顺序展示。报名进度限制最大宽度，与选退按钮同排；已选卡片将考勤与退选放入同一操作区。保留实际字段与既有点击行为，复用交互和原生场景验证。见[卡片布局记录](bykc-detail-2026-10-26.md#课程卡片布局调整)。

## 2026-10-26：博雅列表与详情直接选退

用户明确要求移除选退的独立确认页，并在列表提供选退按钮。点击按钮作为本次操作授权，仍由唯一协调器准备、单次提交和原路线回读。提交中禁用重复操作，失败与未知结果不自动重试；刷新完成后保留用户所在列表或详情及返回路径。真实提交协议不变，验证使用显式内存后端。见[博雅交互跟进](bykc-detail-2026-10-26.md#直接选课与列表操作跟进)。

## 2026-10-26：博雅详情人数为空时允许正常选课

冻结旧版允许详情 `courseCurrentCount` 为空，独立 Rust 参考也明确记录该接口会返回空人数。本轮真实只读请求再次确认此行为。选课资格不再要求已报名人数存在，已选状态、容量和关键时间仍须有效；已知满员继续拒绝，服务器保留最终判定。列表人数仅在同课程、同路线的有效当前快照中补充展示，并可收紧满员按钮状态。刷新详情、缓存失效与账号边界清除此快照。签到配置为空时不显示一组无意义的缺失字段。来源与验证见[修复记录](bykc-detail-2026-10-26.md)。

现行目录与模块规则见 [ADR 0006](../adr/0006-explicit-dart-modules.md)，任务边界见 [goal.md](../../goal.md)。以下条目是历史入口，不重新声明当前完成状态。

## 2026-10-26：项目自有目录统一下划线

用户明确选择下划线命名。将 Rust CLI、三个 crate 根目录和离线启动脚本目录迁移为下划线，同步 workspace、相对依赖、FRB、平台构建、CI 和校验脚本引用。包名、二进制名和命令名保持原值。历史 UI 证据路径对应外部归档与原哈希清单，作为冻结路径保留；第三方与 Android 资源限定目录也保留上游命名。

新增目录规则检查，通过临时路径样例先复现两个拒绝规则失败，再验证规则实现。规则与迁移表见 [目录命名](../development/directories.md)。本轮仅调整路径与检查，不改变业务协议或交互行为。macOS 首次构建发现旧 Pods 脚本缓存，重新运行 macOS／iOS `pod install --no-repo-update` 后仅变更本地绑定 podspec 的校验值；macOS Debug 构建已通过。Flutter 全量 1474 项与静态分析、FRB 零漂移和 Rust 完整检查通过。`just check` 首次在新文档的 Cargo 命令简写处被锁定依赖检查拦下；改为准确说明包名后，从失败的 workspace 测试步骤续跑，测试、启动脚本合同、构建和文档生成均通过。

## 2026-10-26：首页课堂签到直接执行

按用户明确要求，将首页签到点击作为本次提交入口，继续复用原 WriteCoordinator 的准备与单次提交。只有当前 allowed action 可提交；旧状态卡片显示刷新按钮。明确成功后移除当天对应待办，未知结果保留并要求核对，不自动重试。固定原路线回读同时更新首页独立数据，修复只更新功能页导致首页残留的问题。

协议核对、失败反例与测试迁移见 [首页签到记录](signin-home-2026-10-26.md)。1454 项测试与静态分析、2 项 macOS 原生合成场景通过，Debug 已重建并启动。本轮没有执行真实课堂签到。

## 2026-10-26：修复分页列表失效与功能入口

实际窗口复现研讨室入口复用“我的预约”旧子页，刷新后记录恢复。根因是入口未重置子菜单，同时上一轮将分页缓存失效设成 empty。本轮功能入口恢复子菜单，当前列表失效从首批重新读取，后台列表只标记失效；保留菜单返回路径，失败提供重试，拒绝旧追加响应。菜单中的预载内容失效后也必须重新读取。

先运行新增回归复现四处失败，并补充菜单预载失效的失败反例后实现。博雅偏好回归仍验证偏好只加载一次，业务列表读取次数改为失效后一次恢复查询；在途追加回归增加恢复首批和旧页不混入的断言。范围检查、627 项测试与静态分析、4 项 macOS 原生场景通过。Debug 已重建并启动，实际窗口确认记录恢复和入口菜单。详细来源与验证见 [连续列表记录](source-parity-infinite-lists-2026-10-26.md)。

## 2026-10-26：共享分页列表连续滚动

采用导航帧内的分页展示集合，原始 AppController 单页快照、写操作资格和回读依据保持独立。接近列表底部时发送下一页查询，一次一页；重复业务 ID 更新原位置，失败保留已加载内容并显式重试；空页或无进展不无限循环。账号／路线／缓存失效及刷新使追加代次失效，详情返回保持父帧数据与位置。刷新从原始首请求页开始（研讨室零基，其余一基）。移除页码和容量输入，本地长列表使用 ListView 惰性构建。

协议比较、测试迁移和结果记录见 [连续列表来源](source-parity-infinite-lists-2026-10-26.md)。旧分页按钮及手填页码测试迁移为滚动续载、首批刷新与末页停止；保留零／一基参数、原始取消目标、详情返回、路线及零业务提交断言。

验证：三包 621 项测试与静态分析、32 项 macOS 原生合成场景通过；旧测试迁移与各次失败原因见来源记录。Debug 已重建并启动，实际窗口确认博雅自动追加和前批保留、研讨室预约列表连续滚动；当前应用停在预约列表首屏。

## 2026-10-26：移除研讨室时段悬停提示

按用户要求移除时段单元格 Tooltip，保留 TextButton 的悬停高亮、点击行为和外层包含房间／日期／时间／状态的 Semantics。房间与时段仍可通过行列标题和选中汇总核对。纯展示改动复用既有测试，UI、App、原生合成及真实只读测试中的时段定位从 Tooltip 迁移到语义组件，选择、表单、几何位置和双向滚动断言均保留，未删除用例或新增提示文字缺席断言。本轮不执行真实预约写入。 23 项聚焦回归、范围门禁、UI 438／Host 101／官方 App 78 项测试及静态分析、20 个 macOS 原生合成场景通过；Debug 已重建并启动，实际窗口确认时段格保留悬停高亮且无房间／时间浮层。原查询日期与楼层已恢复，截图未保存到仓库。

## 2026-10-26：研讨室恢复旧版直接选择

用户要求撤回楼栋下拉框，并完全移除预约页面搜索筛选。冻结 `examples/ubaa_old` 提交 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 的 `CgyyReservePickerScreen.kt` 使用三排 LazyRow／FilterChip（校区、日期、楼栋）和去除楼栋“研讨室”后缀的简称。本次恢复此交互，增加横向滚动条提示与鼠标操作；所有窗口宽度直接展示选项，表格继续独立纵向滚动。当前同名楼栋／楼层去重保留。

移除预约选择页与入口页的搜索按钮及面板挂载、文本过滤、手填站点／日期和面板选择同步回调。现有记录分页和表单字段不在本次删除范围。改动不涉及读取协议或上游参数，站点与日期仍通过原始 typed 值查询；选择刷新、失效清理及预约确认机制保持原行为。

测试迁移：移除 `queries_test.dart` 的手填日期空间参数用例、`refresh_continuity_test.dart` 的研讨室手填查询键盘用例；对应原始编号／日期由 `features/cgyy/flow_test.dart` 的窄屏直选和 `navigation_test.dart` 的日期／校区切换保留覆盖，大字布局由既有双倍字体与表单测试覆盖。原生场景删除已取消的搜索草稿操作，保留时段选择、表单草稿、日期／校区切换及读取次数断言；真实只读入口的控件定位同步更新，未在本轮执行该入口。 `landing_parity_test.dart` 删除研讨室入口页已取消的手填查询草稿步骤，保留子页实际路线、返回菜单未确定路线及读取次数断言；记录分页草稿仍由 App 导航回归覆盖。

验收：先运行窄屏直接点选楼栋的失败反例，再恢复直选并通过 23 项研讨室 UI 和 7 项 App 导航聚焦回归。范围检查中的引用、敏感扫描、布局、模块及差异检查通过；迁移旧入口查询测试后，三包静态分析及 UI 438／Host 101／官方 App 78 项测试全部通过。macOS 明暗主题 20 个原生合成场景通过，Debug 已重建并重启；实际窗口确认全部三排选项、简化楼栋名称、无搜索入口，并恢复原楼层。未提交真实预约，运行画面未保存到仓库；移动端使用窄屏与双倍字体 Widget 覆盖，本轮未运行 iOS 设备测试。

## 2026-10-26：研讨室时段表与选择反馈

时段列宽由固定 86 调整为按可用空间均分，并保留随字体缩放的最小宽度；窄屏继续同步横向滚动，房间列与吸顶表头保持可定位。楼栋／楼层改用完整选项下拉列表，显示值去除首尾空格及完全重复名称，原始站点编号不变。宽屏日期缩短为月日和星期，当天标注今天，跨年保留年份，原始 ISO 日期保留在 Tooltip 与查询参数中。

可预约使用加号、已选使用勾选与文字、不可预约使用短横线，统一图例并保留未知资格与缺失数据区别；无障碍标签包含房间、日期、时间和状态。移除单元格内部白色缝隙，字号使用主题语义。底部根据原始选择汇总房间／日期／时段，窄屏换行，超长汇总可滚动，并提供清空选择；继续表单仍使用原始 Allowed action、相邻时段规则和单次确认流程。

本次不修改上游读取协议、请求字段、缓存或资格判定。宽屏最后一列无法对齐内容区的失败反例先于实现；保留表单草稿、未知资格、取消与回读测试，增加列宽、同步滚动、大字体、汇总清空及楼栋编号选择覆盖。原生场景的日期与时段表头定位随显示调整，原有查询、草稿及提交次数断言保留，没有删除覆盖。

研讨室原生回归发现旧失败场景仍查找已移除的全局缓存提示，改为核对实际网络错误与仍可阅读的房间时段；保留失败后读取及零提交边界。新增图例固定在表格外，避免长列表滚动时挤动原有吸顶表头。

验收：范围门禁中的引用、敏感扫描、布局、模块和差异检查通过；UI 440、Host 101、官方 App 78 项测试及三包静态分析通过，App 在更新旧表头定位与按当前可见单元格拖动后独立重跑通过，双向滚动同步断言保留。macOS 明暗主题共 20 个原生合成场景通过，包含长列表、长名称、刷新失败、表单草稿及零业务提交。Debug 构建后实际核对表格横向铺满、日期星期、楼栋名称与下拉选择、已选汇总；原日期与楼层已恢复，临时选择已清除，没有提交真实预约。移动端仅做窄屏双倍字体 Widget 回归，本轮未运行 iOS 设备测试。运行画面未写入仓库。

## 2026-10-25：首页待办跨行等高

原布局通过每排 IntrinsicHeight 拉齐高度，长地点只撑高所在排；截止时间紧跟描述，导致位置随行数变化。改为宽屏按当前可见待办的最大自然高度排布，并将文字分为顶部信息和底部时间。自然高度根据实际宽度与字体计算，不截断长地点；单列各卡片保留自己的自然高度，避免移动端空白过多。改动仅涉及本地布局，不修改读取协议、业务筛选和排序。既有展开收起、导航与下拉刷新覆盖保留，增加长短描述的几何位置和大字体全文回归。macOS Debug 构建通过并已重启，实际窗口确认四卡等高、顶部信息与底部时间对齐，长考试地点完整保留；运行画面未写入仓库。

## 2026-10-23：SPOC默认仅显示未提交

按用户最新要求，SPOC“仅显示未提交”默认开启，覆盖冻结旧版的默认关闭设置。保留隐藏已截止、截止时间升序及两个过滤条件独立组合；用户关闭未提交条件后可查看其他状态，全程本地筛选。调整既有规则及Widget测试，先验证原默认仍展示已提交的失败反例，再修改默认值；原生合成用例查看已提交目标前显式关闭条件，不删除原有导航覆盖。13项聚焦回归、完整Rust/Shell、七包1332项Flutter测试及FRB零漂移通过，macOS重建后实际确认默认只显示未提交作业。

## 2026-10-23：移除作业卡片悬停文字

按用户要求移除 SPOC/希冀共享 `AssignmentCard` 外层的“查看作业详情”Tooltip，保留 InkWell 背景反馈及原typed点击导航。纯展示修改，复用既有19项展示/导航聚焦测试；测试和原生合成脚本改为定位卡片，不再依赖提示文案，没有增加文案缺席或Widget数量断言。完整Rust/Shell、七包1332项Flutter测试及分析、FRB零漂移通过。macOS Debug已重建并打开，截图不纳入仓库。

## 2026-10-23：SPOC本地筛选与旧版对齐

SPOC与希冀共用日期、搜索、排序及Material控件，显式保留默认状态和开关联动差异。SPOC默认不限制提交状态，未提交与已截止条件独立，不新增网络筛选或历史读取。移除手输编号查询入口并改为按课程连续展示，来源和覆盖替换见[实施记录](spoc-list-filters-2026-10-23.md)。

## 2026-10-23：希冀列表恢复旧版展示筛选

默认仅未完成、隐藏已截止、截止时间升序，按课程连续展示。删除批量选择和手输查询面板；搜索、排序与状态筛选均在本地完成。历史范围通过独立按钮显式加载，避免反复切换筛选触发读取。来源、覆盖替换与当前验证见[实施记录](judge-list-filters-2026-10-23.md)。

## 2026-10-15：按行为价值整理测试与执行范围

按用户授权删除自证和重复断言，合并场景时保留独立安全断言；视觉基准按真实布局选代表。日常检查按改动及本地依赖传播，未知情况全量；CI 完整确定性门禁保留。Core 默认配置维持编译/文档和关闭态边界，共享单元只执行一次。具体删减映射和反例见[整理记录](test-value-cleanup-2026-10-15.md)。

## 2026-10-15：全界面文字与信息密度整理

按用户授权删除重复介绍、操作复述与开发术语，必要状态和操作后果使用短句，诊断改为按需展开。保留控制行为及协议，界面投影只改显示名。详见[本轮记录](ui-copy-cleanup-2026-10-15.md)。

## 2026-10-14：登录界面说明精简

按用户当前 macOS 界面检查反馈，删除“密码仅保存在系统安全存储；自动登录决定是否自动使用已保存密码。”与连接模式菜单顶部“尚未读取；这里设置登录与后续查询的默认策略。”。保留选项、路线选择和安全存储不可用时的状态提示。本次仅修改展示，不涉及认证协议、读取行为或冻结来源裁决。

复用既有登录回归用例，将说明断言改为不显示；修改实现前运行该用例，因密码说明仍存在而按预期失败。实现后同文件 6 项测试通过，同步更新原生合成流程的旧说明断言（本轮未运行原生合成流程）。`just refs`、`just check-sensitive`、`just check` 和 macOS Debug 构建通过；完整门禁首次因本机固定开发工具缺失退出，显式执行 `just quality-tools-bootstrap` 后重跑通过。更新后的应用已沿用本次独立配置目录重新启动，界面由用户继续检查。

## 2026-10-07：独立工程审查后的边界修复

用户已授权按[独立审查](engineering-quality-independent-review-2026-10-07.md)完整修复。先将确定性反例纳入正式测试，再处理原子路线、认证完成/迟到状态、损坏偏好和验证工具；保留公开数据语义、唯一写协调器与原工作树。真实账号验证和发布不属于本轮范围，详见[当时阶段目标](history/goal-before-quality-2026-10-11.md)。来源裁决与最终结果分别在本轮专项矩阵和实施记录中登记。

## 2026-10-07：可持续开发性审查

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-10-07可持续开发性审查)

## 2026-09-17 安全材料和缓存密钥接线

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-17-安全材料和缓存密钥接线)

## 2026-09-17 所需路线恢复边界

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-17-所需路线恢复边界)

## 决策记录

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#决策记录)

## 2026-09-17：围绕用户任务设计本地首页与立即恢复登录

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-17围绕用户任务设计本地首页与立即恢复登录)

## 2026-09-17：首页按展示来源加载

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-17首页按展示来源加载)

## 2026-09-17：冻结 buaa-api 引用更新至最新上游

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-17冻结-buaa-api-引用更新至最新上游)

## 2026-09-17 课堂签到追加修复

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-17-课堂签到追加修复)

## 2026-09-17：整理时校正签到历史描述

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-17整理时校正签到历史描述)

## 2026-09-17：冻结旧版引用更新至最新上游并收纳至 examples/

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-17冻结旧版引用更新至最新上游并收纳至-examples)

## 2026-09-07：贯通安全错误诊断并保持既有业务权威

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-07贯通安全错误诊断并保持既有业务权威)

## 2026-09-07：修复 macOS 沙箱主动联网权限

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-07修复-macos-沙箱主动联网权限)

## 2026-09-05：将既有视觉基线的宿主条件显式纳入 CI

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-05将既有视觉基线的宿主条件显式纳入-ci)

## 2026-09-05：Just dry-run 输出通道的版本兼容性

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-05just-dry-run-输出通道的版本兼容性)

## 2026-09-05：固定 Flutter 冷启动下载进度的输出合同

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-05固定-flutter-冷启动下载进度的输出合同)

## 2026-09-05：最终候选 CI 的工具链输出与 Windows 文件身份问题

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-05最终候选-ci-的工具链输出与-windows-文件身份问题)

## 2026-09-05：Phase 12 UI 机械拆分与 Core 入口归属

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-05phase-12-ui-机械拆分与-core-入口归属)

## 2026-09-05：Phase 11K 单一写入状态与会话生命周期所有权

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-05phase-11k-单一写入状态与会话生命周期所有权)

## 2026-09-05：Phase 11J 评教 fresh typed 批量提交与逐课程结果边界（来源合同已固定）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-05phase-11j-评教-fresh-typed-批量提交与逐课程结果边界来源合同已固定)

## 2026-09-05：Phase 11I 阳光打卡 typed 资格与单次最终提交边界（本地确定性门禁完成）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-05phase-11i-阳光打卡-typed-资格与单次最终提交边界本地确定性门禁完成)

## 2026-09-04：Phase 11H 场馆取消双 fresh authority 与最终单次发送边界（当前有效）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-04phase-11h-场馆取消双-fresh-authority-与最终单次发送边界当前有效)

## 2026-09-04：Phase 11G 场馆预约 typed 资格与最终单次发送边界（当前有效）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-04phase-11g-场馆预约-typed-资格与最终单次发送边界当前有效)

## 2026-09-04：Phase 11F 图书馆取消 typed 资格与单次发送边界（当前有效）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-04phase-11f-图书馆取消-typed-资格与单次发送边界当前有效)

## 2026-09-04：Phase 11E 图书馆预约 typed 资格与发送边界（当前有效）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-04phase-11e-图书馆预约-typed-资格与发送边界当前有效)

## 2026-09-04：Phase 11D 课堂签到 typed 资格与发送边界（当前有效）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-04phase-11d-课堂签到-typed-资格与发送边界当前有效)

## 2026-09-04：CLI JSON envelope 显式升级为 schema v3（Phase 11C 历史决策；已由 v4 取代）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-04cli-json-envelope-显式升级为-schema-v3phase-11c-历史决策已由-v4-取代)

## 2026-09-03：Phase 11 typed 写资格的来源边界（当前有效）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-03phase-11-typed-写资格的来源边界当前有效)

## 2026-09-02：MethodChannel 平台能力合同（当前有效）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-02methodchannel-平台能力合同当前有效)

## 2026-09-02：无签名平台能力边界与宿主全功能 smoke（当前有效）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-02无签名平台能力边界与宿主全功能-smoke当前有效)

## 2026-09-02：无签名执行目标取代正式发布门禁（当前有效）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-02无签名执行目标取代正式发布门禁当前有效)

## 当前有效性说明（2026-08-31）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#当前有效性说明2026-08-31)

## 2026-08-31：Cgyy WebVPN 网关 Cookie 同步证据

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-31cgyy-webvpn-网关-cookie-同步证据)

## 2026-08-31：HAR 修复后的 Cgyy 双路线重跑（历史快照）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-31har-修复后的-cgyy-双路线重跑历史快照)

## 2026-08-31：最新 Core-live 实时复核处于图书馆非营业时间

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-31最新-core-live-实时复核处于图书馆非营业时间)

## 2026-08-31：Cgyy 路线与 Core-live 真实验证边界校正

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-31cgyy-路线与-core-live-真实验证边界校正)

## 2026-08-29：用户授权 Cgyy Rust CLI 读写探针及提交落库时序

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29用户授权-cgyy-rust-cli-读写探针及提交落库时序)

## 2026-08-29：继续对齐 Cgyy 业务会话、信封和 Direct 路由

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29继续对齐-cgyy-业务会话信封和-direct-路由)

## 2026-08-17 至 2026-08-29：已归档历史决策摘要

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-17-至-2026-08-29已归档历史决策摘要)

## 2026-08-28：场馆预约的 WebVPN 策略必须保留直连业务域（已被 2026-08-31 决策取代）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-28场馆预约的-webvpn-策略必须保留直连业务域已被-2026-08-31-决策取代)

## 2026-08-28 Cgyy 门锁码实时证据

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-28-cgyy-门锁码实时证据)

## 2026-08-28 WebVPN 全量只读证据

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-28-webvpn-全量只读证据)

## 2026-08-29 全量只读复测

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-全量只读复测)

## 2026-08-29 Cgyy 单项复测

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-cgyy-单项复测)

## 2026-08-28 Cgyy WebVPN 路线冲突

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-28-cgyy-webvpn-路线冲突)

## 2026-08-28 Cgyy 直连 URL 复测

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-28-cgyy-直连-url-复测)

## 2026-08-28 只读矩阵复测

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-28-只读矩阵复测)

## 2026-08-28 WebVPN 逐项复测

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-28-webvpn-逐项复测)

## 2026-08-29 逐操作验证器扩展与三路线复测

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-逐操作验证器扩展与三路线复测)

## 2026-08-29 用户独立只读验收

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-用户独立只读验收)

## 2026-08-29 Bykc 已选课程包装修复

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-bykc-已选课程包装修复)

## 2026-08-29 Bykc 修复后全量实时矩阵

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-bykc-修复后全量实时矩阵)

## 2026-08-29 Direct Judge/Cgyy 单项复测

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-direct-judgecgyy-单项复测)

## 2026-08-29 WebVPN Cgyy 直连业务 transport 复测

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-webvpn-cgyy-直连业务-transport-复测)

## 2026-08-29 Judge 路线复测更新

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-judge-路线复测更新)

## 2026-08-29 Direct Judge/Cgyy 复测收敛

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-direct-judgecgyy-复测收敛)

## 2026-08-29 Cgyy 验证器逐操作不中断

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-cgyy-验证器逐操作不中断)

## 2026-08-29 Cgyy 三路线逐操作复测

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-cgyy-三路线逐操作复测)

## 2026-08-29 Cgyy 日期窗口排除复测

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-cgyy-日期窗口排除复测)

## 2026-08-29 锁码 CLI 脱敏边界

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-锁码-cli-脱敏边界)

## 2026-08-29 Cgyy 最新三路线波动

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-cgyy-最新三路线波动)

## 2026-08-29 锁码投影后三路线复测

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-锁码投影后三路线复测)

## 2026-08-29 三路线全量复测更新

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-三路线全量复测更新)

## 2026-08-29 当前轮三路线全量验收

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-当前轮三路线全量验收)

## 2026-08-29 Cgyy 用途类型回退修复

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-cgyy-用途类型回退修复)

## 2026-08-29 Cgyy 回退后 Direct 全量复测

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-cgyy-回退后-direct-全量复测)

## 2026-08-29 Cgyy 回退后 WebVPN/auto 全量复测

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-cgyy-回退后-webvpnauto-全量复测)

## 2026-08-29 用途回退后 WebVPN/auto 全量复测

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-用途回退后-webvpnauto-全量复测)

## 2026-08-29 Cgyy 成功信封代码严格校验

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-cgyy-成功信封代码严格校验)

## 2026-08-29 Cgyy 日期槽位排序

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-cgyy-日期槽位排序)

## 2026-08-29 Cgyy 三路线逐操作复测（二）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-cgyy-三路线逐操作复测二)

## 2026-08-29 三路线全量只读复测

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-三路线全量只读复测)

## 2026-08-29 Cgyy 场馆包装展开

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-cgyy-场馆包装展开)

## 2026-08-29 LibBook 座位排序

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-libbook-座位排序)

## 2026-08-29 LibBook 预约总数回退

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-libbook-预约总数回退)

## 2026-08-29 LibBook 分区编号回退

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-libbook-分区编号回退)

## 2026-08-29 Bykc 签到配置严格解析

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-bykc-签到配置严格解析)

## 2026-08-29 Ygdk 记录时间戳

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-ygdk-记录时间戳)

## 2026-08-29 Ygdk 记录图片字段

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-ygdk-记录图片字段)

## 2026-08-29 Ygdk 数字字符串时间戳

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-ygdk-数字字符串时间戳)

## 2026-08-29 LibBook 原语字段兼容

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-libbook-原语字段兼容)

## 2026-08-29 三路线全量只读复测（二）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-三路线全量只读复测二)

## 2026-08-29 Cgyy 原语字段兼容

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-cgyy-原语字段兼容)

## 2026-08-29 Signin 写响应状态兼容

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-signin-写响应状态兼容)

## 2026-08-29 Evaluation 任务 `yhdm` 身份来源

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-evaluation-任务-yhdm-身份来源)

## 2026-08-29 Ygdk 文本原语

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-ygdk-文本原语)

## 2026-08-29 Evaluation 文本原语

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-evaluation-文本原语)

## 2026-08-29 三路线逐操作实时证据

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-三路线逐操作实时证据)

## 2026-08-29 认证资料持久化冲突

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-认证资料持久化冲突)

## 2026-08-29 三路线逐操作实时复测（认证领域拆分后）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-三路线逐操作实时复测认证领域拆分后)

## 2026-08-29 认证领域拆分后实时只读矩阵

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-认证领域拆分后实时只读矩阵)

## 2026-08-29 Direct 全量验证的聚合登录边界

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-direct-全量验证的聚合登录边界)

## 2026-08-29 WebVPN/auto 全量实时复测

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-webvpnauto-全量实时复测)

## 2026-09-03 Ygdk 路线状态失效代数

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-03-ygdk-路线状态失效代数)

## 2026-09-03 Ygdk OAuth 跳转主机约束冲突

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-03-ygdk-oauth-跳转主机约束冲突)

## 2026-09-03 Bykc 认证失效重试差异

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-03-bykc-认证失效重试差异)

## 2026-09-08 全功能 UI/UX 重设计执行合同

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-08-全功能-uiux-重设计执行合同)

## 2026-09-08 UI/UX 执行阶段的设计与证据裁决

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-08-uiux-执行阶段的设计与证据裁决)

## 2026-09-08：P3B 原生方向与系统键盘证据

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-08p3b-原生方向与系统键盘证据)

## 2026-09-08：B1 读取归属与学业信息层级

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-08b1-读取归属与学业信息层级)

## 2026-09-08：B2 查询选项隔离与主要信息同时可见

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-08b2-查询选项隔离与主要信息同时可见)

## 2026-09-08：统一账号资料保真与默认遮罩设计（待P4-A实施）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-08统一账号资料保真与默认遮罩设计待p4-a实施)

## 2026-09-08：P4-A 资料本地状态与清除确认生命周期

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-08p4-a-资料本地状态与清除确认生命周期)

## 2026-09-08：P4-C 课程归属、全局进度与选择状态

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-08p4-c-课程归属全局进度与选择状态)

## 2026-09-08：按用户要求以旧版UI为优化基准

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-08按用户要求以旧版ui为优化基准)

## 2026-09-08 O1/O2 旧版导航与按需查询

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-08-o1o2-旧版导航与按需查询)

## 2026-09-09 O3-E1考试时间线与签到横卡

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-09-o3-e1考试时间线与签到横卡)

## 2026-09-09：O3-E2a成绩继承与缓存边界

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-09o3-e2a成绩继承与缓存边界)

## 2026-09-09 O3-E2b：成绩变化派生基线与旧首页横幅

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-09-o3-e2b成绩变化派生基线与旧首页横幅)

## 2026-09-09 O3-D1c：不将可空父字段当只读导航资格

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-09-o3-d1c不将可空父字段当只读导航资格)

## 2026-09-09 O3-E3a：恢复旧空教室表格和查询能力

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-09-o3-e3a恢复旧空教室表格和查询能力)

## E3b课表布局决定（2026-09-09，实施前）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#e3b课表布局决定2026-09-09实施前)

## O3-E3b局部终态（2026-09-09）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#o3-e3b局部终态2026-09-09)

## E3c自然周次入口决定（2026-09-09，实施前）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#e3c自然周次入口决定2026-09-09实施前)

## E3c 验收裁决（2026-09-09）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#e3c-验收裁决2026-09-09)

## E4 登录与账号复核（2026-09-09）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#e4-登录与账号复核2026-09-09)

## P5-A 统一确认的交互裁决（2026-09-09）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#p5-a-统一确认的交互裁决2026-09-09)

## P5-B 研讨室表单裁决

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#p5-b-研讨室表单裁决)

## P5-D 阳光独立表单实施前核对（2026-09-10）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#p5-d-阳光独立表单实施前核对2026-09-10)

## P4-E5 关于入口实施前核对（2026-09-10）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#p4-e5-关于入口实施前核对2026-09-10)

## P5-F Android旧版拍照恢复前核对（2026-09-12）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#p5-f-android旧版拍照恢复前核对2026-09-12)

## 暂停目标并保存工作区（2026-09-14）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#暂停目标并保存工作区2026-09-14)

## UI验收媒体改为仓库外保存（2026-09-14）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#ui验收媒体改为仓库外保存2026-09-14)

## 2026-09-21：离线首页缓存分阶段接入与 Bridge v10/v11

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-21离线首页缓存分阶段接入与-bridge-v10v11)

## 2026-09-22：持久渐进读取与共享锁调度边界

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22持久渐进读取与共享锁调度边界)

## 2026-09-22：按目标调度恢复与一次性只读计划重建

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22按目标调度恢复与一次性只读计划重建)

## 2026-09-22：精确查询缓存不等待认证

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22精确查询缓存不等待认证)

## 2026-09-22：学业持久范围与发布错误优先级

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22学业持久范围与发布错误优先级)

## 2026-09-22：学业缓存展示与出分观察分离

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22学业缓存展示与出分观察分离)

## 2026-09-22：首页待办持久 DTO 与可选读取完成信息

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22首页待办持久-dto-与可选读取完成信息)

## 离线首页 P4-E：展示证据与实时操作分离（2026-09-22）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页-p4-e展示证据与实时操作分离2026-09-22)

## 离线首页 P4-F：博雅安全持久投影（2026-09-22）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页-p4-f博雅安全持久投影2026-09-22)

## 离线首页 P4-G：博雅补充来源与写后回读分流（2026-09-22）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页-p4-g博雅补充来源与写后回读分流2026-09-22)

## 离线首页审查修正：禁止缓存 DTO 绕过 Bridge 白名单（2026-09-22）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页审查修正禁止缓存-dto-绕过-bridge-白名单2026-09-22)

## 离线首页 P4-H：研讨室兼容回退不是完整更新（2026-09-22）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页-p4-h研讨室兼容回退不是完整更新2026-09-22)

## 离线首页 P4-I：研讨室部分结果、缓存页面与回读边界（2026-09-22）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页-p4-i研讨室部分结果缓存页面与回读边界2026-09-22)

## 离线首页 P4-J：图书馆兼容空值不等于完整刷新（2026-09-22）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页-p4-j图书馆兼容空值不等于完整刷新2026-09-22)

## 离线首页 P4-K：图书馆持久展示与实时资格分流（2026-09-22）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页-p4-k图书馆持久展示与实时资格分流2026-09-22)

## 离线首页 P4-L：保存拒绝与展示拒绝必须分别成立（2026-09-22）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页-p4-l保存拒绝与展示拒绝必须分别成立2026-09-22)

## 离线首页 P4-M：评教容错结果与完整快照分开（2026-09-22）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页-p4-m评教容错结果与完整快照分开2026-09-22)

## 离线首页 P4-N：评教进度与提交资格分别恢复（2026-09-22）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页-p4-n评教进度与提交资格分别恢复2026-09-22)

## 离线首页 P4-O：阳光分类与分页必须同时归属（2026-09-22）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页-p4-o阳光分类与分页必须同时归属2026-09-22)

## 离线首页 P4-P：概览统计与记录页分开取证（2026-09-22）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页-p4-p概览统计与记录页分开取证2026-09-22)

## 离线首页 P4-Q：资料展示缓存不等于认证身份（2026-09-22）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页-p4-q资料展示缓存不等于认证身份2026-09-22)

## 离线首页 P4-R：展示副本不替代身份，页面归属不使用遮罩文本（2026-09-22）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页-p4-r展示副本不替代身份页面归属不使用遮罩文本2026-09-22)

## 离线首页 P4-S：清理必须终止旧读取链的重新取票（2026-09-22）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页-p4-s清理必须终止旧读取链的重新取票2026-09-22)

## 2026-09-22 P4-T：管理句柄移交与宿主调用链代际

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22-p4-t管理句柄移交与宿主调用链代际)

## 2026-09-22 P4-U：仅清理缓存不复用退出流程

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22-p4-u仅清理缓存不复用退出流程)

## 2026-09-22 P4-V：压力时动态保留，而非永久发布优先级

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22-p4-v压力时动态保留而非永久发布优先级)

## 2026-09-22 P4-W：显式重建与数据库身份隔离

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22-p4-w显式重建与数据库身份隔离)

## 2026-09-22 P4-X：统计集合先交付本地，更新结果另行完成

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22-p4-x统计集合先交付本地更新结果另行完成)

## 2026-09-22 P2-F：账号库打开不使用页面读取代次

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22-p2-f账号库打开不使用页面读取代次)

## 2026-09-22 P4-Y：完整导入独立保留与schema v4

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22-p4-y完整导入独立保留与schema-v4)

## 2026-09-22 P4-Z：逐学期租约与单周读取修订

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22-p4-z逐学期租约与单周读取修订)

## 2026-09-22 P2-G：辅助读同样承担账号冲突关闭责任

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22-p2-g辅助读同样承担账号冲突关闭责任)

## 2026-09-22：P4-AA 整学期导入接入 Bridge 与课表页

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22p4-aa-整学期导入接入-bridge-与课表页)

## 2026-09-22：P4-AB 本地课表索引与日期导航

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22p4-ab-本地课表索引与日期导航)

## 2026-09-22：P4-AC Core关联范围失效与schema v5

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22p4-ac-core关联范围失效与schema-v5)

## 2026-09-22：P4-AD 写提交结果与本地失效分列

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22p4-ad-写提交结果与本地失效分列)

## 2026-09-22：P4-AE 阳光已观察学期与周期隔离

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22p4-ae-阳光已观察学期与周期隔离)

## 2026-09-22：P2-H 前台恢复退避与网络变化提示

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22p2-h-前台恢复退避与网络变化提示)

## 2026-09-22：P2-I 无持久缓存希冀在线计划

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22p2-i-无持久缓存希冀在线计划)

## 2026-09-22：P2-J 无缓存分段生产接线与Bridge v29

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22p2-j-无缓存分段生产接线与bridge-v29)

## 2026-09-22：P5-A 真实App功能证据与性能口径

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22p5-a-真实app功能证据与性能口径)

## 2026-09-22 P2-N 评教真实只读失败分类

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22-p2-n-评教真实只读失败分类)

## 2026-09-23：接续离线首页P2-P与当前候选证据

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-23接续离线首页p2-p与当前候选证据)

## 2026-09-23：部分在线计划的内容稳定性

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-23部分在线计划的内容稳定性)

## 2026-09-23：明确批量详情复用独立持久范围

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-23明确批量详情复用独立持久范围)

## 2026-09-23：只在客户端明确失效时原位替换

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-23只在客户端明确失效时原位替换)

## 2026-09-23：未知结果仅保存最小核对提示

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-23未知结果仅保存最小核对提示)

## 离线首页 P5-B1：原生 iOS 空环境目录修复（2026-09-23）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页-p5-b1原生-ios-空环境目录修复2026-09-23)

## 2026-09-23：P2-S 分段计划复用希冀激活，P5-B 保留失败样本

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-23p2-s-分段计划复用希冀激活p5-b-保留失败样本)

## 2026-09-23：原生日期矩阵的显式时钟装配

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-23原生日期矩阵的显式时钟装配)

## 2026-09-23：P2-T按可见性恢复及严格区分验收范围

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-23p2-t按可见性恢复及严格区分验收范围)

## 2026-09-23：P2-U自动读取按需让位，主动查询共享完整观察

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-23p2-u自动读取按需让位主动查询共享完整观察)

## 2026-09-23：P4-AH将成绩变化基线纳入加密仓库

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-23p4-ah将成绩变化基线纳入加密仓库)

## 2026-09-23：P4-AI 退出保护覆盖本地偏好清理

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-23p4-ai-退出保护覆盖本地偏好清理)

## 2026-09-24：P5-B2完整首页与阶段成本测量边界

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-24p5-b2完整首页与阶段成本测量边界)

## 2026-09-24：P5-B2正式轮次裁决

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-24p5-b2正式轮次裁决)

## 2026-09-24：P2-R显式重建本地首页恢复核对（实施前）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-24p2-r显式重建本地首页恢复核对实施前)

## 2026-10-01：整合现有成果并恢复旧版功能验收

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-10-01整合现有成果并恢复旧版功能验收)

## 2026-09-15：恢复macOS逐按钮核对与安全凭据接线

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-15恢复macos逐按钮核对与安全凭据接线)

## 2026-09-15：完整旧版功能需要的只读接口补齐

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-15完整旧版功能需要的只读接口补齐)

## 2026-09-15：验证码与门锁信息的独立短期显示

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-15验证码与门锁信息的独立短期显示)

## 2026-09-15：博雅完整详情和筛选生命周期

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-15博雅完整详情和筛选生命周期)

## 整合行为裁决与失败回归

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#整合行为裁决与失败回归)

## 2026-10-02：设置真实能力与最新路线选择

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-10-02设置真实能力与最新路线选择)

## 2026-10-02：交互验证码接入当前离线生命周期

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-10-02交互验证码接入当前离线生命周期)

## 2026-10-02：门锁短期页面与独立接口

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-10-02门锁短期页面与独立接口)

## 2026-10-02：GSMIS数据源与时间轴合同

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-10-02gsmis数据源与时间轴合同)

## 2026-10-02：原生按键命中与表单提示避让

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-10-02原生按键命中与表单提示避让)

## 2026-10-02 可见窗口筛选空结果

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-10-02-可见窗口筛选空结果)

## 2026-10-02 空教室正文校区与查询草稿同步

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-10-02-空教室正文校区与查询草稿同步)

## 2026-10-03 空教室已应用条件跨校区复验

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-10-03-空教室已应用条件跨校区复验)

## 2026-10-07：本地分支统一到ubaa2

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-10-07本地分支统一到ubaa2)

## 2026-10-07：应用图标沿用冻结旧版资源

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-10-07应用图标沿用冻结旧版资源)

## 2026-10-07：未确认本机账号时启动必须进入登录页

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-10-07未确认本机账号时启动必须进入登录页)

## 2026-10-07：开发阶段统一安全存储插件

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-10-07开发阶段统一安全存储插件)

## 2026-10-07：通用依赖复用审计

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-10-07通用依赖复用审计)

## 2026-10-07：实施通用依赖收敛

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-10-07实施通用依赖收敛)


## 2026-10-11：F01—F07 的边界修复

依据当前 a0a1736 的实际 CI 失败与故障注入，保留技术栈、严格 lint、CAS 修订及排他锁。Bridge 合同 v41 将生产 open 改为异步，Session 两级锁共用 2 秒预算；初始化错误保留白名单原因。提交发送观察独立于普通收尾，panic 展开不抹去可能发送事实；持久核对提示在 Dart 投影完成后确认。固定路线回读不改全局策略。会话/缓存生命周期分别拥有状态，成绩基线消费统一 scope。

来源与逐操作边界见 [实施前对照](source-parity-quality-2026-10-11.md)，RED/GREEN 与平台记录见 [整改账本](quality-repair-2026-10-11.md)。App Sandbox 保持；原生持锁夹具由外部测试宿主建立，不给产品增加启动子进程权限。源码清单覆盖全部跟踪输入，并将实际产物与作业关联；外部 SDK/系统依赖不伪称源码摘要或可复现证明。


## 2026-10-20：统一加载反馈并保持刷新布局

用户要求将普通加载反馈放回内容区。移除改变内容高度的全局连接条，首次读取用静态骨架，同查询刷新保留已有内容、空状态及滚动位置，进度留在按钮或局部标题；异步出现的成绩学期栏预留原位。旧写入按钮原位禁用，缓存和错误的必要信息继续可见。仅改展示，不改上游协议与业务缓存。失败反例、各页面清单及验证边界见[实施记录](loading-feedback-2026-10-20.md)。


## 2026-10-20：本机 macOS 使用固定开发签名

按用户授权使用本机已有开发证书，解决临时签名随重建改变应用身份的问题。通过被 Git 忽略的本机 Xcode 配置选择身份，原 bundle identifier 与沙盒权限保持；无本机配置的共享默认行为不变。旧钥匙串与容器授权由用户在系统界面确认，不删除数据、不放宽访问控制。两次构建与再次启动的事实见[实施记录](macos-local-signing-2026-10-20.md)。


## 2026-10-21：以成功 HAR 核对 SSO HTTP 跳转

UBAA2 已有有界手动UC激活和最终status校验，但重定向仍原样保留HTTP SSO。用户成功HAR中UC激活经历HTTP Location后使用HTTPS SSO取得ticket；两份冻结源缺少这项显式协议升级。采用实时证据优先规则，计划仅升级精确SSO默认HTTP端口、保留service编码并维持固定路线；实现前完整对照见[来源记录](source-parity-auth-2026-10-21.md)。用户明确不处理中转，不改其配置。

本轮随后确认教务currentUser原校验只依据HTTP200，已用HAR中的字符串code=0、datas.userId及正确最终地址补足成功条件，保留原GSMIS回退；完整反例和两路线真实验证均通过，见[实施记录](auth-repair-2026-10-21.md)。

## 2026-10-23：登录选项悬停样式

用户截图显示登录选项的外层直角矩形与复选框圆形悬停背景叠加。按用户确认的方向，保留整组选项的悬停反馈，使用 12 像素圆角与主题主色 4% 不透明度，文字末端增加 12 像素留白；复选框自身的状态背景始终透明、圆形反馈半径为零，并由外层整行统一接收鼠标和键盘输入，避免复选框与文字之间切换时出现圆形闪烁。整行保留键盘焦点、按压反馈和禁用逻辑。仅改展示样式，复用账号领域已有的点击单次派发、禁用、窄窗大字等 12 项测试，复选框点击测试改为点击其中心坐标，继续验证实际命中外层后的单次派发与禁用行为，未删除覆盖。未新增样式自证断言，也未发起真实学校请求。

首版重启后用户曾观察到背景残留，随后自行恢复，未确定原因；不将该现象记作已修复。

验证：`just check-changed` 因既有未跟踪 `.serena/` 输入而保守选择完整门禁，Rust/Shell、七包 1326 项测试和 FRB 零漂移通过。最终反馈调整后另跑账号领域 12 项测试及 UI 分析/格式检查通过；macOS Debug 已重建并打开，最终鼠标视觉效果交由用户继续预览。`.serena/` 未纳入本轮提交。

## 2026-10-23：共享 Material 交互反馈统一

按用户要求全面排查后，选择共享主题统一悬停/焦点色、选项控件背景、列表行圆角及卡片裁剪，仅特殊点击区域局部调整。不引入第三方 UI 库、不重写官方选项控件，不将独立图标按钮的圆形反馈视为缺陷。已复现卡片越界反例；官方选项行的基线实验未普遍复现双层背景，作为样式统一处理。完整清单、验证与后续独立控件维护规则见[交互审计](interaction-feedback-2026-10-23.md)。

## 2026-10-23：希冀业务获取按当前官网与真实观察修复

实施前核对发现冻结旧版和 UBAA2 均沿用 HTTP Judge service，而当前公开登录页实际链接 HTTPS service；用户引用聊天的真实调查还确认整课历史排除和 WebVPN 共享课程状态会丢失或串课。本轮按来源优先级采用官网 HTTPS service，原生登录页拒绝为空列表，取消批量整课排除并对 WebVPN 课程任务串行；重新认证后恢复选课。另一冻结源不实现 Judge 协议，明确不借用 SPOC 参数。逐操作矩阵及具体文件/提交见[实施前对照](source-parity-judge-2026-10-23.md)。

## 2026-10-23：作业详情保留列表父层并沿旧版分区

用户反馈首页进入作业后直接返回功能列表，重进功能又恢复详情。当前 `openFromHome` 清空父栈，功能入口也未恢复根列表；已用两功能4项反例复现。按用户要求保留/补足列表父层，并依冻结旧版的独立列表、分区详情移除通用“更多信息”；希冀不展示整页文本。实施前来源和协议边界见[导航与展示记录](assignment-navigation-2026-10-23.md)。

## 2026-10-23：共享界面布局重构

按用户确认的预览执行五项展示导航与设置式分组，复用 Flutter Material 3 控件和领域页面。改动限制在 UI 和宿主展示接线；预览与方案继续仅本地保留。阶段记录、覆盖迁移和平台证据见[实施记录](ui-layout-2026-10-23.md)。

## 2026-10-23：课表默认下载整学期

按用户要求，将整学期保存入口改为确定学期后的自动下载，右上角刷新固定重跑当前已应用学期的导入。沿用原逐周读取、任务合并、完整保存与取消机制；失败或取消不因重建再次自动请求。保存后从账号与实际路线匹配的本地精确查询更新当前周，保留查询修订与周次，拒绝迟到、错归属或不完整投影；旧 summary 周查询兼容相同行为。实施前双来源核对、差异与验证见[课表下载记录](source-parity-schedule-default-2026-10-23.md)。

## 2026-10-23：课表同步静默化

用户要求后台下载和保存时间对用户隐藏。移除课表常规同步进度、成功和取消状态栏，右上角提示改为“刷新”；失败保留简短错误和重试，空间不足保留可执行的清理提示。课表正文、首页今日课表、学期及教学周选择移除保存时间。底层整学期任务、数据来源、取得时间、完整度与归属校验保持。详情见[课表实施记录](source-parity-schedule-default-2026-10-23.md)。

## 2026-10-24：课表六项布局与交互调整

根据用户校历和应用截图，统一课表与功能列表宽度，去掉突兀周次背景与顶栏重复周次，补齐标准 14 节时间，按课程稳定分配可区分的颜色，并以直接选择学期替换搜索筛选。明确返回的时间优先，原下载、完整保存与归属校验保持。来源、测试调整映射和原生验证见[实施记录](schedule-layout-2026-10-23.md)。

## 2026-10-24：统一转圈加载动画

用户确认以转圈替代各页静态加载占位。采用共享组件统一首次与局部读取，刷新保留已有内容；首页未发起请求的状态和隐藏页面不持续播放动画。具体范围、旧测试适配与验证见[加载动画记录](loading-indicators-2026-10-24.md)。

## 2026-10-24：课表索引只作为选择数据

根据首页入口闪跳反馈，修复自动链提前交付索引页面的问题；按用户补充要求，学期和教学周仅通过选择控件展示，正文直接交付周课表。自动阶段延续到周结果就绪，失败可重试，取消选择继续原自动链。原因、双来源依据及验证见[实施记录](schedule-entry-2026-10-24.md)。

## 2026-10-24：待办独立滚动与常用功能按访问排序

待办改为约两行高度的独立纵向滚动窗口，保留宽屏两列和窄屏单列；常用功能按最近访问去重置顶，最多四项。访问记录通过已有平台偏好能力按账号保存，支持重启恢复、迟到读取隔离与退出清除。回归及原生截图范围见[实施记录](home-window-2026-10-24.md)。

## 2026-10-24：课表低饱和度配色

用户反馈深色课表色块过于鲜艳。共享课表配色的 HSL 饱和度由 0.62 降为 0.24，深色明度由 0.32 降为 0.28，浅色明度由 0.82 提至 0.87。保留按课程分配色相、学期内颜色保持和文字对比度选择。仅调整样式，不改变读取协议、课程数据或交互。

复用现有课程颜色区分、切周保持和文字对比度至少 4.5:1 的回归覆盖，更新两张课表 golden；不新增样式数值自证测试。Golden 用于颜色和布局核对，默认测试字体不能证明中文原生字体显示效果。

验证完成：26 项聚焦回归、`just check-changed`（完整 Rust/Shell、七包 Flutter 分析与测试、FRB 生成零漂移）、敏感扫描通过。macOS Debug 构建与实际签名权限检查通过，沿用当前检查配置重启，实际进入第 7 周课表核对低饱和度色块和中文文字。此次应用显示检查未执行真实协议专项验收。

## 2026-10-24：加载状态与真实错误分离

用户要求加载过程中不显示失败、保存时间及旧数据说明。修复 stale 被无条件当作失败的判断，错误提示只对应实际失败；更新中保留已有内容或显示动画。展示范围、反例及覆盖迁移见[实施记录](read-feedback-2026-10-24.md)。

## 2026-10-24：成绩学分格式化去除浮点尾数

用户截图中总学分出现 `23.700000000000003`。领域统计按课程累加 double，UI 的非整数分支直接调用 `toString()`，将二进制浮点尾数交付到屏幕。共享成绩数字展示改为最多两位小数并去除末尾无意义的零，保留缺失值占位与有效小数；总学分、单门课程学分和平均分共用，GPA 原有两位显示保持。原始学分、合计与绩点算法及学校读取协议均不修改。

用真实计算的合成反例 `23.5 + 0.1 + 0.1` 和 `0.1 + 0.2` 复现，修改前两项显示断言失败；另覆盖整数 `3` 和两位小数 `0.75`，修改后成绩聚焦测试通过。`just check-plan` 因原有未跟踪 `.serena/` 建议全量，本轮按实际 UI 影响执行共享 UI、宿主与官方应用检查，保留该目录原样。

验证：共享 UI 375、宿主 101、官方应用 79 项测试，共 555 项通过，三包格式与静态分析通过；引用、结构与敏感扫描通过。macOS 正式 Debug 已重建并按独立检查配置打开。本轮无学校请求协议或统计算法变更，也未重新核对真实成绩来源。

## 2026-10-24：首页待办投影按依赖复用

仅复用当前 HomeView 的未变化投影，依赖包含快照、补充结果、加载状态、分钟与提醒设置。保留账号生命周期和动态资格来源；不改网络协议与并发调度。合成基准及收益限制见[实施记录](home-performance-2026-10-24.md)。

## 2026-10-24：博雅上游统计与阳光留空输入

当前统计解析误用了应用 DTO 字段，采用冻结 LocalBykcApi 的 validCount/statistical 映射修复；buaa-api 同样证明嵌套统计结构，但其固定类别编号不适合旧版动态分类。阳光默认值在表单继续时补齐，保持现有明确写意图、资格检查和最终确认，不改公开跨语言合同。参见 [逐项来源与验证](source-parity-statistics-defaults.md)。

## 2026-10-24：统一功能页宽度与空教室夜间配色

移除空教室独有的 1600 宽度，所有正常功能页共用 1040 最大宽度；同步统一检出的正文、选择条、概要和分页边距。空闲格子按明暗主题使用柔和绿色，去掉鼠标悬停文字，保留无障碍说明与详情点击。逐页检查及验证见[实施记录](classroom-width-2026-10-24.md)。

## 2026-10-24：希冀同课程选课去重

以 runtime 私有的已确认课程和 Judge 代次复用选课，保留分批让位、WebVPN 串行与 Direct worker 隔离；错误及状态转换使记忆失效，完整索引和详情继续读取。双源差异、RED/GREEN 与真实只读测量见[实施记录](source-parity-judge-performance-2026-10-24.md)。

## 2026-10-24：紧凑侧栏间距

600–999 逻辑像素窗口原来只展开选中项的文字，导航项高度随选中状态变化；关于入口紧接主导航。紧凑侧栏改用固定图标布局，每项上下各增加 8 逻辑像素留白，悬停显示完整名称，保留导航标签的无障碍语义；设置和关于入口固定在底部，设置保留选中状态，上方四个主导航入口保持可滚动。

本轮属于展示调整，复用导航断点、分组切换、大字和状态测试；原断点测试的选中标签样式断言更新为图标布局，业务与无障碍操作覆盖保留。影响范围检查通过：UI 380 项、宿主 101 项、应用 79 项测试，以及引用、敏感、布局、模块检查。设置移到底部后另跑最终聚焦 30 项测试与 UI 静态分析，全部通过。macOS Debug 构建、产物结构和签名权限检查通过；当前 800 逻辑像素宽窗口已目视确认四项等距导航及底部设置/关于，并实际打开设置、关于后返回首页。

## 2026-10-25：图书馆座位自动加载

按冻结旧版移除预约页搜索筛选，默认采用逐日 DTO 中首日首时段自动加载，只展示 status=1 的座位。保留原缓存只读与 typed 写入校验。双源比较、失败反例及覆盖迁移见[来源记录](source-parity-libbook-auto-seats-2026-10-25.md)。

## 2026-10-25：新增 iHome 的补充来源

用户请求移植更新后的旧版 iHome。两份冻结源尚无 iHome；采用本机旧版仓库已提交实现作为补充证据，冻结目录不变。逐操作协议、支持范围和验收记录见 [iHome 来源对照](source-parity-ihome-2026-10-25.md)。保留既有图书馆未提交工作。

## 2026-10-25：iHome 详情原位展开

按用户反馈，诉求与公告详情在当前列表卡片内展开/收起，支持和关注操作放到卡片底部，移除常驻路线小字。保留列表筛选、滚动上下文、确认路线及未知结果回读；同一诉求的多个评价卡片共享最新操作状态。协议沿用已验证实现，来源与本轮验证见 [iHome 记录](source-parity-ihome-2026-10-25.md#2026-10-25列表内详情与操作调整)。


## 2026-10-25：iHome 紧凑图标操作

用户要求采用旧版 iHome 的轻量关注/支持样式。用无边框星标和点赞图标加独立数量替换带文字的大边框按钮，视觉尺寸20，标准点击区域和操作保护保持。来源与验收见 [iHome 样式记录](source-parity-ihome-2026-10-25.md#2026-10-25关注与支持的紧凑样式)。

## 2026-10-25：首页考试待办

按用户要求将考试加入首页默认读取、离线恢复与待办投影。按已安排、有效日期、未结束判断，开始时间排序；不从说明文字推断日期，也不以 examStatus 代替安排状态。旧版与独立来源、反例和验证见[来源对照](source-parity-home-exams-2026-10-25.md)。


## 2026-10-25：iHome 正文选择复制与固定回复位置

按用户要求，列表直接显示完整诉求和全部回复，使用可选择文本并移除正文点击区域。查看详情只在底部添加处理进度，详情响应不替换列表正文或移动回复。操作状态仍使用已有详情回读结果，关注/支持保护不变。验证见 [iHome 记录](source-parity-ihome-2026-10-25.md#2026-10-25全文显示与选择复制)。

## 2026-10-25：刷新汇总与统一手势

图书馆刷新顺序重读父汇总到当前座位，保留有效父项和日期时段。移动端下拉使用同一页顶栏刷新回调，空/错误展示采用可滚动容器，忽略横向与内嵌纵向通知。请求合并限定当前账号/路线，写入确认和门锁原刷新边界保持。依据和验证见[刷新记录](refresh-2026-10-25.md)。

## 2026-10-25：预约座位页面去重

移除正文中与选中项重复的馆名和分区名，取消座位列表标题和可预约卡片重复的空闲文字；单一日期与时段合并为一行，多项选择不重复显示已选值。选座摘要中名称与编号相同时只显示一次。资格未确认、不可预约、空结果和错误提示保留。仅修改展示，复用既有地图、缓存、选择、刷新及写入确认回归，未新增固定文案缺席或 Widget 数量测试。聚焦 36 项与按范围三包 608 项测试通过，格式、静态分析、引用、敏感、布局和模块检查通过。macOS Debug 已重建并实际查看精简后的预约页；没有准备或提交真实预约。

## 2026-10-25：中性表面与蓝色强调

按用户要求查阅成熟设计系统，采用 Fluent 2 中性色层次与克制品牌色原则，通过现有 Material 3 角色实现浅深主题。首页来源、普通状态和日期改为中性色，保留选中状态、主操作及业务语义。颜色依据、映射和验收见[配色记录](../design/color-system-2026-10-25.md)。

## 2026-10-25：加强图标蓝主题表达

用户反馈中性灰方案偏灰，要求采用图标同色。以图标资源的主色 #1976D2 统一品牌种子与浅色强调色，让侧栏、功能图标、来源标签和时间承担主题表达；来源与普通状态分开设置强调级别。依据、配色和验证见[配色记录](../design/color-system-2026-10-25.md)。

## 2026-10-25：首页预览与功能磁贴

按用户确认实施五项界面改动：待办去外框、图标并入来源、四项预览与原位展开、功能磁贴以及正式 macOS 窗口标题。整页滚动替代待办嵌套滚动，完整列表继续使用当前数据与操作回调。失败反例、旧断言保留覆盖和验收见[实施记录](../design/home-layout-2026-10-25.md)。

## 2026-10-25：首页日程与临近待办

首页仅保留真实最近使用记录。沿原待办投影增加相对日期和临近 48 小时提示；按真实教学周和完整时间区间显示课程状态，全部结束后以既有周课表读取明日，跨午夜保持日期归属。单日读取按账号、路线、代次和日期隔离，优先完整本地结果，刷新强制线上；未知或不完整信息不推断无课。源比较、反例、缓存隔离与原生／真实只读验收见[实施记录](source-parity-home-calendar-2026-10-25.md)。


## 2026-10-26：研讨室预约卡片与取消确认

用户反馈“我的预约”卡片中的详情按钮过大、状态过小、操作位于左下且“准备取消订单”含义不清。宽屏调整为左侧地点、时间、主题和活动类型，右侧状态标签及详情／取消文字按钮。状态与活动类型采用 bodyMedium，状态加粗；窄屏和放大字体时按内容换行，操作保持右对齐，保留默认按钮点击区域。

复读冻结 `examples/ubaa_old` 的 `CgyyOrdersScreen.kt`：旧版使用“查看详情／取消预约”小型操作、加粗状态和地点时间优先的信息顺序。本次依照用户要求改为右侧操作。详情仍使用原 typed 导航；读取协议、参数、字段和分页不变，沿用 [预约来源记录](source-parity-ui-reservations.md) 的来源边界。

原取消确认使用整页视图，本次仅为研讨室取消改为列表上方的模态弹窗，按钮为“保留预约／确认取消”。准备、一次性提交、固定路线核对和未知结果处理继续由现有 WriteCoordinator 执行。背景阻止指针、键盘和无障碍访问；保留预约、Escape 与系统返回统一丢弃待确认意图。提交、丢弃和核对期间禁止重复动作；确认过期仍禁止提交。没有执行真实预约或取消。

失败反例：原实现无法在 AlertDialog 中找到确认操作，且原预约卡片被隐藏，记录于 `<private-evidence>/legacy-tmp/ubaa2_cgyy_cancel_red.log`。修复后，原资格／双回读／未知结果用例继续通过，增加保留预约与 Escape、关闭等待、提交与回读等待、窄屏双倍字体的交互覆盖。既有测试仅更新实际按钮定位，原 typed 目标与未知结果断言保留。`just check-changed` 通过冻结引用、敏感扫描、目录／模块检查与三包静态分析及 634 项测试（UI 455、Host 101、App 78）。研讨室 macOS 原生合成套件 22 项通过，覆盖明暗模式、列表、详情、取消弹窗、刷新和连续追加。另有 macOS 宿主十项写操作矩阵通过，包含研讨室取消的一次提交和订单列表／详情双回读。已通过 Computer Use 检查合成列表的右侧操作、可读状态标签、居中取消弹窗和“保留预约”返回原列表。日常使用的 macOS Debug 应用已重建，通过 `codesign --verify --deep --strict`，并使用原隔离配置启动。实际预约列表已在宽屏窗口核对，保留在“我的预约”页面。运行截图仅用于私有检查，没有加入 Git。

## 2026-10-28：网关探测只接受 10.0.0.0/8 地址

用户在校外使用 iOS 模拟器时发现“自动”仍选择直连。现场观察：本机 Clash Verge（mihomo）启用 fake-ip，`gw.buaa.edu.cn` 解析为 `198.18.0.33`，TCP 连接由本地代理接受，探测因此误判为 `Campus`。冻结 `ubaa_old` 没有校园探测；`examples/buaa-api/src/utils/net.rs` 只做主机端口 TCP 连接，没有地址过滤，两者都不能区分 fake-ip。

按用户要求，探测只尝试解析到 `10.0.0.0/8` 的 IPv4 地址，其余地址（含 IPv6）不尝试；无合格地址为 `OffCampus`，从而解析到 WebVPN。校内解析为 `10.*` 来自用户陈述，本轮在校外，未实地复核；若校内出现非 `10.*` 或仅 IPv6 解析，需要据实时证据扩展。路线矩阵、`unknown_default`、缓存与显式策略不变。失败反例 2 项（fake-ip 不得判为校园网、只尝试 `10.*` 地址）已复现失败并修复。

## 2026-10-28：窄屏底栏压缩至 56pt

用户在 iPhone 17 Pro 模拟器上指出底栏下方空白偏大。原底栏内容高度 80pt，叠加系统底部安全区 34pt 共约 114pt，明显高于 iOS 原生约 83pt。按用户选择将内容高度改为 56pt，字体放大时的增高规则不变。用户随后反馈图标贴近顶边且安全区偏大：顶部增加 8pt 留白，底部安全区最多保留 20pt（Home 指示条约占底部 8–13pt，其上留出视觉间隔），iPhone 17 Pro 上总高度约 84pt；安全区小于 20pt 的设备保持系统值。纯样式改动，复用既有导航覆盖，未新增固定数值断言；已热重载核对选中胶囊与标签未被裁切；按用户要求，慢门禁延后至提交前运行。

## 2026-10-28：路线入口收归设置、手机端改下拉刷新

用户认为路线信息无需逐页呈现：正常情况下各功能同一时刻解析出同一路线，逐项清单只在网络切换间隙出现差异。删除顶栏与研讨室／阳光打卡表单的“实际路线”图标、连接路线弹窗及仅供其汇总的首页／成绩路线回调；路线策略只在设置“连接模式”中以带说明的单选列表切换。Core 路线解析、诊断元数据与 `resolvedRoute` 投影不变，仅不再在页面展示。

刷新改为平台区分：iOS/Android 隐藏首页、功能页与 iHome 的刷新按钮，统一使用已有下拉刷新；macOS/Windows/Linux 因鼠标无法下拉保留按钮，并新增 ⌘R／Ctrl+R。研讨室门锁码与活动类型等局部刷新不受影响。

## 2026-10-28：研讨室活动类型改为底部选择

用户指出活动类型固定且不应手填。表单中改为与其他输入框一致的“活动类型”选择栏，点开底部列表，括号内示例拆为副标题，当前项打勾。删除“刷新活动类型”“手动填写用途编号”以及“预设／未核对完整”提示；列表仍由原 Core 用途读取（含冻结预设回退）提供，读取失败且无可选项时保留重试。提交仍使用所选用途 key，协议与参数不变。

以上界面调整均已在 iPhone 17 Pro 模拟器热重载核对；未提交真实预约。受影响的旧断言与基准截图按用户要求在提交前统一更新。

## 2026-10-28：研讨室预约查找与填写体验

按用户确认的三项建议实施：
- 时段表默认“只看可预约”，隐藏没有可预约格子的房间与时段列；当天该楼层无空位时提示并可一键显示全部。开关与图例放在“预约研讨室”顶栏右上角，开关状态由主界面持有，切换日期、楼层时保持。日期标签上的空位数需要逐日额外读取，本轮不做，不新增请求。
- 手机端去掉横向标签条的常显滚动条（桌面保留以便鼠标拖动）；切换日期或楼层时保留上一张表并在上方显示细进度条，加载中不显示“无可预约”结论；站点已读出但尚未选中时显示加载而非“暂无时段”。
- 表单标题改为“填写预约信息”并与其他页面同为左对齐和箭头返回；已选时段压成一行；提交校验改为逐项标红并说明缺失内容。

用户要求表单默认保留上一次填写：未改动的输入框以灰字显示上次内容并按原值提交，活动类型与附加选项预选上次值，参与人数无记录时灰字为 1。通过校验进入确认时按账号保存。用户明确选择与普通缓存同等保存，因此使用账号作用域的普通偏好存储（`PreferencesCgyyReservationDefaultsStore`），而非系统安全存储；这是对偏好端口“仅普通 UI 偏好”注释的有意例外。“退出并清除本机数据”同步清除。读取或保存失败只影响默认值，不阻断预约。学校协议、参数与写入流程不变；模拟器已核对筛选、顶栏开关与图例、逐项报错，灰字默认值需一次真实预约后才产生，未在本轮执行真实预约。

## 2026-10-28：界面回归补测与证据顺序

本轮为已修改的设置、刷新入口、预约筛选、缓存加载和表单记忆补写回归测试。除原网关探测反例外，这些行为在本轮接手前已经实现，补测不能证明原迭代的失败状态，不计作当时的测试先行。纯样式复用现有覆盖和菜单基准图。

补测过程中，空用途缺少重试入口和缺失用途未逐项标红分别先用失败反例复现，再补最小修复。旧测试删除与保留覆盖、基准图检查和验证结果见[回归记录](ui-regression-2026-10-28.md)。新增预约记忆存储放入现有 `infrastructure` 目录，以符合目录文件数限制。

### 2026-10-29：独立全平台合成预览入口

新增 `integration_test/manual/preview/preview_driver.dart`，直接装配内存后端，不调用生产 bootstrap。预览后端继承 `CourseworkBackend`，复用各业务公开 typed 合成数据函数，独立维护选退、预约、取消、签到、评教和打卡状态。没有修改 `synthetic/app/flow/inspection*.dart`、`support.dart` 或 `packages/`；工作区原有 `inspection_academic.dart` 改动保留。

学业数据独立生成三个学期、18 周动态校历、14 节作息和两校区空教室。所有身份、课程和记录均为合成内容，没有读取真实账号数据。iHome、个人资料、全部成绩统计与课表同步进度也提供合成实现。入口登记为 manual，覆盖五个 Flutter 原生平台，不加入 CI。

验证中先发现并复现两项预览数据问题：选课 107 后已选列表缺失，以及图书馆取消 action 页码为 0 导致按钮禁用。仓库外临时验证用例分别得到失败后修复，覆盖选退回读、一次性意图、签到、评教、预约取消、两校区、单日课表、同步进度及首错/陈旧/空状态。研讨室取消补齐 `readbackQuery`，模拟器已显示“取消状态已核对”。

iPhone 17 Pro / iOS 26.5 已实际检查首页、课表周视图和学期选择、考试分组、成绩及全部成绩统计、学院路空教室、SPOC 和希冀详情、iHome、图书馆选座与记录、研讨室表格/记录/密码、阳光打卡、博雅列表/详情/已选/统计、签到、评教、设置和个人资料。已通过界面提交博雅选课、签到、评教、iHome 关注、图书馆预约与取消、研讨室预约与取消、阳光打卡。macOS Debug 构建、登录、首页及宽屏空教室学院路/沙河切换通过。新目录静态分析、集成目录登记、敏感扫描、目录检查、完整 `just check` 与 `just flutter-check` 通过。

尚未覆盖：Android、Windows、Linux 的实际构建运行；所有状态模式逐页原生验收；系统通知、桌面组件、定位、真实相册和持久化离线场景；图书馆平面图。iPhone 窄屏的空教室校区和日期选择器受产品代码 `ClassroomContent` 的宽屏条件限制，按任务边界不修改产品代码。两校区数据已通过后端验证。课表同步只模拟内存进度，不宣称完成真实持久化。

### 2026-10-29：手机空教室恢复校区与日期选择

10-27 删除通用查询面板时，记录写明校区、日期改由页内选择器进入，但 `ClassroomContent` 的这些选择器只在宽度不小于 600 时显示，手机因此固定停在默认校区和当天。先把“正文切换校区/日期”测试扩展到 390 宽度，两项失败；随后让所有宽度都显示校区分段按钮。宽屏日期按钮与校区同行，手机日期改为与楼栋芯片同高的按钮并放在楼栋行首。页内重复搜索框移除，关键字统一由外层常驻搜索框过滤。原有同名楼栋和横滚断言限定到表格范围。空教室与学业界面测试 30 项、静态分析通过；iPhone 17 Pro 合成预览实测学院路→沙河切换和日期弹窗正常。

### 2026-10-29：写操作改为一点即完成

用户反馈签到等功能先点“准备××”、再到整页确认页点“确认提交”，步骤多余。核对后确认两步来自 Bridge 的 prepare/commit 一次性意图设计；`UBAA2.md` 要求的确认机制针对 Agent 代为执行，首页签到卡片已有“准备后立即提交”的先例。

界面改为：签到、博雅签到/签退/选课、图书馆预约直接完成；研讨室预约与阳光打卡以表单“提交预约/提交打卡”为确认；博雅退选、图书馆与研讨室取消、评教提交保留一个系统弹窗（“再想想/确认××”），弹窗在 prepare 之前出现。整页 `WriteConfirmationView` 与研讨室取消遮罩从主界面移除，按钮去掉“准备”字样。新增 `_runDirectWrite` 统一 prepare→commit→未消费即 discard，提交期间禁用其他写按钮。Bridge、Core、协调器和 CLI 不变。

先改写 `actions_test.dart` 中签到与博雅两条用例为新预期并观察失败，实施后通过。iPhone 17 Pro 合成预览实测签到、博雅退选、图书馆预约与取消、研讨室取消、评教、阳光打卡均一次完成且弹窗按预期出现。其余依赖确认页的旧测试待适配。

本轮测试适配保留 `WriteConfirmationView` 的公开导出及组件测试。组件仍是公开接口，单独覆盖提交中跨过有效期、过期后禁止提交且允许取消；主界面不再使用组件。各业务测试改为直接核对 prepare/commit 次数、typed 目标和回读上下文。四类不可撤销操作均覆盖“再想想”后不发起 prepare/commit。阳光打卡能力丢失测试把失效时点移到表单提交之前，保留零提交覆盖；提交期间回读能力丢失仍单独验证。

删除的主界面专属用例及保留覆盖如下：

| 删除用例 | 保留或替代覆盖 |
| --- | --- |
| `write/actions_test.dart`：丢弃待确认意图首次失败保留，第二次成功清理；丢弃尚未完成时保留确认页并禁用取消与提交 | `ubaa_app` 协调器原有取消失败、重试和并发覆盖不变；`write/direct_lifecycle_test.dart` 验证过期自动丢弃、再次操作及跨按钮防重入。 |
| `write/confirmation_parity_test.dart`：确认页保留取消返回且不提供侧栏和刷新；确认页系统返回调用取消，忙碌各阶段禁止返回与提交 | 删除确认页专属导航规则；原导航、加载布局测试继续覆盖普通主界面，组件提交中与过期测试保留。 |
| `write/coordination_test.dart`：确认页完全消费宿主写状态并将确认命令交回宿主 | `write/actions_test.dart` 和 `direct_lifecycle_test.dart` 通过真实协调器核对提交、丢弃和防重入；缺少宿主写命令时关闭入口的测试保留。 |
| `features/cgyy/cancellation_test.dart`：保留预约和 Escape 丢弃确认，关闭完成前锁定且保留原卡片；取消确认提交及核对期间阻止重复点击、Escape 和系统返回 | prepare 前的系统弹窗无需丢弃意图。窄屏大字“再想想”验证 prepare、commit、discard 均为零；typed 取消目标、双回读、未知结果和资格限制继续由同文件覆盖。提交防重入由 `direct_lifecycle_test.dart`、图书馆写测试及博雅列表测试覆盖。 |

补测发现立即过期的 intent 未被自动丢弃：prepare 和 confirm 在同一轮异步任务完成时，shell 尚未收到协调器的新 `writeState`，以 widget 中的 intent ID 判断是否清理会遗漏。先运行 `direct_lifecycle_test.dart`，观察 commit 为 0、预期 discard 为 1 而实际为 0；随后仅调整 UI 清理条件，在 confirm 无结果时直接请求协调器取消。相同清理条件用于通用写流程与博雅选退流程，协调器仍负责拒绝无意图或提交中的取消。反例复验通过，第二次操作也能重新 prepare 并清理。Bridge、Core、`ubaa_app`、CLI 和宿主产品代码未修改。

合成图书馆后端改为在内存中记录并消费一次性 intent，日期测试核对完整 canonical 目标与一次提交。集成写流程同步使用系统弹窗及表单提交入口，并补齐活动类型的 typed 合成数据以适配现有选择器。所有数据均为合成测试数据。

现有六张 golden 覆盖菜单、课表、成绩和错误页面，全部比较通过，没有受本次按钮变更影响的基准，因此未重写 PNG；`test/visual/failures/` 不纳入提交。

最终验证：依次执行的 `just refs`、`just layout-check`、`just check-sensitive`、`just check` 与修正残留旧断言后重跑的 `just flutter-check` 均通过。七包静态分析通过，测试分别为 60、93、676、459、20、101、81 项，共 1490 项。完整门禁额外发现宿主确认目标显示断言及应用博雅退选导航断言，均改为新流程并保留状态、请求和返回路径覆盖。本轮未运行原生集成入口，未请求真实学校服务。按产品代码与文档、测试与基准两次提交，不推送。

### 2026-10-29：首页待办紧凑化与登录页去掉线路入口

按用户反馈调整首页：“待办区”标题改为与“今日课表”相同的 headlineSmall；课表与待办区之间的额外间距从 16+16 收为 12；加载提示紧跟标题，“查看全部”贴齐右边距。待办卡片的类型标签、标题与状态合并为一行（状态紧跟标题之后），以“待”开头的状态（待打卡、待考试、待提交、待完成、待使用、待签到）与时间信息重复，不再显示；考试中、进行中、使用中、即将开始、状态待更新、签到处理中、结果待确认等仍显示。领域层 `statusLabel` 不变，仅界面不渲染。

登录页右上角线路选择按钮移除，与“线路设置只在设置页、自动模式无感”的既定方向一致；删除已无消费者的 `onRoutePolicyChanged` 参数及共享宿主接线；保留 `routePolicy`，因为 `login_verification.dart` 仍根据自动模式显示验证码继续操作，删除会影响验证流程。`apps/ubaa_flutter` 复用共享宿主，无独立接线。纯样式与入口删除复用既有覆盖，iPhone 17 Pro 合成预览已核对首页。

删除 `account/login_parity_test.dart` 的“登录路线入口可展开并选择连接模式”。保留 `app/shell_parity_test.dart` 的“设置页点选连接模式立即生效，当前模式不重复保存”，以及宿主 `capabilities/callbacks_test.dart` 的设置页回调、策略更新覆盖。宿主登录测试继续核对默认自动模式。

短窗口大字测试改为注入顶部 24 像素安全区，检查标题保留安全区与表单内边距，确认滚动范围非零、滚动位置增加且登录按钮可点击。首页 `features/home/projection_test.dart` 新增合成考试组件测试，同时检查待考试隐藏、考试中保留，以及类型、标题、状态纵向中心对齐和横向顺序。原首页和登录页改动接手时已经存在，本轮补测不作为先失败后实现的证据。

本轮验证环境：系统 Flutter SDK 缓存不可写，使用仓库外临时目录的相同 SDK 副本（3.41.9，固定提交不变）运行。`ubaa_ui`、`ubaa_host`、`ubaa_flutter` 的 `flutter analyze --no-pub` 均通过。三个包的 `flutter test` 分别有 79、24、16 个测试文件在启动阶段因无法绑定 `127.0.0.1` 失败，尚未执行组件断言，因此未判断 golden 是否需要更新，也未修改 PNG。`just refs`、`just layout-check`、`just check-sensitive` 通过。尝试暂存时无法创建 `.git/index.lock`，当前沙箱禁止扩大权限，尚未生成提交。

指定门禁已依次尝试完成。`just check` 在 Core 单元测试阶段停止：358 项通过、5 项失败，其中 4 项创建本地服务时明确报 `PermissionDenied`，另 1 项发送失败诊断的错误分类不符合预期，推断与网络限制有关，未修改 Core。`just flutter-check` 在首包测试运行器绑定本地端口时失败。上述门禁未达到全部通过条件，需在允许本地测试端口和 Git 写入的环境复验后提交。

### 2026-10-29：学业页面紧凑化与隐藏教务内部编号

用户目视学业部分后要求按建议全部优化，并明确课程号完全不向用户展示。

- 成绩：“全部成绩”“本学期”两张统计卡合并为一张，主数字为所选学期，全部学期压成底部一行；门数与学分移到标题右侧。课程卡改为两行：课程名与分数同行，学分/属性/成绩类型合为一行小字；去掉课程号、星标和图标，不及格分数用错误色，未出分显示“待出”。宽屏页内重复搜索框移除，统一使用外层搜索。
- 课表：周末无课时只画周一至周五；今天的表头高亮并给整列浅色底，今天有课时画当前时间线；时间轴只显示节次与开始时间，宽度由 52 收为 40；课程块地点去掉“@”并降为次要文字。
- 课表详情与学期：星期、节次、时间合为“时间”一行，去掉课程代码与序号；学期弹窗不再显示学期编码，“当前”改为副标题，已选项打勾；顶栏日历图标改为“学期 ▾”文字按钮。
- 考试：日期下增加星期与“今天/明天/N天后”；已结束考试折叠区移到底部；时间与考场合为一行，座位改为醒目标签。
- 评教：批量栏改为常驻底部操作栏（待评/已选数量、全选、提交）；列表按待评在前、已评折叠分组；资格说明缩为“资格待确认/不可评”短标签，完整原因仍在详情。
- 空教室：删除与选择器重复的“日期 · 校区”行；查询当天高亮当前节次（表头与整列），新增“此刻空闲”快速筛选；详情去掉教室编号与楼层编号。
- 内部编号：新增 `uiHiddenAcademicField`，课程号、课程代码、课程编号、课程序号、课序号、课程 ID、学期编码等在课表/成绩/考试/签到/评教/空教室/博雅详情中不再显示；搜索与写入目标仍使用原字段，读取和提交行为不变。

以上为纯展示调整，不改领域、Bridge、Core 和读取写入协议。iPhone 17 Pro 合成预览已逐页核对。测试适配：成绩、课表、时间轴、评教、空教室、考试、博雅详情等 11 个测试文件改为新布局下的等价断言，原保护行为保留（统计不受筛选影响、刷新不推移、学期联动、重叠与未知节次可查看、评教只消费 typed action 且回读不重发）；“显示课程编号”类断言改为“正文不展示、搜索仍可命中”，并只检查正文 Text，避免误匹配搜索框输入。新增三条：有无周末课程时 7/5 列且今天表头高亮、“此刻空闲”只在当天出现并只留当前节次空闲教室、评教底部栏未选禁用/全选提交 N 门/已评默认收起。顶栏“学期”按钮补回“选择学期”提示，表头高亮内边距导致的 1 像素溢出通过表头高度 52→56 修复。golden 更新 schedule_desktop、schedule_phone_dark_large、grades_tablet；ubaa_ui 462 项、ubaa_host 101 项、ubaa_flutter 81 项通过。

### 2026-10-29：成绩卡片去掉详情弹窗

按用户要求，成绩卡片不再点击打开详情：课程名、分数、学分、属性、成绩类型均已在卡片上，绩点改为不带标签的小字紧跟分数（非数值绩点原样显示，不推算）。四条依赖弹窗的测试改为直接在卡片上核对绩点与次要字段，并断言点击不再弹窗；grades_tablet 基准更新。

### 2026-10-29：课程与作业、校园服务、设置页紧凑化（真实账号只读核对）

先用合成数据、再用真实账号只读浏览（未点任何签到、选课、预约）核对，区分出合成数据造成的假问题（图书馆分区空白、统计 9/1 未达标、“开始时间待确认”）后按用户要求调整：

- 课堂签到：只在课前 10 分钟到下课前显示“签到”按钮；其他时间显示“HH:mm 起可签”“未签到”或“已签到”标签，可签的课排最前，每 30 秒按校园时间刷新。时间只显示“08:00–09:35”。签到资格、目标缺失等内部提示不再显示，资格不明时按钮只是禁用。Bridge 资格判断不变。
- SPOC/希冀作业：卡片两行，截止改为“11月8日 23:59 · 还有 N 天”（未交且 3 天内标红），不再显示开始时间；提交状态按枚举显示彩色标签；“满分 0”不显示；SPOC 学期编码卡片与博雅“已选查询范围”卡片不再显示。
- 博雅：去掉二级菜单，进入即“选课”，顶部分段切换“选课/已选/统计”（`openFromHome` 单帧栈，返回直接退出功能）；可选/已满不再重复标签，“未指定校区”不显示，日期统一“11月7日 19:00”；已选课程退选截止已过时不显示截止和灰色退选按钮；统计大卡压成一行并附“达标 x/y 类”，大类相同不逐行重复。
- 图书馆：同样去掉二级菜单，分段切换“预约座位/我的预约”；楼馆（即校区）移到顶栏右上角，楼层与分区改为可左右滑动的方块，显示“空 x/y”；座位一行 5 个；无平面图时不显示按钮；修复座位网格继承安全区内边距造成的大块空白，去掉只有一个时段时重复的时间行。
- 空教室：校区同样移到顶栏右上角，日期并入楼栋方块行。顶栏控件通过 `UiAppBarSlot` 由页面登记、外壳只显示当前功能的控件。
- 最近选择：新增 `UiPlaceMemory`（键见 `UiPlaceKeys`：空教室校区/楼栋、图书馆楼馆/楼层/分区），进入时按“楼馆→楼层→分区”依次恢复，选项不存在则回落第一项。外壳提供 `placePreferences`/`onSavePlacePreference`，宿主持久化待接入。
- 内部状态提示：“资格未确认/待确认”“状态不一致”“尚未核对完整”“查询范围尚未更新完整”等列表提示全部移除，只保留确定的不可操作原因（如“该预约当前不可取消”“不可评”“人数已满”）；写入结果不确定的“勿重复提交”提示保留。阳光打卡记录详情不再显示记录编号、项目编号、状态编号。
- 首页课表时间统一为长横线；设置主题改为三段切换并隐藏未启用的统计开关；登录页回车按输入框内容提交，验证码框也支持回车。

纯展示与导航调整，不改领域、Bridge、Core 和读写协议；ubaa_app 仅去掉三处“尚未核对完整”的摘要文案。真实数据下首页仍缺“第 N 周”，原因待查。


### 2026-10-29：将 UBAA v2.0 文档站迁入开发分支

用户要求迁移旧站 VitePress，按新版功能更新正文，不另设旧版归档；品牌仍为 UBAA，v2.0 仅作为版本号。选择 `docs/site/` 作为网站源码根目录，保留现有工程文档与证据位置。沿用旧站功能与技术页面路径，重写 Kotlin/Compose、服务器中转、Web/Wasm、隐私和发布说明。

使用 GitHub Pages 产物部署，移除文档站对 SSH 与自有服务器的依赖。工作流在 PR 和相关分支 push 时构建，只有显式配置的发布分支部署，便于本地迁移与线上域名切换分别进行。未来 `ubaa2` 改名 `main` 时同步调整发布变量、环境规则和源码链接。

旧站使用 VitePress 2 alpha 系列。迁移中评估 1.6.4 时，npm 审计报告了旧 Vite/esbuild 依赖问题，因此固定为官方当前 2.0.0-alpha.21，并锁定依赖。该版本仍属预发布版本，后续升级需复验导航、搜索与构建；当前审计为 0 项已知漏洞。

验证结果及并行 Flutter 改动的阻塞见[迁移记录](docs-site-2026-10-29.md)。未修改应用协议、学校请求、Pages 仓库配置或 DNS。

宿主持久化补齐：`ubaa_platform/src/infrastructure/place_preferences.dart` 使用 `AccountPreferences` 保存账号地点编号，白名单由宿主传入 `UiPlaceKeys.all`；主题通过 `PreferenceValues` 保存为设备偏好。宿主在账号地点读取完成后展示外壳，切账号清空旧内存、丢弃过期读取与回调，明确清账号时删除对应身份的地点偏好，主题保留。损坏或读取失败回落默认值，保存失败静默忽略；合成宿主使用内存存储。实现仅涉及平台、宿主和 UI 接线，保留接手的三处摘要文案修改。

测试适配保留 typed 写入目标、提交与回读次数、未知结果不重试、筛选条件清理及迟到结果丢弃。新增固定 `clock` 的课前 11 分钟、课前 10 分钟、课中、下课时刻、下课后和已签到覆盖，以及未知资格禁用、作业剩余天数和三天标红边界、楼馆→楼层→分区恢复与失效选项回落、宿主地点恢复和清除、设备主题跨宿主恢复。补测发现不完整空缓存误报“暂无数据”，先复现后改为“暂时没有可显示的内容”；时间缺失仍出现签到按钮也先复现失败，再限制为明确时间窗内显示。接手已有的界面改动仅作回归补测，不追溯声称 TDD。

删除项的保留覆盖：`navigation/landing_parity_test.dart` 中博雅、图书馆“先显示二级菜单”的两个参数用例改为进入第一页、分段替换和返回退出功能；图书馆“再次进入先回菜单”的参数用例移除，由新分段导航用例和原迟到结果用例继续保护读取、返回与请求失效。研讨室菜单用例保留。设置未启用统计的测试改为检查宿主能力关闭且不展示开关；平台统计能力和授权测试保留。其余用例只调整入口、布局或状态展示断言，不删除业务覆盖。

最终结果：地点与设备主题持久化及相关回归测试通过，`just refs`、`just layout-check`、`just check-sensitive`、`just check`、`just flutter-check` 全部通过；七包静态分析无问题，测试分别为 60、95、676、478、20、102、81 项，共 1512 项，另对最后整理的作业日期样本与空缓存断言聚焦复验通过。六张 golden 均比较通过，没有更新 PNG。测试日志保存在仓库外，本轮未执行真实学校请求。并行文档站工作在验证期间独立产生提交 `9186156b`，本轮没有修改或暂存其文件。


### 2026-10-29：整理首页入口、资料页和侧栏并适配回归

接手六个未提交的 UI 文件：首页最近使用改为课表标题右侧图标，手机底栏保留四个业务分组，设置和退出移入抽屉；宽屏侧栏增加退出入口，资料页直接显示传入的姓名、学号、院系与联系人，清除账号放在设置页。没有修改认证或读取协议。联系人按传入值显示，本轮只用合成遮罩值验证展示，没有新增真实上游打码保证。

先运行现有 UI 回归，确认旧底栏、资料展开与最近使用卡片断言失败，再适配实际入口。保留同账号更新不退出资料页、换账号移除旧内容、旧清除确认不能清理新账号、资料导航零读取、最近访问排序与去重、设置清理失败与防重入、跨宽度导航、键盘和大字检查。删除的资料展开/显示/隐藏断言对应已移除的交互，替换为直接显示传入联系人、返回再进入与账号更新覆盖。没有把接手改动追溯记为 TDD。侧边留白滚动测试按实际可滚动范围选取步长，继续检查左右留白与正文共用位置及上下边界。

结构检查发现 shell.dart 超过 1000 行，底栏组件机械移入已有 shell_navigation.dart，未提高结构上限。仅更新 menu_desktop_dark 与 menu_phone_large 两张 golden，已检查布局；golden 使用测试字形，未据此宣称原生中文字体验收。

工作树整理确认两个旧工作树均干净且 HEAD 已包含于 ubaa2，将完整目录与 Git 管理信息移至仓库外私有快照，撤销活动工作树注册并删除已合并临时分支。主目录本机配置、冻结引用及忽略文件保留，未提交凭据、运行响应或运行截图。

验证：七包静态分析通过，Flutter 测试分别为 60、95、683、478、20、102、81 项，共 1519 项全部通过；六张 golden 比较通过。冻结引用、目录结构、敏感扫描、差异检查和 FRB 生成零漂移检查通过。本轮没有执行真实学校请求或原生设备验收。

本轮界面与回归提交为 `ed0fa38a`，最终 `just check` 完整通过，包括 Rust 编译、Clippy、测试、Shell 合同与文档构建。验收日志及工作树恢复说明保存在仓库外私有目录。

## 2026-10-29：阶段 1 去除个人机器依赖

本阶段只调整工具链配置、证据路径保护、路径脱敏、搭建文档和许可证，不改变学校服务的协议行为。项目工具链使用本地 `.env.toolchain`，just 自动加载，直接运行的脚本共用 `scripts/lib/toolchain.py` 回退读取。工具入口不加载 `.env.local`，已导出的变量优先。Dart/Flutter 使用 `just dart`、`just flutter` 和 `just flutter-ohos`，位置参数原样透传。just 的 dotenv 文件名与显式路径均限定为 `.env.toolchain`，避免向父目录搜索其他配置。

敏感扫描对 index 与工作区同时检查 macOS、Linux 和 Windows 家目录路径。唯一接受的文档占位形式为 `<private-evidence>/...`、`<repo-root>/...` 等逻辑标识，不为任何用户名、历史文档或证据目录增加豁免。原外部源码诊断测试改用普通的外部路径，保留诊断裁剪覆盖。

历史证据的个人前缀统一脱敏，原临时目录改为 `<private-evidence>/legacy-tmp/`。此改动没有迁移原日志，也没有重新验证原摘要。模拟器标识改为占位，历史来源提交、协议事实与验收结论保留。iHome/评教的补充旧版来源仍沿用已登记例外，本阶段未扩大冻结引用范围，也未补充无法取得的原始证据。

历史 UI JSON 暂不迁出：这些 JSON 保留批次、状态和媒体摘要的对应关系，贸然删除会损失追溯线索。迁出前应生成逐批索引、明确私有归档维护位置，并校验摘要与提交映射。阶段 1 只做路径和设备标识脱敏，继续保留全部 JSON。个人 Windows 设置草稿移入被忽略的 `.ubaa_local/drafts/`，不删除内容、不提交草稿。

项目 MIT 许可证版权人为 MooreFoss。第三方声明补充 Cargokit、connectivity_plus_ohos、package_info_plus_ohos，并随仓库保存 buaa-api MIT 原文。Cargokit 的单独上游 commit 当前无可靠本地记录，本阶段如实说明，不猜测版本。其出处格式统一留待 Dart/OHOS 整理阶段。

验证：工具链入口、敏感扫描及证据目录检查均保留失败日志，修复后聚焦测试通过。`just refs`、`just layout-check`、`just check-sensitive`、`just check-strict`、`just flutter-check`、差异检查和以 `691dce841f972076d2d3d0a06f9f18814d7aef29` 为基线的 `just check-plan` / `just check-changed` 全部通过，七包 Flutter 共 1523 项测试通过。按改动检查同时执行 FRB 生成检查，锁定生成器 2.13.0 生成零漂移；审计 H3/A116 记录的漂移本轮未复现，没有修改生成物。生成检查的工作区副作用及未跟踪文件检测仍按总纲留待门禁整改阶段，不在本阶段扩展实现。OHOS 工具链预检及安全存储、网络插件合同检查通过。未执行学校请求、原生构建或设备验收。

## 2026-10-29：阶段 2 统一权威来源与规范

本阶段先以 `fd96b0bf` 单独修正工具入口：只保留 dotenv-path，限定根目录工具配置，缺失文件仍允许非 SDK 命令运行；三个转发 recipe 静默执行。既有参数透传测试增加真实 stderr 回显反例，先观察失败再修复，七项入口测试通过。配置文件仍被忽略，工具入口没有读取凭据文件。

长期权威入口为 AGENTS.md，goal.md 只保存当前阶段目标，状态页报告实际结果。整理前的首页任务完整保存在 history 的日期快照中，历史授权只描述原任务。工具链调用规则只在 AGENTS 维护，setup/commands/其他入口改为链接，保留项目级 just 入口、唯一回退解析器、环境优先和凭据分离要求。

规则冲突按用户要求取更严格者：认证、读取和写入功能变更全部先做双冻结来源逐操作对照，保留原 AGENTS 的所有字段列、冲突停止、不适用禁止类比、失败证据及提交前检查语义；最终维护验收采用 check-strict，并保留既有测试/发布说明中的独立 FRB 与默认原生集成要求。全部门禁清单只在 commands.md 维护，其他文档引用。纯文档日常修改与触及门禁/公共合同/跨模块的完整验收分开说明，不能因选择器对 docs 免检而省略应做检查。

真实账号规则采用当前会话用户任务的功能与路线范围，同一会话仍适用的授权继续有效。文档、旧 goal 与存在凭据均不能扩大范围。协议变更或发布要求 Direct/WebVPN 两条路线；不可达或未获授权时保持未完成并登记重跑条件，不静默豁免。真实写入继续要求具体操作、目标、路线和时间授权，发送后禁止自动重试。本轮没有改变协议，不执行学校请求。

冻结换钉不是本轮新操作：Git 提交 `f63e6d060059beaa68a4b9372c393ea56e3a4c61` 于 2026-09-17 同步修改 references.md、bootstrap 与 checker，把旧版从 `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e` 换到 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`，并从根目录移到 examples/ubaa_old；buaa-api 从 `efb7976bf513f38364b88aeb83d704586cff9b2a` 换到 `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。原换钉理由和用户要求保存在历史决策的[旧版换钉](history/decisions-before-maintainability-2026-10-07.md#2026-09-17冻结旧版引用更新至最新上游并收纳至-examples)与[buaa-api 换钉](history/decisions-before-maintainability-2026-10-07.md#2026-09-17冻结-buaa-api-引用更新至最新上游)两节，因此“未找到换钉记录”只适用于现行索引缺失，不能据此声称历史决策从未记录。本轮 just refs 确认当前固定值，source-parity 的当前声明据此校正；旧矩阵和专项的当时 SHA 不改写为新证据。专项索引补全，旧版文件引用前缀统一为 examples/ubaa_old/，不暗示历史行号已按当前提交重验。

conventions.md 新增命名、语言、分支、版本、依赖、日志和 ADR 模板。main/dev/ubaa2 的未来合并流程与统一产品版本没有足够依据，本轮不猜测或改分支/版本；规则明确依用户任务与发布配置执行，工作流真实触发范围如实记录。编辑器按现有代码修正 Python/Kotlin/justfile 为四空格，Swift 抽样七个文件均为两空格，保留两空格；没有因审计示例建议而批量格式化生成或平台文件。

本阶段没有修改 CI、选择器、锁文件、冻结目录或生产源码。后续 Action 锁定、test-contract 跨平台缺口、OHOS 覆盖与文档断链门禁按既定阶段继续。约 4000 个历史 UI 证据 JSON 本轮保留：这些元数据仍承担旧批次与提交映射的追溯作用，尚无逐项迁出核对结果，删除会损失原记录关联。是否打包迁出及对应摘要、校验清单按后续文档阶段评估，本轮不新增忽略或 baseline。


阶段 2 实际验收：工具转发七项、合同版本、布局、敏感扫描、严格 Rust/Shell、七包静态分析及 1523 项 Flutter 测试、FRB 生成零漂移和网站构建通过。首次严格入口因文档中的不完整格式化命令片段触发既有锁约束合同失败，补全实际命令后，聚焦合同及完整严格入口均通过，没有修改该合同或放宽检查。

默认 macOS 原生集合未全通过：网络恢复 1 项、插件 2 项通过，应用流程 5 项通过/2 项失败；失败位置为 integration_test/navigation.dart:51 的滚动容器查找和 synthetic/app/flow/write.dart:162 的提交次数断言。补跑缓存 Bridge 1 项通过；启动锁夹具因本机 Sandbox 容器临时目录权限拒绝，在测试开始前退出。这些 Dart/原生源码与阶段基线一致，规范整理不扩展为 UI 测试修复，不删除失败项或放宽原生验收。后续需要修复应用流程测试并在允许容器临时目录访问的环境重跑启动锁。日志留在本地监督目录，受跟踪文档不复制个人路径。

按阶段开始提交 ff9a52e7 生成并执行检查计划，完整 Rust/CLI、七包 Flutter 与 FRB 零漂移全部通过。新增和修改的 230 个文档链接检查无新增失效，50 份专项索引齐全，全仓 15 个当前 goal 链接均能解析且无旧章节锚点；改动文档中继承的 50 条历史断链保留后续阶段处理，没有新增豁免。最终提交只包含已审阅的规范、索引、历史目标引用和编辑器配置。
