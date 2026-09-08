# 学业与课堂签到旧版界面对照（O3-E，2026-09-09）

基点 `eafa01f6`。冻结引用：ubaa_old `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`，examples/buaa-api `efb7976bf513f38364b88aeb83d704586cff9b2a`。本记录在E1生产修改前建立；E2成绩尚待单独补齐，不视作已实现。

## E1旧版依据—必要优化—当前实现

| 页面 | 逐段读取的旧版依据 | 保留与必要优化 | 基点差异及实施位置 |
|---|---|---|---|
| 考试 | `composeApp/.../screens/exam/ExamScreen.kt`全390行、ExamViewModel：已结束默认收起置顶；日期分组，未来升序/结束降序；日期时间线→课程/座位→时间→地点；未安排最后 | 三端同结构；单侧时间不丢；完整日期和低频字段按需详情；日期非法不推为已结束。结束时刻严格大于，缺失/非法结束时间按旧23:59。查询/搜索仍顶栏面板并保留草稿 | 基点手机大字段卡、宽屏表格和本地20条分页会让大量过去考试淹没未来考试；改共享考试时间线，对无服务端分页的考试全结果分组，保留真实分页元数据；不增加请求 |
| 课堂签到 | `screens/signin/SigninScreen.kt`全137行、SigninViewModel全文件：20内边距横卡，左课程与时间、右已签到图标或签到按钮，列表间距16 | 右侧操作仍原typed target/eligibility且经唯一协调器确认，已签到和资格未知不能凭展示字段放行；短风险提示保留；低频原始字段移本地详情 | 基点堆叠状态Chip、准备按钮和更多信息占高；收为横卡，评教已恢复的旧行保持；完整写入提交属P5 |
| 系统控件 | 旧界面中文标签；D5 macOS实窗发现默认菜单tooltip英文 | 共享Material/Widgets/Cupertino中文委托，包含日期时间等系统控件；不逐控件伪造tooltip | `ubaa_host/src/callbacks.dart`的MaterialApp与共享UbaaTheme接线；无业务读取变化 |

## 逐操作协议与投影复核

| 操作 | 启动/服务URL | 跳转/最终URL | Cookie/会话 | 方法/精确参数 | 请求头/编码 | 加密 | DTO/解析 | 缓存/并发 | 错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| 学期→考试 | 复读LocalScheduleApi的currentUser探测与exams.do，继承source-parity.md“未改变的课表/考试证据”及既有AAS激活 | 原Core允许主机与固定路线规则，不新增跳转 | 原路线内教务Cookie，不增加宿主会话 | GET `student/exams.do`，原样termCode；学期查询不变 | Accept `*/*`、XHR、homeapp/home/index.html Referer；无正文 | 无新增 | 复读dto/Exam.kt全字段及LocalScheduleApiBackendTest考试Mock；仍code0/datas→arranged，notArranged仅公开信封已有值。只用ExamPresentation，不输出考籍个人资料 | 原当前学期/请求代数不变；UI本地日期分组和折叠，无新缓存或网络 | 非法日期不隐藏；原输入/上游/解析错误与stale保护不变，不能伪空 |
| 今日签到 | 复读LocalSigninApi、SigninApi、LocalSigninApiBackendTest查询Mock。采用既有source-parity.md“课堂签到今日查询”的真实证据裁决 | 原8346 loginName解析与主机限制 | 原进程内独立iClass会话，禁止跨路线/写session文件 | 原GET get_stu_course_sched.action及id/dateStr，不改为示例POST | 原sessionId头，无正文 | 无新增 | 公开courseId/起止时间/可空signStatus及原SigninPerformAction；字符串/整数兼容仍由Core处理 | 原加载、刷新、代数和唯一prepare/commit保持；本地详情不请求 | 保留真实错误而非旧伪空；未知状态/目标缺失/资格冲突继续明确显示；没有真实写入 |

两来源差异：已读examples `api/class/core.rs`、`data.rs`：Class签到有等价业务，但示例新登录URL/POST查询/状态布尔解析不能整体移植，沿既有真实证据决定。考试最近对应为`api/aas`（不是iClass）；既有对照已记录相同AAS激活与不同campusCode查询，无等价考试DTO/UI，不借其字段。E1未改认证、Core、Bridge v9、资格、写入协议或参数。

验证计划：先日期边界/全结果折叠与顺序、签到右操作及未知状态、宿主中文委托RED；聚焦GREEN、全Flutter与根门禁；显式合成backend手机/平板/macOS实际渲染操作及独立实窗；生产双路线考试/签到只读，空结果如实记录。旧候选截图不能作为E1通过。
