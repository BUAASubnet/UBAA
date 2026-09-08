# O3-D3 博雅旧版依据与公开字段上限（实施前）

2026-09-08。冻结old=`6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`，examples=`efb7976bf513f38364b88aeb83d704586cff9b2a`。本文件静态核对，不代表实现、测试或原生验收。

## 页面对应

| 旧版实际源码 | 必要优化 | 当前实现与待处理 |
|---|---|---|
| `BykcHomeScreen.kt`、`BykcViewModel.kt:95–111`：选择课程/我的课程/课程统计，按领域缓存 | 沿用三个入口和当前子标题，返回保留读取上下文 | O3-C菜单已恢复；内容仍通用fields |
| `BykcCoursesScreen.kt:544–677`：整卡点击，课程标题/状态→教师、地点、时间及选课时段→类别/自主签到→人数条 | 同结构紧凑卡片；搜索与全部筛选收纳顶栏，不保留旧源码的常驻大型筛选说明卡 | BridgeCourse支持名称/教师/地点、课程/选课/退选时间、容量/人数、状态、selected与独立资格；需要typed投影/详情导航 |
| `BykcCourseFilters.kt`：默认selected/preview/full/available，状态不限或含ended/expired才requiresAllCourses；状态、类别、校区多选交叉，full需区分容量已满 | 状态选择仍按旧语义，关闭面板保留；仅对当前页过滤时明确范围，不伪称服务器跨页搜索 | Core all=false仅本地过滤当前页expired/ended且保留服务器总数。App目前all固定true，不能偷偷改默认值而声称无行为变化。分类/校区字段上限见下 |
| `BykcChosenCoursesScreen.kt:104–277`：名称、教师、地点、课程时间/退选截止、类别、自主签到，底部考勤/考核/成绩 | 列表突出课程/时间/地点/状态，低频配置进详情；考勤状态与写资格分离 | BridgeChosenCourse保留这些公开字段和signConfig；必须区分record.id与courseId，不能由兼容展示ID生成写目标 |
| `BykcCourseDetailScreen.kt:117–417`：主色课程标题状态卡→基本信息→时间安排→适用范围/联系方式/简介/签到信息→底部动作 | 保留能由公开字段支撑的卡片顺序及原操作顺序，继续用typed资格；不复制旧版客户端重算写资格 | 当前Bridge详情仍返回BridgeBykcCourse，不含旧详情的简介/适用范围/联系方式/签到配置；签到动作仍在已选记录权威路径，不能借旧私有rawData补曝光 |
| `BykcStatisticsScreen.kt:43–173`：总体净有效次数主色卡→小类/通过指标/达标三列 | 小屏保持三列可读，必要行高随1.3字体变化；不增加仪表盘 | totalValidCount与qualified保留null为未知，不以分类数或passed>=required重算；空categories也不能丢已返回totalValidCount |
| 博雅资料独立只读查询 | 从顶栏查询保留现有入口，身份信息无需常驻课程首屏 | 仅既有id/realName/studentNo/collegeName白名单；不增加额外个人字段 |

## 读取与合同

旧API `BykcApi.kt:65–98`、Local `LocalBykcApi.kt:61–182/369–400`以及BackendTest课程、详情/已选/统计例已复读。五操作分别沿`source-parity.md`“博雅课程只读查询”的九列：相同CAS service与受限最终URL、当前路线Cookie和业务token内存范围；POST getUserProfile空对象、课程pageNumber/pageSize、详情id、getAllConfig选真实当前学期后查询已选startDate/endDate、统计空对象；双token/ak/sk/ts头及加密JSON；旧AES/RSA/SHA1常量和现有向量；公开DTO字段；单飞/缓存与失败语义不变。examples `boya/core.rs`、`opt.rs`和`data.rs`已复读，存在同业务协议，但其首次学期/估算学期、自动跳转token和错误解包差异继续采用已裁决旧版路径，不借示例改变认证或签名。

**明确字段上限**：`crates/ubaa-flutter-bridge/src/api/read/mod.rs`的BridgeBykcCourse没有category、subCategory、audienceCampuses、audienceColleges、audienceTerms、audienceGroups、description、organizer、contact、signConfig；列表和详情共用该结构。旧版源码具有这些能力不等于当前Host已获得字段。不得从课程名称/地点猜类别校区，不借已选记录给未选课程强行补关系，不修改Bridge v9或读取内部rawData来迁就UI。已选的category/subCategory/signConfig和统计的分类字段可以在其各自视图使用。完整旧版列表类别/适用校区筛选与完整详情因此存在公开数据边界，需显式记账，不能用空控件冒充保留能力。

## 待执行

先用脱敏RED固定课程时间/状态/容量、typed导航、已选记录id≠courseId及权威统计零/空/null；实现最小公开投影与旧版卡片/统计。所有查询能力和独立资格保留；按需面板草稿不重置，页面正文不出现大型搜索筛选卡。每批之后仍需聚焦/完整门禁、三端原生及真实只读，不能以本文件关闭BY-01–05或P4-D。
