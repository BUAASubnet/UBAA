# 首页考试待办

## 实施前来源核对

冻结旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`：核对 `shared/.../api/local/LocalScheduleApi.kt`、`api/feature/ScheduleApi.kt`、DTO `model/dto/Exam.kt`、`LocalScheduleApiBackendTest.kt` 和 `composeApp/.../screens/exam/ExamViewModel.kt`、`ExamScreen.kt`。考试安排所属列表区分 arranged/notArranged，旧时间轴按结束时刻划分；当前 `ExamPresentation.calendarDate/isFinishedAt` 已复刻日期和结束规则，首页复用该判断。首页新增考试待办是用户明确要求的展示扩展。

冻结 `buaa-api` 的 `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`：核对 `api/app/opt.rs/core.rs/data.rs`。其考试来自 `https://app.buaa.edu.cn/exam/wap/default/index` 的 HTML 内嵌 JSON，采用 App CAS 入口、专用 UA、exame_start_time/exame_end_time 字段；与旧版本科教务 JSON 协议不同，不借用字段、URL、会话或错误语义。学期和 AAS 激活继续沿主来源表。

| 操作 | CAS/bootstrap、重定向与最终地址 | 会话与请求 | 头、编码和加密 | DTO/缓存/并发/错误 |
| --- | --- | --- | --- | --- |
| 当前学期 | 既有 SSO service 指向 `https://byxt.buaa.edu.cn/jwapp/sys/homeapp/index.do?contextPath=/jwapp`；沿现有已知主机跳转、UC/currentUser 业务校验 | 当前账号、Direct/WebVPN 隔离 Cookie；复用 schoolCalendars.do GET 和现有学期选择，不推断学期编码 | 沿 LocalScheduleApi 与 Core 请求器的 Accept/XHR/Referer，无新签名或加密 | 保留 selected/code 与既有缓存；缺少当前学期保持原空结果/错误语义 |
| 考试安排 | 同上，不新增登录入口 | GET `https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/student/exams.do?termCode=原学期编码`，无正文 | Accept=`*/*`、XHR=`XMLHttpRequest`、Referer=`https://byxt.buaa.edu.cn/jwapp/sys/homeapp/home/index.html`，按路线包装；无加密 | 原课程名/号、日期、开始/结束时间、地点、座位、周次、状态、类型、taskId；原 code=0、datas 数组解析和本科不支持/网络错误语义。复用账号/路线/学期缓存与读取调度，不新增并发学校协议；不改 CLI 退出码 |

实现范围：考试加入首页默认来源与离线恢复。仅 arranged 且有效日期、尚未结束的考试生成待办；显示课程、时间、地点和座位，按开始时间排序，时间缺失时明确待定。点击进入考试安排。历史学期查询不覆盖首页默认来源；失败不清除已显示的缓存。没有新增公开合同或学校写操作。

## 验证

反例先行：Domain 期望三项未结束考试但实际得到空列表；首页加载测试期望考试来源但实际默认列表缺少考试，两者均失败。实现后领域日期/排序、默认读取、缓存恢复、来源替换与时钟推进、卡片跳转通过。补充当前学期首页与历史学期查询互不覆盖用例通过。

七包分包全量测试通过：Domain 54、Platform 87、App 663、UI 386、Bindings 20、Host 101、Flutter App 73；随后新增学期隔离用例及相关认证回归 11 项通过。原先考试首次打开才加载的宿主场景改为自动首页加载和卡片跳转；原惰性读取合同继续由成绩、博雅、教室、图书馆、研讨室和评教覆盖，认证与刷新期望同步加入考试。

macOS 明暗主题各一项完整首页原生流程通过，覆盖七来源排序、考试点击跳转、其他待办与合成签到准备后取消。正式 Debug 重建、产物结构及签名权限通过；真实账号首页已观察到考试待办，点击进入考试安排后返回首页。截图不纳入仓库，记录不含课程名称或考场等个人信息。

Direct/WebVPN `verify-live feature=exam` 均通过 prepare/login/status、学期、周次、课表和考试安排。没有学校写入。`just refs`、敏感扫描、布局及完整 `just check` 通过。检查先发现既有 iHome 测试 transport 函数超出 Clippy 行数限制；仅将空响应构造提取为辅助函数后完整复跑通过，独立提交该机械测试整理。
