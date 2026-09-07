# P4-D 博雅、阳光展示与导航计划

2026-09-08，仅静态核对，未改生产代码、联网、运行测试或native。路径相对 `/Users/moorefoss/Code/UBAA`。冻结old为6e75e120a26b0eefb3ab4a6f8251d1230db4a62e，examples为efb7976bf513f38364b88aeb83d704586cff9b2a。本计划复用现Core/Bridge，不能作为新写入授权或已验证结果。

## 最小typed字段与完整视图

| 视图 | 必须保留的公开字段 | 展示与导航 |
|---|---|---|
| 博雅课程列表/详情 | id、courseName/Position/Teacher、courseStartDate/EndDate、courseSelectStartDate/EndDate、courseCancelEndDate、courseMaxCount/CurrentCount、status enum、selected?；独立selectEligibility/deselectEligibility沿现actions | 课程/教师/地点/时间优先，报名与退选窗口、容量/已选数次级，更多信息保留ID。列表typed id→bykcDetail.courseId字符串（原正整数验证）；手输课程ID、页码/容量仍可用。状态译中文但不据文本计算资格。 |
| 博雅已选 | id与courseId分别保留；课程名称地点教师开始结束、selectDate、courseCancelEndDate、category?/subCategory?、checkin?/score?/pass?、signConfig四时间窗口和可用签到范围摘要、courseSignType?；三项资格沿actions | 课程查询及退选/签到/签退均用内层courseId，不能误用已选记录id。已选可点击课程详情，不新增已选详情API。原始考勤/考核未知单独呈现，不把null当0；courseSignType只展示，不改资格。 |
| 博雅统计 | 集合totalValidCount?；categories逐项categoryName?/subCategoryName?/requiredCount?/passedCount?/qualified? | 分类卡或表格保留可选值；达标直接用qualified，不能由passed>=required重建业务结论；有效总数不能由分类相加得到。集合无分类但有总数也要显示，不误判空数据。 |
| 博雅个人资料 | id、employeeId?、realName?、studentNo?、collegeName? | 展示原有姓名/学号/学院，employeeId仅更多信息；这是博雅资料，不填回主用户department或覆盖主用户身份。无证件/联系人新请求。 |
| 阳光概览 | summary的termId?/termName?/termCount/termTarget?/weekCount?/weekTarget?/monthCount?/monthTarget?/dayCount?/goodCount?；classifyId/classifyName/defaultItemId/defaultItemName；items(itemId/name/kind?/sort?) | 学期/周/月进度及当日/有效次数，保留null未提供；分类名称和默认项目作说明，不凭默认ID建立提交target。项目列表按响应顺序，不因sort字段任意改排序。选择项目只用既有YgdkSubmitAction。 |
| 阳光记录 | recordId/itemId?/itemName?/startTime?/endTime?/place?/imageCount/isOpen/state?/createdAt?/createdAtLabel?；page/size/total/hasMore | 时间、地点、项目、公开性、图片数量优先；状态数值未知保留，不猜含义。createdAtLabel优先沿原显示回退createdAt，不重新解释时区。仅记录列表，无公开记录详情/图片读取API，不增加网络详情按钮。 |

公开上限位置：`crates/ubaa-flutter-bridge/src/api/read/mod.rs:232`博雅profile、`:255`course、`:309`chosen、`:331`statistic、`:339`statistics；阳光`:421`item、`:430`termSummary、`:443`overview、`:452`record、`:466`page。Core对应`crates/ubaa-core/src/domain/bykc.rs`、`ygdk.rs`。原始附件路径、内部业务标识、照片URL不是因此可增加的展示字段。

## App现状与接入位置

