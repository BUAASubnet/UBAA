# 功能总览

UBAA 把常用 BUAA 校园服务集中到一个跨平台客户端中。普通功能侧重日常查询和课程作业，高级功能侧重需要额外上游流程或写操作的服务。

## 普通功能

- [课表与考试](/features/schedule-and-exam)：学期、周次、周课表、今日课程和考试安排。
- [成绩查询](/features/grades)：按学期查询成绩，并支持全部学期并发加载。
- [博雅课程](/features/bykc)：课程浏览、筛选、详情、已选课程、统计、选退课和签到签退。
- [空教室查询](/features/classroom)：按校区、日期、节次查询空闲教室。
- [SPOC 作业](/features/spoc)：当前学期作业列表、提交状态、截止时间和详情。
- [希冀作业](/features/judge)：聚合希冀课程作业、提交状态、分数和题目明细。
- [图书馆座位](/features/libbook)：查询楼馆、分区、座位，提交座位预约并管理预约记录。

## 高级功能

- [iHome](/features/ihome)：校园诉求搜索、回复与进度、支持、关注、个人记录和公告。
- [研讨室预约](/features/cgyy)：查询场地、预约时段、提交预约、查看订单和门锁码。
- [阳光打卡](/features/ygdk)：查看体育活动完成情况、历史记录并提交打卡。
- [自动评教](/features/evaluation)：读取待评课程并批量提交默认评教结果。

## 横切能力

- [登录与连接模式](/features/auth-and-connection)：统一登录、Token 刷新、验证码和直连/WebVPN/服务器中转选择。
- 首页待办会聚合博雅、SPOC、希冀、研讨室、签到和阳光打卡事项，避免用户进入多个模块后才能看到未完成事项。
- 公告和版本检查由服务端公开接口提供，客户端启动后按返回内容展示。

## 来源文件

- `composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/menu/RegularFeaturesScreen.kt`
- `composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/menu/AdvancedFeaturesScreen.kt`
- `composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/menu/HomeTodo.kt`
- `composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/navigation/MainAppScreen.kt`
