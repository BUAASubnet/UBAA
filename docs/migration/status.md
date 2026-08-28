# 迁移状态

Updated: 2026-08-29

## 2026-08-29 阶段提交

- 新增 `crates/ubaa-core/src/session/ports.rs`，收拢 `SessionStore` 持久化端口；保持版本化加载、比较交换、保存/清理循环和错误语义不变；Session、CLI、敏感扫描与全量门禁通过。
- 新增 `apps/ubaa-cli/src/login_args.rs`，收拢登录参数及敏感 Debug 脱敏实现；保持参数名称、隐藏属性、标准输入校验和 JSON/交互登录语义不变；CLI、敏感扫描与全量门禁通过。
- 新增 `crates/ubaa-core/src/session/types.rs`，收拢单路线/双路线会话快照、版本包装、校验与比较交换结果类型；保持 schema-v2 字段、旧版迁移、Deref 和序列化语义不变；Session、CLI、敏感扫描与全量门禁通过。
- 新增 `crates/ubaa-core/src/session/cookies.rs`，收拢 `StoredCookie`、`CookieJar` 及其容器逻辑；保持 Cookie 的 Domain/Path/Secure/Max-Age/Expires 过滤、替换、持久化和敏感 Debug 脱敏语义不变；Cookie、Session、支持库测试及全量门禁通过。
- 新增 `apps/ubaa-cli/src/routing.rs`，收拢 `ReadonlyRouteContext` 及路由决策转换；保持 CLI 公共导出、路由元数据和 JSON 输出语义不变；Core、CLI、敏感扫描与全量门禁通过。
- 三路线逐操作只读复核（本轮）：Direct 的 User、Schedule、Exam、Grades、Classroom、SPOC、Judge、Signin、Ygdk、LibBook、Bykc、Evaluation 通过，Cgyy 站点通过而日期为 `invalid_semantics`、锁码为 `upstream_unavailable`；WebVPN 的 User、Schedule、Exam、Grades、Classroom、SPOC、Signin、Ygdk、LibBook、Bykc、Evaluation 通过，Judge 为 `timeout`，Cgyy 日期/订单/锁码为 `upstream_unavailable`；auto 解析到 Direct，除 Schedule 当前周 `timeout` 外非 Cgyy 操作通过，Cgyy 日期/详情/锁码为 `upstream_unavailable`。未执行真实写操作；失败项与冻结请求逻辑一致，按上游实时证据保留。
- 新增 `facade/types.rs`，收拢 `Routed`、`RoutedError` 与内部 `Operation` 类型；通过 facade 重新导出稳定结果包装器，保持 CLI/API 可见性、路由元数据和错误语义不变；Core、CLI、敏感扫描与全量门禁通过。
- 新增 `domain/judge.rs`，收拢希冀状态、作业摘要、诊断、详情键、题目和详情 DTO；保持字段、公开导出与序列化语义不变；Core、CLI、敏感扫描与全量门禁通过。
- 新增 `domain/spoc.rs`，收拢 SPOC 作业状态、列表、诊断和详情 DTO；保持字段、公开导出与 camelCase/SCREAMING_SNAKE_CASE 序列化语义不变；Core、CLI、敏感扫描与全量门禁通过。
- `domain/cgyy.rs` 进一步收拢 `CgyyReservationSelection`、`CgyyReservationSubmitRequest` 及其 Debug 脱敏实现；保持验证码字段 `skip_serializing`、CLI 写操作保护和序列化语义不变；Core、CLI、敏感扫描与全量门禁通过。
- `domain/bykc.rs` 继续收拢 `BykcCourse` 与 `BykcCourseStatus`，保持 camelCase/snake_case 序列化、默认状态和公开导出不变；Core、CLI、敏感扫描与全量门禁通过。
- `domain/bykc.rs` 已收拢课程分页、已选课程、分类、签到配置和统计 DTO，保持字段、默认值与 serde 语义不变；Core、CLI、敏感扫描与全量门禁通过。
- `domain/bykc.rs` 继续收拢 `BykcActionResult` 与 `BykcSignRequest` 写操作 DTO；仅调整模块归属，保持字段、camelCase 序列化和 CLI 默认阻止语义不变；Core、CLI、敏感扫描与全量门禁通过。
- 新增 `domain/libbook.rs`，收拢图书馆库房、区域、座位、预约请求及结果 DTO；保持公开导出、字段和 camelCase 序列化不变；Core、CLI、敏感扫描与全量门禁通过。
- 新增 `domain/ygdk.rs`，收拢阳光打卡概览、记录、图片上传和提交 DTO；保持字段、序列化与图片 Debug 脱敏语义不变；Core、CLI、敏感扫描与全量门禁通过。
- 新增 `domain/evaluation.rs`，收拢评教任务、课程、进度及结果 DTO；保持字段、进度计算和 camelCase 序列化语义不变；Core、CLI、敏感扫描与全量门禁通过。
- 新增 `domain/signin.rs`，收拢 iClass 课堂签到状态与签到结果 DTO；保持字段、状态值和 camelCase 序列化不变；Core、CLI、敏感扫描与全量门禁通过。
- 新增 `domain/schedule.rs`，收拢学期、教学周、课表、今日课程和考试 DTO；保持字段、默认值与 camelCase 序列化语义不变；Core、CLI、敏感扫描与全量门禁通过。
- 新增 `domain/grades.rs`，收拢成绩课程与学期结果 DTO；保持字段、可空性和 camelCase 序列化语义不变；Core、CLI、敏感扫描与全量门禁通过。
- 新增 `domain/classroom.rs`，收拢空闲教室查询及教室信息 DTO；保持严格字段类型、公开导出和 camelCase 序列化语义不变；Core、CLI、敏感扫描与全量门禁通过。
- 新增 `domain/cgyy.rs`，收拢场馆站点、用途、时段、空间、日期和订单等只读 DTO；验证码敏感写请求仍保留原边界，公开导出与 camelCase 序列化语义不变；Core、CLI、敏感扫描与全量门禁通过。
- `domain/cgyy.rs` 进一步收拢场馆写操作结果与安全锁码载荷；预约请求及验证码敏感字段保持原位和 Debug 脱敏，公开导出、字段与序列化语义不变；Core、CLI、敏感扫描与全量门禁通过。
- `domain/bykc.rs` 先拆出 `BykcUserProfile` DTO，保持 camelCase 序列化和公开导出不变；Core、CLI、敏感扫描与全量门禁通过，后续继续在同一模块收拢 Bykc 类型。
- `domain/route.rs` 拆出 `ConnectionMode`、`RoutePolicy` 与 `ReadonlyFeature`，保持序列化名称、配置键和路由语义不变；Core 全部测试与全量门禁通过。
- 最新三路线只读复测：Direct 仅 Cgyy 日期/锁码为 `upstream_unavailable`；WebVPN 的 Cgyy 日期为 `invalid_semantics`、锁码为 `upstream_unavailable`；auto 解析为 Direct，Cgyy 日期为 `invalid_semantics`、订单为 `upstream_unavailable`。其余功能逐项通过，未执行真实写操作。
- 认证领域拆分后重新执行三路线逐操作只读矩阵：Direct 仅 Cgyy 日期/锁码为 `upstream_unavailable`；WebVPN 的 Cgyy 日期为 `invalid_semantics`、锁码为 `upstream_unavailable`；auto 解析为 Direct，Cgyy 日期为 `invalid_semantics`、订单为 `upstream_unavailable`。其余功能逐项通过；未执行真实写操作。
- `domain/auth.rs` 拆出认证输入、聚合登录结果、用户资料与认证状态 DTO；字段、serde 别名、脱敏 Debug/Display/Serialize 语义保持冻结实现一致。认证、契约、只读集成测试与全量门禁通过。
- `execution.rs` 拆出 CLI 的公共后端执行入口与命令到功能映射；具体 feature 分支和渲染逻辑保持原边界，CLI、Core、敏感扫描和文档门禁全部通过。
- 后续结构提交将 CLI 顶层解析器与命令分派移入 `apps/ubaa-cli/src/commands.rs`，保持现有命令、参数、输出和退出语义；本阶段全量确定性门禁通过。
- `0d6284b` 将 CLI 连接模式解析及 `ConnectionMode` 转换拆分到独立模块；命令名、参数、退出码、路由和协议行为保持不变，`just check-sensitive` 与 `just check` 均通过。
- `a70ea60` 固化 Cgyy 签名请求的 WebVPN 路线合同：场馆业务签名请求保持
  `cgyy.buaa.edu.cn` 直连主机，不被错误包装为 WebVPN 地址；测试使用无网络传输，
  不读取或写入真实会话。
