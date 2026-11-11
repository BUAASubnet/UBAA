# 普通与高级功能卡片的原生按钮动作

2026-09-15；实施前记录。旧版 `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`、示例 `efb7976bf513f38364b88aeb83d704586cff9b2a` 已通过冻结校验。

## 已复现的独立问题

当前 `_FeatureCard` 在 `packages/ubaa_ui/lib/src/app/home.dart` 中以外层 `Semantics(container: true, button: true, label: …)` 声明按钮，物理手势则位于内部 `InkWell.onTap`。临时共享组件测试证实：带完整“课表查询：…点击查看详情”标签的顶层语义节点没有 `SemanticsAction.tap`，而物理手势可以正常进入课表。

行为证据保存在仓库外 `macos-ui-20260915/navigation-semantics-probe.log`：期望 tap 动作为true，实际false，退出1。此前普通手势导航序列通过1项。这是原生语义按钮的动作接线缺口，不能扩大解释成所有鼠标点击都失败；也不是之前窗口处于hidden而暂停绘制的根因。两类问题分别处理。

## 旧版与当前入口

| 入口 | 冻结旧版 | 当前读取/动作边界 |
|---|---|---|
| 课表、考试、成绩、博雅、空教室、SPOC、希冀、图书馆 | `RegularFeaturesScreen.kt:111–135`：按原feature.id分派八个回调，Card本身使用Compose `clickable` | `_FeatureGridSliver`沿既有FeatureId建立同一张卡，进入现有页面；不改变初始FeatureQuery或父子导航 |
| 研讨室、阳光、评教 | `AdvancedFeaturesScreen.kt:85–107`：三个实际业务回调与同样的Card clickable；旧占位卡不当作业务动作 | 保留当前三个领域入口及既有typed写权限，语义激活只能进入页面，不能直接提交写入 |
| 当前已有课堂签到入口 | 旧功能来自首页待办和SigninScreen，旧高级页没有对应第四个实际回调 | 保留当前已有入口与typed查询/资格；本批不调整分组或增加业务能力 |

`examples/buaa-api` 没有原生UI、卡片语义或导航回调实现；本项不能向示例借UI行为。已有十二领域读取方法、DTO、协议和写入边界继续使用主[source-parity.md](source-parity.md)中各自操作矩阵。

## 九列不变性核对

| 本批操作 | CAS/bootstrap/service | 跳转/最终URL | Cookie/session | 方法/参数 | Header/编码 | 加密/签名常量 | DTO/解析 | 缓存/并发 | 错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| 普通功能八张卡的语义激活 | 不在卡片层认证；沿各目标页面原读取矩阵 | 不变 | 不变，不向语义节点加入会话材料 | 只调用该卡原onTap，不调用新读取接口或添加参数 | 不变 | 不变 | 原FeatureId/snapshot/label保留，不从标签猜路由 | 进入同一个已访问页面与原navigator；不增加请求或重试 | 只打开页面；原错误页/返回和写入确认均不变 |
| 高级功能当前四张卡的语义激活 | 沿研讨室/阳光/评教/签到各自原矩阵 | 不变 | 不变 | 同原onTap；不得把原生activate连到prepare/commit | 不变 | 不变 | 原展示/typed资格/target保留 | 原页面和WriteCoordinator生命周期不变 | 未认证、无资格或未知结果仍按原规则；不直接触发任何学校写入 |

## 最小修复与验证要求

外层声称是按钮的节点必须承载与可见卡片相同的tap动作，并避免把同一张卡暴露为两个彼此脱节的按钮；保留可读标签和物理手势。视觉、分组、卡片尺寸和原onTap目标不变。

正式测试需使用Flutter语义动作激活实际共享卡片，验证八个普通入口和四个当前高级入口均能打开正确页面；先观察行为RED，再最小修复并GREEN。物理点击、返回和既有导航测试继续通过。只修这一处原生按钮接线，不扩成完整无障碍认证或另造测试专用页面。最终仍需真实macOS的computer use操作；确定性语义测试不能替代实窗验收。

## 2026-09-15 实施事实

实施基点为 `41ece772c93749c4b592afd0cdf1e687fb45bb8e`。`_FeatureCard` 的外层 `Semantics` 新增 `onTap: onTap` 与 `excludeSemantics: true`：完整标签节点直接承载原点击回调，内部文字与 `InkWell` 不再另行产生重复语义。内部 `InkWell.onTap` 保留，卡片布局、可见内容、入口分组与原目标页均未改动。

正式回归文件为 `packages/ubaa_ui/test/navigation/feature_card_navigation_test.dart`。测试使用实际 `UbaaMainShell`、800×632 视口和合成成功快照，固定列出八个普通入口及研讨室、阳光、评教、课堂签到四个当前高级入口。每个入口经完整标签找到实际语义节点，从其所属 `SemanticsOwner.performAction(node.id, SemanticsAction.tap)` 激活，验证目标页面、按钮标记、完整标签、卡片子树仅一个 tap 动作、一次返回原分组及不新增读取；另有对应十二项物理点击与返回测试。

最终相同测试的 RED→GREEN 日志保存在仓库外私有 `macos-ui-20260915/navigation-actions/`：`red-current-sdk.log` 退出 1，十二项语义激活均未进入目标页，十二项物理点击通过；`green-current-sdk.log` 退出 0，24 项全部通过。RED 前已核对 `home.dart` 与基点无差异，测试副本为 `red-current-sdk-feature-card-navigation-test.dart`。既有导航、查询草稿、返回与迟到结果等相关回归 81 项通过，见 `navigation-regression.log`。以上均为确定性组件证据，本批未运行 native、live 或真实 macOS 窗口操作。
