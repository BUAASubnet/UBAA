# Core 读取实现精简的来源对照

本轮只合并重复读取原语和内存解析步骤，保留公开 DTO、错误、请求顺序、分页停止条件、路线隔离及写前 fresh authority。没有执行真实认证、读取或写入。

冻结旧版为 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`，冻结 buaa-api 为 `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`，已运行 `just refs` 校验。以下文件均已只读核对：

- 旧版 `shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalBykcApi.kt`、`LocalSpocApi.kt`、`LocalSpocSupport.kt`、`LocalEvaluationService.kt`、`LocalLibBookApi.kt`，以及对应 `api/feature` 接口、DTO 和 `shared/src/commonTest/kotlin/cn/edu/ubaa/api/Local*BackendTest.kt`。
- buaa-api 的 `src/api/boya/{core,opt,data}.rs`、`src/api/spoc/{core,opt,data}.rs`、`src/api/tes/{auth,opt,data}.rs`。图书馆无等价模块，不适用。
- 既有逐操作结论见[来源对照索引](source-parity.md)的博雅、SPOC、评教和图书馆章节。本轮不选择另一套来源行为，也不扩大其授权或发布结论。

## 九列逐操作核对

表中“保持”表示继续使用当前实现与既有来源记录；转换后的 `Value` 只在同一操作的内存中传递，完整度不能兑换写入权限。

| 操作、CAS/引导 URL 与 service | 重定向及最终 URL | Cookie、Session、Token 作用域 | HTTP 方法与精确参数 | 请求头与正文编码 | 加密/签名 | DTO 字段及类型 | 缓存、并发、重试 | 错误、退出及产品语义 |
|---|---|---|---|---|---|---|---|---|
| 博雅资料 `getUserProfile`；旧版 `https://bykc.buaa.edu.cn/sscv/cas/login`，buaa-api 使用 SSO service 到该地址 | 两源均从业务回调取得 token；保持当前白名单、八跳和路线转换 | 两源业务 token；当前按路线内存保存 | POST `/sscv/getUserProfile`，JSON `{}` | 保持当前 JSON、Accept、双 token 头、Origin、Referer | 两源 RSA 包装 AES key/SHA1 和 AES-ECB；常量与加密器保持 | `id` 整数，身份/学院等可选字符串；直接消费已校验 data | 保持业务登录锁与既有请求策略 | 保持读取信封容错和错误映射；删除伪造成功信封的内存往返 |
| 博雅课程分页 `queryStudentSemesterCourseByPage` | 与资料相同 | 与资料相同 | POST，`pageNumber/pageSize` 整数；两源确认分页接口 | 与资料相同 | 与资料相同 | `content` 数组，分页整数；课程映射、过期过滤和完整目录投影保持 | 不合并两种公开 DTO，只共享同一次 data 解析 | 保持 `all` 过滤与无效课程错误 |
| 博雅详情 `queryCourseById` | 与资料相同 | 与资料相同 | POST，`id` 整数 | 与资料相同 | 与资料相同 | 保持详情 ID 校验、完整显示投影和写前严格计数字段校验 | 显示与写前读取继续分别请求 | 写前严格信封和 fresh 校验继续保留，显示配置不授予写权限 |
| 博雅当前学期 `getAllConfig` 与已选 `queryChosenCourse` | 与资料相同 | 与资料相同 | POST `{}`，随后 `startDate/endDate`；以冻结旧版精确字段为准 | 与资料相同 | 与资料相同 | 学期起止字符串、已选列表及嵌套课程；配置优先级保持 | 保持当前学期解析和请求顺序 | 显示配置标准化与写前 authority 分开；不沿用示例的估算学期 |
| 博雅统计 `queryStatisticByUserId` | 与资料相同 | 与资料相同 | POST `{}` | 与资料相同 | 与资料相同 | 保持统计 map、数量与分类投影 | 无新增缓存/请求 | 保持统计解析失败语义 |
| SPOC 当前学期 `inco/ht/queryOne`；CAS `/spocnewht/cas` 与 `/sys/casLogin` | 两源 CAS 相同，旧版另激活角色；保持当前八跳、最终 URL 和业务认证仲裁 | 旧版 token/role，示例仅 token；保持路线内 token/role | POST 固定 `param`；示例 queryOne 的最近操作不替代旧版常量 | JSON、XHR、`Token: Inco-...`、RoleCode；示例缺 RoleCode，保持旧版 | 固定 AES key/IV；本操作固定密文保持 | `mrxq/dqxq` 可空字符串；旧读取与 scan 各自校验保留 | 共享请求，保留登录锁与一次认证恢复 | 旧入口非空检查和 scan 空白/长度检查分别保留 |
| SPOC 课程 `jxkj/queryKclb` | 同上 | 同上 | GET，`kcmc=""`、`xnxq` | XHR、Token、RoleCode | 无 | 课程 ID/名称字符串，可选教师 | 共享课程请求/映射；旧入口仍容忍课程元数据失败，scan 保留仲裁 | 不改变元数据失败后的列表请求与完整度 |
| SPOC 全局分页 `inco/ht/queryListByPage` | 同上 | 同上 | POST，加密明文含 `pageSize=15/pageNum/sqlid/xnxq/kcid=""/yzwz=""`；示例按课程 GET 不等价 | JSON param、XHR、Token、RoleCode | 保留旧版 CBC 零填充规则；示例对齐填充不同，不采用 | 共享摘要映射/排序；分页整型默认值与 scan 回显检查分别保留 | 停止条件仍为无下一页、达到页数或空页；保持旧入口诊断计数 | scan 范围检查不隐式加入旧入口；解析失败和认证恢复保持 |
| 评教激活 `/pjxt/cas` | 旧版直接业务激活，示例 SSO service；保持当前终点 `/pjxt` 检查 | 同路线 Cookie，未新增持久 token | GET，无新增参数 | 保持现有请求头，无正文 | 无 | 无公开新增字段 | 显示容忍非认证错误，严格 authority 失败即止 | 不改变主认证失效、上游错误和显示空结果合同 |
| 评教 tasks → questionnaires → courses | 两源均为相同三个端点；保持每次精确最终 URL | 与激活相同 | GET；tasks `yhdm/pageNum=1/pageSize=10`，forms `rwid`，courses `wjid` | 无新增请求头/正文 | 无 | 保持 result/list/数组、rwid/wjid/msid 与课程字段；示例只取首任务，保持旧版遍历全部任务 | 共享 URL 与行解析，scan 保留分段游标；写前仍 fresh 全量读取 | 删除旧路径无人消费的完整度累计；显示容错与写前严格错误策略保持 |
| LibBook 楼馆 `space/pcTopFor`、分区 `space/pick` | 旧版 CAS service `https://booking.lib.buaa.edu.cn/v4/login/cas`，最多八跳；示例无等价模块 | 旧版独立业务 token；当前仍路线内存保存 | POST JSON；楼馆 `day`；分区 `premisesIds/categoryIds/storeyIds/boutiqueIds/date` | 保持固定 Accept/User-Agent、XHR、Authorization、Origin、Referer | 读取无加密 | 保持列表别名、原语兼容、楼层与父 ID；同一次 data 解析返回 DTO 和完整度 | 一次失效恢复；不改变请求数/顺序 | 缺失或丢项列表不可覆盖完整缓存；显式空数组可覆盖 |
| LibBook 分区详情/日程 `Space/map` | 同上 | 同上 | POST JSON `id` | 同上 | 无 | 一次解析 data，复用日期/时段结构；旧展平时段与逐日日程语义分别保留 | 不新增学校请求 | 保持日程关联检查、重复日期错误与详情容错 |
| LibBook 座位 `Space/seat` | 同上 | 同上 | POST `id/day/label_id=[]/start_time/end_time/begdate=""/enddate=""` | 同上 | 无 | 保持 nullable status、typed 写资格和座位排序；与完整度共享已解析 data | 失效恢复保持 | 完整度仅用于缓存，写前 fresh 座位校验保留 |
| LibBook 预约记录 `member/seat` | 同上 | 同上 | POST `type="1"/page/limit` | 同上 | 无 | 保持列表与分页回退、严格写 authority 的元数据检查 | 显示读取共享解析；取消前仍 fresh 同页读取 | 保持取消资格与未知结果保护；本轮不修改任何最终写请求 |