- `baf295f` 校正扩展功能库存，使 Signin、Ygdk、LibBook、Cgyy、Bykc 和 Evaluation
  的 Core/CLI 实现状态与当前代码一致，并明确真实写操作永久禁止。
- Bykc 已选课程曾因 Rust 仅接受数组而在三条路线返回 `upstream_changed`；提交 `29a83b2`
  已按冻结 `data.courseList` 包装修复并通过完整门禁。2026-08-29 Direct、WebVPN、auto
  单项复测均通过。
- 当前阶段扩展 `verify-live` 的逐操作只读矩阵：Ygdk 记录、LibBook 区域/详情/座位/预约、
  Bykc 资料/课程详情/已选/统计、Cgyy 用途/日期/订单详情和 Evaluation 待评教均会独立
  执行；详情请求仅在上游返回脱敏标识时继续，空集合不会伪造详情成功。
- User `user show` 已纳入验证器的独立操作和 `all` 聚合，并以完整脱敏 profile 校验
  字段集合、类型和掩码规则；验证器脚本 stub 已覆盖该调用路径。
- 早期三路线复测中的 Judge/Bykc/Cgyy 失败已分别通过后续修复或重跑收敛；当前保留的实时失败集中在 Cgyy 日期、订单、锁码等上游阶段，按最新逐操作证据记录，不能由其他读操作成功替代。
- 本阶段 `just check-sensitive && just check` 全部通过。整体迁移仍未完成：Cgyy
  WebVPN 业务会话返回 `authentication_required`，Direct 门锁码返回
  `upstream_unavailable`，Signin/Ygdk/Evaluation 等逐操作实时矩阵仍有失败项。

## Conclusion

冻结源逐操作复核、Core/CLI 确定性门禁和大部分只读实时能力已完成；写操作均有
协议实现、Mock/向量和 CLI 确认保护，但真实验收永不调用。当前整体仍未达到最终完成：
Cgyy 日期、订单、锁码等操作仍有路线相关的 `upstream_unavailable`、`upstream_changed`
或安全结构校验失败。验证码图像求解器已迁移并有 PNG/JPEG、加密向量、重试和逐请求
Mock 证据；Judge 三路线和其他领域的最新逐操作重跑通过。

## Baseline

- Branch: `ubaa2`.
- Frozen `ubaa_old/` HEAD: `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`.
- Frozen `examples/buaa-api/` HEAD: `efb7976bf513f38364b88aeb83d704586cff9b2a`.
- `just refs` on 2026-08-23 verifies both clean reference worktrees and fixed HEADs.
- `.env.local` remains a read-only sensitive input; no value is printed, logged, staged or persisted.
- 先前未提交的 `goal.md` 扩展现已纳入本次合同修复阶段。

## Remediation Status

### 2026-08-28 Cgyy/Bykc/扩展只读 CLI

Cgyy 场馆预约五项只读查询已完成 DTO、解析器、路线隔离业务会话、Core Facade、CLI 双执行路径和 JSON Schema；Bykc 五项只读查询同样已完成。当前 CLI 已覆盖合同六类业务以及 Signin、Ygdk、LibBook、Bykc、Cgyy 的全部只读入口。所有真实上游验证仍需按路线矩阵单独执行，不能由 Mock 或编译通过替代。

2026-08-28 的 CLI 命令矩阵审计发现 `cgyy` 已接入普通与聚合执行路径，但遗漏在
`requires_session()` 的会话预检枚举之外。新增覆盖所有扩展只读子命令的解析与功能映射
测试后复现该缺口，并将 `cgyy` 纳入会话预检；场馆查询现在与其他只读功能一致，会在
构造客户端时装载已有双路线会话。

### 2026-08-27 Ygdk

Ygdk 阳光打卡已完成只读概览与记录的 Core 解析、独立 OAuth/业务令牌请求、路线 facade、CLI `ygdk overview`/`ygdk records` 及 JSON Schema 接线。提交打卡和照片上传已具备协议实现、Mock/向量和确认保护，但真实写操作永久排除；三路线只读验证已纳入全量矩阵。