`packages/ubaa_app/lib/src/bridge/read/bykc.dart`五个switch分支都输出通用FeatureField：列表漏课程开始结束与selected等公开上下文；已选漏selectDate/category/subCategory/退选截止；统计只把totalValidCount编入summary字符串；profile未投影employeeId。P4-D应直接从Bridge对象构造typed presentation，保留现fields兼容与actions，不从旧summary/翻译状态/字符串ID反解析。列表和详情重复课程投影宜共用明确的mapper，避免字段漂移。

`packages/ubaa_app/lib/src/bridge/read/ygdk.dart`中 `_mapYgdkOverviewResult` 当前仅项目ID/kind与学期计数字符串，丢大量集合字段；`_mapYgdkRecordsResult`当前丢itemId/state但保留图片数量。普通加载和 `_loadYgdkOverviewOnRoute/_loadYgdkRecordsOnRoute`已经共用这两mapper，新增typed字段必须继续共用，不能只修普通查询而让写后回读退回旧模型。

可复用P4-C拟定集合overview传递设施。依据 `docs/design/ui-ux-implementation.md:95`、`:229`、`:235`：FeatureOverview独立于details，穿过FeatureResult/FeatureSnapshot/copyWith/Controller/返回帧/写后回读。新增BykcStatisticsOverview(totalValidCount)、YgdkOverview(summary+分类/默认项目)；不能把总计塞进伪课程首行或从summary拆数字。若C设施尚未落地，依赖它的全链契约先完成，不能只加DTO并忽略生命周期。新query清旧overview，同query stale保留，显式空结果清旧或采用当前overview，只有overview而details空仍展示；局部搜索/分页不重算总量。

## 资格、位置与照片边界

博雅actions已经由App创建BykcSelectAction/BykcDeselectAction/BykcSignAction。列表detail取item.id，已选取item.courseId。保留原typed eligibility及requiresCoordinates；status enum、selected、checkin、pass、人数、截止文本都不能用来重建action。特别是现App“通过”文案使用pass>0，不应将它当作Core的pass==1业务判定。

现 `_requiresBykcCoordinates` 检查配置为空/空点/非有限或越界坐标/非正半径；这是输入能力提示，不是签到许可。Core最终prepare/commit会fresh预检和沿冻结位置规则处理。展示可用“指定范围n处/位置配置未知/需要当前位置”等摘要；不必把所有经纬度铺进课程卡。权限或平台能力不可用应明确提示并保留草稿，不自动生成虚构坐标，不以缺定位把只读课程隐藏。

阳光 `read/ygdk.dart::_ygdkSubmitActions` 已要求分类ID/name有效、项目ID/name有效、项目ID唯一，且allowed target的classifyId/itemId与概览父分类和项目准确一致。保留这层校验，重复项目、缺目标、target错父分类不能从默认项目或名称修复。新展示应能说明unknown/能力不足而不把它们变成可写。

阳光记录图片只读**imageCount**：Bridge `read/mappers.rs:565`将Core images长度映射为计数，BridgeYgdkRecord没有原图URL。禁止Image.network、远端原图抓取、缩略图下载或URL复制入口。用户为本次提交主动选择的本地照片是另一条已有能力：`packages/ubaa_ui/lib/src/write/ygdk_form.dart:87`选择器、Image.memory本地预览、`:116`无能力提示、`:199`释放引用。可保留此本地预览，不把它等同历史记录图片展示；取消/关页/换账号清照片引用，日志不打印字节。地点目前是文本字段“打卡地点”，不擅自新增GPS上传参数；照片选择能力和地点填写能力分别说明。

所有写操作仍复用单一WriteCoordinator：准备、确认、提交结果、unknown不自动重试、固定路线一次读回。`packages/ubaa_app/lib/src/write/receipt_verifier.dart:72`、`:134`、`:205`保存原readbackQuery与阳光概览/记录回读说明；阳光两OnRoute方法使用pinnedRoute，不能在刷新时重新Auto选路线。博雅既有查询readback也不能由新导航当前草稿替换。

## 分页与读取语义

