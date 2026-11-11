# 希冀任务内复用业务激活证据

日期：2026-09-23。P2-S为当前阶段，整体离线目标继续执行。

## 实施前来源与行为约束

## P2-S：希冀分段任务复用业务激活（2026-09-23）

macOS进程测量发现详情新鲜期过后完整读取显著变慢。代码核对：`features/judge/scan.rs` 对每次索引/详情都传入新的 `&mut false`，导致每个安全批次重复 CAS 业务激活。old固定1f4b8f84 `LocalJudgeApi.kt:245-368` 的 LocalJudgeClient 持有 `judgeSessionActivated`，成功后跨索引/详情复用；每次仍在courseSelectionMutex内显式选课，只有认证失效时清标记并有界重新激活。old最近等价测试为 `LocalJudgeApiBackendTest.kt` 和 `JudgeApiTest.kt`。buaa-api固定a63712fa的`src/api`模块清单没有Judge协议，不能借用spoc/cloud的URL、参数、DTO或错误。

| 操作 | CAS/跳转/会话 | HTTP/精确参数/头/编码/加密 | DTO/缓存/并发/错误 |
|---|---|---|---|
| 课程列表 | 首次激活沿`https://sso.buaa.edu.cn/login?service=http%3A%2F%2Fjudge.buaa.edu.cn%2F`，跳转/最终URL仍沿当前受校验get_with_redirects；同一路线原client Cookie | GET `https://judge.buaa.edu.cn/courselist.jsp?courseID=0`；沿`judge_headers`的Accept/Accept-Language/User-Agent；无正文和业务加密/签名 | parse_courses/字段不变；LIST_TTL不变；同Core client串行；现有认证/业务错误不变 |
| 课程作业索引 | 同任务已激活时复用，计划失效仍先拒绝；不复制Cookie | GET courselist.jsp?courseID=课程ID，然后GET assignment/index.jsp；头/编码/签名与上一行相同 | parse_assignment_list/字段不变；每批仍含完整选课+读取+会话收尾；完整/部分发布与历史复查不变 |
| 作业详情 | 同上；另一任务切课程不借用其选课上下文 | GET courselist.jsp?courseID=课程ID，然后GET assignment/index.jsp?assignID=作业ID；头/编码/签名不变 | parse_detail/ID字符串/字段不变；DETAIL_TTL、账号/路线/查询隔离不变；每批仍重新选课，允许在收尾后让位 |
| 业务认证失效 | 当前get_html继续原最多3次业务重新激活与主会话仲裁；不把原计划跨代次复活 | 原GET有界重试，无新端点/参数/加密 | 保留authentication_required/network_error等原分类；取消、clear、logout、路线及client代次验证仍在前后执行 |

拟通过任务内激活状态复用去除重复CAS；必须先以同账号同路线同计划多批读取的精确请求次数RED确认，同时证明所有索引/详情仍取全、每批仍显式选课，认证失效仍按原规则重新激活。该状态只属于当前Core任务和原client，不授予认证资格，也不并发改写会话。

P2-S已观察3项请求次数RED：缓存/无缓存完整扫描均多发为6次激活、认证失效前额外多发1次；全部索引/详情的覆盖断言先于次数断言通过。最小实现将激活标记保存在原Core计划，课程真实网络激活成功后传入；课程仅命中内存时标记仍为false，由首次网络批次激活。旧聚合入口仍传入独立false，不修改其隔离策略。增加缓存课程不授予新计划激活的回归，分段专项29项GREEN；原跨课程插队、取消、路线/客户端代次、部分失败及历史新增测试保留。完整just check最终通过，含CLI端到端16项及Bridge139项（另2项原有子进程隔离ignored）；FRB零漂移通过。Flutter1069项和7包分析通过。尚未据此声明真实App耗时或停滞已修复。


## 失败与修复边界

完整门禁首次发现测试内JudgeOnlineScan构造遗漏新增标记，补齐false；下一次发现4份Bridge脚本仍预期每批CAS，按已验证请求序列移除重复激活，保留每次选课及所有索引/详情，同时新增assert_exhausted，未放宽匹配或吞掉错误。对应失败日志保留，最终全门禁重新执行通过。

原生合成80项矩阵在macOS/iPhone/iPad模拟器运行通过，分别属于FFI和脱敏交互证据；学校新分段、重复刷新停滞诊断和最终三端性能仍独立验证。全部日志存仓库外`p2s-judge-activation-20260923`：

| 文件 | SHA-256 |
|---|---|
| `ubaa-p2s-activation-red.log` | `b48faa565cef3646afa1c7911b7b0a0d85352d8d6a6e895964450a32714ef008` |
| `ubaa-p2s-activation-green.log` | `5d00bce4c33cffe36da5c02f920eb803a2fa03e9e43ba9f54997777199a0e94c` |
| `ubaa-p2s-bridge-green.log` | `87dfa26be6a014c92f2ef05aeb67cadce2bd3bf2282146d05ba0bd41c6a42996` |
| `ubaa-p2s-check.log` | `aaec6ccbf802b4a2f94587c6aa50b32e470f1377142d1acdcbdab85889a33a0e` |
| `ubaa-p2s-check-green.log` | `c4711608dd62ae512b355cf2266b68420a7cec379a02d6b583ca74fba5596710` |
| `ubaa-p2s-check-final.log` | `f58f8a1451e827141248c0f4bd053e5e1229d4bac1d5e25507617eb008c11b65` |
| `ubaa-p2s-refs.log` | `534334fd86cb3a1e18d73f92643100e7433d193d4d49b1552ec9d7a1dd5639b3` |
| `ubaa-p2s-layout.log` | `4f00b00a68dd8c9e6e16234e025883051e3585b02de206ac445d05f4d7b39498` |
| `ubaa-p2s-sensitive.log` | `d8fa9ff95644cdc39ba415e264f162607fe7e9fc45f2f8f6f846a1f6bd6946ae` |
| `ubaa-p2s-codegen.log` | `1f0bcd15e0b680e82a713aa16e209763615a179d2b066bebca0904ce267a1cc7` |