| 阶段 | 当前状态 | 收尾要求 |
|---|---|---|
| 0-6 基线 | 保留；最终确定性门禁通过 | 当前工作树已通过冻结引用、敏感数据扫描、格式、Clippy、工作区测试、构建、文档和差异检查。 |
| 7 route policy | Deterministic remediation complete; live Direct/auto/WebVPN resolution accepted | TCP target/total budget/failure classes, explicit-policy probe bypass, 60-second single-flight cache and Core-owned operation resolution are covered; future WebVPN retries may encounter transient upstream Judge snapshot drift. |
| 8 dual sessions | Deterministic remediation complete; aggregate login live-checked | Atomic load, shared coordinator, route-logical CAS, uncertain-write termination, unconditional remote attempts, one-CAS aggregate logout, terminal conflict fail-fast and whole-facade invalidation are covered; aggregate Direct/WebVPN login succeeded in the accepted `all` runs. |
| 8a authentication verification boundary | Deterministic remediation complete | The old challenge registry, image fetch, answer binding and captcha exit contract are removed. A `config.captcha` or other interactive verification marker returns `upstream_changed` before image fetch or credential POST; the sanitized regression proves the one-GET/no-POST boundary. |
| 9a schedule/exam/grades | Corrected live Direct/auto aggregate and WebVPN explicit runs passed | Schedule display `code` is validated as a non-empty string independent of the requested term, matching the frozen parser and live shape; preserve the source-parity record. |
| 9b classroom | Corrected live Direct/auto aggregate and WebVPN explicit runs passed | Exact long UA, one no-follow query, strict required `e/m/d/list` and room strings, best-effort once-per-route synchronization, route isolation, and session lifecycle clearing are covered and live-checked. |
| 9c SPOC | Corrected live Direct/auto aggregate and WebVPN explicit runs passed | The hidden diagnostic observed one authoritative global page on each accepted run; the empty result is therefore evidence-backed. Non-empty detail remains conditional on upstream data. |
| 9d Judge | Direct/auto/WebVPN aggregate accepted on the latest complete matrix | Frozen DOM/problem/score/status parsing, link filtering, grouped four-worker batch reads, clamped cutoff, bounded route/client caches, lifecycle invalidation, safe diagnostics, and terminal UC arbitration are covered. Judge list snapshots can drift between the two required reads; the verifier remains strict and a transient `judge_cutoff` failure is recorded rather than normalized. |
| 9e 签到查询 | Core 解析、独立 iClass 会话、facade 与 CLI 已接入；Direct/WebVPN 实时验证通过 | `signin today` 使用路线隔离的 iClass 业务会话，按旧版固定跳转、登录参数和今日查询参数实现；脱敏解析、确定性接线和双路线 live 证据均已覆盖。签到提交属于写操作，仍禁止真实调用。 |
| 9f 扩展查询与写入口 | Signin、Ygdk、LibBook、Bykc、Cgyy、Evaluation 的 Core/CLI 入口已接入；写操作具备确定性证据 | 所有写操作均要求显式确认并由实时验证器排除；请求向量、Mock 链和输入拒绝测试已覆盖，实时只读失败仍按逐操作矩阵收敛。 |
| 10 CLI/JSON | Deterministic remediation complete; final CLI E2E passed | Ordinary commands use the aggregate Core facade; every renderer, startup/argument failure and hidden diagnostic emits schema v2; aggregate auth/logout metadata and route data are fixed Direct then WebVPN; unsafe config targets and concurrent atomic writes are covered. |
| 10a live verifier | Deterministic remediation complete | The harness rejects unsafe errors, non-v2/wrong aggregate order, invalid integer bounds, cross-request term/SPOC identity drift, missing SPOC query proof, incomplete Judge semantics, route contradictions, sensitive/raw output and Judge JSON in argv; it proves xtrace suppression and username/password stdin routing. Production verification is non-interactive and records an upstream interactive verification page as `upstream_changed`. |
| 11 live matrix | 三路线逐操作验证器已完成；最新全量仍有 Judge/Cgyy 上游失败 | Keep the strict `judge_cutoff` subset check and rerun the complete aggregate when upstream list volatility or Cgyy business authentication causes a nonzero result. |
| 12 交接/门禁 | 已可继续开发；当前改动按功能分别提交 | `just refs`、`just check-sensitive`、`just check`、CLI E2E、认证 Direct/WebVPN、六类显式路线、`all/auto`、`all/direct` 和最新 `all/webvpn` 均有记录。后续真实重跑仍属于发布流程。 |

## 2026-08-26 Corrected Live Matrix

Only safe counts, route metadata and stable outcomes are recorded here. No
assignment IDs, titles, response bodies, cookies, tokens or digest salt are
stored.

## 2026-08-28 扩展只读实时结果

使用临时进程内摘要盐运行 `feature=all route=auto`，未保存盐值或任何敏感
响应。课表、考试、成绩、空闲教室、SPOC、Judge、图书馆和场馆预约均成功；
Signin 与 Ygdk 在业务登录页返回 `upstream_changed`；Bykc 在 CLI 聚合路由修复
后仍返回 `authentication_required`，表示业务 CAS 会话未建立。随后单独运行
`feature=auth route=direct` 成功，但 `feature=bykc route=auto` 仍未通过语义门禁。
这些结果只证明本次真实运行的具体功能状态，不把认证成功推导为业务成功。
同日 `feature=auth route=webvpn` 认证成功，但 `feature=cgyy route=webvpn`
返回 `authentication_required`，因此场馆 WebVPN 业务路线仍未验证通过。
Bykc 首次结果的 `invalid_semantics` 后经审计确认为验证器误将合法分页字段
`data.content` 判为敏感键；修复提交 `adc3d4f` 后，`feature=bykc route=direct`
成功并解析到 1 条课程。该结果不替代 WebVPN 路线验证。
- Bykc 写链阶段新增选课、退选、签到三条端到端 Mock，覆盖 CAS token 跳转、随机 AES/RSA 请求封装、双认证头及 `ak`/`sk`/`ts` 元数据；响应使用脱敏明文信封，真实业务写操作仍永久禁止。
随后 `feature=auth route=webvpn` 成功，但 `feature=bykc route=webvpn`
返回 `upstream_changed`，因此 Bykc WebVPN 业务路线仍未验证通过。
重新建立 Direct 主认证后，`feature=signin route=direct` 与
`feature=ygdk route=direct` 仍返回 `upstream_changed`，而
`feature=cgyy route=direct` 成功并解析 4 个站点；这排除了会话残留导致的假失败。
再次复测 Bykc WebVPN（主认证成功后）仍返回 `upstream_changed`；当前没有冻结
证据支持新增跳转参数或放宽主机/令牌解析，保持失败关闭并待上游协议确认。
本轮重新执行 Direct 显式路线：认证、课表、考试、成绩、空闲教室、SPOC、
图书馆、博雅和场馆预约均通过；空闲教室返回 158 条、图书馆返回 2 个馆区、
博雅返回 1 条课程、场馆预约返回 4 个站点。SPOC 全局分页证据为 1 页且当前
作业为空。Signin 与 Ygdk 再次稳定返回 `upstream_changed`，确认其失败并非
聚合路由或残留会话造成；在取得脱敏上游结构证据前继续失败关闭。
同轮 WebVPN 显式路线中，认证、课表、考试、成绩、空闲教室、SPOC 和图书馆
通过；空闲教室仍返回 158 条，SPOC 仍为 1 个全局分页且作业为空，图书馆返回
2 个馆区。Signin 与 Ygdk 返回 `upstream_changed`，Bykc 返回
`upstream_changed`，Cgyy 返回 `authentication_required`。这些失败与此前复测
一致，不能用主认证或其他业务成功替代对应业务路线的协议证据。