## 验证范围

本轮复用既有请求、解析、分页、完整度、扫描、写入资格及不可重放测试。字符串 Fixture 仍先经过真实信封检查，随后调用与生产相同的 data 解析器。生产代码没有为复用 Fixture 重新构造成功信封。

首页不可达旧分支移除后，SPOC 普通列表和详情的 observed 完整度也已没有消费者，因此连同内部包装一起删除。扫描的分页回显、范围和完整度检查继续保留。评教严格写前读取依然重新请求 authority，显示读取的错误容忍和分段扫描分别保持原有行为。

聚焦验证结果：

- `cargo check --locked -p ubaa-core --all-features` 通过。
- `cargo test --locked -p ubaa-core --all-features --lib features::` 通过 221 项，1 项手动性能基准忽略。
- `cargo test --locked -p ubaa-core --all-features --test bykc --test libbook --test evaluation --test facade` 整合后复核通过 184 项。
- 重构途中将 LibBook JSON 解码前移后，新增畸形 JSON 反例发现取消列表错误绕过固定安全文案。RED 显示实际文案为“图书馆响应无法解析”。将取消资格请求和解析的整个结果经既有安全错误映射后，prepare/commit 均返回固定资格核对错误，并且最终取消请求为零。该用例复跑通过。公开错误分类和可重试标记保持。
- Core Clippy 的协议与缓存变量命名诊断均已修复。最终完整门禁结果由[整合记录](2026-10-30-core-simplification.md)统一登记。

以上聚焦结果均来自脱敏 Fixture/Mock。整合后的真实账号 Direct/WebVPN 只读结果见[整合记录](2026-10-30-core-simplification.md)。检查日志仅保存在 Git 忽略的 `.ubaa_local/core_simplification/`。
