# 独立工程审查 Rust 修复：实施前来源裁决

日期：2026-10-07。基线：`06e4dfdb`。范围：七类写入的确认路线原子化、十类共同回归、私有会话冲突原因、Judge/SPOC 日期运算复用。主审线程已运行纯校验 `just refs`；本阶段不运行 bootstrap，不发学校请求，不修改冻结目录。

## 来源与裁决

冻结旧版为 `examples/ubaa_old @ 1f4b8f8412272b6a423d4ad92b396e3db721e6f3`；独立示例为 `examples/buaa-api @ a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。直接读取旧版 `shared/src/commonMain/kotlin/cn/edu/ubaa/api/{feature,local}/` 的 Bykc/Signin/LibBook/Cgyy 接口与实现、对应 `model/dto` 及 `commonTest`；日期读取 `LocalJudgeApi.kt`、`LocalSpocSupport.kt` 及其测试。读取示例 `src/api.rs`、`api/boya/{core,opt,data}.rs`、`api/spoc/{core,opt,data}.rs`、`store/{cookies,cred}.rs`、`crypto` 及 `error.rs`。完整既有协议对照继续以 [source-parity.md](source-parity.md) 为依据；以下逐项限定本次变更。

日期补充核对冻结旧版 `gradle/libs.versions.toml` 的 Kotlin 2.3.20 与 `kotlin.time.Instant` import，读取 [Kotlin v2.3.20 Instant.kt](https://github.com/JetBrains/kotlin/blob/v2.3.20/libraries/stdlib/src/kotlin/time/Instant.kt) 的 `parseIso`。其大小写 T/Z、1–9 位小数、±HH/±HH:MM/±HH:MM:SS、最大 ±18:00 与拒绝闰秒规则不能直接等同于 Chrono RFC3339 的接受集合；因此保留很小的语法适配，将日期有效性、月份及跨日/时区运算交给已有库。超出 Chrono 可表示范围的文本保持原回退，不产生 panic；校园协议的既有四位年份及新增合成边界均覆盖。

交叉复核补充：同版本 `parseIso` 允许带符号、十位且首位为 0/1 的年份文本；`+0000002026` 的数值仍为 2026。正式合成 RED 证明先前 4–9/5–9 位正则错误回退该输入。修复只恢复这种词法兼容：先校验长度/符号/首位，再把数值规范化给 Chrono；不新增大年份运算，对超过 Chrono 范围、十一位或十位首位大于 1 的输入继续明确回退。

旧版部分写方法会认证重放，场馆还在重试块内发送最终提交；这不构成安全重放依据。本次遵守现行单次写入/unknown 合同，不恢复旧版重放。两个冻结实现均无 FRB 两阶段 intent，也无跨进程双槽修订冲突，因此不能从其 URL 或错误文字推断 intent 原子性。本次采用审查中当前代码的合成复现修复：确认 Direct 后不得因第二次 Auto 解析转到 WebVPN。

## 逐操作九列

“保持”表示本次只移动路线匹配/私有错误分类，不改变列内已冻结的请求或解析；不是省略核对。B 表示旧版 `LocalBykcApi/LocalBykcCrypto` 与示例 Boya；L 表示旧版 `LocalLibBookApi/LocalLibBookCrypto`；C 表示旧版 `LocalCgyyApi/LocalCgyySigner`；I 表示旧版 `LocalSigninApi`。示例 `api.rs` 未提供与 L/C/I 的座位、场馆、课堂签到等价模块，不借用名称近似的 Class 接口。

| 操作 | CAS/bootstrap 与 service | 跳转与最终 URL | Cookie/Session | 方法与参数 | Header/正文 | 加密/签名 | DTO/解析 | 缓存/并发 | 错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| 博雅选课 | B：SSO service 指向 `/sscv/cas/login` | B：从最终 URL/Location 提取 token；保持当前有界主机校验 | 当前路线 Cookie 与内存业务 token | POST `/sscv/choseCourse`，`courseId` | JSON 类型、双 token 头、ak/sk/ts | 冻结 AES-ECB、RSA PKCS1、SHA1 | 同 ID fresh detail 的 typed 资格；选课结果保持 | Core 单次路线解析绑定资格与 final；去掉 Bridge 重复详情复核 | 变化在 HTTP 前拒绝；最终最多一次、unknown 不重发 |
| 博雅退选 | B，同上 | B，同上 | B，同上 | POST `/sscv/delChosenCourse`，`id` | B 同上 | B 同上 | 同 ID fresh detail 与退选截止资格 | 与选课相同，保持 Core authority | 同上；资格冲突继续映射 OperationConflict |
| 博雅签到/签退 | B，同上 | B，同上 | B，同上 | POST `/sscv/signCourseByUser`，courseId/signLat/signLng/signType | B 同上 | B 同上；不更改坐标算法 | 当前学期 chosen/config，checkin/pass/时间窗/坐标 | 保留 fresh authority，绑定 intent 路线 | 输入与资格错误保持；final 不重放 |
| 课堂签到 | I：教室站点登录与 `/iclass` 既有 bootstrap | Direct `/eschool` 与 WebVPN 已冻结路径分别保留 | 内存 userId/sessionId，所属路线隔离 | GET timestamp；POST stu_scan_sign；query courseSchedId/timestamp，form id | sessionId Header，URL encoded | 无新增加密 | STATUS 与 result.stuSignStatus；保留 success=false | 原子路线内 fresh authority、时间戳及单次 final | 保留当前发送边界分类，不复制旧认证重试 |
| 图书馆预约 | L：图书馆 CAS 与独立 bearer token | 保持既有有界跳转/final 校验；示例无等价 | 路线 token 与主 Cookie 分离 | POST `/v4/space/confirm`，aesjson | JSON，Authorization bearer | 日期数字及逆序派生 key；固定 IV，CBC/PKCS7 | map/seat fresh 唯一座位、时段；结果布尔保持 | 同一路线预检和 final；不复用旧资格 | 同上，未知不得重试 |
| 图书馆取消 | L 同上 | L 同上 | L 同上 | POST `/v4/space/cancel`，正文仅 id；page/limit 仅 authority 查询 | L 同上 | 无额外加密 | 原分页同 ID active 记录、typed cancel target | 同一路线 fresh 查询和 final | 资格变化拒绝；不因回读重发 |
| 场馆预约 | C：manageLogin→`/api/login`；不新增 service | 保持当前路线包装，拒绝 final 跳转；不复制旧固定 Direct | cgAuthorization 与预约 token/challenge 各自范围保持 | day/info→order/info→captcha get/check→order/submit；现有字段集合不变 | 固定 Accept/Referer/app-key/timestamp/sign，URL encoded | 冻结 MD5 signer、验证码 AES-ECB | 同日期/空间/时段 fresh typed target；安全 receipt | final 之前有限验证码流程不变；新增 expected-route 原子匹配 | final 至多一次，任何发送后歧义 unknown |
| 场馆取消（共同回归） | C，同上 | 当前有界规则 | 当前路线 credential generation | GET orders/id；POST new/cancel/id，空表单 | C 同上 | C signer，无 captcha | canonical ID、状态及上海时间截止保持 | 保留已有 expected-route 原子入口，纳入共同合同 | 现行 strict success/unknown 不变 |
| 阳光打卡（共同回归） | 旧 LocalYgdkApi OAuth→campusAppLogin；示例无等价 | 既有有界 code 跳转，允许主机集合的旧 gap 不在本次猜测 | uid/token 当前用户与路线 generation | classify/item→upload→clockin；既有字段不变 | URL encoded/XHR；upload multipart | 无新增加密 | 正数唯一 typed target；上海日期和照片校验 | 保留已有原子路线；upload/final 各一次 | 现行成功、失败、unknown 与回读不变 |
| 教学评教（共同回归） | 既有 LocalEvaluationService 与示例 TES 对照沿主来源表 | 既有 CAS service/final 规则不变 | 当前 route/session 及内部 questionnaire | 既有按课程 typed 有序目标与问卷 final，不改正文 | 既有表单编码保持 | 不新增算法 | 四态逐课程结果，问卷不越 Core | 保留已有原子路线，无跨路线重放 | success/failure/unknown/unattempted 不变 |
| Judge 六个月截止 | 无新增请求；既有 Judge 激活/列表/详情 | 不变 | 不变 | 无新增参数 | 不变 | 无 | 月末钳制、时分秒保留；非法日期保持 None/false | 使用已锁定 Chrono 月减法；当前上海时钟策略不变 | 无新公开错误；示例无 Judge 等价截止算法 |
| SPOC 时间规范化 | 原 query/list/detail 不变 | 不变 | 不变 | 不变 | 不变 | 原零填充 CBC 不变 | 旧 Instant.parse→Asia/Shanghai；失败后 T 替空格、截断小数点；示例 Homework 保留字符串而非等价规范化 | 复用 Chrono/chrono-tz；不改变非标准字符串回退 | 不把兼容文本改成报错；非敏感合成边界用例先行 |
| 本地 Session 冲突 | N/A，本地修订 CAS | N/A | 当前双槽版本比较及清理保持 | 无 HTTP | 无 | 无 | UbaaError 四个 wire 字段不变；内部增加私有原因 | cause 随内存错误传播，不从 message 推断 | 真正 SessionConflict 才映射 OperationConflict；普通同文案错误不误判 |

## 兼容与实现约束

`UbaaError` 内部原因使用 `#[serde(skip)]`，不出现在 CLI、FRB 或磁盘数据。Core 错误公开构造函数 `UbaaError::new` 保留，code/kind/retryable/message 保留；仓库未发现结构体字面量构造或反序列化错误后参与写入控制流。新增私有字段意味着外部 Rust 调用者须用 `new`，不能继续自行构造结构体字面量；现行合同没有保证这种构造形式。补真实构造/JSON 兼容回归，并保证反序列化不能伪造可信内部原因。公开 JSON/FRB/磁盘版本不因此升级。