| Run | Result |
|---|---|
| `feature=all route=auto` | Exit 0; resolved Direct; all six features passed. Classroom count 158; SPOC global page count 1 with empty assignments; Judge counts course/raw/filtered/current/cutoff `5/88/83/65/18`, detail present. |
| `feature=all route=direct` | Exit 0; all six features passed. Judge counts `5/88/83/65/18`, detail present. |
| `feature=schedule`, `exam`, `grades`, `classroom`, `spoc`, `judge` on Direct | Exit 0 for each; Judge counts `5/88/83/65/18`, detail present; SPOC global page count 1 with empty assignments. |
| `feature=schedule`, `exam`, `grades`, `classroom`, `spoc`, `judge` on WebVPN | Exit 0 for each; Judge standalone counts `5/49/49/17/32`, detail present; SPOC global page count 1 with empty assignments. |
| `feature=all route=webvpn` first attempt | Exit 1 at strict `judge_cutoff`; schedule/exam/grades/classroom/SPOC passed. The failure is retained as upstream snapshot volatility evidence. |
| `feature=all route=webvpn` immediate rerun | Exit 0; all six features passed. Judge counts `5/77/57/17/40`, detail present. |
| final `feature=all route=webvpn` verification attempt | Exit 1 at strict `judge_cutoff`; schedule/exam/grades/classroom/SPOC passed. The failure is retained as upstream snapshot volatility evidence. |
| final immediate `feature=all route=webvpn` rerun | Exit 0; all six features passed. Judge counts `5/77/57/17/40`, detail present. |

## 2026-08-26 Deterministic Gates

- `just refs`: passed for both frozen commits listed above.
- `just check-sensitive`: passed; no credentials, cookies, tokens, captcha data or raw live material entered the checked tree.
- `just check`: passed, including format, Clippy with `-D warnings`, all workspace tests, shell verifier regression, build, docs and diff checks.
- `cargo test --locked -p ubaa-cli --test binary_e2e`: 11 passed.
- `bash ./scripts/test-verify-live.sh`: passed.

These repository gates are deterministic and were rerun after the production fixes. The live
matrix above is separate evidence; it is not replaced by fixture or Mock success.

## Historical Live Authentication

These commands exited 0 on 2026-08-23 and established only that both
authentication routes worked at that time. They do not prove atomic logout,
the intentionally unsupported interactive-verification boundary, Core-owned selection or any business endpoint.

| Command | Historical result |
|---|---|
| `just verify-live feature=auth route=direct` | Exit 0; `auth_status` parsed a user. |
| `just verify-live feature=auth route=webvpn` | Exit 0; `auth_status` parsed a user. |

## Historical Read-Only Commands And Limitations

| Feature | Direct historical result | WebVPN historical result | Auto historical result | Current interpretation |
|---|---|---|---|---|
| Schedule (terms/weeks/current/today) | Exit 0; all four reads parsed | Exit 0; all four reads parsed | Exit 0; all four reads parsed | Pre-fix historical evidence only; current Direct/WebVPN/auto cells remain pending. |
| Exam arrangement | Exit 0 | Exit 0 | Exit 0 | Pre-fix historical evidence only; rerun with a term returned by schedule. |
| Grades | Exit 0 | Exit 0 | Exit 0 | Pre-fix historical evidence only; rerun with strict old term semantics. |
| Empty classroom | Exit 0; reported 158 for campus 1/date 2026-08-23 | Exit 0; reported 158 | Exit 0; reported 158 | The result predates exact UA/no-redirect/strict-DTO remediation; rerun is required. |
| SPOC assignments/detail | Exit 0; reported empty | Exit 0; reported empty | Exit 0; reported empty | **Unverified until the global empty-`kcid` query is observed.** The pre-remediation implementation could return a false empty result when course metadata was empty. No live detail ran. |
| Judge list/detail | Exit 0; reported 65 plus one detail | Exit 0; reported 17 plus one detail | Exit 0; reported 65 plus one detail | Counts are historical observations only. That sampled detail did not prove score/problem/status semantics, and the Direct 65/WebVPN 17 difference is unresolved. |

The following individual command summaries are retained as historical command
evidence, not current acceptance:

```text
feature=schedule route=auto: exit 0; terms/weeks/current/today parsed
feature=exam route=auto: exit 0; term selected and response parsed
feature=grades route=auto: exit 0; term selected and response parsed
feature=classroom route=auto: exit 0; result_count=158 date=2026-08-23
feature=spoc route=auto: exit 0; reported result_count=0; INVALID AS EMPTY-SEMANTICS PROOF
feature=judge route=auto: exit 0; reported result_count=65 plus one detail; DETAIL SEMANTICS UNVERIFIED
```

Additional explicit-route commands historically exited 0:

```text
schedule direct/webvpn: terms/weeks/current/today parsed on both
exam direct/webvpn: parsed on both
grades direct/webvpn: parsed on both
classroom direct/webvpn: reported result_count=158 on both
spoc direct/webvpn: reported result_count=0 on both; global empty-kcid request not established
judge direct: reported result_count=65 plus one detail
judge webvpn: reported result_count=17 plus one detail
```

The historical aggregate
`just verify-live feature=all route=auto` also exited 0 after reporting each
feature successful. It is not a current hard-gate pass because SPOC could have
short-circuited before the authoritative global query, Judge detail assertions
did not cover the old parser semantics, and automatic selection used the
superseded host-owned resolver implementation.

Historical failed Judge attempts remain relevant: explicit Direct previously
returned `upstream_unavailable`; later WebVPN/auto attempts returned `timeout`
or `upstream_changed`; stale sampled IDs returned not found. These observations
show upstream volatility but select neither a permanent route nor a parser
contract. The 65/17 count divergence must be investigated using safe in-memory
IDs/counts after the parser/cache fixes; it must not be normalized or hidden.

## Historical Deterministic Gates

Before this audit, the following passed:

- `cargo test --locked --workspace`.
- `cargo clippy --locked --workspace --all-targets -- -D warnings`.
- `cargo test --locked -p ubaa-cli --test binary_e2e` (10 passed).
- `cargo test --locked -p ubaa-test-support --test readonly` (19 passed).
- `cargo test --locked -p ubaa-test-support --test support` (8 passed).
- `./scripts/test-verify-live.sh`.
- `just refs`, `just check-sensitive`, and `just check`.

Those passes describe the pre-remediation implementation. They do not validate
the newly corrected contract and must be rerun after every production phase.
CI remains deterministic-only and never reads `.env.local`.

## Open Defects And Evidence Gaps

- Production automatic selection now uses the accepted TCP reachability implementation and Core-facade ownership; corrected Direct/auto and latest WebVPN aggregate evidence is accepted. A transient WebVPN Judge snapshot failure remains recorded and must be retried strictly if it recurs.
- Interactive verification is intentionally unsupported: the Core regression proves that `config.captcha` causes `upstream_changed` after the login-page GET with no image request or credential POST. A live occurrence is a hard-gate upstream-change result, not a reason to add a prompt or bypass.
- Config persistence now has deterministic symlink, regular-file, unique-temp, permission and concurrent-write coverage; real routing configuration behavior remains part of the later live matrix.
- Classroom now matches the frozen UA/redirect/DTO/state contract in deterministic tests and passed the corrected Direct/auto aggregate plus WebVPN explicit runs.
- SPOC transport tests now capture and decrypt both actual global page requests, including `kcid=""`; corrected live diagnostics observed one authoritative global page on Direct, WebVPN and auto. Non-empty detail/submission semantics remain conditional on upstream data.
- Judge parser, detail, cutoff, grouped batch and cache lifecycle are deterministically covered. Direct/auto and the latest WebVPN aggregate passed safe semantic checks; multiple WebVPN aggregate attempts failed `judge_cutoff` because upstream list snapshots drifted, and each immediate rerun passed, so the strict check remains unchanged. Route-local count differences remain observations, not normalization rules.
- Judge terminal business-authentication failures now have a source-backed UC arbitration path under test and live-ready behavior: only explicit UC Invalid clears the selected route; valid or unavailable UC results preserve the primary session and return retryable `upstream_unavailable`.
- CLI schema v2 and the live verifier's semantic rejection cases are deterministically covered for routed, unresolved, aggregate, SPOC query/detail identity, and Judge list/detail output. Judge cross-request comparison uses stdin rather than argv. Interactive verification fields and error codes are absent from the schema. This establishes verifier behavior only, not a real route result.
- All in-scope write operations have Core/CLI protocol implementations with deterministic Mock, vector, parser and confirmation-protection evidence; real submission/upload, answer, reservation, attendance, grading-change and other side-effect requests remain permanently disabled for this contract.
- Windows owner-only directory ACL enforcement remains a release-audit item from the baseline.

