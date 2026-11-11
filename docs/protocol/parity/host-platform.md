# 宿主界面与平台能力

本文件收录列表连续滚动、系统选图与拍照、功能卡片按钮等宿主侧行为的来源边界。

## 专项记录

### 列表连续滚动的来源与边界

实现前核对（2026-10-26）：`just refs` 验证旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`、buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。本次改变宿主展示和请求触发时机，继续调用现有 facade／Bridge 查询，不修改协议实现。

| 操作 | 冻结来源与交叉来源 | 请求与分页字段 | 本次决策 |
|---|---|---|---|
| 博雅课程 | 旧版 `BykcApi.kt`、`LocalBykcApi.kt`、`Bykc.kt` 与 LocalBykcApiBackendTest；buaa-api `api/boya/opt.rs`、`core.rs`、`data.rs` | POST `sscv/queryStudentSemesterCourseByPage`，原始 `pageNumber/pageSize`，一基；totalElements/totalPages，保留原课程 ID | 连续追加，以课程 ID 去重；本地筛选作用于已加载集合；末页依据服务端元数据 |
| 研讨室订单 | 旧版 `CgyyApi.kt`、`LocalCgyyApi.kt`、`Cgyy.kt` 与 LocalCgyyApiBackendTest；buaa-api 无等价模块 | GET `/api/orders/mine`，`page/size/nocache`；请求零基，`number/size/totalElements/totalPages`，Bridge 展示一基 | 自动请求仍为零基；按订单 ID 去重，不修改取消 target 与原始回读上下文 |
| 图书馆预约 | 旧版 `LibBookApi.kt`、`LocalLibBookApi.kt` 及 DTO／测试；buaa-api 无等价模块 | POST `v4/member/seat` JSON `type=1/page/limit`；一基，`current_page/per_page/total` 及已有回退规则 | 复用页码／总量投影，以预约 ID 去重；不从已加载数量伪造总数 |
| 阳光记录独立列表 | 旧版 `YgdkApi.kt`、`LocalYgdkApi.kt`、YgdkApiTest；buaa-api 无等价模块 | POST `api/Front/Clockin/Clockin/getList`，原 query＋form `page/limit/classify_id/user_id`；一基，total/hasMore | 独立分页列表连续追加，按 recordId 去重；既有阳光首页增量列表保持其业务聚合 |

启动 CAS／OAuth URL 与 service、跳转和最终 URL、Cookie／token 账号路线范围、请求头与正文编码、签名与加密常量、错误退出语义分别沿用 [source-parity](../README.md) 的“博雅课程只读查询”“场馆预约只读查询／我的订单”“图书馆座位只读查询”“阳光打卡只读查询”九列。已核对本地 API 以及 buaa-api Boya request／crypto／cred／cookie 入口：Boya 示例的列表返回及加密包装不能替代旧版的元数据及错误规则；另外三项没有对应协议，禁止类推。当前参数与 Bridge 的 page 映射已逐项核对，本次无需新增认证或协议参数。

展示缓存仅属于当前导航帧，不写回 AppController，不作为写资格或回读证据。单帧一次续载；账号、路线、缓存代次、刷新或查询变化使旧集合与在途追加失效。失败保留已加载结果，显式重试；重复页面、页码错配或无进展停止自动续载。详情返回保持列表和滚动位置，刷新从首请求页重建。本地分页改为同一惰性列表，不重新请求已在内存中的数据。范围是现有上一页／下一页分页条，iHome 与阳光首页已有独立增量流程不在本次分页条替换范围。

#### 回归覆盖与旧用例迁移

共享列表的新回归验证滚动触发第二批、保留前批、失败后显式重试同一页、进入详情后返回原位置、刷新回到首批，以及在途追加只发一次请求和缓存失效后拒绝迟到结果。聚合测试检查零基请求映射、业务编号去重、服务端总数保留、错误页码与路线变化。本地长列表保留 21 项筛选、千项列表离屏释放和连续访问后部条目的覆盖。

旧分页测试按用户操作迁移：`features/details_test.dart` 的本地翻页和服务端下一页改为滚动；`query/queries_test.dart` 的手填页码与容量改为筛选应用从首批开始；App `features/cgyy/navigation_test.dart` 改为连续三批与刷新首批。各原生和真实只读入口删除手填分页步骤，保留原始取消目标、查询页码映射、刷新及读取次数检查。本轮未运行真实只读集成脚本。

博雅筛选回归不再断言分页条中的“61”，合成目录改为与实际条目一致的单批元数据，筛选交集、并集与偏好保留继续覆盖。服务端总数保留由聚合测试检查。原生博雅定位辅助函数回顶时直接设置滚动位置，避免定位步骤意外触发下拉刷新；实际追加仍由滚动手势触发。旧原生用例将已选详情误判为零读取，本轮依据基线已有的 `_openBykcChosen` 修正为一次带原课程 ID 的完整详情查询。

另在仓库外从基线 `368f9239` 提取 UI 源码，运行同一滚动回归：滚到末尾后请求序列为空，未产生预期的第二页请求。当前实现通过该回归。基线复现只使用合成数据。

阳光原生旧流程还保留了“空时间和空照片必须报错”的旧断言，但当前表单已有默认一小时时间段和默认图片。本轮将该步骤改为只填写开始时间，验证缺少结束时间时禁止准备提交，随后补全时间并继续原有照片、准备与取消检查。该调整只更新合成测试，没有改变打卡表单行为。

#### 验证结果

按 `just check-plan` 的范围完成冻结引用、敏感扫描、布局、模块依赖和 Flutter 检查。UI 442、Host 101、官方 App 78 项测试通过，三包静态分析通过。原生 macOS 合成验证共 32 项通过：研讨室 22 项，博雅课程长列表与正常流程 4 项，阳光独立记录长列表与正常流程 4 项，图书馆正常流程 2 项。研讨室连续追加验证请求 0、1、2 与末页停止；博雅和阳光验证滚到第 42 项；所有合成写入步骤只准备和取消，没有提交。

范围检查首次暴露的下拉刷新回退、失效后空转和旧分页断言均已修复。完整范围执行在 App 静态分析处发现两个删除分页后不再使用的测试辅助函数，清理后单独补齐 App 检查。多个原生入口同次启动时出现调试连接失败，改为逐文件运行后通过。未执行 iOS／Android 真机、远程 CI 或真实写入。

Debug 构建成功，并使用既有隔离配置启动。实际窗口中，博雅列表到末尾显示续载状态，随后出现后续课程，向上滚动仍能返回原首批；研讨室预约记录可连续滚到末尾，底部分页栏已移除。应用留在预约记录首屏。本轮实际窗口只读取和滚动，没有预约、选课或打卡提交；截图未写入仓库。

#### 入口与失效恢复修正

用户反馈再次点击研讨室入口直接进入旧订单子页，并显示空记录。实际窗口复现后，点击刷新立即恢复记录。源码确认功能入口仅为作业列表重置导航，其他保留页面直接复用旧子页；分页帧遇到 readCacheEpoch 变化时又被设置成 empty，缺少重新读取。四项新增回归分别复现研讨室／图书馆再次进入未显示菜单、当前订单失效后未重新读取、后台失效后重新进入仍留在空子页。

实现前继续采用上述两个冻结引用。旧版 `CgyyHomeScreen.kt` 明确将预约、我的预约、密码列为独立菜单，`CgyyOrdersScreen.kt` 进入后由既有 ViewModel 读取记录；buaa-api 无研讨室 UI 或协议实现。本次只修复 Flutter 导航与失效状态，读取继续使用既有 `cgyyOrders` 零基请求，认证、会话、参数、解析及错误语义沿用本记录前述比较。当前分页列表失效后从首批重新读取，后台页仅标记失效，重新点击功能入口先回菜单；失效不再伪造空结果，返回路径与迟到响应隔离继续保留。

修正验证：新增菜单再进入、前台／后台失效、恢复失败后显式重试和失效菜单预载六项回归；原在途追加测试进一步确认重新读取第一页且不混入旧追加结果。`just check-changed` 通过，UI 448、Host 101、App 78 项测试及三包静态分析通过。4 项 macOS 明暗原生场景通过，覆盖连续三批、返回功能分类再进入菜单、订单重新读取以及原有表单和取消准备。原生定位最初点击了窄导航隐藏的文字，改为实际可点击图标后通过。

修正后的 Debug 已重建并使用既有隔离配置启动。实际窗口确认首页“最近使用”先打开研讨室菜单，“我的预约”读回 15 条记录；退出到校园服务后再次点击研讨室仍显示菜单。应用留在研讨室菜单。上述实际操作仅查询和导航，缓存失效自动恢复与迟到响应由合成回归验证，没有执行真实预约或取消。

### Windows/Linux系统选图接线

日期：2026-10-02，起点`345d1236`。冻结旧版`1f4b8f84`的`composeApp/src/jvmMain/kotlin/cn/edu/ubaa/ui/common/util/PlatformImagePicker.jvm.kt`：打开系统FileDialog，用户取消不返回图片；选定后读取字节、basename和Files.probeContentType；桌面不支持拍照。共同表单`YgdkClockinFormScreen.kt`接选择、预览、重选和清除。示例`buaa-api@a63712fa`没有本地桌面UI/选图能力；学校上传协议不改，不类比其它接口。

| 操作 | 旧版行为与当前选择 | 网络/会话/参数/header/crypto/DTO | 生命周期与错误 |
|---|---|---|---|
| 选择 | 系统单文件对话框，取消返回空；Win/Linux接Flutter官方file_selector，其它平台保留现有原生选择 | 无学校请求、URL、Cookie、表单或crypto；路径只在Platform内部，Host仅YgdkPhotoInput | 单次在途；取消不覆盖旧图，平台异常统一固定错误 |
| 读取 | 保留原图字节、basename与MIME；当前既有10MiB限制继续应用，先检查长度并流式限额 | 不落盘复制、不上传；MIME按已选文件名/文件头识别，复用既有canonical字段校验 | 空文件、超限、非image或不安全basename拒绝，错误不含路径/正文 |
| 权限 | 桌面用户在对话框明确选择单个文件，不需要申请移动端相册库权限 | photos/files仅允许进入系统选择器，不产生广泛目录授权；其它权限仍由既有Gateway处理 | 不声称桌面相机/位置可用，未实现能力继续返回unavailable |
| 后续提交 | 旧表单选图/预览/重选/清除；当前唯一WriteCoordinator与Core fresh资格不改 | 学校上传URL、方法、参数、headers、编码、token、crypto全沿当前已证Ygdk合同 | 本次只做本地能力接线，真实学校提交为0，合成backend验证表单 |

官方资料：Flutter维护的[file_selector](https://pub.dev/packages/file_selector)说明Windows/Linux原生文件选择，`openFile`取消返回null；[MIME识别API](https://pub.dev/documentation/mime/latest/mime/lookupMimeType.html)说明优先检查文件头。锁定file_selector 1.1.0，MIME复用2.0.0接口，仍以当前pubspec.lock和实际解析为准。平台能力依赖进入真实原生注册清单；单元测试不冒充Windows/Linux实际窗口或构建验收。

### 普通与高级功能卡片的原生按钮动作

2026-09-15；实施前记录。旧版 `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`、示例 `efb7976bf513f38364b88aeb83d704586cff9b2a` 已通过冻结校验。

#### 已复现的独立问题

当前 `_FeatureCard` 在 `packages/ubaa_ui/lib/src/app/home.dart` 中以外层 `Semantics(container: true, button: true, label: …)` 声明按钮，物理手势则位于内部 `InkWell.onTap`。临时共享组件测试证实：带完整“课表查询：…点击查看详情”标签的顶层语义节点没有 `SemanticsAction.tap`，而物理手势可以正常进入课表。

行为证据保存在仓库外 `macos-ui-20260915/navigation-semantics-probe.log`：期望 tap 动作为true，实际false，退出1。此前普通手势导航序列通过1项。这是原生语义按钮的动作接线缺口，不能扩大解释成所有鼠标点击都失败；也不是之前窗口处于hidden而暂停绘制的根因。两类问题分别处理。

#### 旧版与当前入口

| 入口 | 冻结旧版 | 当前读取/动作边界 |
|---|---|---|
| 课表、考试、成绩、博雅、空教室、SPOC、希冀、图书馆 | `RegularFeaturesScreen.kt:111–135`：按原feature.id分派八个回调，Card本身使用Compose `clickable` | `_FeatureGridSliver`沿既有FeatureId建立同一张卡，进入现有页面；不改变初始FeatureQuery或父子导航 |
| 研讨室、阳光、评教 | `AdvancedFeaturesScreen.kt:85–107`：三个实际业务回调与同样的Card clickable；旧占位卡不当作业务动作 | 保留当前三个领域入口及既有typed写权限，语义激活只能进入页面，不能直接提交写入 |
| 当前已有课堂签到入口 | 旧功能来自首页待办和SigninScreen，旧高级页没有对应第四个实际回调 | 保留当前已有入口与typed查询/资格；本批不调整分组或增加业务能力 |

`examples/buaa-api` 没有原生UI、卡片语义或导航回调实现；本项不能向示例借UI行为。已有十二领域读取方法、DTO、协议和写入边界继续使用主[source-parity.md](../README.md)中各自操作矩阵。

#### 九列不变性核对

| 本批操作 | CAS/bootstrap/service | 跳转/最终URL | Cookie/session | 方法/参数 | Header/编码 | 加密/签名常量 | DTO/解析 | 缓存/并发 | 错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| 普通功能八张卡的语义激活 | 不在卡片层认证；沿各目标页面原读取矩阵 | 不变 | 不变，不向语义节点加入会话材料 | 只调用该卡原onTap，不调用新读取接口或添加参数 | 不变 | 不变 | 原FeatureId/snapshot/label保留，不从标签猜路由 | 进入同一个已访问页面与原navigator；不增加请求或重试 | 只打开页面；原错误页/返回和写入确认均不变 |
| 高级功能当前四张卡的语义激活 | 沿研讨室/阳光/评教/签到各自原矩阵 | 不变 | 不变 | 同原onTap；不得把原生activate连到prepare/commit | 不变 | 不变 | 原展示/typed资格/target保留 | 原页面和WriteCoordinator生命周期不变 | 未认证、无资格或未知结果仍按原规则；不直接触发任何学校写入 |

#### 最小修复与验证要求

外层声称是按钮的节点必须承载与可见卡片相同的tap动作，并避免把同一张卡暴露为两个彼此脱节的按钮；保留可读标签和物理手势。视觉、分组、卡片尺寸和原onTap目标不变。

正式测试需使用Flutter语义动作激活实际共享卡片，验证八个普通入口和四个当前高级入口均能打开正确页面；先观察行为RED，再最小修复并GREEN。物理点击、返回和既有导航测试继续通过。只修这一处原生按钮接线，不扩成完整无障碍认证或另造测试专用页面。最终仍需真实macOS的computer use操作；确定性语义测试不能替代实窗验收。

#### 2026-09-15 实施事实

实施基点为 `41ece772c93749c4b592afd0cdf1e687fb45bb8e`。`_FeatureCard` 的外层 `Semantics` 新增 `onTap: onTap` 与 `excludeSemantics: true`：完整标签节点直接承载原点击回调，内部文字与 `InkWell` 不再另行产生重复语义。内部 `InkWell.onTap` 保留，卡片布局、可见内容、入口分组与原目标页均未改动。

正式回归文件为 `packages/ubaa_ui/test/navigation/feature_card_navigation_test.dart`。测试使用实际 `UbaaMainShell`、800×632 视口和合成成功快照，固定列出八个普通入口及研讨室、阳光、评教、课堂签到四个当前高级入口。每个入口经完整标签找到实际语义节点，从其所属 `SemanticsOwner.performAction(node.id, SemanticsAction.tap)` 激活，验证目标页面、按钮标记、完整标签、卡片子树仅一个 tap 动作、一次返回原分组及不新增读取；另有对应十二项物理点击与返回测试。

最终相同测试的 RED→GREEN 日志保存在仓库外私有 `macos-ui-20260915/navigation-actions/`：`red-current-sdk.log` 退出 1，十二项语义激活均未进入目标页，十二项物理点击通过；`green-current-sdk.log` 退出 0，24 项全部通过。RED 前已核对 `home.dart` 与基点无差异，测试副本为 `red-current-sdk-feature-card-navigation-test.dart`。既有导航、查询草稿、返回与迟到结果等相关回归 81 项通过，见 `navigation-regression.log`。以上均为确定性组件证据，本批未运行 native、live 或真实 macOS 窗口操作。

### P5-E 原生照片能力来源核对（2026-09-10）

基点f9115633。CAP-01生产只读已暴露缺口：默认photo.capability无原生实现，宿主安全隐藏新增入口。此批补平台能力，不改变Core/Bridge、学校请求或写入资格；真实选择照片只在显式脱敏业务backend中操作，生产账号仅浏览表单，禁止上传/提交。

| 冻结依据 | 必要优化 | 当前实施位置 |
|---|---|---|
| common PlatformImagePicker：bytes/fileName/mimeType、取消无回调；Ygdk表单选择/清除/原文件信息 | 保持当前10MiB、只读原文件、取消保原图、退出释放、未知/失败明确；不恢复透明图片兜底 | packages/ubaa_platform/src/media.dart及共享独立表单 |
| Android GetContent image/*、displayName/getType；TakePicturePreview→JPEG92 | 系统授予所选内容的临时读取，不申请全量媒体库；读取大小限制；拍照作为原能力后续单独接线验收，未列为本批已完成功能 | Android PhotoChannel与MainActivity |
| JVM FileDialog LOAD、basename/MIME；相机不可用 | macOS NSOpenPanel仅用户选中文件只读；原路径不离开原生层，读取错误不当取消 | macOS PlatformChannel、PhotoHandler与窗口接线 |
| iOS明确“图片选择暂未接入”，无已实现旧相册能力 | 为本轮手机/平板一致任务补系统PHPicker，用户选择后才可读所选照片，无全量相册访问 | iOS PhotoChannel与Engine注册 |
| examples无图片选择UI或阳光等价协议 | 不借上游字段/加密/错误；沿现有阳光九列协议和typed写入 | docs/protocol/source-parity.md既有阳光矩阵不变 |

边界：permission.request的photos表示能请求系统选择器，不代表获全相册权限；系统选择器内选择是取得单张内容的授权，取消返回null。其他权限/凭据/位置仍不可用，不因接线照片而报告它们可用。iOS PHPicker、Android系统GetContent与OHOS PhotoViewPicker均仅选定内容；macOS添加user-selected.read-only entitlement，不能开放整个目录或写权限。所有native异常使用固定code/message且无details，跨通道不传URI/路径/原始系统错误。

官方依据：Apple PHPickerViewController及Selecting Photos and Videos in iOS（https://developer.apple.com/documentation/photokit/selecting-photos-and-videos-in-ios）；NSOpenPanel（https://developer.apple.com/documentation/appkit/nsopenpanel）；Android permission alternatives及Photo Picker（https://developer.android.com/privacy-and-security/minimize-permission-requests）。实际签名以锁定本机SDK头文件为准。

验收：先原生默认probe不可用RED及平台错误不应伪装取消RED；最小原生接线、方法通道聚焦、实际选择/取消/预览/重选/清除、明暗与两端/真实Mac观察，全部写入使用显式内存backend。Windows/Linux原生照片尚待接线与对应环境核验，不冒称六平台全部完成；OHOS仅构建不代替设备。


P5-E最终审查补强：原生展示名不得修剪或替换掉非法原始值以绕过Dart canonical约束。Apple/Android对已提供的首尾空白、路径、引号、控制字符及超128码点展示名明确拒绝；仅Android provider未提供名称时使用明确的“所选图片”默认展示名，OHOS不从不透明URI猜文件名。Swift合成文件拒绝分支、Android构建与三端原生接线重新验证；原始文件保持只读。此补强不改变业务字段或资格。


#### P5-F Android旧版拍照恢复前核对（2026-09-12）

基点5d988362。再次逐行读取冻结PlatformImagePicker.kt、Android PlatformImagePicker.android.kt及YgdkClockinFormScreen.kt照片区：图片与“拍摄照片”同一行，仅canCapturePhoto=true显示后者；Android使用TakePicturePreview返回Bitmap，在内存压缩JPEG质量92，以camera_时间戳.jpg和image/jpeg回传。JVM/iOS/OHOS不由此类推新增相机能力。examples无此UI或阳光拍照实现；学校上传/提交九列继续沿source-parity-ui-campus，不改变CAS、Cookie、参数、DTO、资格、缓存/并发、实际路线或错误合同。

AndroidX官方源码[TakePicturePreview](https://android.googlesource.com/platform/frameworks/support/+/dd97834aa54671ee1f56d65fa46668b4ffeb57e8/activity/activity/src/main/java/androidx/activity/result/contract/ActivityResultContracts.kt)核实其Intent为MediaStore.ACTION_IMAGE_CAPTURE、成功结果Bitmap来自data extra。当前AndroidManifest没有CAMERA权限；恢复系统相机委托，不新增直接相机/存储权限或持久照片文件，能力探测需核对可处理Intent。必要优化为原生及Dart均受10MiB约束、固定错误、取消保原图、选择/拍照单pending及代次失效保护。拍照作为可选本地平台接口穿过宿主/共享UI，不能放宽学校业务写入资格。先记录缺少拍照能力行为RED，再实现、构建、脱敏原生渲染；真实设备相机操作仍独立验收。


#### 2026-09-15 macOS通道组合

macOS注册入口现为Runner/Platform/PlatformChannel.swift，原PhotoChannel拆为PhotoHandler，只将通道所有权移到聚合器。照片pick/permission语义、系统NSOpenPanel、PhotoPayload和10MiB边界不变；Keychain由独立CredentialHandler处理，未重复注册同名MethodChannel。真实原生回归仍可探测照片与photos权限；系统选图完整CUA行为需按本轮候选单独复验。