博雅列表目前bykcCourses(page<=0→1,size clamp1..100,all:true)，保持all:true，不因为UI只显示报名可用而改请求/总数。服务端number/size/totalElements/totalPages原样显示；已选不接受新学期参数，Core按冻结当前学期策略选择，不从页面日期重算。

阳光records默认page<=0→1、size clamp1..100；pinned读取明确拒绝非正page/size，保持原有调用契约，不统一重写边界。page/total/hasMore均为返回元数据，不以当前过滤后的条目数重算。概览不是当前记录页的聚合，统计缺失不能通过分页样本补算。

## 两冻结来源及既有parity

- 博雅API：old `shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/BykcApi.kt:16`至`:30`；DTO `model/dto/Bykc.kt:62`课程、`:99`详情、`:171`已选、`:206`签到配置、`:237`资料、`:255`统计；`api/local/LocalBykcApi.kt`五读映射/当前学期选择/资格及 `LocalBykcCrypto.kt`。测试`LocalBykcApiBackendTest.kt:71`列表资料、`:307`详情已选统计、`:435`写、`:526`WebVPN；本轮只读不执行。
- examples的`api/boya/opt.rs:19`课程页、`:37`详情、`:50`已选、`:63`统计为最近同端点交叉证据；其调用方传Semester和简单写方法不能替代旧本地产品的学期选择、加密及资格。`docs/migration/source-parity.md:541`五读九列已完整说明CAS/service、跳转、Cookie/token、每操作精确方法参数、编码/签名、DTO、缓存与错误；`:331`及`:529`解释签到/签退窗口/位置规则，`:590`Bridge附件/内部字段收窄。只复用，不重开协议。
- 阳光API：old `api/feature/YgdkApi.kt:21`概览、`:23`记录、`:25`提交；DTO `model/dto/Ygdk.kt:6`统计、`:20`项目、`:28`概览、`:38`记录、`:53`分页；`api/local/LocalYgdkApi.kt:63`、`:82`、`:107`三操作。测试`LocalYgdkApiBackendTest.kt:63`概览、`:113`记录、`:182`提交、`:249`会话复用。旧DTO有图片集合不代表当前Bridge可以公开图片。
- examples/buaa-api无阳光等价模块，不借app/spoc上传协议。`source-parity.md:256`九列记录OAuth/独立uid-token/分类-项目-汇总/分页参数/表单/DTO/缓存/错误；`:457`写入九列保留照片上传和最后提交边界。OAuth完整允许主机集合仍为既有未决项，不在展示批次猜补，不将历史live陈述当本候选PASS。

## 下一批关键RED（尚未执行）

1. 展示假课程ID与typed id冲突，列表和已选详情导航用正确ID；已选record.id与courseId刻意不同，三个动作仍用courseId。手输和五个博雅/两个阳光只读视图保持可达。
2. 博雅status看似available但eligibilityunknown/denied；已选通过文案与原始pass异常值；时间或人数看似允许但资格未知，均不能新增可写。字段缺失、unknown分类和无定位能力仍可读。
3. 博雅统计只overview无categories；阳光项目为空但summary存在；新query/空结果/同query stale/返回旧父页/固定路线回读分别验证overview生命周期。qualified与计数刻意冲突仍沿typed布尔，null目标不变成0/0达标。
4. 阳光重复itemId、目标分类不匹配、默认项目ID未在有效target中、allowed缺target，均不得合成action。普通加载和OnRoute回读相同typed投影，pinnedRoute及原页码不得漂移。
5. 阳光记录三张图片只显示3，无URL/网络图片请求；state未知数值保留；本地选择照片取消/权限失败保持表单且最终清引用。手机键盘/1.3长文本/600和1000断点下卡片与写表单按钮可达。
6. 服务端第1/2页元数据、局部搜索不改total；写后刷新不采用未应用草稿；新增定制内容不绕过原action消费者或结果确认。实际native由主代理冻结后另行执行。
