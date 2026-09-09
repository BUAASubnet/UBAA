# P4-D 图书馆与场馆展示来源和接入计划

2026-09-08；静态读取当前 App/UI/Core/Bridge 与两冻结源。本文件为实施前静态核对；未运行测试或 native。路径相对 `/Users/moorefoss/Code/UBAA`。冻结 old=`6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`，examples=`efb7976bf513f38364b88aeb83d704586cff9b2a`。本计划不代表完成验证。

## 总体裁决

保留图书馆5个只读视图：馆列表、馆区列表、分区详情、座位查询、预约记录；保留场馆6个只读视图：站点、用途、日期空间、订单列表、订单详情、门锁状态。楼层作为馆列表中的typed嵌套选择，不虚构额外上游API。所有现有手输ID/日期/时间/时段/页码/容量入口保留；typed选择只填草稿，显式应用才请求。可另提供实体上的“查看馆区/详情”typed导航，明确其会发起读取，与填草稿区别开。

P4-D仅改变公开DTO到App presentation/UI的投影，不更改Bridge v9、Core参数、状态、资格、写入流程。父层搜索、草稿、分页与返回栈按已实现typed导航合同保留。无网络或真实写入授权由本计划推导。

## 当前问题与最小投影

| 视图 | 当前准确位置与缺口 | 最小typed展示/导航字段 |
|---|---|---|
| 图书馆馆/楼层 | `packages/ubaa_app/lib/src/bridge/read/libbook.dart` summary仅将storeys折为数量；`packages/ubaa_ui/lib/src/features/libbook.dart` 从`_detailFieldValues('馆 ID')`取picker | Library id/name/freeNum/totalNum +嵌套storeys(id/name/freeNum/totalNum)；带本次请求day上下文。进入areas携premisesId，选择楼层再携同父storeyId；不能以名称推ID。 |
| 馆区 | App同文件libbookAreas仅展示id/storeyId/余量，未保留premisesId归属；UI取FeatureField分区ID | Area id/name/areaName/premisesId/storeyId/freeNum/totalNum；按typed父馆/楼层关联，详情导航areaId，不凭当前页面标题或索引猜父项。 |
| 分区详情 | App只拼availableDates和slot.label，丢slot.id/start/end | AreaDetail id/name/availableDates/timeSlots(id/start/end/label)；原顺序、原字符串，不从label切出时间。不新增座位平面坐标。 |
| 座位 | App座位分支已有完整LibbookReserveAction，但正文仍通用fields | Seat id/name/no/status?/statusName +本次query的areaId/day/segment/startTime/endTime。action独立保留，不从id或状态文案重建reserveTarget。无目标也可展示未知座位。 |
| 预约记录 | App已有LibbookCancelAction和服务器pagination | Booking id/nameMerge/areaName/seatNo/day/beginTime/endTime/status?/statusName；独立资格/target及原page/limit/total。没有公开预约详情API，不能虚构网络详情入口。 |
| 场馆站点 | `packages/ubaa_app/lib/src/bridge/read/cgyy.dart` summary通用fields，UI从“站点 ID”反推 | Site id/siteName/venueName/campusName/seatCount?/reservationSpaceCount?/openStartDate?/openEndDate?/siteTelephone?；电话是场馆公开联系方式，可放更多信息，不变成用户资料。日期空间导航siteId；开放区间只展示，不自行裁定资格或构造可预约日期。 |
| 用途 | App已有source文案，未保留typed key | Purpose key/name+来源Upstream/StaticFallback；保留独立只读入口和表单typed选择，不能以用途名称当key，不能隐藏冻结回退来源。 |
| 日期空间 | App cgyyDayInfo循环中会continue丢弃所有非allowed/坏目标；只剩“可预约时段” | DayInfo venueSiteId/reservationDate/availableDates/reservationTotalNum? +timeSlots(id/beginTime/endTime/label) +spaces(spaceId/spaceName/venueSiteId/venueSpaceGroupId?/slots)。每slot保留timeId/reservationStatus?/startDate?/endDate?/eligibility与独立target。显示所有公开slot，包括denied/unknown，不能把结果计数称为全部可预约时段。 |
| 订单及详情 | App `_mapCgyyOrdersResult/_mapCgyyOrderDetailResult`通用fields；UI从“订单编号”反推 | Order id/venueSiteId?/reservationDate?/reservationDateDetail?/venueSpaceName?/campusName?/venueName?/siteName?/reservationStartDate?/reservationEndDate?/orderStatus?/checkStatus?/theme?/purposeTypeName?/joinerNum?；独立取消资格、cancelTarget、cancelledTarget。列表点击用正整数typed id→orderDetail；保留原分页number/size/totalElements/totalPages。 |
| 门锁 | App cgyyLockCode仅available | 仅available布尔与成功/错误状态；不得补锁码、token、二维码或复制敏感值入口。 |