Chrono/chrono-tz 已存在于锁文件，不新增依赖。标准日期运算参考 [Chrono checked_sub_months](https://docs.rs/chrono/latest/chrono/struct.NaiveDate.html#method.checked_sub_months)、[RFC3339 解析](https://docs.rs/chrono/latest/chrono/struct.DateTime.html#method.parse_from_rfc3339)、[chrono-tz](https://docs.rs/chrono-tz/latest/chrono_tz/)。迁移保留协议 wrapper 和格式门禁，避免库解析器更宽松导致接受集合变化。

## RED/GREEN 记录

- 生产修改前：`cargo test --offline --locked -p ubaa_flutter_bridge api::write::tests -- --quiet` 编译成功后 103 通过、3 失败：完整博雅链最终路线 WebVPN 与已确认 Direct 不符；共同矩阵准确报出七类重复解析；普通同文案错误误判 OperationConflict。不是缺 API 的编译失败。
- 生产修改前：`cargo test --offline --locked -p ubaa-core 非法时区前缀 -- --nocapture` 的合成 `...15:59:59junkZ` 被错误转换为 `23:59:59`，未按冻结解析失败规则保留文本，1 项行为失败。
- 迁移中：补 Kotlin 标准偏移兼容用例并运行 `cargo test --offline --locked -p ubaa-core 冻结Instant -- --nocapture`，小写分隔被错误回退，1 项行为失败；随后按准确版本源码保留语法适配。原始安全日志位于 `<private-evidence>/legacy-tmp/ubaa2-engineering-rust-red.log`，不含学校账号或真实响应。
- 最终聚焦 GREEN：Bridge 写入 106 项通过（2.41 秒），SPOC 21 项（0.01 秒）、Judge 9 项（0.02 秒）、公开合同 7 项通过；日志 `<private-evidence>/legacy-tmp/ubaa2-engineering-rust-final-focused.log`。共同路线矩阵是 Rust Bridge 分派单元合同，合成 intent 只用于覆盖十类共有边界；另保留真实 prepare→commit 的博雅链及各领域现有准备/资格/正文测试，不将注入合同称为 UI 证据。
- 扩大验证：Core+Bridge 的 test-contract 运行先通过 Core 单测 340、Bykc 20、Cgyy 39、配置 3、连接 6、公开合同 7、评教 15、facade 116、公开边界 22、交互认证 19、内部边界 7、图书馆 26；随后旧 route_matrix 不能识别新的共享执行器而失败。保留原有计数守恒与原三类检查，将新七类逐函数验证放进 `tests/route_matrix/atomic_write.rs`；修正后 `cargo test --offline --locked -p ubaa-core --features test-contract --test route_matrix -- --quiet` 9 项全部通过（0.33 秒）。这次中途退出不记作完整工作区测试通过。
- `cargo clippy --offline --locked -p ubaa-core -p ubaa_flutter_bridge --all-targets --features ubaa-core/test-contract -- -D warnings` 通过（15.59 秒）。首次运行提醒私有 cause 未在 Debug 中说明省略，改为 `finish_non_exhaustive`，没有输出内部原因或放宽 lint。日志 `<private-evidence>/legacy-tmp/ubaa2-engineering-rust-green.log`。
- 最终只读复核：七类入口在 expected-route 比对后进入原 feature fresh authority；原发送前 Session 修订检查、非幂等边界和 `finish_routed_write` 未被绕过。Bridge 不再用 `message` 决策；内存 typed 原因不经 JSON roundtrip，外部 JSON 即使提供 cause 也不能伪造可信原因。
- 本阶段未调用真实账号、Direct/WebVPN 验证或任何学校写入。完整工作区门禁、FRB 机械生成检查和各平台证据由主修复记录另记，不继承既往通过。
- 十位前导零年份补修：`cargo test --offline --locked -p ubaa-core 带符号前导零 -- --nocapture` 编译成功后实际得到回退文本，1 项失败；修复后 `cargo test --offline --locked -p ubaa-core features::spoc::tests -- --quiet` 22 项全部通过（0.01 秒），Core 全目标、test-contract 的 Clippy `-D warnings` 通过（12.14 秒）。日志分别为 `<private-evidence>/legacy-tmp/ubaa2-engineering-rust-year-red.log`、`<private-evidence>/legacy-tmp/ubaa2-engineering-rust-year-green.log`。