## Rerun Handoff

1. On future upstream changes, rerun `just refs`, `just check-sensitive`, `just check`, CLI binary E2E and verifier regression from the integrated tree.
2. Generate one ephemeral `UBAA_VERIFY_DIGEST_SALT`, keep it only in the current shell for comparable Judge digests, and never record its value.
3. Rerun `feature=auth` on Direct and WebVPN, `feature=all route=auto`, every feature on both explicit routes, and both complete explicit aggregates. Every multi-request feature must retain one resolved route.
4. For SPOC, require `global_page_count >= 1`; if non-empty, require one detail. For Judge, require course/raw-anchor/filtered/current/cutoff counts and one semantic detail when available.
5. Record only safe route, timing, count, presence, stable error and salted-digest summaries. If list snapshots drift, retain the strict failure and rerun; never normalize route differences or weaken subset checks.
随后依据固定 Class 模块证据修正签到业务登录入口、会话头和查询方法，并将
`STATUS=2` 识别为合法空课程结果。修正后 `feature=signin route=direct` 与
`feature=signin route=webvpn` 均通过，返回 0 条课程；签到只读功能的两条真实路线
验收完成，签到提交仍不在范围内。
阳光打卡随后按冻结实现补齐 fragment OAuth code、项目/记录 query 与表单双传、
精确表单编码和业务会话失效重登。最终根因是 token 解码把不含等号的值误解析为空；
改为按独立 URL 值解码后，`feature=ygdk route=direct` 与
`feature=ygdk route=webvpn` 均通过并解析到 11 个项目。阳光打卡只读双路线验收完成。
博雅 WebVPN 登录失败的根因是网关绝对 `Location` 未先还原为业务直连语义，
因此被未知主机检查拒绝。修正为先反解最终地址和跳转目标、校验 `sso/bykc`
主机、再按当前路线包装后，`feature=auth route=webvpn` 与
`feature=bykc route=webvpn` 均通过并解析到 1 条课程；结合此前 Direct 成功结果，
博雅五项只读功能的双路线入口已验证。
# 2026-08-28 execution update

- 新增评教 Core 只读链路（CAS 激活、任务/问卷/课程请求、稳定课程 DTO 和进度）以及 CLI `evaluation all|pending` 命令。
- 新增 Bykc Core 选课、退选、签到请求构造和 CLI 命令。所有 Bykc、Cgyy 写命令都要求显式 `--confirm-write`，实时验证绝不执行写操作。
- `just check-sensitive`、`just check`、`cargo test --locked -p ubaa-core --tests` 和 `cargo test --locked -p ubaa-cli --tests` 均通过。
- `just verify-live mode=direct feature=evaluation` 与 `just verify-live mode=webvpn feature=evaluation` 均通过，仅记录脱敏的 `course_count=0` 摘要。
- 剩余验收缺口：写操作的 Core 协议、向量、Mock 和 CLI 默认阻止均已具备，真实写操作永久禁止。当前缺口集中在 Judge 与 Cgyy 的三路线只读实时稳定性，迁移尚未完成。
- 本阶段补齐 LibBook 预约/取消 Core 与 CLI 写入口，并以冻结 golden 向量验证字段顺序、日期派生 AES-128-CBC、PKCS#7 和固定 IV；本阶段提交为后续审查起点。
- LibBook 写链阶段进一步增加了确定性 Mock 端到端测试，覆盖预约 `/v4/space/confirm` 与取消 `/v4/space/cancel` 的顺序、请求体和路线内会话；提交为 `24acd8b`。该证据不等同于真实写操作验收，verify-live 仍永久跳过写入口。
- 新增 Ygdk `submit` Core/CLI 写入口，按冻结实现上传照片后提交打卡表单；默认拒绝，必须显式 `--confirm-write`，未执行真实写操作。
- Ygdk 写入阶段完成了 multipart 上传边界、固定表单字段、CLI 文件输入校验及脱敏请求向量；真实写操作仍永久禁止，最终验收仍受全局实时矩阵门禁约束。
- Cgyy 阶段已提交 `1d25ef2`：完成日期上下文、空间/时段校验、预约上下文创建和最终预约表单的冻结字段实现；验证码挑战、受控图像求解和重试已迁移，CLI 提交入口和真实写验收继续禁止调用。
- Signin 阶段已提交 `0824947`：按冻结协议严格读取 `get_timestamp.action` JSON 的 `timestamp` 字段，并拒绝非 JSON 或空值响应；Signin 写操作仍需补充 CLI 专用安全测试和 Mock 请求断言。
- Signin 写链阶段新增 `crates/ubaa-core/tests/signin.rs` 端到端 Mock 断言，覆盖业务会话跳转、时间戳 GET、签到 URL 查询参数、`sessionId` 请求头和仅含 `id` 的表单；真实签到仍永久禁止。
- Evaluation 阶段已完成最终提交 JSON 信封、问卷题目读取/答案构造和逐课程自动提交链；CLI 提供 `evaluation submit-pending --confirm-write`，并以未确认不访问后端的测试覆盖安全门禁。仍需补充逐请求 Mock/错误向量以及真实只读矩阵收敛，评教写操作永不进入 live 验收。
- 2026-08-28 只读实时矩阵：Direct 全量除 `cgyy_lock_code`（`upstream_unavailable`）外通过；WebVPN 全量的 Cgyy 与 Evaluation 返回 `authentication_required`，其余功能通过。Cgyy WebVPN 与冻结 `localCgyyUpstreamUrl` 的直连语义存在已记录路线冲突，尚未修复。
- Cgyy 验证码阶段已补齐 Core `/api/captcha/check` 的 `pointJson`、挑战 token 和成功判定；敏感验证码字段仅存在当前请求内，CLI 暂不通过 argv 暴露，验证码获取/求解和 WebVPN 直连 runtime 仍未完成。
- Cgyy 验证码挑战阶段已固化 `/api/captcha/get` 的冻结参数及四个响应字段解析测试；图像求解已接入 Core，未将任何默认位移或验证码写入真实请求。
- Cgyy 图像验证码阶段现已接入受控 PNG/JPEG 解码、冻结滑块匹配算法和三次获取/校验重试；挑战图片、密钥和生成凭据仅在当前请求内存中流转，真实写操作仍禁止。
- 2026-08-28 复跑只读矩阵：Direct 除 `cgyy_lock_code=upstream_unavailable` 外通过；WebVPN 的 Grades 为 `upstream_changed`、Judge 为 `invalid_semantics`，Cgyy/Evaluation 为 `authentication_required`，其余已执行项通过。该结果不满足最终实时验收门禁。
- Ygdk 写请求阶段已补充 multipart 上传正文确定性测试，覆盖冻结的 `uid`、`token`、`file` 字段及边界/文件元数据；仍不执行真实打卡写操作。
- Ygdk 写入口现将照片非空、开始/结束时间成对校验前置到业务登录之前；新增无网络回归测试，确保无效写请求不会建立业务会话。
- Ygdk 写链阶段新增完整 Mock 端到端测试，覆盖 OAuth 回调、业务登录、概览四请求、照片 multipart 上传和最终打卡表单；仅使用合成会话与响应，真实打卡仍禁止。
- Evaluation 提交请求已补充固定地址、`Content-Type`、`X-Requested-With` 和 JSON 信封的确定性测试。
- Evaluation `submit_payload` 现将空结果列表校验前置到会话和网络请求之前，新增禁止网络回归测试，避免无效评教写请求触发业务登录。
- Evaluation 写链新增 `crates/ubaa-core/tests/evaluation.rs` Facade 到 HTTP 的 Mock，断言最终提交 URL、JSON 信封、`Content-Type` 与 `X-Requested-With`；真实评教提交仍永久禁止。
- Evaluation 自动逐课程写链新增 Mock，覆盖 CAS 激活、`reviseQuestionnairePattern`、题目读取和 `submitSaveEvaluation` 的冻结顺序，并断言课程标识与 `pjdf=93`；真实评教仍永久禁止。
- Cgyy CLI 已新增 `cgyy submit --request-stdin --confirm-write`，从标准输入读取包含敏感字段的 JSON 请求并在确认前拒绝读取；未执行真实预约。
- Cgyy RouteClient 现补齐 `cgyy_cancel_order` 直接 Facade 入口，并以签名路径/订单标识 Mock 覆盖；聚合与直接宿主均要求显式确认，真实取消仍禁止。