公共字段位置：`crates/ubaa-flutter-bridge/src/api/read/mod.rs:345`(馆)、`:353`(楼层)、`:360`(区域)、`:370`(时段)、`:377`(详情)、`:384`(座位)、`:394`(预约)、`:408`(分页)；场馆`:487`(站点)、`:499`/`:509`(用途及来源)、`:514`(时段)、`:521`(预约target)、`:530`(slot)、`:539`(space)、`:547`(day)、`:560`(order)、`:581`(page)、`:601`(lock)。这些是本轮字段上限，Core中更多内部字段不等于Host可公开字段。

## 日期与时段：必须保留的边界

图书馆依据 `docs/design/ui-ux-redesign.md:70` 的“首日可确认”限制，绝不将相同timeSlots复制给全部availableDates。冻结 `LocalLibBookApi.kt:466` 把date.list中的非空日期收集为availableDates，却取原始第一项times为timeSlots；当前 `crates/ubaa-core/src/features/libbook/parser.rs:152` 同样如此，`:175` 还支持顶层timeSlots回退。Bridge AreaDetail没有日期→时段关联或解析来源标志。

**额外需裁决的细节：仅凭availableDates.first与timeSlots均非空，不能对所有合法公开DTO证明关联。** 原始第一项日期为空但有times时，availableDates过滤空日期后会以第二天开头，times仍来自第一项；顶层回退同样无显式日期关联。本轮不能宣称“非空即确认”。建议将首日作为明确受限的候选展示，只有经既有受支持来源合同确认关联的场景才自动组合；如果App没有这样的证据，首日也只读列示并保留手输，记录“当前数据未提供可确认的日期时段”。要普遍自动关联须另开来源RED与公开合同决策，不偷偷改Bridge或假设一对一。

Core内部 `parse_area_detail_for_day`（同parser`:193`）能从原始响应唯一选取指定日期，只用于内部权威逻辑；它不是现有Host公开按日详情API，不可借内存/反射/新请求调用它。Core最终预检可拒绝不匹配组合，不构成前端可随意组合的证据。

明确手输仍保留areaId/date/start/end/segment；“需核对该日期时段”的说明不修改原校验。Libbook座位读取方法参数为area/day/start/end，segment不参与座位读取但参与reserveAction，不能省略或拿显示label替代。选择slot若可确认，原slot.id/start/end同时回填；任何父馆/楼层/分区/日期变化应清空联动产生的旧slot/座位/action，不能用新日期悄悄重标旧action。手工草稿与已应用query分别保留，返回旧缓存须恢复其原上下文。

场馆DayInfo有明确reservationDate和venueSiteId，可以按它的availableDates选择后重新query该site/date；旧时段不直接迁移给新日期。timeSlot按唯一timeId关联，重复/缺失映射显示“时段信息不完整”，不能采用first匹配构造authority。reservationTarget中的timeOrdinal是当前fresh响应顺序，不是timeId排序、不是时间字符串推算；多选仅沿同站点/日期/space/group的typed target及已有连续性校验。

## 状态、动作来源

