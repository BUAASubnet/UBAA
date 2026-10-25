# 首页日程与临近待办来源核对

2026-10-25，实施前 `just refs` 通过：旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`，buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。本轮复用现有学期、周次与周课表公开接口，不新增或猜测日期查询协议。

## 双源逐操作比较

旧版核对 `ScheduleApi.kt`、`LocalScheduleApi.kt`、`model/dto/Schedule.kt`、`ScheduleRepository.kt` 及 `ScheduleRepositoryTest.kt`、`ScheduleViewModelTest.kt`；buaa-api 核对 `src/api/aas/{core,opt,data}.rs`、`src/request.rs` 与 `src/store/{cookies,cred}.rs`。认证恢复、跳转终点、WebVPN 映射、Cookie／凭据及加密细节沿[既有课表矩阵](source-parity-schedule-default-2026-10-23.md)、[离线来源](source-parity-offline-recovery-2026-09-17.md)和[认证修复](source-parity-auth-2026-10-21.md)，不修改其常量或规则。

下表相对路径均以 `https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/` 为基准。

| 操作 | 认证、跳转及会话 | 请求、参数、头与编码 | DTO、缓存并发、错误 |
|---|---|---|---|
| 学期 | 既有本科门户校验；CAS service 为 `https://byxt.buaa.edu.cn/jwapp/sys/homeapp/index.do?contextPath=/jwapp`；保持现有精确终点验证和账号／实际路线会话 | GET `student/schoolCalendars.do`，无参数；旧版 Accept `application/json, text/javascript, */*; q=0.01`、X-Requested-With `XMLHttpRequest`、映射后的 `homeapp/index.html` Referer | 仅唯一 selected 学期；共享现有读取合并，未知学期不取第一项 |
| 教学周 | 同上述门户会话，无新 Cookie、加密或签名 | GET `getTermWeeks.do`，query `termCode`，同 AJAX 头 | 以 requestTerm/responseTerm、number、startDate/endDate 定位目标日期；周次歧义、日期非法或缺失不推断周号 |
| 周课表 | 同上述门户会话，现有受调度的只读操作 | POST `student/getMyScheduleDetail.do`，form-urlencoded：`termCode`、`type=week`、`week`；同 AJAX 头，不加入 campusCode | arrangedList 的 dayOfWeek、beginTime/endTime、课程名称与地点；选出目标星期后投影为单日课程，保留完整度、实际路线及错误 |
| 单日展示 | 只对公开 DTO 做本地日期／时间判断 | 不调用新 URL，不改今日接口 rq；旧版在线今日入口固定读取今日，不能将其结果标成明日 | 沿旧版 Repository 的日期所属周与 dayOfWeek 过滤方式；新增用户要求的明日切换。按账号／路线／读代次／目标日期隔离，迟到响应不覆盖新日期；未知结束时间不判已结束 |

buaa-api 使用相同周课表路径，但通过 query 传递 POST 参数且含 campusCode；其学期查询 type=term，与旧版表单路径不同，不采用。buaa-api 没有同构学期／周次索引和首页明日切换；不借用 currentUser 的 week 值推断明日。研究生沿现有 Core 适配输出，不新增研究生协议。认证、网络重试和稳定错误码保持，新增的日期不可确定错误只用于首页展示，不改变 CLI 退出语义。

单日展示默认先查当前账号、路线、精确查询且完整的本地课表；缺失才走现有受调度读取。该本地优先策略用于首页的新增日期预览，复用旧版 offlineOnly 能力与完整学期投影；不改变课表页的在线优先策略。强制刷新读取线上，失败保留同日期已显示内容并提供重试。日期请求合并限定当前读取代次，学期／周次读取复用现有协调器，退出或切路线后的迟到结果拒绝发布。

## 本轮边界

首页入口仅保留真实最近使用记录，无记录时不伪造常用入口。待办沿原投影资格与排序，只增强相对时间和临近 48 小时的视觉提示，不能授予写资格。星期按校园日期计算；教学周来自真实覆盖日期；课程状态由完整合法时间区间决定。今日有课程且全部结束后显示明日，今日无课或时间未确定时保留今日。

## 实现与验证

- 首页移除校园生活和默认常用入口，仅显示已有最近使用记录；没有记录时不展示入口区。
- 待办保持原资格与时间排序，距截止或开始时间大于 0 且不超过 48 小时使用暖色时间；今天／明天保留精确时刻，不叠加重复倒计时。颜色在浅／深卡片上的对比度分别为 6.11:1／8.75:1。
- 课表显示校园日期、星期、确有日期覆盖的教学周和未开始／进行中／已结束／时间待定。今日有课程、结果完整且所有结束时间明确并已到达后显示明日；无课或未知时间继续显示今日。
- 单日结果带确切日期和教学周。跨午夜复用同日期课表并重新命名为今日；日期不符、周次歧义、无日期覆盖、周次索引不完整或排课缺少星期均不当作无课。显示路线随当前日程来源更新。
- 刷新保留同日期内容；失败可重试，账号／路线／读取代次失效后的结果丢弃。只有当前可见首页按分钟更新状态，不增加每分钟学校请求。

实施前反例分别复现了临近作业仍使用绝对日期、课程缺少结束状态、周次索引完整度被丢弃、缺失星期被误判为空日；均已修复。宽窄窗口用例改为在确实需要滚动的视口中验证主滚动；最近访问排序和下拉刷新覆盖保持。成绩提醒夹具使用未知结束时间，使成绩用例不随本机运行时刻自动切换日程，其原课程保留、提醒顺序、忽略和查看行为断言全部保留。日程切换由独立日历用例覆盖。

最终检查：`just check`、`just flutter-check`、`just flutter-codegen-check` 通过。七包分别为 Domain 60、Platform 87、App 674、UI 435、Bindings 20、Host 101、官方应用 78 项，共 1455 项。新增覆盖跨周／年界、午夜、时间边界、48 小时边界、读取合并、缓存账号／路线／查询／完整度拒绝、强制刷新、迟到结果、错误日期及显示路线。

`just verify-live mode=direct feature=schedule` 与 WebVPN 对应命令均退出 0，验证既有课表只读协议；未提交学校写入。明日日期选择与投影由上述确定性用例验证，未将既有接口成功扩大为所有日期数据均完整。

macOS 与 iPhone 17 Pro 模拟器各 16 个原生合成场景通过，分别导出 56 张 PNG，已目视核对明暗日程、状态、暖色时间与最近使用。媒体和真实只读日志均在仓库外私有目录：`UBAA-private-evidence/home-calendar-20261025-*`。模拟器已恢复关闭。Mac 锁屏阻止电脑操作工具读取实际用户窗口，应用内部的原生渲染验证已完成，实际窗口重启与查看待解锁。

最终 macOS Debug 构建与产物结构、签名及权限检查通过。用户窗口未重启，待手动解锁后继续实际窗口验收。
