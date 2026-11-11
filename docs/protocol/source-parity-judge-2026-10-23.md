# 希冀获取修复实施前来源对照

日期：2026-10-23；UBAA2 基线 `01ab4f59`。本文件在生产代码改动前建立。

## 来源与冲突裁决

- 冻结旧版 `examples/ubaa_old`：`1f4b8f8412272b6a423d4ad92b396e3db721e6f3`。核对 `shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/JudgeApi.kt`（接口）、`model/dto/Judge.kt`、`api/local/LocalJudgeApi.kt`（请求、解析、Cookie worker、缓存与错误）、`shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalJudgeApiBackendTest.kt` 和 `JudgeApiTest.kt`。
- 固定 `examples/buaa-api`：`a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。`src/api.rs` 无 Judge 模块；最邻近的 `api/spoc/{core,data}.rs` 使用 SPOC token/AES JSON 协议，与希冀 HTML 不等价。另核对 `api/sso/auth.rs`、`request.rs`、`context.rs`、`store/{cookies,cred}.rs` 的认证、重定向、凭证及错误边界；不能借用 SPOC URL、加密常量、字段或错误语义，TLS 仍严格验证。

> 本段的聊天与 `docs/_audit/` 属于当时的仓库外补充材料，当前克隆无法复现；只保留历史来源说明，不将其登记为新的冻结引用。可复现的协议依据仍按[冻结参考](references.md)与本页实际受跟踪的测试定位核对。

- 用户引用的聊天 `01a15d06-1f02-7723-a877-ffbccbceb335` 已实际读取。其 UBAA 工作区审计 `docs/_audit/2026-10-21-judge-login-har.md` 记录 HTTPS service、原生登录页误判、历史整课排除与 WebVPN 网关共享课程状态。另仓库 HEAD 为 `d6dd8f2e5c8121e43f22cd1fbf15152ae87100e9` 且含未提交优化，仅作补充证据，未修改或替换冻结引用。
- 本轮新鲜公共上游观察：GET `https://judge.buaa.edu.cn/indexcs/simple.jsp` 返回 HTTP 200，含 `cgstuloginbtn`，其 SSO `/login` 链接的 service 为 `https://judge.buaa.edu.cn/`。只输出状态、固定路径与公开 service，不保存原始页面。
- 原 HAR 在 Downloads 中未找到，本轮不声称重新分析原 HAR；历史真实业务结果来自上述记录，当前账号验证单独记录。

冻结旧版 HTTP service 与本轮官网链接冲突：采用当前官网 HTTPS service。历史课程整课排除、WebVPN Cookie worker 独立性与用户引用的真实观察冲突：取消整课排除，WebVPN 同一客户端批量任务按课程串行，选课与业务请求不交错；Direct 保留独立 Cookie worker 与四并发上限。渐进读取原本通过原客户端逐批串行且每批重选课程，保留。

## 逐操作矩阵

所有行中固定 buaa-api 均无同协议实现，不通过类比补参数。下列「现状」来自 UBAA2；「旧」指冻结实现。

| 操作 | CAS/bootstrap 与 service | 重定向与最终 URL | Cookie/会话 | 方法与精确参数 | 请求头/正文 | 加密签名 | DTO/解析 | 缓存并发 | 错误/退出 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 业务激活 | 旧及现状为 SSO `/login?service=http%3A%2F%2Fjudge.buaa.edu.cn%2F`；改为官网证实的 HTTPS 编码 service | 旧跟随激活跳转；现有有界跳转固定路线，完成根目录 ticket 回调；`/indexcs/simple.jsp` 即使 200 也应拒绝，WebVPN 先解包判定 | 沿用所属路线 SSO/网关 Cookie；不暴露票据，不建立跨账号共享状态 | GET SSO，GET 服务回调；不增加业务 POST | 旧浏览器 Accept、`zh-CN,zh;q=0.9`、精确 Chrome 58 UA 保持；无正文 | 无新增 Judge 加密或签名；WebVPN 沿现有编码 | 不将登录页当数据；识别固定原生登录路径及登录按钮标记 | 现有批次 activated 复用保持；业务重新激活有界 3 次 | 保留 AuthenticationRequired 内部分支与 UC 仲裁；UC 有效/不确定时上抛 UpstreamUnavailable，UC 明确无效才失效主会话 |
| 课程索引 | 同上，先激活 | `https://judge.buaa.edu.cn/courselist.jsp?courseID=0`；最终地址经过现有允许列表 | 与对应路线一致；发现课程亦会影响网关当前课程，不能与本次批量 worker 重叠 | GET `courselist.jsp`，`courseID=0` | 同上，无正文 | 无 | courseId/courseName 字符串，排除课程 0，保留既有 HTML 链接解析 | 原 5 分钟非空缓存与代次保护保持；索引发现先完成再启动课程任务 | 原生登录页作为认证失败，非200/网络/解析错误保留原分类；空课程仍可合法返回空 |
| 每课程作业列表/全量摘要/诊断 | 同一激活 | 先 `courselist.jsp?courseID=<id>` 再 `assignment/index.jsp`；中间重新认证后必须恢复目标课程 | Direct worker 排除 Judge Cookie 后独立激活；WebVPN 共用网关会话，批量课程执行并发上限改为1，许可覆盖激活/选课/列表/详情全链 | 两个 GET；includeExpired 仅本地过滤，不作为上游参数 | 同上，无正文 | 无 | assignID 数字锚点、排除 problemContent/judgeDetails、非空标题及去重保持；诊断计数来自实际处理索引 | 5分钟非空列表缓存保持；取消历史整课排除；六个月过滤逐项进行，不因一条旧作业停止后续遍历 | 失败不发布成功空列表；沿用诊断/普通读取一致结果、稳定错误与 CLI 失败退出 |
| 单项/批量详情与渐进读取 | 同一激活 | 选课后 GET `assignment/index.jsp?assignID=<id>`；重新认证后先重选目标再重试业务 GET | 与列表同规则；渐进原客户端每批重选保持；WebVPN 批量不能跨课交错，Direct 保留独立会话 | GET；本地键为 courseId+assignmentId，不臆造 URL 中 courseId 参数 | 同上，无正文 | 无 | title/courseName/时间/分数均可选字符串；题目数和已提交数整数；提交状态枚举、题目列表和纯文本详情保持旧 DTO 对照及当前类型 | 2分钟详情缓存、输入顺序、重复键规整、生命周期失效保持；原持久缓存历史策略不扩成永久排除 | 不存在/无权限/格式变化保留原错误；有界重激活失败仍经 UC 仲裁，不抹平为成功 |

## 实施与证据要求

先建立脱敏回调/原生登录页、重新认证丢失选课、WebVPN 共享课程竞争、混合新旧作业及重复读取反例，再实施。完整核心/Flutter/敏感/冻结门禁，以及 Direct/WebVPN CLI 真实只读列表、刷新和详情分别验收。历史数量不作当前期望值。