- 图书馆：`features/libbook/parser.rs:267` seat status1+非空目标allowed，2/3+目标denied，其它unknown；`:320` booking status1+目标allowed，6/8+目标denied，其它unknown。statusName仅展示，不授予资格。action定义 `packages/ubaa_domain/lib/src/write/actions.dart:136`及`:267`，保留prepare→确认→commit→固定查询readback与unknown停止边界。没有target不生成action，仍展示短原因。
- 场馆：`features/cgyy/parser.rs:417` 除reservationStatus，还检查身份、timeOrdinal及内部tradeNo/orderId/takeUp有效性；status1且未占用才allowed，其它已知状态denied，缺失/畸形/身份不完整unknown。因此**不能把denied一概显示“已占用”**，应以公开原始状态给保守文案并另显示不可预约；内部字段被Bridge有意剔除，不得补曝光来“解释原因”。
- App现只给allowed有效target生成CgyyReserveAction；P4-D保留此权威，不因显示denied/unknown而新增可点写入。现UI `_isUsableCgyyReserveAction/_cgyyReserveCandidates` 位于 `features/cgyy.dart`，按同site/date/space/group筛选并以typed timeOrdinal排序；不得从新presentation/FeatureField猜target。
- 取消：CgyyCancelAction定义`actions.dart:198`及hasCanonicalTarget`:220`，同时保留cancelTarget与cancelledTarget（已取消的幂等/回读语义），不是“订单ID存在就可取消”。订单状态和审核状态沿App既有 `_cgyyOrderStatusText/_cgyyCheckStatusText` 映射，并保留未知数值；显示理由不重算资格。
- 成功读取但无允许时段，不等于没有任何空间；新只读投影不能继续用allowed过滤造成假空。网络/解析错误不可替换为empty；stale显示旧数据及原query，不把旧action绑定到新筛选。

## 冻结来源与既有parity复用

| 领域 | 冻结API/DTO/本地实现/测试 | examples与已有parity列 |
|---|---|---|
| 图书馆 | old `shared/.../api/feature/LibBookApi.kt:23`、`:25`、`:31`、`:33`、`:42`五读；`model/dto/LibBook.kt:7`、`:16`、`:24`、`:35`、`:43`、`:51`、`:84`、`:92`；`api/local/LocalLibBookApi.kt:54`、`:57`、`:66`、`:69`、`:109`及`:466`日期投影；`shared/src/commonTest/.../LocalLibBookApiBackendTest.kt:68`含单日期times脱敏例，`:307`取消已结束错误；LibBookBookingStatusTest与LibBookReserveScreenLogicTest供状态/选择交叉来源 | 固定examples/buaa-api没有booking.lib/v4等价模块；不借其它预约API。`docs/migration/source-parity.md:264`九列覆盖基址、CAS跳转、独立token、五POST JSON方法参数、headers、只读无AES、DTO、缓存、错误；写入AES与preflight沿已有写合同，不重做无关协议。 |
| 场馆 | old `api/feature/CgyyApi.kt`、`model/dto/Cgyy.kt`；`api/local/LocalCgyyApi.kt:58`站点、`:63`用途、`:69`日期空间、`:182`订单、`:194`详情、`:207`锁；`:339`slot状态、`:477`day请求；对应LocalCgyyApiBackendTest、CgyyOrderDateDisplayTest、CgyyOrderCancellationTest、CgyyOrderStatusTest | examples/buaa-api无venue-zhjs-server等价实现；已有HAR说明是历史受控证据，本文未读取HAR/响应。`source-parity.md:594`逐操作九列覆盖站点/用途/日期空间/订单/详情/锁；`:278`及写批次矩阵描述提交边界；`:590`Bridge禁止交易号/内部占用审计等公开。不得由旧DTO含字段就向Host加字段。 |

## 实施顺序与关键RED（尚未执行）

1. App/domain增最小typed presentation，保留原FeatureField兼容与actions，不动协议。RED用“展示假ID vs typed真实ID”证明馆/楼层/分区/站点/订单导航来自DTO；各种异域presentation注入同FeatureId仍回退通用展示，不能cast崩溃或丢项。
2. 图书馆父选择与返回栈：同名不同ID楼馆/楼层隔离；返回保留父搜索和分页；换馆不能继续选旧storey，换分区日期不能沿旧segment/action；epoch变化伴新loading后success能补新选项，旧/迟到快照不能复活；仅填草稿不增加readContext，请求后精确检查其参数。
3. 日期关联RED：两日期不同times不能复制；首项空日期+times与第二日期不能错配；顶层times回退无来源不得自动确认；缺id/start/end或空列表只读保留；手输完整原值仍走既有query。该组是首日自动选择是否有证据的前置门槛，不得靠最后Core拒绝过关。
4. 场馆全状态RED：allowed/denied/unknown三slot都可读，只有allowed规范target可写；显示“可预约”字符串但unknown无target不能写；重复timeId不随意关联；同space名跨site/date不混组，timeId非顺序数仍按target.timeOrdinal；切日期后必须重新read，不能复用旧动作。
5. 订单/用途/门锁RED：正整数typed orderId导航；列表页1/2真实服务器元数据和固定路线回读不变；取消资格unknown/denied/已取消target状态不被展示status覆盖；用途fallback来源保留；门锁仅available，禁止新增原始data输出。
6. 手输兼容、600/1000断点、1.3长名称、手机键盘滚动与完整按钮可达；列表/详情筛选恢复。原生图由主代理冻结候选后独立执行；本计划不制作伪viewport或已通过截图证据。