## 2026-08-29 全量只读复测

- Direct：schedule、exam、grades、classroom、spoc、signin、ygdk、libbook、bykc、evaluation 均通过；Judge 返回 `upstream_unavailable`，Cgyy 返回 `timeout`，聚合退出码为 5。
- WebVPN：schedule、exam、grades、classroom、spoc、judge、signin、ygdk、libbook、bykc 均通过；Cgyy 与 Evaluation 返回 `authentication_required`，聚合退出码为 3。
- 两次运行均只调用读接口，未执行任何真实写操作；失败项保留，不以聚合成功掩盖。
- Cgyy 单项复测（2026-08-29）：Direct 站点查询通过（4 个站点），门锁码仍为 `upstream_unavailable`；WebVPN 业务入口稳定返回 `authentication_required`。未跨路线复制 Cookie 或令牌。
- Cgyy RouteClient 现补齐 `cgyy_cancel_order` 直接 Facade 入口，并以签名路径/订单标识 Mock 覆盖；聚合与直接宿主均要求显式确认，真实取消仍禁止。
- Signin 写请求已提取冻结表单构造器并增加只含 `id` 字段的确定性断言；真实签到和写请求 live 验收仍永久禁止。

## 2026-08-29 Bykc 修复后全量只读复测

- Direct：User、schedule、exam、grades、classroom、spoc、signin、ygdk、libbook、bykc、Cgyy 站点查询和 evaluation 成功；Judge 为 `upstream_unavailable`，Cgyy 日期查询为 `upstream_unavailable`，聚合退出码 5。
- WebVPN：User、schedule、exam、grades、classroom、spoc、judge、signin、ygdk、libbook、bykc 成功；Cgyy 与 evaluation 为 `authentication_required`，聚合退出码 3。
- auto：实际解析到 Direct；User、schedule、exam、grades、classroom、spoc、signin、ygdk、libbook、bykc、Cgyy 站点查询和 evaluation 成功；Judge 为 `upstream_unavailable`，Cgyy 用途查询为 `upstream_unavailable`，聚合退出码 5。
- 本轮确认 Bykc 已选课程对象包装修复在三路线聚合中生效；所有命令仅执行读操作，未调用任何真实写接口。上述 Judge/Cgyy 失败仍是最终实时验收未满足项。
- 随后 Direct 单项复测仍在 `cgyy_day` 返回 `upstream_unavailable`、在 `judge_all` 返回 `upstream_unavailable`；站点查询和请求前置均正常，未放宽解析或错误语义。
- WebVPN Cgyy 在切换 Direct 业务 transport 后，站点查询已通过（4 个站点）；用途查询进入业务请求阶段但返回 `upstream_unavailable`，原先的 `authentication_required` 已消除，后续继续复核上游可用性。
- 后续 WebVPN 全量复测：User、课表、考试、成绩、教室、SPOC、Judge、Signin、Ygdk、LibBook、Bykc、Evaluation 均通过；Cgyy 站点通过（4 个站点），用途查询为 `upstream_unavailable`，聚合退出 5。
- auto Judge 单项复测已通过（课程 5、当前任务 65，详情语义通过）；Direct Judge 同轮仍为 `upstream_unavailable`。Judge 列表存在实时快照波动，继续保留逐路线结果。
- Direct Judge 随后单项复测通过（课程 5、当前任务 65，详情语义通过）；Judge 的 Direct/WebVPN/auto 成功证据现已齐备。
- Direct Cgyy 同轮站点查询通过（4 个站点），日期查询仍为 `upstream_unavailable`；Cgyy 是当前唯一未收敛的只读实时领域。
- `verify-live` 的 Cgyy 分支已改为逐操作继续执行：用途、日期、订单、条件详情和锁码失败会逐项输出脱敏错误，只有依赖标识缺失时才跳过对应详情；末尾返回首个失败码。shell 回归测试已覆盖完整调用顺序。
- 验证器进一步修正站点失败语义：站点响应未通过时不再输出成功摘要，也不从错误信封提取站点标识。三路线 Cgyy 复测显示 WebVPN 站点/用途/订单通过、日期和锁码失败；auto 站点通过、用途/日期/订单/锁码失败；Direct 站点、用途和锁码均受上游失败影响。详情仅在真实订单标识存在时尝试。
- 更新后的三路线全量复测：Direct 的 User、课表、考试、成绩、教室、SPOC、Judge、Signin、Ygdk、LibBook、Bykc、Evaluation 均通过，Cgyy 用途/订单为 `upstream_unavailable`、日期为 `upstream_changed`、锁码为 `invalid_semantics`；auto 除 Cgyy 日期/锁码 `upstream_unavailable` 外其余通过；WebVPN 除 Cgyy 日期/锁码 `upstream_unavailable` 外其余通过。Judge 三路线均完成完整详情语义校验。
- Direct Cgyy 使用只读日期覆盖 `2026-09-01` 复测后，站点仍通过（4 个），用途/日期/订单仍为 `upstream_unavailable`，锁码为 `invalid_semantics`；失败不随日期窗口改变，暂不能归因于当天无数据。
- CLI 锁码输出已改为仅返回 `{available: boolean}`，Core facade 仍保留旧版不透明 `data`；CLI schema、验证器和脱敏单测均已同步。Direct 复测中锁码现按上游 `upstream_unavailable` 记录，不再误报 `rawData` 结构错误。
- 锁码投影后的 WebVPN/auto 单项复测均未再出现 `rawData` 结构误报：WebVPN 站点成功但用途、日期、订单、锁码均为 `upstream_unavailable`；auto 在站点、用途、订单阶段失败并按依赖规则跳过详情，锁码同样为 `upstream_unavailable`。
- 最新三路线 Cgyy 单项复测：Direct 在站点、用途、订单、锁码均为 `upstream_unavailable`；WebVPN 站点通过后用途、日期、订单、锁码均为 `upstream_unavailable`；auto 在站点、用途、订单失败后结束，均为 `upstream_unavailable`。该波动未提供足够证据修改请求或重试策略。

