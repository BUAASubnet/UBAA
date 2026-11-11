# Rust Core 精简与缺陷修复

基线：`7348b8b3693d2254aa72c160911317955123a0f9`。本轮保留开始时的 OHOS、工具链及状态文档改动，所有实现只按明确路径提交。用户在当前会话授权必要的真实账号、网页及可撤销写操作检查。只有验证需要时才执行学校请求，写请求发送后的未知结果仍先只读核对。

## 修复方案与完成条件

| 发现 | 实施方案 | 验收条件 |
|---|---|---|
| 七处缓存刷新重复且退出/替代处理不同 | 先证明 Judge/今日课表迟到结果问题，再共享准备和发布收尾 | 失效结果拒绝返回，普通磁盘失败仍允许在线结果，各领域缓存测试通过 |
| RouteClient 与 UbaaClient 重复安全编排 | 共用已选路线的会话检查、清理和写入收尾，保留公共入口 | Direct/WebVPN 隔离、会话 CAS、写后结果保护和全部 CLI 合同通过 |
| SPOC 两套学期/分页/投影/排序 | 共享协议读取步骤与投影，分别保留一次性和分段调度 | 精确请求、原容错策略和分页完整度覆盖保留 |
| 评教重复遍历且计算无消费者的完整度 | 共享任务、问卷与课程读取步骤，删除无效累计 | 显示容错、fresh authority 和单次写入保护保持 |
| 博雅 JSON 反复序列化/解析 | 已验证 data 直接传给领域解析器 | Fixture 与请求合同保持，移除内存中的伪响应包装 |
| LibBook 重复解析正文 | 一次 JSON 解码同时产生 DTO 与完整度 | 缺列表/畸形内容不覆盖旧完整缓存，预约/取消资格不放宽 |
| 多种业务凭据重复锁与生命周期代码 | 共享小型私有凭据状态，保留各领域 typed 值、独立登录锁和失效范围 | 原并发、失效代次、脱敏测试通过 |
| 旧单路线磁盘写入参与生产编译 | 生产只保留双路线写入和旧格式读取迁移，旧造数入口留在测试 | 旧数据迁移、CAS、权限和冲突测试通过 |
| 首页旧分支、重复守卫和重复测试 | 删除不可达分支，收敛重复检查，保留一份相同测试 | 删除项逐项登记对应保留覆盖 |
| 无效 legacy_priority 与历史格式 | 按用户后续决定移除旧缓存迁移、兼容列和策略计算；格式升级后旧版本明确要求重建 | 当前格式可重开，旧版本安全拒绝，显式重建及当前加密/隔离覆盖保留 |
| Cgyy 记录敏感正文 SHA1 | 先增加日志失败反例，再删除正文摘要及专用函数 | 登录、订单、写响应和门锁日志均不含正文或摘要 |