最小文件范围建议：`ubaa_domain/.../presentation`新图书馆/场馆模型；App `bridge/read/libbook.dart`、`cgyy.dart`；UI `features/libbook.dart`、`cgyy.dart`及新领域内容part；`common/query_controls.dart`必要typed输入/缓存；沿既有FeatureReadNavigation与shell栈。保留所有原读视图与手填控制，不把领域展示改为通用字段表。完整跨日期自动图书馆时段关联维持阻塞，不改Core/Bridge v9。


## D1图书馆执行补记

O3-C已提交ba9fadde，现执行图书馆子批。库API/DTO/Local实现与Mock已逐段复读，原五请求和v9合同不改。5项投影行为RED在`/tmp/ubaa-old-d1-libbook-red.log`观察到presentation缺失，6项聚焦GREEN（含原取消回读）。与旧版相同的可见预约页初始楼馆/楼层/分区加载保留；没有自动跨日期时段配对，未调用真实写入。明确空结果不复活座位选择，隐藏页面不自动继续子查询。原生r1发现fixture默认页问题与测试按钮类型误定位，保留失败并修复后重跑；子批尚未完成三端实屏验收。


## D2研讨室执行前裁决

D1b已提交`50147317`，接续研讨室。逐段读`CgyyReservePickerScreen.kt`：校区→日期→楼栋/层横向芯片，房间×时段矩阵，选择后下一步；`CgyyOrdersScreen.kt`地点/状态/时间优先，主题/用途随后，详情与取消；`CgyyLockCodeScreen.kt`状态区。`CgyyViewModel.kt`保留首站点、换校区/日期/站点清旧选择及同房间相邻时段规则。必要优化为查询参数留在顶栏面板、矩阵固定房间上下文、选择后才显示下一步；现有typed确认流程保留。

再次核对old API接口、公开DTO、Local站点/用途/日期空间/订单/详情/锁读取与BackendTest；examples模块清单仍无同协议。逐操作认证引导、重定向、Cookie、方法参数、签名/编码、字段类型、缓存/错误继续采用本文件前述九列及`source-parity.md`“场馆预约只读查询”的当前实现补充，没有协议差异或新请求。此次仅补公开字段投影及UI自动可见页选站点读取，不改变网络层。门锁继续只有available，订单没有公开驳回正文、手机号或锁码，不仿造旧rawData内容。

D2投影以独立日期上下文条目保存原日期/可选日期/时段/空间（含无slot空间），其后逐条保留全部slot，包括denied/unknown/无target。写action仍只来自独立allowed完整target，不从新展示结构授予资格。重复timeId不取first时间；状态未知不伪装占用。读取成功但无允许slot不是empty。订单列表及固定路线回读用同一typed投影，取消资格与服务器元数据不改。先为这些缺口增加脱敏RED再实现。


## D2b 真实生产读取发现的零基订单分页偏差（修复前）

2026-09-08，生产macOS `ab1a777b` 真实直连：站点/日期表正常，但“我的预约”为空；同账号Core-live以page=0取得15条。静态定位App普通读取把query.page=0改成1，原Core/Bridge和取消固定路线回读均用零基，分页投影也错误地把number=1当显示第1页。此前合成backend沿错误的一基约定，未发现这个缺陷；不能把D2历史测试作为该行为的通过证据。

重新读冻结 `CgyyApi.kt:69` 默认page=0；`CgyyViewModel.kt:359–390`默认0并用响应number刷新；`LocalCgyyApi.kt:182–191/610–618`原样传page/size和number。`LocalCgyyApiBackendTest.kt:200–203/236`以page=1检查原样传值，是第二页参数透传测试，不能据此认定首页为1。旧DTOnumber默认0。固定examples模块清单与srs模块复读，srs是byxk选课而非研讨室，无cgyy订单等价协议；不借其分页规则。