## 2026-08-29 当前轮三路线全量复测

- Direct 全量使用进程内临时摘要盐执行：User、课表、考试、成绩、教室、SPOC、Judge、Signin、Ygdk、LibBook、Bykc、Evaluation 均通过；Judge 详情语义通过。Cgyy 站点通过（4 个），用途与订单为 `upstream_unavailable`，日期为 `upstream_changed`，聚合退出码 5。
- WebVPN 全量使用进程内临时摘要盐执行：除 Cgyy 外全部只读操作通过，Judge 详情语义通过；Cgyy 站点通过（4 个），用途与订单为 `upstream_unavailable`，日期为 `upstream_changed`，聚合退出码 5。
- auto 全量解析到 Direct：除 Cgyy 外全部只读操作通过，Judge 详情语义通过；Cgyy 站点通过（4 个），用途与订单为 `upstream_unavailable`，日期为 `upstream_changed`，锁码为 `upstream_unavailable`，聚合退出码 5。
- 本轮未调用任何真实写操作。摘要盐仅存在当前 shell，未输出、保存或提交；Cgyy 失败仍是未解决的实时硬门禁，不能宣告迁移完成。

## 2026-08-29 Cgyy 用途类型冻结回退修复

- 根据冻结 `LocalCgyyApiBackend.getPurposeTypes` 的 `runCatching` 语义，动态 `/api/codes` 请求或解析失败时回退十项静态用途类型；无主会话仍返回认证错误。新增单路线 Mock 测试先失败后通过，并补齐 `RouteClient::cgyy_purpose_types` 入口。
- 修复后 Direct、WebVPN、auto 的 Cgyy 用途阶段均不再失败；三路线继续执行到日期/订单阶段。Direct 日期/订单为 `upstream_unavailable`；WebVPN 与 auto 日期及依赖详情为 `upstream_unavailable`。未执行真实写操作。

## 2026-08-29 Cgyy 回退后 Direct 全量复测

- Direct 全量：用途阶段通过静态回退，站点查询成功（4 个）；其余非 Cgyy 只读操作及 Judge 详情语义均通过。Cgyy 日期为 `upstream_changed`、锁码为 `upstream_unavailable`，聚合退出码 6。
- 本轮仍只执行读操作；未改变日期/锁码请求或错误分类，也未执行任何真实写接口。

## 2026-08-29 Cgyy 回退后三路线复测更新

- WebVPN 全量：用途静态回退成功，站点成功（4 个）；其余只读操作及 Judge 详情语义通过，Cgyy 日期和依赖详情为 `upstream_unavailable`，聚合退出码 5。
- auto 全量解析到 Direct：用途静态回退成功，站点成功（4 个）；其余只读操作及 Judge 详情语义通过，Cgyy 日期和订单为 `upstream_unavailable`，聚合退出码 5。
- 两次运行均未调用真实写接口；失败集中在日期/订单实时上游，暂无新协议证据支持修改请求或错误策略。

## 2026-08-29 用途回退后 WebVPN/auto 全量复测

- WebVPN 全量：用途回退成功，站点查询成功（4 个）；其余只读操作及 Judge 详情语义通过。Cgyy 日期和依赖详情为 `upstream_unavailable`，聚合退出码 5。
- auto 全量解析到 Direct：用途回退成功，站点查询成功（4 个）；其余只读操作及 Judge 详情语义通过。Cgyy 日期和订单为 `upstream_unavailable`，聚合退出码 5。
- 本轮仅执行只读请求，未改变协议策略或执行任何真实写操作。

## 2026-08-29 Cgyy 成功信封严格校验

- 对照冻结 `LocalCgyyApi.requestJson`，将 Core Cgyy 信封校验收紧为必须存在且等于 `code=200`；新增缺失码和 `code=0` 的脱敏测试，先失败后通过。
- 该修复仅影响异常响应的解析语义，不改变实时 URL、重定向、签名或缓存；实时日期/订单硬门禁仍未通过，未执行真实写操作。

## 2026-08-29 Cgyy 日期槽位排序

- 对照冻结日期映射补齐每个空间槽位按 `timeId` 升序输出，逆序脱敏响应测试已通过。
- 本轮未改变上游协议或执行真实写操作；Cgyy 日期/订单实时硬门禁仍待上游可用证据。

## 2026-08-29 Cgyy 三路线逐操作复测

- Direct：站点成功（4 个），日期和锁码 `upstream_unavailable`，退出码 5。
- WebVPN：站点成功（4 个），日期 `upstream_changed`，订单和锁码 `upstream_unavailable`，退出码 6。
- auto：解析到 Direct；站点成功（4 个），日期 `upstream_changed`、订单 `upstream_unavailable`，退出码 6。
- 仅记录路由、阶段、计数和稳定错误类别；没有输出凭据、Cookie、令牌、原始响应或个人数据，也没有调用真实写接口。Cgyy 仍是未通过的实时硬门禁。

## 2026-08-29 三路线全量只读复测

- Direct：全部非 Cgyy 功能及 Judge 详情通过；Cgyy 站点 4 个通过，日期/订单 `upstream_unavailable`，退出码 5。
- WebVPN：全部非 Cgyy 功能及 Judge 详情通过；Cgyy 站点 4 个通过，日期/订单 `upstream_unavailable`，退出码 5。
- auto：解析到 Direct，全部非 Cgyy 功能及 Judge 详情通过；Cgyy 站点 4 个通过，日期 `upstream_changed`、订单 `upstream_unavailable`，退出码 6。
- 这些失败项已确认不是本地缺失功能；按冻结实现保持现状并记录，未执行真实写操作。整体迁移仍未完成，待 Cgyy 实时上游恢复或取得新证据。

