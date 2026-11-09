# GSMIS研究生课表逐操作对照

日期：2026-10-02。起点`178a4591`。旧版`examples/ubaa_old@1f4b8f8412272b6a423d4ad92b396e3db721e6f3`；示例`examples/buaa-api@a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。本页在生产实现修改前记录。

## 当前学期选择（2026-11-09）

课表候选学期与当前学期分别确定。冻结旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 的 `GsmisSchedule.kt::parseGsmisTerms` 将代码倒序第一项标为当前，`GraduateScheduleUpstream.kt::fetchGraduateSchedule` 在未指定学期时取第一项，`LocalScheduleApi.kt` 的学期列表和今日课表均使用该默认请求。对应测试只有单学期请求样本。提前开放下一学期时，排序无法确定当前学期。

固定 buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81` 的 `api/aas/{core,opt,data}.rs`、`request.rs`、`store/{cookies,cred}.rs` 只提供本科当前学期与会话处理，研究生当前学期操作不适用。GSMIS 当前学期标志采用本页已接入的 [PR #98 固定来源记录](https://github.com/BUAASubnet/UBAA/blob/72e46968445b1357b880b53042f1c1ce90ad27db/docs/migration/evidence/2026-09-20-graduate-academic.md)中的 `getXnxqList.do` 与 `SFDQXQ`，复用现行 `academic/gsmis/academic.rs::exam_terms`。

| 操作 | 引导、重定向与会话 | 请求、编码与加密 | 字段与产品行为 | 缓存、并发与错误 |
|---|---|---|---|---|
| 课表候选列表 | 原 `wdkbapp/*default/index.do` 引导、同路线重定向及 Cookie | 原空正文 POST `modules/xskcb/kfdxnxqcx.do`，原 Accept/XHR/Referer，无新加密 | 保留 XNXQDM、XNXQDM_DISPLAY、完整性、去重与倒序；排序不产生 selected | 沿原会话、错误处理，不新增持久存储 |
| 默认学期与今日课表 | 复用 GSMIS `wdksapp/*default/index.do` 引导，沿现行最终地址、认证与同路线 Cookie 检查 | 空表单 POST `modules/ksxxck/getXnxqList.do`；沿该操作 Accept/XHR/Referer 和表单 Content-Type，无新签名 | 在考试学期中取得唯一 SFDQXQ=1 的 DM，必须与课表候选 XNXQDM 精确匹配，再标记课表 selected 并查询该学期；考试候选列表不替代课表候选列表 | 每次默认读取串行核对，不缓存用户选择；标志缺失、多个当前学期或当前代码不在课表列表时明确失败，不回退到最大代码或有课学期 |
| 指定学期周次与课表 | 原课表引导和当前路线会话 | 原 `loadXskbData.do` 与 ZC/XNXQDM/XH/XQDM 四项表单 | 保留显式学期校验、校历和周课表投影；不改用户指定学期 | 不依赖考试学期读取；不新增重试，课程空结果仍保留为空 |

当前学期的来源取舍见[决策记录](decision-log.md#2026-11-09研究生当前学期采用学校标志)。Direct/WebVPN 的新组合请求尚缺当前候选真实研究生账号证据，需在两条路线分别完成默认学期、指定学期和今日课表只读验收。

`wdksapp` 的 `GSMIS` 引导标签与既有“研究生课表”标签共用 `gsmis.buaa.edu.cn` 重定向主机许可。许可仅补齐已经接入的同主机业务引导，仍保留八跳限制、路线转换与未知主机拒绝。

Flutter 自动选择等待学期索引的在线读取结束，避免 `loading` 状态携带旧缓存 `selected` 时抢先切换查询。离线 `stale` 索引和已确定学期的缓存周课表仍可直接显示。`offline_test.dart` 保留离线自动进入、周课表加载中先显缓存及部分索引拒绝用例，另覆盖旧缓存选择下一学期、在线结果选择当前学期的切换。

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

## 2026-10-31：展示优先级补充

Core 与 Bridge 继续保留 GSMIS 的完整节次方案和课程时间。Dart 的第 1–14 节时间轴改用用户确认的 2026—2027 校历作息，适用于空周、在线投影、离线投影和 Android 课表组件导出。校历以外节次仍按接口与课程边界处理，具体取舍见[校历作息优先](decision-log.md#2026-10-31课表节次轴固定采用校历作息)。此次没有上游请求变更，也未执行真实学校请求。

## 2026-11-08：排课缺失作息方案编号

冻结旧版 `1f4b8f84` 的 `GsmisSchedule.kt` 直接按排课与节次的 `JCFADM` 匹配，`GsmisScheduleTest.kt` 只覆盖排课已有编号的响应。冻结 buaa-api `a63712fa` 的 `aas/core.rs`、`opt.rs` 和 `data.rs` 仅支持本科协议，GSMIS 缺失编号的处理不适用。

[issue #109](https://github.com/BUAASubnet/UBAA/issues/109) 记录了真实响应中排课 `JCFADM=null`、`jcfaList` 只有编号 `01` 的方案，以及补全编号后解析成功的观察。[PR #100](https://github.com/BUAASubnet/UBAA/pull/100) 提供对应 Kotlin 实现与脱敏回归。这里使用公开问题记录作为兼容依据，未取得原始个人课表或重新实测。来源取舍见[决策记录](decision-log.md#2026-11-08研究生排课缺失方案编号)。

| 操作 | CAS/bootstrap与service | redirect/final URL | Cookie/session | 方法与精确参数 | headers/body | crypto | DTO/parser | cache/concurrency | 错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| GSMIS 课表规范化 | 沿本页 GSMIS 引导，例无 | 沿现有同路线重定向和最终地址检查 | 沿当前会话与来源标记 | 沿 `loadXskbData.do` 的原有 POST 与四项表单 | 沿原有请求头和表单编码 | 无新增 | 排课 `JCFADM` 缺失、null 或空白时，仅从唯一 `jcfaList` 项的非空 `DM` 补全；起止节次仍须按编号各唯一匹配；补全编号保留在规范化 Row 中，参与合并和时间轴过滤 | 复用现有类型化缓存、会话代次和完整解析后交付 | 多方案、声明无编号、节次缺失/重复/不匹配继续返回 `upstream_changed`；已有明确编号不覆盖，不丢弃失败排课 |

## 门户身份分流与研究生成绩、考试（2026-11-08）

本次按用户要求采用门户 `d.info.identity` 选择学业数据源，替换本科失败后尝试 GSMIS 的规则。门户协议与既有 HAR 对照见[校园账户来源](source-parity-campus.md)。`本科生` 对应本科；`研究生`、`硕士研究生`、`博士研究生` 对应 GSMIS。这些标签是应用接受的精确分类，未知标签明确返回不支持，不按学号、子串或请求失败推断身份。身份仅缓存于当前路线和认证代次，注销、重新认证和会话清理后重新读取。

已对照冻结旧版 `LocalGradeApi.kt`、`GradeApi.kt`、`Grade.kt`、`LocalConnectionAuth.kt`、`GraduateScheduleUpstream.kt` 与现有 GSMIS 测试；固定 buaa-api 的 `api/app/{core,opt,data}.rs`、`api/aas/{core,opt,data}.rs`、`api/user/auth.rs`、`request.rs`、`store/{cookies,cred}.rs`。两个冻结来源均无研究生成绩和考试协议，在这些操作上不适用。新增操作取自用户指定的 [PR #98](https://github.com/BUAASubnet/UBAA/pull/98)，固定提交 `72e46968445b1357b880b53042f1c1ce90ad27db` 的 `features/gsmis/{mod,academic}.rs` 与其来源记录。PR 记录的旧 APK 验证和合成测试属于历史证据，当前候选仍需真实研究生账号验证。

| 操作 | 引导、方法、参数及头 | 响应与产品行为 | 会话、缓存、错误及来源差异 |
|---|---|---|---|
| 身份 | 既有门户 GET `/personal/frontend/data/info`，JSON Accept、XHR、Referer home；10013 时使用既有门户 CAS 引导一次 | `e=0,d.info.identity`，学院仍按既有资料解析 | 当前路线 Cookie；身份不写磁盘。失败不请求任何教务系统。两个冻结来源无此门户身份字段，沿用现有 HAR 证据 |
| 全量成绩 | GET `https://gsmis.buaa.edu.cn/gsapp/sys/wdcjapp/*default/index.do`，POST `modules/wdcj/xscjcx.do`，表单 `pageSize=12&pageNumber=1..` | `code=0,datas.xscjcx.rows/totalSize/pageNumber`；总数稳定、WID 唯一，完整读取后返回；成绩学期来自 XNXQDM/XNXQDM_DISPLAY | 只读串行分页，无自动重放，不借课表学期；两个冻结来源不适用 |
| 成绩字典及统计 | 同入口，非空成绩时 POST `modules/wdcj/cjfzdjcx.do` 空表单 | `datas.cjfzdjcx.rows/totalSize` 完整；CJFZDM 与 DM/MC 唯一匹配，DYJDZ/DYBFZCJ；百分制及有效性规则沿 PR98，GPA 与均分各自按有效正学分加权，空分母为 null | 不根据课程名称猜测计分；空成绩无需字典；不返回部分统计。两个冻结来源不适用 |
| 考试学期 | GET `https://gsmis.buaa.edu.cn/gsapp/sys/wdksapp/*default/index.do`，POST `modules/ksxxck/getXnxqList.do` 空表单 | `datas[].DM/MC/SFDQXQ`，独立于课表学期，代码唯一 | 两个冻结来源不适用 |
| 考试列表 | 同考试入口，POST `modules/ksxxck/getWdksxx.do`，表单 `xnxqdm` | success=true 且 countKs/countKcks/countJk 全零才返回空，任一正数明确不支持明细 | 不推断非空字段；两个冻结来源不适用 |

GSMIS 共用既有 TLS、有界重定向、Direct/WebVPN URL 与 Referer 转换、按路线和域/路径隔离的 Cookie；不硬编码 CAS service、票据或浏览器参数。XHR 头为 JSON Accept、X-Requested-With 与对应应用入口 Referer，表单 Content-Type 沿 Core。无新增加密或签名常量；SSO 落点、登录表单与401返回认证错误，非200及格式不符返回安全错误，不公开响应正文。