操作级九列继续逐项采用`source-parity.md`“我的订单”：manageLogin/api/login业务引导；重定向和最终URL按当前路线；独立业务令牌；GET /api/orders/mine原样page>=0、size>0及nocache；既有headers与无正文；既有MD5参数签名；content/number/size/totalElements/totalPages公开DTO；不缓存订单、当前UI generation仍防迟到；错误不变。只修App误改页码与显示层换算，不修改Core、Bridge、认证、写入资格或公开合同。

裁决：FeatureQuery研讨室订单保留原始零基page，与取消回读query.page=0一致；通用FeaturePagination仍为一基展示，Cgyy number+1；页码输入1/2及前后页按钮在UI转成原始0/1。普通与固定路线订单结果使用同一投影，写入回读仍请求原始0不改。先增加默认首页、后页和UI输入/前后页脱敏RED，修复后复验原生与真实两路线。


## D1c生产只读发现：可空父标识阻断自动分区详情（2026-09-09）

基点8498d97f，冻结引用未变。WebVPN两轮生产UI分区列表成功2项，却无法自动进入详情；Direct安全结构计数确认两项premisesId/storeyId均为空，而请求本身已有馆/楼层，Core-live双路线五类读取通过。没有输出真实ID、名称、预约或响应正文。

复读冻结LocalLibBookApi.getAreas/mapArea（194–211、453–464）、LibBookAreaDto默认空字符串、LibBookViewModel.loadAreas（307–335）和主source-parity.md图书馆表：原POST space/pick请求premisesIds/storeyIds/date，解析两个父标识允许空；旧UI选返回列表中的原唯一area.id进入Space/map，未要求响应重复父标识。固定examples/buaa-api没有等价LibBook模块。现UI新增的非空父字段相等条件错误地把可缺省字段当成必需，不是认证或HTTP协议变化。

必要修复只在当前已接受分区查询的原数据上：父标识为空允许沿该请求的原馆/楼层继续读取原唯一area.id；非空且冲突仍不自动进入。绝不回填或伪造DTO父标识，仍保留queryDate与迟到/生命周期保护；座位查询仍须明确日期/原时段，预约资格与prepare/commit不变。URL/service、重定向、Cookie/token、POST方法/JSON字段、Header/编码、加密、Core解析/缓存/并发/错误均沿原合同；仅UI自动只读顺序恢复旧实现。先以明确缺省父标识合成失败测试复现，再修复并三端/生产双路线复验。


## P5-B 研讨室用途与独立表单（实施前，2026-09-09）

基点dcfb1570。完整复读冻结CgyyReserveFormScreen：单独页面，16外边距/12字段间距，已选时段→填写预约信息→附加选项；活动类型从CgyyPurposeTypeDialog选原key，人数默认1，活动内容至少3行、参与人说明至少2行。CgyyViewModel的初始化加载站点和用途，保留仍有效的原选项否则first；返回修改时段时保留表单。当前窄AlertDialog、手填用途编号和每次新建controller丢草稿偏离旧版。

用途逐操作核对：old shared CgyyApi.getPurposeTypes、LocalCgyyApi.getPurposeTypes/getPurposeTypesRaw/parsePurposeTypes/fallbackPurposeTypes、DTO CgyyPurposeTypeDto及LocalCgyyApiBackendTest的动态key=3和失败回退10项均已读取。固定examples的api模块清单无venue-zhjs协议，对本操作九列均不适用，不借srs的byxk参数。业务引导沿manageLogin→api/login；有界跳转/最终URL与路线隔离沿现Core；Cookie/业务令牌仍只归Core；GET /api/codes无新业务参数，nocache沿原请求器；Header/编码及MD5签名常量不变；只使用已公开key/name/isStaticFallback；原信封解析、Core回退与错误语义不改。App只增加独立用途选项读取，不覆盖已选时段snapshot；成功缓存按backend/生命周期/readCacheEpoch隔离，并发合并、失败可重试、迟到结果拒绝。

预约提交逐列继续采用source-parity.md的Cgyy预约提交矩阵：fresh上下文与一次性发送仍由原prepare/commit负责，不从展示名构造target，不增加手机号格式/文本长度/容量限制。表单草稿仅页面内存，账户/路线/生命周期失效即清除，不复制旧明文持久化。正文不再常驻编号输入，保留低频手填兼容入口；自然选择使用原唯一正key、标注冻结回退来源，异常不捏造列表。独立表单单顶栏实际路线并保留路线说明/策略入口；返回时段保草稿，继续确认只prepare，学校写入不运行。