## 2026-08-29 Cgyy 场馆包装展开

- 对照冻结 `asVenueSiteArray`，Core 现将 `data` 中场馆对象的 `siteList` 展开为扁平站点并继承 `venueName/campusName`；新增脱敏回归测试已通过。
- 扁平响应仍兼容；本轮未改变实时协议或执行真实写操作。Cgyy 日期/订单实时硬门禁仍按上游不可用记录。

## 2026-08-29 LibBook 座位排序

- 对照冻结实现补齐座位 DTO 按 `no` 字符串升序输出；新增脱敏回归测试已通过，LibBook focused suite 6/6 通过。
- 本轮未改变上游请求或执行真实写操作。

## 2026-08-29 LibBook 预约总数回退

- 对照冻结实现补齐预约分页缺少 `total` 时回退为当前条数；新增脱敏回归测试已通过，LibBook focused suite 7/7 通过。
- 本轮未改变上游请求或执行真实写操作。

## 2026-08-29 LibBook 分区编号回退

- 对照冻结实现补齐分区详情缺少区域 ID 时回退请求 ID；新增脱敏回归测试已通过，LibBook focused suite 8/8 通过。
- 本轮未改变上游请求或执行真实写操作。

## 2026-08-29 Bykc 签到配置严格解析

- 对照冻结 `LocalBykcApi.parseSignConfig`，补齐签到点列表的整体失败语义：任一点坐标缺失或类型错误时返回空配置，而不是静默丢弃坏点。
- 新增脱敏测试先失败后通过，Bykc focused suite 9/9 通过；未改变请求协议、加密或实时验收策略。

## 2026-08-29 Ygdk 记录时间戳

- 对照冻结 `LocalYgdkRecordRaw` 与 `timestampToDateTimeText`，补齐记录 Unix 秒时间戳到东八区文本的转换；新增脱敏测试先失败后通过。
- 未改变请求参数、会话、上传或真实写操作策略。

## 2026-08-29 Ygdk 记录图片字段

- 对照冻结 `extractRecordImages`，补齐 `images_fmt` 非空字符串作为单个地址的兼容解析；新增脱敏测试先失败后通过。
- 未改变请求参数、会话、上传或真实写操作策略。

## 2026-08-29 Ygdk 数字字符串时间戳

- 对照冻结 `JsonObject.long`，补齐数字字符串时间戳的东八区格式化；新增脱敏测试先失败后通过。
- 未改变请求参数、会话、上传或真实写操作策略。

## 2026-08-29 三路线全量只读复测

- Direct：User、Schedule、Exam、Classroom、SPOC、Judge（含详情）、Signin、Ygdk、LibBook、Bykc、Evaluation 通过；Grades 本轮未出现失败；Cgyy 在用途/站点后业务阶段返回 `upstream_unavailable`，聚合退出码 5。
- WebVPN：User、Schedule、Classroom、SPOC、Signin、Ygdk、LibBook、Bykc、Cgyy 站点和 Evaluation 通过；Grades 返回 `parse_error`，Judge 严格快照校验返回 `invalid_semantics`；Cgyy 日期、订单、锁码均 `upstream_unavailable`，聚合退出码 6。
- auto：解析到 Direct；User、Schedule、Exam、Classroom、SPOC、Judge（含详情）、Signin、Ygdk、LibBook、Bykc、Evaluation 通过；Grades 返回 `upstream_changed`；Cgyy 用途/站点后订单、锁码等阶段 `upstream_unavailable`，聚合退出码 6。
- 三次运行均只执行认证和读操作，未调用任何真实业务写接口；失败项均保留冻结实现语义，未根据单次实时错误猜测新协议。

## 2026-08-29 LibBook 原语字段兼容

- 对照冻结 `JsonPrimitive.contentOrNull`，补齐图书馆字段由数字/布尔原语转文本的行为；新增数字座位字段脱敏测试先失败后通过。
- 未改变请求、加密、会话或真实写操作策略。

## 2026-08-29 Cgyy 原语字段兼容

- 对照冻结 `LocalCgyyApi.string`，补齐场馆文本字段从数字/布尔原语转为字符串的行为；新增数字站点字段脱敏测试先失败后通过。
- 未改变签名、请求、路线、会话或真实写操作策略。

## 2026-08-29 Signin 写响应状态兼容

- 对照冻结 `jsonStringValue`/`int`，补齐签到写响应中数字字符串 `STATUS` 与 `stuSignStatus` 的解析；新增脱敏单元测试通过。
- 未改变签到登录入口、请求参数或真实写操作禁止策略。

## 2026-08-29 Evaluation 任务身份参数

- 对照冻结 `LocalEvaluationService.fetchTasks`，补齐任务列表 `yhdm` 使用登录资料 `schoolid`、空值回退 `username` 的语义；新增脱敏单元测试并通过。
- 账号标识仅保存在 Core 运行时内存，不写入会话文件、日志或实时证据；未改变评教写操作禁止策略。

## 2026-08-29 Ygdk 原语文本兼容

- 对照冻结 `JsonPrimitive.contentOrNull`，补齐记录文本字段对数字/布尔原语的文本化；新增脱敏测试覆盖 `item_name` 与 `place` 并通过。
- 未改变阳光打卡请求、令牌、上传或真实写操作禁止策略。

## 2026-08-29 Evaluation 原语文本兼容

- 新增布尔原语脱敏测试，先确认旧实现失败，再补齐评教文本字段对数字/浮点/布尔原语的文本化；focused 测试通过。
- 未改变评教请求顺序、提交信封或真实写操作禁止策略。

## 2026-08-29 三路线全量只读复测（原语兼容后）

- Direct：User、Schedule、Exam、Grades、Classroom、SPOC、Judge（含详情）、Signin、Ygdk、LibBook、Bykc、Evaluation 逐项通过；Cgyy 站点通过，日期返回 `upstream_unavailable`，聚合退出码 5。
- WebVPN：上述非 Cgyy 功能逐项通过；Cgyy 站点通过，日期为 `invalid_semantics`、锁码为 `upstream_unavailable`，聚合退出码 1。
- auto：路由解析为 Direct；上述非 Cgyy 功能逐项通过；Cgyy 站点通过，日期与详情为 `upstream_unavailable`，聚合退出码 5。
- 本轮只执行认证和读操作，未调用选课、签到、预约、取消、提交或上传；失败项按用户约定保留冻结实现并记录，未依据单次实时响应猜测新协议。

## 2026-08-29 认证资料持久化边界

- 冻结旧版会在 `LocalAuthSession` 中保存 `schoolid/username`，评教任务等请求可在进程重启后继续发送身份参数。
- UBAA2 当前合同与公开会话契约明确禁止在 `session.json` 持久化用户名或个人资料；Core 因此只在本次进程登录成功后以内存状态提供身份参数，加载旧会话时缺失身份会保持空值并返回上游实际结果。
- 该项是安全契约与旧版持久化语义的已记录边界，不从 Cookie 或未证实响应字段推导身份，也不因此修改上游协议。
