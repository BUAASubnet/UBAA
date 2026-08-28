# 迁移状态

Updated: 2026-08-28

## Conclusion

冻结源逐操作复核、Core/CLI 确定性门禁和大部分只读实时能力已完成；写操作均有
协议实现、Mock/向量和 CLI 确认保护，但真实验收永不调用。当前整体仍未达到最终完成：
Cgyy WebVPN 业务会话持续认证失败，Direct 门锁码上游不可用。验证码图像求解器已迁移
并有 PNG/JPEG、加密向量、重试和逐请求 Mock 证据；WebVPN Grades/Judge/Evaluation
的最新单项重跑通过，但聚合矩阵仍必须保留瞬态失败证据并继续复核。

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

Ygdk 阳光打卡已完成只读概览与记录的 Core 解析、独立 OAuth/业务令牌请求、路线 facade、CLI `ygdk overview`/`ygdk records` 及 JSON Schema 接线。提交打卡和照片上传仍明确排除；Direct/WebVPN 真实上游验证尚未完成。

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
| 9f 扩展查询与写入口 | Signin、Ygdk、LibBook、Bykc、Cgyy、Evaluation 的 Core/CLI 入口已接入；写操作具备确定性证据 | 所有写操作均要求显式确认并由实时验证器排除；Ygdk、Evaluation、Cgyy 已补请求向量或 Mock 链，仍需继续补齐逐操作证据和错误矩阵。 |
| 10 CLI/JSON | Deterministic remediation complete; final CLI E2E passed | Ordinary commands use the aggregate Core facade; every renderer, startup/argument failure and hidden diagnostic emits schema v2; aggregate auth/logout metadata and route data are fixed Direct then WebVPN; unsafe config targets and concurrent atomic writes are covered. |
| 10a live verifier | Deterministic remediation complete | The harness rejects unsafe errors, non-v2/wrong aggregate order, invalid integer bounds, cross-request term/SPOC identity drift, missing SPOC query proof, incomplete Judge semantics, route contradictions, sensitive/raw output and Judge JSON in argv; it proves xtrace suppression and username/password stdin routing. Production verification is non-interactive and records an upstream interactive verification page as `upstream_changed`. |
| 11 live matrix | Latest complete matrix passed; transient WebVPN Judge snapshot failures retained | Keep the strict `judge_cutoff` subset check and rerun the complete aggregate when upstream list volatility causes a nonzero result. |
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
- No write operation is migrated: submission/upload, answers, reservations, attendance, grading changes and other side effects remain out of scope.
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
- 剩余验收缺口：Ygdk、Cgyy、Evaluation 写操作仍需完整 Core 协议、向量和 Mock 测试；LibBook 与 Signin 已有 Core/CLI 写入口，但仍需专门的请求和向量测试。所有功能逐项 Direct/WebVPN/auto 读验证仍未完成，迁移尚未完成。
- 本阶段补齐 LibBook 预约/取消 Core 与 CLI 写入口，并以冻结 golden 向量验证字段顺序、日期派生 AES-128-CBC、PKCS#7 和固定 IV；本阶段提交为后续审查起点。
- LibBook 写链阶段进一步增加了确定性 Mock 端到端测试，覆盖预约 `/v4/space/confirm` 与取消 `/v4/space/cancel` 的顺序、请求体和路线内会话；提交为 `24acd8b`。该证据不等同于真实写操作验收，verify-live 仍永久跳过写入口。
- 新增 Ygdk `submit` Core/CLI 写入口，按冻结实现上传照片后提交打卡表单；默认拒绝，必须显式 `--confirm-write`，未执行真实写操作。
- Ygdk 写入阶段完成了 multipart 上传边界、固定表单字段、CLI 文件输入校验及脱敏请求向量；真实写操作仍永久禁止，最终验收仍受全局实时矩阵门禁约束。
- Cgyy 阶段已提交 `1d25ef2`：完成日期上下文、空间/时段校验、预约上下文创建和最终预约表单的冻结字段实现；验证码挑战与求解端口尚未迁移，CLI 提交入口和真实写验收继续禁止调用。
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
- Signin 写请求已提取冻结表单构造器并增加只含 `id` 字段的确定性断言；真实签到和写请求 live 验收仍永久禁止。
