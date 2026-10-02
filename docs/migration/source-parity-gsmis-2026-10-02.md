# GSMIS研究生课表逐操作对照

日期：2026-10-02。起点`178a4591`。旧版`examples/ubaa_old@1f4b8f8412272b6a423d4ad92b396e3db721e6f3`；示例`examples/buaa-api@a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。本页在生产实现修改前记录。

## 适用来源

旧版接口`shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/ScheduleApi.kt`、本地`api/local/LocalScheduleApi.kt`的withScheduleAccess/graduateSchedule、`api/feature/GraduateScheduleUpstream.kt`的fetchGraduateSchedule/checkGraduateResponse，以及`model/dto/GsmisSchedule.kt`和`GraduateSchedule.kt`构成协议与转换依据。测试为`shared/src/commonTest/kotlin/cn/edu/ubaa/api/GsmisScheduleTest.kt`、`GraduateScheduleTest.kt`和`GraduateScheduleUpstreamTest.kt`。课表UI与SectionTime来自旧版同名DTO及课表组件。

示例`src/api/aas/{core,opt,data}.rs`只实现本科byxt，`src/request.rs`负责共享请求、`src/context.rs`与`src/store/{cookies,cred}.rs`负责共享会话；没有GSMIS模块、字段、密码学或错误协议。不能借用其campusCode、query式POST或AAS service拼接研究生请求。现有本科协议和测试全部保留。

## 九列对照

表中“例无”指示例没有同协议操作，全部列均不按其他模块类比。

| 操作 | CAS/bootstrap与service | redirect/final URL | Cookie/session | 方法与精确参数 | headers/body | crypto | DTO/parser | cache/concurrency | 错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| 选择数据源 | 旧LocalScheduleApi先probe本科，成功读取优先；失败才实际访问GSMIS。例无 | 不以probe失败断言研究生不可用；不引入跨网络路线回退 | 旧标记username+authenticatedAt；当前用同客户端路线会话生命周期标记，不借外部浏览器Cookie | 本科现有请求不改；成功确认研究生后同会话后续直接GSMIS | 继承两来源已证本科headers；研究生如下 | 无新增 | 身份不能从学号规则推断 | 不缓存raw课表；标记不跨账号/清会话/路线runtime复用，迟到不得复活 | 本科失败可试GSMIS，最终失败如实返回，不造空成功；CLI沿安全错误码 |
| GSMIS引导 | GET `https://gsmis.buaa.edu.cn/gsapp/sys/wdkbapp/*default/index.do`；不手填service。例无 | 旧client自动跟随；当前继承有界8跳，只为此操作加入gsmis主机，WebVPN每跳同路线；最终SSO login拒绝 | caller当前Direct/WebVPN jar，认证由已有会话承担 | GET无参数无正文 | 旧未额外设置headers | 无 | 引导正文仅用于认证/HTTP检查，不当课表 | 每次fetch执行一次，不复制会话 | 401、SSO最终URL、CAS Login标题或execution输入为认证错误；非200失败 |
| 学期 | 旧引导后POST `/modules/xskcb/kfdxnxqcx.do`，例无 | 同上，不新增主机；POST重定向不提交第二份学校业务写入 | 同caller jar | POST空正文，无term/campusCode/XH | Accept=`application/json, text/javascript, */*; q=0.01`；X-Requested-With=`XMLHttpRequest`；Referer为同路线index.do；不伪造表单字段 | 无 | code的primitive文字为0；datas.kfdxnxqcx.rows且totalSize等于实际数；XNXQDM匹配四位年份+1/2/3；显示XNXQDM_DISPLAY；去重倒序首选 | 每次fetch读取；不是仅取得terms就假称整个GSMIS可用 | 缺字段/总数不符/畸形代码失败，不保存不完整索引 |
| 课表 | 旧POST `/bykb/loadXskbData.do`；例无 | 继承同路线认证判定；课表必须JSON，不删除未知脚本/HTML | 同caller jar，禁止复制浏览器token | 按原顺序`ZC=&XNXQDM=<term>&XH=&XQDM=`；term必须在学期列表中 | 上述三个headers，application/x-www-form-urlencoded | 无 | code文字1；jgList/rwList/jcfaList[].skjcList；所有课程term匹配、排课BJDM必须可关联；SCSKRQ减最早mask周/星期偏移得唯一周一，不猜开学日期 | 每次完整fetch，不存原始JSON；共享会话标记只在成功转换后生效 | 日历冲突、未匹配slot、非01位图/非法节次或时间失败；保持安全固定错误，不含rawbody |
| 周/今日/时间轴 | 无新上游地址，使用同一次完整fetch；例无 | 无新增 | 不创建新session | 周>0，今日用上海日期；无写入 | 无 | 无 | 按班号/课程/星期/地点/排序教师/mask/方案分组；去重节次与时间，仅合并相邻节；保留全部适用合法SectionTime，空周也返回；weeks为mask可查询范围，不是学校学期长度；today筛对应周/日 | 普通缓存保存规范化DTO，默认空时间轴兼容旧记录；导入仍要求完整校历 | 研究生考试没有对应协议，保留本科考试边界，不借课表推断考试 |

## 合同与实现裁决

旧版新增完整节次时间轴，当前WeeklySchedule无法承载。增设可选SectionTime列表，旧数据反序列化默认空；课程或元数据不包含额外个人信息。CLI JSON公开形状显式升级v11、Bridge升级v40并重生成，磁盘Session2/配置1不变。缓存仍保存类型化课表且旧记录可读，新增可选字段不删除旧缓存。UI仅增加旧版已有的时间文字/方案数据，维持七日网格与原有多端布局，不引入新产品样式。

实现前先观察GSMIS学期解析行为RED，再补请求/解析、校历、分组合并、空周时间轴、来源标记生命周期、缓存重读及Host显示回归。真实账号若只提供本科课表，不将本科live或Mock视为研究生live。当前校外业务验证使用WebVPN。