来源比较由[缓存专项](2026-10-30-core-cache-simplification.md)、[协议专项](2026-10-30-core-protocol-simplification.md)、[边界专项](2026-10-30-core-boundary-simplification.md)及下文记录。公共 CLI/Bridge 合同保持，FRB 重生成必须零漂移。完整确定性检查采用[开发命令](../development/commands.md#检查选择与完成条件)，按改动计划始终使用本页基线。

## 凭据与日志来源比较

冻结引用经本轮 `just refs` 确认：旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`，buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。

旧版对应实现位于 `shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/Local{Cgyy,Bykc,LibBook,Ygdk,Signin,Spoc}Api.kt`，各客户端分别拥有登录锁、业务令牌与缓存清除。buaa-api 已读取 `src/store/cred.rs`、`src/cell.rs`、`src/request.rs` 和对应 `api/boya`、`api/spoc`、`api/class` 实现。buaa-api 的 iClass 凭据及路径与适用旧版不同，维持既有来源裁决，不能在本轮复用其字段。buaa-api 无同一 Cgyy、LibBook、Ygdk 协议，相关列不适用。

| 操作范围 | CAS/service 与最终 URL | Cookie/业务凭据 | HTTP 方法/参数 | Header/编码 | 加密/签名 | DTO/解析 | 缓存/并发/重试 | 错误/退出与产品语义 |
|---|---|---|---|---|---|---|---|---|
| Cgyy 登录及全部响应日志 | 沿用 LocalCgyyApi 与当前 auth 引导；不变更 URL/跳转 | 独立路线内存 token，登录解析仍取 access_token | 日志删减不改发送 | 签名请求和正文不变 | 业务签名保留，仅删除日志 SHA1 | 不改业务解析；日志只保留安全元数据 | 独立登录锁及原重试边界保留 | 只减少日志字段，不改错误结果 |
| Bykc/LibBook 凭据槽位 | 各自 feature 继续拥有原 CAS 与回调校验 | 保留 typed token，账号/路线不共享 | 不改 feature 请求 | 不改原 header 与正文 | 不改业务密码学 | 不改 DTO | 只共用内存锁、取值、清除；独立单飞锁 | 原清除入口及会话错误保留 |
| Ygdk/Signin/Spoc 凭据槽位 | 各自原登录流程不变；不采用 buaa-api 不同 iClass 路径 | 保留 uid/token、user_id/session_id、token/role 的各自类型 | 不改请求 | 不改 header/编码 | 不改密码学 | 不改字段及类型 | generation 与存入比较、清除递增、独立登录锁保留 | 旧代次登录不能恢复已清除凭据 |
| iHome 凭据 | 原引导与最终 URL 不变 | 原内存 token 不变 | 不变 | 不变 | 不变 | 不变 | 原子快照与 mutation 锁有独立用途，按实现收益决定复用范围 | 原清除/迟到保护保留 |

## 执行结果

日志保存在被忽略的 `.ubaa_local/core_simplification/`，其中不得归档凭据、原始真实响应或个人资料。

日志失败反例先在 `business_login.api` 触发“泄露了敏感正文摘要”，删除正文 SHA1 后通过。合成登录、订单列表、详情、取消和预约响应共同验证正文及其 SHA1 不进入日志，门锁原有低熵秘密保护继续覆盖。

首次完整严格检查在 CLI 的命令锁定测试失败，原因是协议专项记录中的三个 Cargo 命令漏写 `--locked`。文档已修正，三组命令按锁定依赖重新执行通过，命令锁定测试转为通过。首轮失败保留在 `strict-first.log`，没有修改检查规则。

六种凭据状态已复用一个私有 `CredentialState<T>`，typed 凭据、每个实例的登录锁和失效代次分别保留。原 Signin 与 Ygdk 的两种竞争时序仍由测试钩子验证，生产构建不包含钩子。iHome 自身还有串行修改锁及同时取得代次/token 的原子快照，保留该小型实现，避免为了统一类型增加转发层。

## 代码规模与验收

按 `crates/ubaa_core` 下全部 Rust 文件的物理行数统计，基线为 297 个文件、68,000 行，修复后为 300 个文件、67,353 行，净减少 647 行。统计包含注释、空行、内联测试及本轮新增回归测试。新增文件用于共享刷新逻辑和集中测试适配。记录位于本地忽略目录的 `size.json`。

当前 `tests/` 目录占 20,961 行，`src/` 下按文件名识别的测试及测试支持文件占 10,070 行，两者合计 31,031 行。其余 36,322 行仍含内联测试。评估业务实现规模时需要计入这种组成差异。

本轮把重复的生命周期和解析步骤集中到现有模块，没有增加公共调度框架。路线隔离、会话 CAS、失效代次、写前资格复核和写入未知结果保护都有实际安全用途，继续保留。代码量统计不能单独判断这些机制是否应该删除。

| 检查 | 结果 |
|---|---|
| `just refs` | 两个冻结来源校验通过 |
| `just layout-check`、`just docs-link-check`、`just check-sensitive` | 通过，严格入口也包含布局和文档检查 |
| `just check-strict` | 完整严格入口通过，Rust 测试汇总为 1110 次通过、3 次按既有设置忽略，包含不同构建配置的重复执行 |
| `just flutter-check` | 八个 workspace 成员的格式、静态分析及 1531 项测试全部通过 |
| `just integration-test` | macOS 默认五组原生集成通过，共 7 项，覆盖宿主 smoke、网络恢复、插件、FFI 缓存和跨进程启动锁 |
| `CARGO_INCREMENTAL=0 CARGO_BUILD_JOBS=1 just flutter-codegen-check` | FRB 2.13.0 重生成零漂移 |
| `CARGO_INCREMENTAL=0 CARGO_BUILD_JOBS=1 just check-changed base=7348b8b3693d2254aa72c160911317955123a0f9` | 审阅完整计划后执行通过，包含 Rust/脚本、八成员 Flutter 和再次 FRB 零漂移检查 |
| `git diff --check` | 通过；提交前另外检查每组暂存差异并重新执行敏感扫描 |

真实只读验证使用 `just verify-live mode=direct` 与 `just verify-live mode=webvpn`。Direct 首次 50 项全部通过。WebVPN 首次 45 项通过，Judge 的同一次诊断调用超时导致 2 项失败，另外 3 项按依赖关系阻断。复用同一生产二进制单独重跑 Judge，5 项在约 13 秒内全部通过；随后完整 WebVPN 单次复跑在约 35 秒内通过全部 50 项。两条路线均已有完整通过记录。

Judge 的协议实现和只读脚本本轮没有差异，两次复跑间也未修改生产代码。观察结果支持首次为偶发网络或上游超时，现有摘要无法确定发生超时的具体请求。原失败保留在 `live-webvpn.stdout`，模块复跑和完整复跑分别在 `judge-webvpn-retry.stdout`、`live-webvpn-rerun.stdout`。本轮没有执行真实业务写入，也没有遇到需要浏览器核对的协议疑点。

本轮仅完成本机工程修复和验证，没有触发远端 CI、签名发布或实体设备验收。旧缓存需要用户在设置中显式重建，当前开发阶段不提供旧缓存迁移。

实现按主题提交如下，方案、来源比较和验证记录另作一次文档提交。所有提交均保留在本地，未推送。开始时已有的 OHOS、工具链和两份状态文档末尾改动未纳入本轮提交。

| 提交 | 内容 |
|---|---|
| `92fcc22f` | 删除场馆响应正文 SHA1 日志并保留敏感日志回归 |
| `c8719fe6` | 合并私有凭据状态，保留并发失效保护，删除重复测试 |
| `b1bc2f38` | 共享路线安全收尾，清理未完成登录残留状态，限定旧会话写入口 |
| `0f90d442` | 共享缓存刷新，拒绝迟到结果，删除历史开发格式迁移 |
| `05f93ecf` | 复用博雅、SPOC、评教及图书馆的解析与读取步骤 |

## 测试整理登记

| 删除或调整项 | 保留覆盖 |
|---|---|
| `route_state/mod.rs` 重复的 `concurrent_classroom_bootstraps_use_one_double_checked_sync` | 同名测试在 `route_state/classroom.rs` 原样保留，继续验证并发双重检查只执行一次引导 |
| `route_state/mod.rs` 重复的 `failed_or_cleared_classroom_sync_remains_retryable` | 同名测试在 `route_state/classroom.rs` 原样保留，继续验证失败可重试及清除后重新引导 |
| Ygdk 测试专用 `set` 的带代次写入 | 原竞态测试改为直接调用生产 `store_credential`，继续在旧登录存入前暂停并验证清除后不能回写 |

其余缓存格式和解析适配的测试调整见各专项记录。
