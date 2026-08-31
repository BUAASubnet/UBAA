# Decision Log

## 2026-08-31：Cgyy 路线与 Core-live 真实验证边界校正

本周期先对照冻结 `ubaa_old`、固定版本 `examples/buaa-api` 和现有脱敏 Mock。原有 WebVPN Cgyy 测试复现了业务请求误走 Direct 的失败：WebVPN-only 会话无法完成站点读取，且写入口也固定访问 Direct。新增失败测试后，Core facade 将每个 Cgyy 公共操作分别绑定到解析出的路线 runtime；WebVPN 现在只使用 WebVPN URL，Direct 会话缺失不会触发偷偷回退。相同批次内业务令牌仍只在当前客户端内存复用，认证失效最多清理、重登并重放一次。

冻结旧版 `LocalWebVpnSupport.localCgyyUpstreamUrl` 曾返回直连地址，`examples/buaa-api` 没有等价实现；该冻结行为与本周期明确的 WebVPN-only 路线合同冲突。冲突边界以脱敏 WebVPN-only 失败/修复测试和当前路线安全要求为依据，未从示例协议借用任何 URL、字段或令牌；后续真实 WebVPN 结果必须逐操作记录，若上游不支持该路线则记录失败而不回退 Direct。

锁码解析另以脱敏失败测试复现了 CLI 序列化原始 `data` 的泄漏，现已收敛为 Core/CLI 公共结果 `{available: boolean}`；锁码正文不会进入 Session、日志或文件。以上修复均通过 focused Cgyy 测试、敏感扫描和确定性检查；协议 URL、参数、签名常量仍只取冻结实现，`examples/buaa-api` 无对应 Cgyy 实现，未作类比推断。

真实验证入口已拆为单批次 `core-live` 与薄 `verify-live`：Core-live 一次创建固定路线 `RouteClient`，从 stdin 读取凭据并串行执行只读 facade 操作，逐项输出路线、操作、`PASS/FAIL/BLOCKED/NOT_APPLICABLE` 和稳定错误码；不调用任何写方法。`verify-live` 仅校验参数、临时读取 `.env.local`、锁定构建并转发，拒绝 `auto`；`auto` 只保留 Mock/确定性路由证据。Direct/WebVPN 的真实结果必须在本周期重新逐项记录，不能沿用旧脚本聚合摘要。

新入口真实结果：Direct 全量逐项退出码 0，仅 SPOC 详情与 Bykc 课程详情因空列表为 `NOT_APPLICABLE`；课表、考试、成绩、教室、SPOC、Judge（含批量详情）、Signin、Ygdk、LibBook、Bykc、Cgyy、Evaluation 均有安全 `PASS`。WebVPN 的认证、用户、课表、考试、成绩、教室、SPOC、Judge、Signin、Ygdk、LibBook、Bykc 逐项通过，SPOC/Bykc 详情因无标识为 `NOT_APPLICABLE`；Cgyy 站点/用途/订单/锁码和 Evaluation 全部得到 `authentication_required`，依赖日期/订单详情为 `NOT_APPLICABLE`，Evaluation pending 为 `BLOCKED`，退出码 5。该失败保持 WebVPN 路线，不以 Direct 结果替代。

## 2026-08-29：用户授权 Cgyy Rust CLI 读写探针及提交落库时序

用户明确授权使用 `.env.local` 中的真实测试账号执行一次 Cgyy Rust CLI 预约并立即清理订单；该授权仅覆盖本次单笔 Direct 探针，不改变 `verify-live` 永远只读的全局规则。实时读操作中，Direct 登录、站点、用途、日期和订单读取均成功；日期返回 84 个时段，其中存在可预约时段。请求 JSON 省略验证码材料，由 Core 自动获取挑战、求解图片、校验并提交。

首次提交返回成功后立即调用取消，取消接口和 CLI 均返回成功，但订单列表仍暂时为 `orderStatus=1`。对照冻结 Python 脚本的 `sleep(5)`，等待 5 秒后对同一订单再次取消，订单列表最终变为 `orderStatus=2`；因此记录“提交完成到取消之间需要等待旧版落库窗口”，不能仅以取消接口的成功信封作为最终状态证据。没有保留或记录订单号、手机号、令牌、Cookie、验证码或原始响应。

取消后的详情请求第一次返回 `upstream_unavailable`，随后成功信封的 `data` 为空，Rust 按冻结旧版映射为空详情；订单列表状态 2 是本次取消的最终实时证据。另发现日期 DTO 曾将预约上下文 `reservationToken` 序列化到 CLI，导致安全合同拒绝成功响应；已通过脱敏失败测试先复现，再对 `CgyyDayInfo.reservation_token` 增加仅 Core 内部可用的序列化屏蔽。

## 2026-08-29：继续对齐 Cgyy 业务会话、信封和 Direct 路由

冻结 `ubaa_old` 的 `requestJson` 对场馆 GET/POST 请求都使用同一业务访问令牌，并在业务认证失效时清理业务令牌、强制登录后只重放一次；预约上下文返回的 `token` 只作为后续预约表单的业务字段，不能替代 `access_token` 放入 `cgAuthorization`。Rust 原实现在上下文、验证码校验和最终提交中误用了该预约 `token`，且业务认证失败没有按旧版重试；`WebVPN` facade 的 Cgyy 写操作也错误地使用了主路线 transport。

历史记录：本轮先以脱敏 Mock 固定上述失败行为，再完成最小修复：所有 Cgyy 业务 GET/POST 统一经过一次认证重试，写请求头恢复使用业务 `access_token`。当时的 WebVPN Direct 兼容分支已被本周期路线校正 supersede；当前 facade 读写均使用解析出的路线 runtime。日期接口严格要求 `code=200` 且 `data` 存在并为 JSON 对象（允许空对象）；锁码接口严格要求成功代码，缺失 `data` 映射为空值，保持旧版可空语义。

确定性证据为 Core Cgyy 集成测试 12/12、CLI 合同测试 23/23，以及 Cgyy facade 路由回归测试通过。实时只读证据仅确认两条路线的站点列表各返回 7 个；日期、订单和锁码在不同日期/路线出现 `upstream_unavailable` 或 `invalid_semantics`，部分日期结构探针曾返回正常对象，因此需把上游窗口/限流不稳定与本地协议错误分开处理。本轮没有调用预约、验证码校验、提交或取消写接口。`examples/buaa-api` 在冻结提交中没有等价 Cgyy 协议，未借用其 URL、字段或错误语义。

## 2026-08-29: Direct Cgyy read-only verification after signer parity fix

`just verify-live mode=direct feature=cgyy route=direct` completed with a safe
summary (`stage=cgyy`, `exit_code=0`, `site_count=7`). The verifier did not call
reservation or cancellation writes. This confirms the Direct site-list read for
this run only; date, order, detail and lock-code operations remain separately
subject to their own live outcomes and are not inferred from the site count.

## 2026-08-29: Auto Cgyy read-only verification

`just verify-live mode=auto feature=cgyy route=auto` resolved to Direct and
returned a safe site summary with `site_count=7`. The dependent date operation
returned `invalid_semantics`, while lock-code returned `upstream_unavailable`;
the verifier continued according to its dependency rules and did not invoke
reservation or cancellation writes. These are live upstream outcomes, not a
change to the frozen request or signing behavior.

## 2026-08-29: Align Signin today request with frozen local API

The frozen `LocalSigninApi.getTodayClasses` uses a GET request with the
`sessionId` header and `id`/`dateStr` query parameters. Rust had temporarily
used the non-equivalent example module's POST/`Sessionid` shape. A sanitized
request-construction test reproduced the mismatch; Core now follows the frozen
local method and header, while the example is recorded as supplemental and not
authoritative for this operation.

## 2026-08-29: Direct Signin verification after method correction

`just verify-live mode=direct feature=signin route=direct` succeeded with a
safe summary (`stage=signin`, `exit_code=0`, `result_count=0`). The run only
queried today's classes and did not invoke the sign-in write operation.

## 2026-08-29: WebVPN Signin verification after method correction

`just verify-live mode=webvpn feature=signin route=webvpn` succeeded with a
safe summary (`stage=signin`, `exit_code=0`, `result_count=0`). The run only
queried today's classes and did not invoke the sign-in write operation.

## 2026-08-29: Direct and WebVPN LibBook read-only verification

`feature=libbook` completed successfully on both explicit routes. Each run
returned a safe `library_count=2` summary and did not invoke reservation or
cancellation writes. The source-parity entry is updated from its stale
"not verified" wording to reflect this evidence; write operations remain
explicitly excluded from live verification.

## 2026-08-29: Preserve optional Ygdk overview enrichments

Frozen `LocalYgdkApi.getOverview` treats `getCount` and `Term.get` as optional
enrichments via `runCatching`; failures do not discard the required classify and
item list. A sanitized transport test reproduced Rust's previous propagation
of those errors. Core now substitutes an empty successful envelope for a failed
or malformed optional response, yielding zero/empty enrichment fields while
preserving the primary overview result.

## 2026-08-29: Direct Ygdk verification after fallback correction

`just verify-live mode=direct feature=ygdk route=direct` succeeded with a safe
summary (`stage=ygdk`, `exit_code=0`, `item_count=11`). The run performed only
read-only overview calls and did not invoke clock-in submission or photo upload.

## 2026-08-29: WebVPN Ygdk verification after fallback correction

`just verify-live mode=webvpn feature=ygdk route=webvpn` succeeded with a safe
summary (`stage=ygdk`, `exit_code=0`, `item_count=11`). The run performed only
read-only overview calls and did not invoke clock-in submission or photo upload.

## 2026-08-29: Preserve optional Evaluation list fallbacks

Both explicit route runs of `feature=evaluation` completed successfully with a
safe `course_count=0` summary. They performed only task/list reads and did not
invoke evaluation submission.

Frozen `LocalEvaluationService` treats activation, task, questionnaire and
course-list non-authentication exceptions as empty results/lists through
`runCatching`; authentication failures remain errors. A sanitized CAS-503 Mock
reproduced Rust's previous propagation. Core now returns an empty evaluation
response for non-auth activation failure and empty nested lists for later
non-auth fetch failures, while preserving authentication error propagation.

## 2026-08-29: Auto read-only matrix for corrected features

The independent auto-route runs resolved to Direct and completed successfully:
Signin returned `result_count=0`, LibBook returned `library_count=2`, Evaluation
returned `course_count=0`, and Ygdk returned `item_count=11`. These commands only
performed read operations; no sign-in, reservation, evaluation submission,
clock-in or photo-upload write was invoked. The results are recorded separately
from the explicit-route evidence and do not mask any other feature's outcome.

## 2026-08-29: Aggregate live gate blocked by missing Judge digest configuration

Fresh `feature=all` runs for Direct, WebVPN and auto each stopped before Judge
route comparison with exit code 2 because `UBAA_VERIFY_DIGEST_SALT` is unset.
The local environment contains only the test username/password keys and no
digest salt. This is a configuration prerequisite failure, not evidence of an
upstream protocol result; per-feature read-only runs remain the authoritative
evidence and no write operation was invoked.

## 2026-08-29: Full three-route matrix with ephemeral digest salt

With `UBAA_VERIFY_DIGEST_SALT` supplied only as a shell-scoped temporary value,
Direct and WebVPN completed User, Schedule, Exam, Grades, Classroom, SPOC, Judge
(including detail checks), Signin, Ygdk, LibBook, Bykc and Evaluation. Auto
resolved to Direct and completed the same set. Direct Cgyy failed at date and
lock-code with `upstream_unavailable`; WebVPN failed at date with
`invalid_semantics` and at orders/lock-code with `upstream_unavailable`; auto
failed at Cgyy date with `upstream_unavailable`. The salt was never persisted or
printed, and no real write operation was called. These Cgyy outcomes remain
strict live gates rather than reasons to alter frozen protocol behavior.

## 2026-08-29: CLI contract end-to-end gate

`cargo test --locked -p ubaa-cli --test cli_contract` passed all 23 tests. The
suite exercises the thirteen feature command groups, schema-v2 envelopes,
human/JSON redaction, route diagnostics, session preconditions and the complete
write-command default-deny plus explicit-confirmation behavior. No live write
request is part of this test.

## 2026-08-29: Authentication status across all routes

Separate `feature=auth` runs succeeded for Direct, WebVPN and auto; each
returned `stage=auth_status`, `exit_code=0` and `parsed_user=yes`. These checks
only established or inspected read-only authentication state and did not call
any business write operation.

## 2026-08-29: Method-level direct API inventory audit

The frozen `ubaa_old/shared/api/feature` interfaces for all thirteen in-scope
domains were compared with the Rust feature functions, facade methods and CLI
commands. Every listed direct read/write operation has a corresponding Core and
CLI entry; no missing direct method was found. Server-only routes and
non-equivalent example modules were excluded from this conclusion.

## 2026-08-29: Preserve Classroom response status field semantics

The frozen classroom implementation deserializes the complete `e/m/d` envelope
without checking that `e == 0`; `e` is a response field rather than a success
gate. A sanitized Rust test with `e=1` first failed because Core returned
`upstream_changed`. Removing that unevidenced gate makes the test pass while
retaining required envelope and room-field type validation. No URL, request or
live behavior was changed.

## 2026-08-29: Core integration test gate

`cargo test --locked -p ubaa-core --tests` passed with exit code 0. The run
covered feature parsers, connection and session isolation, deterministic Mock
request chains, crypto/signature vectors and write-operation error paths. It
performed no real write request.

## 2026-08-29: Cgyy read-only availability recheck

Fresh per-feature runs returned `site_count=7` on Direct, WebVPN and auto (auto
resolved to Direct). Date and order stages returned `upstream_unavailable` on
all three routes; WebVPN lock-code also returned `upstream_unavailable`. No new
request, redirect, signing or response evidence was observed, so the frozen
protocol and failure-closed behavior remain unchanged. The verifier performed
read-only calls only and invoked no reservation or cancellation write.

## 2026-08-29: Full three-route matrix with ephemeral digest salt

With `UBAA_VERIFY_DIGEST_SALT` supplied only as a shell-scoped temporary value,
Direct and WebVPN completed User, Schedule, Exam, Grades, Classroom, SPOC, Judge
(including detail checks), Signin, Ygdk, LibBook, Bykc and Evaluation. Auto
resolved to Direct and completed the same set. Direct Cgyy failed at date and
lock-code with `upstream_unavailable`; WebVPN failed at date with
`invalid_semantics` and at orders/lock-code with `upstream_unavailable`; auto
failed at Cgyy date with `upstream_unavailable`. The salt was never persisted or
printed, and no real write operation was called. These Cgyy outcomes remain
strict live gates rather than reasons to alter frozen protocol behavior.

## 2026-08-17: Execute the authentication contract from frozen evidence

The active design is `goal.md`. The old and example repositories match their required HEAD and origins and are clean. No protocol conflict has been identified during the initial inventory. Unknown upstream behavior will not be guessed; it will be recorded here with evidence before a decision.

## 2026-08-17: Preserve verified HTTP redirect compatibility

Fixed SSO and User Center entry points remain HTTPS and TLS verification remains enabled. Redirect resolution continues to accept both `http://` and `https://` only for the authentication host allow-list. This follows `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalConnectionAuth.kt::resolveRedirectUrl`, which explicitly recognizes both schemes, and the frozen WebVPN URL codec/tests that preserve HTTP protocol segments. Rejecting HTTP would be an unevidenced protocol change. Secure-cookie filtering still prevents Secure cookies from being sent over HTTP.

The scheme and host checks are both mandatory. Non-HTTP schemes such as `ftp` are rejected even when their host is otherwise allowed, and WebVPN conversion never encodes them.

## 2026-08-17: Keep the public facade concrete and runtime private

Hosts consume the non-generic `UbaaClient`; injected transport and session ports are boxed inside private `ClientRuntime`. Authentication and User Center workflows live in `auth` and `features/user`, while `facade` delegates stable DTO operations. `upstream` is crate-private, and the CLI uses `UbaaClient::open` rather than inspecting `FileSessionStore`. This keeps host APIs independent of upstream and storage implementation types without removing deterministic port injection.

## 2026-08-17: Add bounded buffering and locked session replacement

Authentication/User Center response bodies are capped at 8 MiB and persisted session JSON at 1 MiB. These are conservative UBAA 2 memory/file safety budgets, not upstream protocol facts. Session operations reject symlink/non-regular targets, open final files without following links, restore owner-only Unix permissions, use a sidecar OS lock and unique exclusive temporary files, synchronize writes, and preserve the existing `session.json` schema.

The sidecar lock also stores a synchronized monotonic revision. A runtime loads the snapshot and revision atomically, then compare-exchanges every save, invalidation, mode-mismatch clear, and logout clear. The revision is advanced and synchronized before replacing or deleting `session.json`; a crash may cause a conservative conflict but cannot authorize a stale writer. This prevents snapshot-equality ABA and ensures an old process cannot recreate a cleared session or delete a newer one. Windows inherits the selected directory ACL; explicit owner-only ACL enforcement remains a release audit item.

## 2026-08-17: Preserve JSON captcha non-interactivity (superseded)

This historical design recorded the old JSON `captcha_required` and human-fallback
workflow. It is superseded by the 2026-08-25 decision below: the current Core, CLI
and verifier are non-interactive and return `upstream_changed` before any image or
credential request when an unsupported verification step is detected. The old
workflow is retained only as frozen-source evidence and is not an acceptance gate.

## 2026-08-25: Remove the unsupported interactive verification branch

The previous JSON challenge and human-fallback design is superseded. The user-facing product now runs client-direct and must remain non-interactive for this authentication boundary. `LoginInput` and `DualLoginInput` contain only username and password; the Core domain, facade, CLI, JSON schema, live verifier and tests expose no challenge, image, captcha answer or captcha-specific exit code. The frozen old implementation still documents and implements a captcha branch, while the pinned example has no equivalent protocol. UBAA2 therefore keeps only the ordinary evidence-backed login form. If the SSO page contains the observed `config.captcha` marker or another interactive verification step, Core returns `upstream_changed` before any image request or credential POST. This is an intentional source-parity difference, not an inferred upstream field; it must be treated as a live hard-gate failure and recorded for future protocol work rather than worked around.

## 2026-08-25: Do not equate weekly schedule display code with the request term

The corrected Direct and WebVPN live verifier reached `schedule current` and
returned a successful `WeeklySchedule` envelope with an empty `arrangedList`.
Its `data.code` was a non-empty string but did not equal the selected semester
term on either route. The frozen `WeeklyScheduleResponse` and
`WeeklySchedule` only define decoding of `datas` and do not specify an equality
invariant; the pinned AAS example is non-equivalent for this local DTO. The
prior verifier assertion was therefore an unsupported semantic restriction,
not a Core parse failure. It now checks only the evidenced non-empty string
contract and keeps term selection/request parameters independently validated.
Empty code remains rejected. No raw live value is recorded.

## 2026-08-17: Preserve remote-first logout while protecting local revisions

Both `LocalConnectionAuth.kt::logout` and the remote-backed `AuthApi.kt::logout` attempt remote logout before clearing local state. UBAA 2 preserves that evidenced order and always clears the current client's in-memory Cookie/login state. The persisted clear is revision-conditional so a stale process cannot delete a newer local session. Frozen code and current live evidence do not define whether a stale process's remote logout can invalidate a concurrently created upstream session, so future long-lived hosts must serialize logout for a shared account rather than inventing a remote concurrency guarantee.

## 2026-08-17: Require locked dependency resolution in deterministic gates

`just check`, macOS/Windows CI, the live verifier, and documented user commands use `--locked` for every Cargo command that resolves dependencies. `just check` first runs `cargo metadata --locked --no-deps --format-version 1`; a cross-platform binary test uses the Git index to scan tracked Markdown, `justfile`, workflow, and shell command sources so later edits cannot silently remove the lock contract. `cargo fmt` is exempt because it does not resolve the dependency graph.

## 2026-08-19: Historical Judge auto WebVPN route (superseded 2026-08-23)

The frozen `LocalJudgeApi` and its tests establish the Judge SSO service URL, route-local business pages, course selection, and isolated worker clients. At that time live verification showed Judge Direct unavailable while the explicit WebVPN route completed list/detail parsing with exit 0, so the route matrix temporarily forced `auto` to WebVPN for all network states. This was a deterministic feature exception, not a fallback replay. Later WebVPN/auto attempts also returned upstream timeouts or changed responses; those observations remain historical rerun conditions. Fresh campus evidence and the superseding 2026-08-23 decision below removed the stale override.

## 2026-08-19: Require AAS service activation before schedule reads

The frozen local schedule implementation probes `byxt.buaa.edu.cn/.../currentUser.do` and classifies an SSO page as authentication-required. The pinned `examples/buaa-api/src/api/aas/core.rs` proves that the same AAS protocol has a service-specific CAS bootstrap URL ending in `.../homeapp/index.do?contextPath=/jwapp` and requires the final URL to start with that AAS landing page. Live `.env.local` verification initially returned an SSO-shaped response for the probe, so terms/weeks could not begin even though generic SSO and User Center authentication succeeded. Core now performs the proven AAS activation only after that probe condition, verifies the route-local final URL, then probes again. Direct and WebVPN schedule terms/weeks/current/today subsequently passed; no generic SSO bypass or cross-route cookie replay was added.

## 2026-08-19: Preserve form content type for schedule/grade POSTs

The old local implementations use Ktor `FormDataContent` for the weekly schedule and grade query forms. The Rust helper serialized the same fields but omitted `Content-Type: application/x-www-form-urlencoded`. A TDD request-contract test observed the missing header, and the minimal fix was applied in the shared form helper. The first real schedule-current response had only safe structural error keys (`code`, `logId`, `msg`), and after the header fix the full schedule auto/Direct/WebVPN verifier passed. The pinned AAS example uses a POST query payload rather than this local form helper; it is not used to override the local endpoint's observed form contract.

## 2026-08-19: Do not merge non-equivalent example protocols

The pinned `buaa-api` App module exposes a mini-program exam page and no local `buaascore` grades operation; its Class module exposes iClass course/check-in endpoints and no free-classroom query; its tree has no Judge module. The frozen local implementation has separate grades, free-classroom, and Judge protocols. These are documented as non-equivalent in `docs/migration/source-parity.md`; their URLs, headers, DTOs, encryption, or errors must not be borrowed by analogy. This is a deliberate evidence boundary, not an implementation omission.

## 2026-08-19: Choose a stable Judge detail sample in the live verifier

The verifier contract requires one real Judge detail when the list is non-empty; it does not require the last list item. Three required/diagnostic auto attempts selected `.data[-1]` and returned `Judge assignment was not found` at the separate detail CLI process, while an evidence probe selecting `.data[0]` completed list plus detail with exit 0. The list and detail are separate processes and the upstream list can change between them, so the verifier now selects the first returned item and has a shell regression test. This changes only verifier sampling, not Core Judge lookup or its old-reference semantics; stale-ID results remain nonzero rather than being hidden.

## 2026-08-23: Revalidate Judge Direct in the campus network

The previous Judge `auto -> WebVPN` override was introduced after an explicit Direct attempt returned `upstream_unavailable`. With the test account on the campus network, later live checks returned exit 0 on Direct (reported 65 assignments) and WebVPN (reported 17 assignments), while the other five features also returned exit 0 on both explicit routes. The old implementation supports route-local Judge requests and does not require WebVPN, so the stale feature override was removed. This decision did not explain the 65/17 difference and did not prove the old detail parser semantics; the remediation decision below therefore reclassifies these values as historical observations rather than completed parity evidence.

## 2026-08-23: Use a bounded TCP gateway probe

The accepted product signal is a TCP connection attempt to `gw.buaa.edu.cn:80`, following the concrete target, port and 500ms duration in pinned `examples/buaa-api/src/utils/net.rs`. The entire operation, including hostname resolution and all resolved-address attempts, has one 500ms budget. Any successful connection is `Campus`; ordinary resolution failure, no addresses, refusal, unreachable network or deadline exhaustion is `OffCampus`. Only an internal probe implementation failure or deliberately injected diagnostic failure is `Unknown`. Results are process-local and cached for 60 seconds. The probe sends no HTTP/TLS request, reads no credential and hard-codes no IP address/range.

This supersedes the earlier resolver-only authority. The total-budget and `Unknown` boundary are explicit UBAA 2 product constraints because the example applies 500ms per address and returns only Boolean; they are not presented as frozen upstream behavior.

## 2026-08-23: Move ordinary route selection into the aggregate Core facade

The earlier host-owned diagnostic design is superseded. The ordinary `UbaaClient` facade owns strict config loading, the cached gateway probe, route resolution/readiness checks, two private route runtimes, the shared dual-session coordinator and route-owned feature state. CLI and future hosts only parse input, call facade methods and render the facade's safe diagnostics. Explicit `ConnectionMode` remains available only through a clearly separate diagnostic/test path.

One coordinator owns the loaded dual snapshot and revision. It never adopts a revision written by another process in order to retry a mutation. Aggregate logout performs both best-effort remote calls, clears this process, and attempts one dual compare-exchange; a conflict preserves the complete newer persisted snapshot.

## 2026-08-23: Preserve route CAS semantics inside the dual coordinator

The two route runtimes share one file revision but retain independent route-local logical revisions. A route adapter rejects an outdated logical revision before building a candidate, so two same-route writers that loaded the same state cannot both succeed. A valid sibling-route mutation may advance the file revision without making the other route's logical revision stale; the coordinator then merges that route's replacement into its client-owned full snapshot and performs one file CAS. Aggregate logout advances both route-local revisions and the file revision through one full-snapshot clear, including when this client originally loaded no slots.

An external file CAS conflict is terminal for that coordinator instance. It clears the coordinator snapshot and both route runtimes/auth workflows, stops any not-yet-started sibling request, preserves the complete external snapshot, and returns the stable retryable conflict. Later calls on that instance keep returning the conflict without network I/O; recovery requires opening a new facade. This prevents a stale process from silently adopting the external revision or continuing with sibling Cookies after one route has lost ownership.

A file CAS error is treated as equally terminal because the crash-safe store intentionally advances and synchronizes its revision before replacing or deleting `session.json`. An error may therefore mean that revision ownership was lost even when the body operation did not complete. The coordinator clears its client-owned snapshot and the facade clears all in-memory Cookies/workflows before returning; it never assumes that an `Err` happened before the revision write. A Unix permission fault-injection test covers this post-revision/body-write failure boundary.

Remote logout remains an unconditional best-effort request on each owned route, matching both frozen logout implementations and the aggregate contract. An absent local slot suppresses Cookie attachment but does not suppress the Direct or WebVPN logout attempt. Deterministic CLI tests route these requests through a local rejecting proxy, so the repository gate never depends on the real upstream.

Receiving SSO prepare-page Cookies does not establish a local authenticated session. Only an `authenticated_at` value restored from a persisted route slot or produced after successful User Center status validation authorizes user/business preflight. This keeps `prepare_login` state usable for credential submission while ensuring status, profile and all read-only features make zero requests between prepare and completed login. Any persistence-port error while committing that validated state clears the runtime Cookie jar, timestamps and pending workflow before the error escapes, including for injected non-file stores.

## 2026-08-23: Make CLI schema v2 the only output contract

All ordinary commands, hidden diagnostics, argument failures, authentication results and read-only results emit only schema version 2. The unshipped schema-v1 CLI branch is removed rather than maintained as compatibility surface. This does not change `config.toml` on-disk format version `1` or the versioned `session.json` migration reader; those are independent disk formats.

## 2026-08-24: Represent pre-resolution CLI failures without inventing a route

Neither frozen source defines a CLI JSON envelope. The UBAA 2 contract requires schema version 2
for argument and startup errors, but those failures can occur before configuration is loaded or a
route is resolved. Such failures use the routed schema-v2 envelope with an unresolved metadata form
containing only the stable command feature. They never fabricate `routePolicy`, `networkState`,
`initialRoute`, `resolvedRoute`, `usedFallback`, or aggregate route results. Once Core returns a
`RouteResolution`, the complete six-field resolved metadata is mandatory. Aggregate authentication
envelopes are emitted only after an actual two-route outcome exists and always carry Direct then
WebVPN in fixed order.

## 2026-08-23: Bind aggregate captcha answers before credential submission (superseded)

This historical design recorded route-scoped captcha challenge state and answer
binding from an earlier implementation. It is superseded by the 2026-08-25
non-interactive authentication decision; no challenge IDs, answers or image data
exist in the current public or internal login workflow.

## 2026-08-23: Reopen SPOC and Judge live conclusions

Frozen `LocalSpocApi.kt` treats course metadata as optional and always calls the encrypted global `queryListByPage` operation with `kcid=""`. Pinned `buaa-api` instead calls per-course `queryXsZyList`, so its list/auth flow is non-equivalent; only matching AES constants, token facts and the detail endpoint may supplement the old source. The prior three-route empty result is unverified until the corrected global empty-`kcid` request is observed. It cannot be called a valid empty list merely because the command exited 0.

Pinned `buaa-api` has no Judge module. Frozen `LocalJudgeApi.kt` filters `problemContent`/`judgeDetails` assignment links and parses nested problem tables, scores, `PARTIAL` state and fallback counts. The current historical exit-0 detail checks did not assert all those semantics. Direct reported 65 items while WebVPN reported 17; the difference is unresolved and must be investigated after parser/cache parity without persisting IDs, titles or raw bodies. Neither route is permanently preferred from this observation.

## 2026-08-24: Keep Judge cutoff and batch behavior deterministic

The frozen local Judge API returns `historicalCutoffCourseIds`, groups batch work by course and
subtracts six months while retaining the current local time of day. UBAA 2 keeps cutoff course IDs
inside route-owned state rather than exposing them in the current summary-list DTO, and restores
normalized batch results to the caller's original key order. The cutoff retains the current
Shanghai time of day and clamps the day to the target month's final valid day (for example,
August 31 becomes February 28 or 29). These are explicit host-contract choices: internalizing the
cutoff IDs and restoring input order differ from the old public DTO/group traversal, while the
time-of-day rule preserves the applicable frozen comparison boundary.

## 2026-08-24: Resolve SPOC crypto and public-content source conflicts

The frozen local implementation and pinned example use the same AES-128-CBC key and IV, but they
do not agree for plaintext whose byte length is already a multiple of 16. `LocalSpocCrypto` adds
no zero block in that case; the example AES helper always appends a full zero block. UBAA 2 follows
the applicable frozen local implementation and covers aligned and unaligned plaintext with fixed
vectors. The example corroborates constants and CBC operation only.

The old detail DTO publicly exposes both raw HTML and derived plain text. UBAA 2 intentionally
keeps raw upstream HTML internal and exposes only normalized plain text. This is a security and
host-contract divergence, not a claim of exact DTO parity; detail/submission fields, fallback
rules, and status semantics continue to follow the frozen local implementation.

## 2026-08-24: Scope read-only feature state to one route runtime

Frozen `LocalClassroomApiBackend` owns a double-checked synchronization flag and mutex per backend,
and clears the flag with the selected authentication session. Pinned `buaa-api` exposes an iClass
API rather than this free-classroom protocol, so it contributes no URL, header, DTO, or state rule.
UBAA 2 therefore gives every Direct and WebVPN `ClientRuntime` a distinct
`Arc<RouteFeatureState>`. Read workers forked from that runtime share only that route's state;
separately constructed runtimes and the sibling route do not share it.

`clear_memory` is the common invalidation boundary for Cookies, authentication timestamps, and all
feature state. Authentication-required read-only errors in the diagnostic `RouteClient` now clear
the selected persisted route through the same compare-exchange path used by aggregate routed
operations. Logout, terminal conflict, explicit invalidation, and every successful login exit also
reach the same feature-state clearing contract. Classroom synchronization failures remain
best-effort and retryable, while a successful 200..399 bootstrap is reused only until that route's
state is cleared. The business query uses the no-redirect transport exactly once and treats a raw
SSO Location, 401, or evidenced login HTML as selected-route authentication invalidation.

## 2026-08-24: Bind SPOC retries and tokens to verified operation and route boundaries

Frozen `LocalSpocClient.withAuthenticatedCall` wraps current-term, course, assignment-page, detail,
and submission requests separately. Therefore an authentication failure on page two refreshes the
route credential once and repeats page two, rather than restarting the term/course/page-one
sequence. UBAA 2 follows that boundary with one common retry helper returning the second failure
unchanged. The outer frozen course lookup uses `runCatching`, so exhausted course authentication is
still optional metadata and cannot suppress the authoritative global assignment query.

The frozen token parser checks the landing path but not its host. Applying it literally before
redirect allow-listing would allow a foreign host with the same path to supply a token, while a
Direct client could consume a WebVPN terminal. UBAA 2 therefore adds a security boundary without
inventing protocol fields: the decoded terminal must be HTTPS `spoc.buaa.edu.cn`, its path must be
exactly `/spocnew/cas`, and its raw representation must match the active route. Direct redirect
resolution rejects gateway URLs; WebVPN decodes, validates, then re-encodes only allow-listed BUAA
targets. The route state checks its generation while holding the credential lock so a login
completing across logout, conflict, or session replacement cannot repopulate an invalidated token.
The credential itself has no token-revealing `Debug` implementation.

The production transport does not follow redirects. A SPOC business response whose raw
`Location` resolves to `sso.buaa.edu.cn` is therefore an authentication failure even when its
`final_url` remains the business URL; the one-refresh helper repeats only that failed operation.
The frozen client also treats the standalone text `权限` as an authentication marker, but that
would replay an evidenced permission denial such as code 403. The active remediation contract
explicitly forbids retrying permission errors, so UBAA 2 recognizes only the evidenced login,
token, `未认证`, and `未登录` markers and returns a permission envelope unchanged as an upstream
error. No field, URL, or retry beyond those boundaries is inferred.

## 2026-08-24: Preserve primary sessions after exhausted SPOC authentication

Frozen `LocalSpocApiBackend.runLocalSpocCall` sends a terminal business-authentication failure to
`resolveLocalBusinessAuthenticationFailure`. That helper validates the User Center session and
clears it only when UC explicitly returns Invalid; Valid, transient, and inconclusive validation
preserve the primary session and become a SPOC business error. UBAA 2 applies this arbitration only
after required current-term, global-page, or detail operations exhaust one credential refresh.
Optional course metadata and submission enrichment retain their surrounding frozen `runCatching`
behavior. Deterministic dual-slot tests prove an invalid Direct result clears Direct only, while a
valid or 5xx UC result retains the selected session and returns retryable `upstream_unavailable`
instead of `authentication_required`.

The no-follow transport exposes a raw SSO `Location` from `/sys/casLogin`; null `content` and a
content object without `jsdm`, `rolecode`, or `jsdmList` also fail to establish a credential. All
three are treated as SPOC authentication failures and enter the same primary-session arbitration.
The frozen JSON decode fallback scans malformed raw bodies and can retry solely because arbitrary
text contains `token`. That conflicts with the active contract that parse/unknown failures are not
authentication evidence, so UBAA 2 returns `parse_error` without a second login for malformed JSON.
Valid parsed envelopes with evidenced authentication markers retain the bounded one-refresh rule.

The frozen page DTO defaults absent `total/pageNum/pageSize/pages` to `0/1/15/1`, while present
values must be integers; assignment `xnxq` and detail `sskcid` are optional strings, and detail
`zymc` is a required string. UBAA 2 now preserves those exact presence rules and rejects wrong
types. Its transport test captures both encrypted page POSTs, decrypts their actual `param` values
only inside the test process, and asserts the complete ordered page-one and page-two plaintext. No
live token, Cookie, raw response, assignment identity, or decrypted request is persisted.

## 2026-08-24: Keep semantic live diagnostics hidden and count-only

Neither frozen source defines a CLI verifier or diagnostic DTO. Ordinary SPOC and Judge results
cannot by themselves prove that an empty SPOC list reached the authoritative global page or show
where Judge link filtering changed a route count. UBAA 2 therefore adds hidden test/live-only CLI
commands backed by facade methods that reuse the ordinary operation, route, cache, parser and error
path. They add no upstream URL, request, redirect, header, parameter or retry.

SPOC diagnostics return the ordinary result plus the number of successfully parsed authoritative
global pages. Judge diagnostics return the parsed course count, pre-filter numeric assignment-anchor
count, post-filter unique count and ordinary summaries. These values are evidence metadata, not a
stable user feature, and remain schema-v2 routed output.

The verifier rejects any route change between requests in one feature run, unsafe stable errors,
incomplete, causally inconsistent or unmasked profile fields, fractional or out-of-range Rust
integer fields, term drift, a SPOC detail that does not preserve both sampled IDs, a SPOC UNKNOWN
value contradicted by the frozen status mapping, impossible Judge diagnostic/status/score
relationships, any incomplete or extra business DTO field, or a duplicate Judge
`(courseId, assignmentId)` key. Interactive verification is not a verifier state: Core rejects
the login page before any credential POST, and the verifier accepts only the resulting safe
`upstream_changed` error. Judge IDs remain parser-produced digit strings rather than numbers;
only the exact course ID `"0"` is excluded. Judge cross-request JSON is supplied to jq through
stdin so titles and IDs do not enter the process argument vector.

The string gate rejects obvious complete HTML documents and CAS execution forms, but deliberately
does not infer that arbitrary angle-bracket text is raw markup: an encoded assignment can normalize
to literal text such as `<html>`. Stable DTO closure forbids every HTML/raw-body field, while Core
parser fixtures prove HTML-to-plain-text conversion. This division avoids both a false live pass
claim about fragment provenance and rejection of valid assignment content.

The verifier requires a fresh caller-provided salt for Judge/all, hashes sorted identifiers only in
memory, and prints only the short digest plus safe counts. The shell contract proves that the same
salt and payload are stable, a different salt changes the digest, and a missing salt exits before
login. Known credential/session/request/response key aliases are rejected independently of their
values, and resolved metadata objects are closed. It never prints or persists identifiers, titles,
bodies, raw HTML, tokens, Cookies, captcha
material, profile fields, decrypted SPOC parameters or the salt. The corrected real matrix was
still pending when this decision was recorded, so the diagnostics do not promote any historical
route result.

An earlier draft of this record described an aggregate human-captcha child, PTY ownership and
synthetic captcha-artifact cleanup. That design was superseded by the 2026-08-25 non-interactive
authentication decision above; it is historical planning text, not an implemented flow or
acceptance proof. The current verifier never opens `/dev/tty`, starts a human child, fetches an
image or persists a challenge. The Core classifier rejects the frozen captcha fields, deny-only
interactive `config.*` markers and any unknown visible verification control before the credential
POST, and the shell regression proves that only safe summaries are emitted.

## 2026-08-26: Preserve the primary session after Judge business-auth exhaustion

The frozen `LocalJudgeApi` catches a terminal Judge business-authentication failure and delegates
to `resolveLocalBusinessAuthenticationFailure`. That helper checks the User Center session and
clears the primary route only when UC explicitly reports Invalid; a valid, unavailable, network,
or inconclusive UC result preserves the session and returns a business failure. The current Rust
Judge retry loop returned `authentication_required` directly, so the facade treated every terminal
Judge failure as route invalidation. This round adds the missing Judge top-level arbitration,
mirroring the already implemented SPOC boundary, and maps preserved-session failures to the stable
retryable `upstream_unavailable` code because no Judge-specific public error code exists.

The arbitration is applied once after a list/diagnostics or batch/detail operation exhausts its
three reactivations; it is not placed inside `get_html`, which would issue a User Center status
request for every internal course or detail request. Tests cover UC valid, explicit Invalid, and
unavailable outcomes, including preservation of the sibling route slot. No URL, request
parameter, Cookie, token, raw response, or live credential is recorded.

UC status JSON that is syntactically malformed after an object prefix is treated as inconclusive:
the parser error is preserved for direct status callers, while Judge maps it to the same retryable
business failure and keeps the primary session. A syntactically valid nonzero `code` or missing
`data`, as well as an explicitly non-JSON or non-2xx invalid response, remains an authentication
invalidation according to the frozen classifier.

If the UC validation itself cannot commit refreshed authentication because of a persistence or
CAS conflict, that `internal_error` is propagated unchanged instead of being relabeled as an
upstream business failure. When the aggregate facade observes that the route was already cleared
by explicit UC invalidation or conflict handling, it also clears the route's pending AuthWorkflow
state without issuing a second persistence mutation.

## 2026-08-26: Keep WebVPN root slash and omit empty separators

The frozen `LocalWebVpnSupport` omits blank query and fragment components while decoding and
encoding, so Rust now filters empty `?` and `#` values as well. Its decoder does not add a root
slash when the wrapped path has only the protocol and encrypted host. Rust retains an explicit
root slash because the URL/runtime path representation and root Judge request/final-URL semantics
use that distinction; Cookie matching itself remains against the gateway URL. The choice is covered
by sanitized round-trip tests and does not change the gateway, AES, protocol, port, or redirect-host
contract.

## 2026-08-26: Record the complete live matrix and Judge snapshot volatility

The corrected live matrix passed authentication on Direct and WebVPN, `feature=all route=auto`,
all six explicit Direct features, all six explicit WebVPN features, and `feature=all route=direct`.
The first complete `feature=all route=webvpn` attempt passed schedule, exam, grades, classroom and
SPOC but failed the unchanged Judge `judge_cutoff` subset check. An immediate rerun passed all six
features with safe Judge counts `5/77/57/17/40`; the standalone WebVPN Judge run in the same
round passed with `5/49/49/17/32`. The differing snapshots are upstream list volatility, not a
reason to weaken the verifier or merge identifiers across requests. The failure and rerun are both
recorded in `docs/migration/status.md`; a later final verification showed the same failure followed
by another passing immediate rerun. Future reruns must keep the strict cutoff check.

## 2026-08-28：场馆预约的 WebVPN 策略必须保留直连业务域

本轮真实验证中，WebVPN 主认证成功，但场馆预约返回
`authentication_required`；同一账号的 Direct 场馆查询成功并返回 4 个站点。
冻结 `LocalWebVpnSupport.localCgyyUpstreamUrl` 明确规定
`cgyy.buaa.edu.cn` 公网可达，任何连接模式下都使用直连 URL；冻结
`LocalCgyyApi.ensureBusinessLogin` 进一步固定使用 Direct Cookie 存储和直连客户端
完成 SSO 跳转，再从场馆域 Cookie 取得 `sso_buaa_zhjs_token`。
`examples/buaa-api` 没有等价协议，不能提供替代路线。

当前 Rust 实现将场馆登录、业务登录和查询统一交给所选路线的
`ClientRuntime`。当路线为 WebVPN 时，`runtime.url` 会包装场馆 URL，且 Cookie
仍属于 WebVPN 路线；这与冻结实现的“主认证路线可为 WebVPN，但场馆业务交换固定
直连”并不等价。禁止通过放宽认证错误、跨域复制 Cookie 或把缺少令牌解释为空结果
来规避该差异。后续修复必须先用脱敏 Mock 固定以下合同：WebVPN 主会话保持隔离；
场馆入口和业务请求使用直连 URL；Direct SSO/场馆 Cookie 仅在场馆业务交换范围内
使用；最终业务令牌仍按调用客户端隔离且不持久化。该调整需要明确的双运行时 facade
接口，不能仅在 `features/cgyy.rs` 中替换 URL。
# 2026-08-28 Cgyy 门锁码实时证据

- 命令：`UBAA_VERIFY_DIGEST_SALT=<临时值> just verify-live mode=direct feature=all`。
- 结果：schedule、exam、grades、classroom、spoc、judge、signin、ygdk、libbook、bykc、evaluation 均通过；`cgyy` 站点查询通过。
- 失败：`cgyy_lock_code` 返回稳定错误 `upstream_unavailable`（退出码 5），因此 `feature=all` 聚合失败。
- 处理：不把上游失败改写为空数据，不调用任何写操作；继续执行 WebVPN 同项验证，并核对门锁码冻结接口/错误语义。

# 2026-08-28 WebVPN 全量只读证据

- 命令：`UBAA_VERIFY_DIGEST_SALT=<临时值> just verify-live mode=webvpn feature=all`。
- 结果：schedule、exam、grades、classroom、spoc、judge、signin、ygdk、libbook、bykc 均通过；Judge 仅记录脱敏计数和盐化摘要。
- 失败：Cgyy 与 Evaluation 在业务阶段均返回 `authentication_required`（退出码 3），聚合以 `one_or_more_features_failed` 结束。
- 处理：保留逐项失败，不用 all 聚合结果掩盖；不调用写操作。下一步核对 WebVPN 下 Cgyy 登录跳转与 Evaluation CAS 激活的路线 Cookie/最终 URL 证据。

# 2026-08-29 全量只读复测

- Direct 全量：Judge 为 `upstream_unavailable`、Cgyy 为 `timeout`，其余已执行只读功能通过；聚合以 `one_or_more_features_failed` 结束。
- WebVPN 全量：Cgyy 与 Evaluation 为 `authentication_required`，其余已执行只读功能通过；聚合以 `one_or_more_features_failed` 结束。
- 以上仅记录脱敏错误类别和功能结果；未记录摘要盐、Cookie、令牌、原始响应，也未调用任何写接口。

# 2026-08-29 Cgyy 单项复测

- Direct：站点查询成功，门锁码返回 `upstream_unavailable`（退出码 5）。
- WebVPN：Cgyy 业务入口返回 `authentication_required`（退出码 3）。
- 结论：失败可复现；不放宽错误分类，不跨路线复制 Cookie/令牌，不执行任何写操作。

# 2026-08-28 Cgyy WebVPN 路线冲突

- 冻结依据：`ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalWebVpnSupport.kt` 的 `localCgyyUpstreamUrl` 明确返回原始直连 URL；注释说明 Cgyy 在校外公开可访问，不通过 WebVPN 包装。
- 当前 Rust：`features/cgyy.rs` 通过所选 `ClientRuntime::url` 包装全部场馆地址；显式 WebVPN 验收的 Cgyy 业务阶段返回 `authentication_required`。
- 决策：不能复制 Direct Cookie/令牌到 WebVPN，也不能只改 URL 而让 WebVPN 传输承载直连 Cookie。需要后续设计“主路线诊断与 Cgyy 直连业务 runtime”边界，并补充隔离 Mock；在此边界明确前不猜测修复。

## 2026-08-28 Cgyy 直连 URL 复测

- Rust 已按冻结 `localCgyyUpstreamUrl` 将 Cgyy 地址改为原始直连 URL，同时保留当前路线的 Cookie 容器和传输对象。
- WebVPN 单项复测仍为 `authentication_required`；因此问题不只是 URL 包装，不能据此宣称 WebVPN 通过。
- Direct 单项站点查询继续通过，门锁码仍返回 `upstream_unavailable`。后续必须设计独立直连业务 runtime，并用 Mock 证明 Cookie 不跨主认证路线复制。

# 2026-08-28 只读矩阵复测

- Direct：schedule、exam、grades、classroom、spoc、judge、signin、ygdk、libbook、bykc、cgyy 站点及 evaluation 均通过；`cgyy_lock_code` 仍为 `upstream_unavailable`（退出码 5）。
- WebVPN：schedule、exam、classroom、spoc、signin、ygdk、libbook、bykc 通过；grades 返回 `upstream_changed`（退出码 6），judge 返回 `invalid_semantics`（截止阶段退出码 1），cgyy 与 evaluation 返回 `authentication_required`（退出码 3）。
- 处理：保留逐操作失败证据，聚合命令以 `one_or_more_features_failed` 结束；本轮只读验证未调用任何写操作，以上摘要不含原始响应或个人数据。

## 2026-08-28 WebVPN 逐项复测

- `feature=grades`、`feature=judge`、`feature=evaluation` 单项重跑均成功；Judge 脱敏计数为课程 5、原始锚点 49、过滤后 49、当前 17、截止跳过 32，并取得语义详情。
- `feature=cgyy` 单项重跑仍为 `authentication_required`（退出码 3）。该失败与此前结果一致，不能由其他场馆或主认证成功替代。
- 本次复测全部为只读操作，未调用任何提交、取消、预约、签到、上传或选课接口。

## 2026-08-29 逐操作验证器扩展与三路线复测

- 提交 `c35c9ca` 将 `verify-live` 的扩展领域从代表性查询扩展为逐操作链：Ygdk
  概览/记录，LibBook 楼馆/区域/详情/座位/预约记录，Bykc 资料/课程/详情/已选/统计，
  Cgyy 站点/用途/日期/订单/详情/锁码，以及 Evaluation 全部/待评教。详情请求只有在
  上游返回脱敏标识时才继续，空集合不会伪造详情成功；脚本 stub 覆盖调用顺序且不输出
  原始响应。
- 提交 `406177b` 将 User 的 `user show` 纳入独立验证和 `all` 聚合，并校验完整脱敏
  profile 字段集合、类型与掩码规则。
- Direct 三路线复测命令为
  `UBAA_VERIFY_DIGEST_SALT=<临时值> just verify-live mode=direct feature=all`：课表、
  考试、成绩、教室、SPOC、User、Signin、Ygdk、LibBook、Cgyy 站点/用途/日期/订单、
  Evaluation 成功；Judge 返回 `upstream_unavailable`，Bykc 已选返回 `upstream_changed`，
  Cgyy 锁码响应未通过当前安全结构校验，聚合退出 5。
- WebVPN 同命令：课表、考试、成绩、教室、SPOC、Judge、User、Signin、Ygdk、LibBook
  成功；Bykc 已选返回 `upstream_changed`，Cgyy 与 Evaluation 返回
  `authentication_required`，聚合退出 6。
- auto 同命令解析到 Direct：课表、考试、成绩、教室、SPOC、User、Signin、Ygdk、
  LibBook、Evaluation 成功；Judge 返回 `upstream_unavailable`，Bykc 已选返回
  `upstream_changed`，Cgyy 在用途查询阶段返回 `upstream_unavailable`，聚合退出 5。
- 以上运行只执行读操作；未记录凭据、Cookie、令牌、摘要盐、原始响应或个人数据，
  未调用任何选课、退选、签到、预约、取消、提交或上传接口。整体迁移继续保持未完成。

## 2026-08-29 User 独立只读验收

- `feature=user route=direct`、`feature=user route=webvpn` 和
  `feature=user route=auto` 均退出 0；auto 实际解析到 Direct。
- 三次运行均通过完整脱敏 profile 结构校验；没有记录姓名、联系方式、身份信息、Cookie、
  令牌或原始响应，也没有调用任何写操作。

## 2026-08-29 Bykc 已选课程包装修复

- 冻结 `ubaa_old/shared/.../LocalBykcApi.kt` 的 `queryChosenCourse` DTO 是
  `data.courseList`，Rust 原实现把解密后的业务数据直接当数组解析，导致 Direct、WebVPN
  和 auto 均在 `bykc_chosen` 返回 `upstream_changed`。
- 按 TDD 先加入 `courseList` 对象包装 fixture，旧实现失败；随后让解析器从对象读取
  `courseList`，并保留已有数组兼容路径。聚焦测试通过后，三路线单项命令均退出 0，
  返回脱敏课程计数摘要；未记录课程标识、令牌、密文或原始响应。

## 2026-08-29 Bykc 修复后全量实时矩阵

- Direct 全量：User、课表、考试、成绩、教室、SPOC、Signin、Ygdk、LibBook、Bykc、Cgyy 站点和 Evaluation 通过；Judge 在 `judge_all` 返回 `upstream_unavailable`，Cgyy 在 `cgyy_day` 返回 `upstream_unavailable`，聚合退出 5。
- WebVPN 全量：User、课表、考试、成绩、教室、SPOC、Judge、Signin、Ygdk、LibBook、Bykc 通过；Cgyy 与 Evaluation 在业务阶段返回 `authentication_required`，聚合退出 3。
- auto 全量解析到 Direct：User、课表、考试、成绩、教室、SPOC、Signin、Ygdk、LibBook、Bykc、Cgyy 站点和 Evaluation 通过；Judge 在 `judge_all`、Cgyy 在 `cgyy_purposes` 返回 `upstream_unavailable`，聚合退出 5。
- 本轮使用临时摘要盐，仅保留退出码、阶段和脱敏计数；没有输出或持久化凭据、Cookie、令牌、原始响应、课程/个人标识，也没有调用真实写操作。失败项继续作为硬门禁，不以 `all` 聚合掩盖。

## 2026-08-29 Direct Judge/Cgyy 单项复测

- `feature=cgyy` 站点查询成功（4 个站点），日期阶段仍为 `upstream_unavailable`，退出 5。
- `feature=judge` 在列表阶段仍为 `upstream_unavailable`，退出 5。
- 两次复测均未改变请求、解析或错误策略；没有跨路线复制 Cookie/令牌，也没有调用真实写操作。该结果确认失败位于实时上游可用性边界，不能由其他功能成功替代。

## 2026-08-29 WebVPN Cgyy 直连业务 transport 复测

- 按冻结 `LocalCgyyApi.ensureBusinessLogin` 的 Direct 客户端语义，聚合 facade 在 WebVPN
  路线解析和会话预检后改用 Direct 业务 transport；Cookie 仍由 Direct 路线槽位独立提供，
  未从 WebVPN 槽位复制材料。
- `feature=cgyy route=webvpn` 的站点查询通过（4 个站点），用途查询阶段返回
  `upstream_unavailable`（退出 5），不再返回此前的 `authentication_required`。
- 该结果证明 transport 分派方向正确，但尚不足以宣告 WebVPN Cgyy 全部读操作通过；
  日期、订单、锁码等后续操作仍需逐项实时证据。

## 2026-08-29 Judge 路线复测更新

- auto（实际解析到 Direct）的 Judge 单项复测通过，返回课程 5、当前任务 65，并完成
  详情语义校验；摘要仅保留脱敏计数和临时盐摘要。
- Direct Judge 同轮仍在 `judge_all` 返回 `upstream_unavailable`。这与历史列表快照
  波动一致，不能用 auto 成功替代 Direct 路线证据；继续保留逐路线硬门禁。
- WebVPN 全量同轮除 Cgyy 用途查询 `upstream_unavailable` 外，其余已执行只读操作通过，
  包括 Judge 和 Evaluation。所有运行均未调用真实写接口。

## 2026-08-29 Direct Judge/Cgyy 复测收敛

- Direct Judge 随后单项复测通过：课程 5、当前任务 65，详情语义校验通过；结合本轮
  WebVPN 与 auto 成功结果，Judge 三路线证据已齐备。
- Direct Cgyy 站点查询通过（4 个站点），日期阶段仍返回 `upstream_unavailable`，退出 5。
  该失败不被站点成功掩盖，也未改变冻结请求和错误分类。

## 2026-08-29 Cgyy 验证器逐操作不中断

- 旧验证器在 Cgyy 用途或日期失败时提前返回，无法证明订单、详情和锁码是否被独立
  尝试。现按操作分别记录脱敏失败，继续执行不依赖失败响应的后续查询；订单详情仅在
  订单列表提供标识时调用，日期详情仅在站点列表提供标识时调用。
- `scripts/test-verify-live.sh` 已补齐站点、日期、订单、订单详情和锁码的合成响应与调用
  顺序断言；真实验证仍不执行写操作，聚合返回首个失败退出码。

## 2026-08-29 Cgyy 三路线逐操作复测

- WebVPN：站点与用途通过，日期和锁码为 `upstream_unavailable`；订单查询通过但没有
  可用详情标识，因此未伪造详情请求。
- auto（解析到 Direct）：站点通过；用途、日期、订单和锁码均为
  `upstream_unavailable`。
- Direct：站点请求本轮为 `upstream_unavailable`，用途和锁码同样失败；验证器不再从
  失败信封提取站点标识或打印成功摘要。上述运行均未执行真实写操作。

## 2026-08-29 Cgyy 日期窗口排除复测

- Direct Cgyy 使用验证器允许的只读日期覆盖 `2026-09-01` 重跑：站点仍通过（4 个），
  用途、日期、订单返回 `upstream_unavailable`，锁码为 `invalid_semantics`。
- 改变日期未改变失败类别，因此当前证据不足以把问题归因于当天没有可预约数据；不据此
  修改日期格式、响应字段或错误映射，也未执行任何真实写操作。

## 2026-08-29 锁码 CLI 脱敏边界

- 冻结旧版允许 `getLockCode()` 返回可空不透明 `data`，但 CLI 安全合同禁止输出原始
  锁码或 `rawData` 字段。提交 `8ef875a` 保留 Core facade 的原始 `Value`，将单路线与
  聚合 CLI 投影为仅含 `{available: boolean}`，并同步 schema、验证器与脱敏单测。
- Direct Cgyy 随后复测中锁码阶段返回 `upstream_unavailable`；验证器不再因旧的
  `rawData` 结构要求产生误报。真实写操作仍未调用。

## 2026-08-29 Cgyy 最新三路线波动

- Direct 单项：站点、用途、订单、锁码均为 `upstream_unavailable`。
- WebVPN 单项：站点查询通过，随后用途、日期、订单、锁码均为
  `upstream_unavailable`。
- auto 单项：站点、用途、订单均为 `upstream_unavailable`，在没有订单标识时按规则
  跳过详情。
- 本轮没有出现新的可验证 URL/字段冲突；不据此增加网络重试、改写参数或放宽错误分类，
  继续保留失败证据并禁止真实写操作。

## 2026-08-29 锁码投影后三路线复测

- WebVPN：站点成功，用途、日期、订单、锁码均为 `upstream_unavailable`。
- auto：站点、用途、订单、锁码均为 `upstream_unavailable`；站点失败后未构造依赖详情。
- 两路线均未出现旧 `rawData` 结构误报，说明 CLI 安全投影与验证器合同已生效；Cgyy
  实时硬门禁仍未满足，未执行任何写操作。

## 2026-08-29 三路线全量复测更新

- Direct 全量：除 Cgyy 外所有 User、课表、考试、成绩、教室、SPOC、Judge、Signin、
  Ygdk、LibBook、Bykc、Evaluation 通过；Cgyy 用途/订单为 `upstream_unavailable`、
  日期为 `upstream_changed`、锁码为 `invalid_semantics`。
- WebVPN 全量：除 Cgyy 日期和锁码 `upstream_unavailable` 外，其余只读操作通过，Cgyy
  站点、用途、订单已通过。
- auto 全量（解析到 Direct）：除 Cgyy 日期和锁码 `upstream_unavailable` 外，其余只读
  操作通过。Judge 三路线均完成课程/任务/详情语义校验；所有命令仍未调用真实写接口。

## 2026-08-29 当前轮三路线全量验收

- Direct 全量逐操作运行成功完成 User、课表、考试、成绩、教室、SPOC、Judge、Signin、Ygdk、LibBook、Bykc、Evaluation；Judge 课程/任务/详情语义校验通过。Cgyy 站点查询通过（4 个站点），用途和订单返回 `upstream_unavailable`，日期返回 `upstream_changed`，聚合退出码 5。
- WebVPN 全量逐操作运行成功完成除 Cgyy 外的全部只读操作，Judge 详情语义校验通过。Cgyy 站点查询通过（4 个站点），用途和订单返回 `upstream_unavailable`，日期返回 `upstream_changed`，聚合退出码 5。
- auto 全量解析为 Direct，除 Cgyy 外的全部只读操作通过；Cgyy 站点通过，用途和订单为 `upstream_unavailable`，日期为 `upstream_changed`，锁码为 `upstream_unavailable`，聚合退出码 5。
- 三次运行均使用未持久化的进程内摘要盐，仅记录路由、阶段、计数和错误类别；没有输出凭据、Cookie、令牌、原始响应或个人标识，也没有调用真实写接口。Cgyy 仍未满足实时硬门禁，不修改协议实现或错误策略。

## 2026-08-29 Cgyy 用途类型回退修复

- 冻结 `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalCgyyApi.kt` 的 `getPurposeTypes` 在已有主会话后对动态请求和解析使用 `runCatching`，失败即采用静态十项列表。Rust 原实现传播 `/api/codes` 的上游错误，与冻结行为不符。
- 新增 `crates/ubaa-core/tests/cgyy.rs` Mock：`/api/codes` 返回合成 502 时，单路线 facade 仍返回十项静态用途；测试先观察到 `UpstreamUnavailable` 失败，再实现回退并通过。`RouteClient` 同步补齐用途类型入口。
- Direct、WebVPN、auto 复测中用途阶段均成功，失败边界后移到日期/订单（及依赖详情）的实时上游错误；未改变 URL、签名、重试或错误映射，也未调用真实写接口。

## 2026-08-29 Cgyy 回退后 Direct 全量复测

- Direct `feature=all` 在用途回退修复后继续完成所有独立操作：非 Cgyy 功能及 Judge 详情语义通过，Cgyy 站点成功（4 个），日期返回 `upstream_changed`，锁码返回 `upstream_unavailable`，聚合退出 6。
- 该结果确认用途回退减少了一个实时失败点，但日期和锁码仍缺乏新的协议证据；不猜测参数或增加重试，未执行真实写操作。

## 2026-08-29 Cgyy 回退后 WebVPN/auto 全量复测

- WebVPN 全量中用途阶段通过静态回退，站点成功（4 个），非 Cgyy 操作与 Judge 详情语义通过；日期和依赖详情返回 `upstream_unavailable`，聚合退出 5。
- auto 全量解析到 Direct，用途阶段通过静态回退，站点成功（4 个），非 Cgyy 操作与 Judge 详情语义通过；日期和订单返回 `upstream_unavailable`，聚合退出 5。
- 两次运行只进行了只读请求，未改变日期/订单协议、未增加重试或放宽错误分类，也未执行真实写操作。

## 2026-08-29 用途回退后 WebVPN/auto 全量复测

- WebVPN 全量中用途静态回退成功，站点成功（4 个），非 Cgyy 操作与 Judge 详情语义通过；日期和依赖详情返回 `upstream_unavailable`，聚合退出 5。
- auto 全量解析到 Direct，用途静态回退成功，站点成功（4 个），非 Cgyy 操作与 Judge 详情语义通过；日期和订单返回 `upstream_unavailable`，聚合退出 5。
- 本轮无新的 URL、字段或重定向证据；不猜测协议、不增加重试，未执行真实写操作。

## 2026-08-29 Cgyy 成功信封代码严格校验

- 冻结 `LocalCgyyApi.requestJson` 在 JSON 解析后明确要求 `code == 200`；缺失代码或其他数值均抛出业务错误。
- Rust `features/cgyy.rs::data` 原先允许缺失代码及 `code=0`，新增脱敏解析测试先复现错误再收紧为仅接受 `Some(200)`；非 JSON、数组或标量结构仍按原错误分类处理。
- 未改变 URL、请求、重定向、签名、缓存或实时错误边界；未执行真实写操作。

## 2026-08-29 Cgyy 日期槽位排序

- 冻结 `LocalCgyyApi.mapDayInfo` 会过滤无效槽位并按 `timeId` 升序整理每个空间的槽位；Rust 原实现保留上游顺序。
- 新增逆序 `spaceTimeInfo` 脱敏测试先失败后通过，当前输出与冻结排序一致；未改变请求协议或实时错误策略。

## 2026-08-29 Cgyy 三路线逐操作复测

- 使用未持久化进程内摘要盐执行 `feature=cgyy` 的 Direct、WebVPN、auto 只读验证；三次站点查询均成功并返回 4 个站点。
- Direct 日期和锁码为 `upstream_unavailable`；WebVPN 日期为 `upstream_changed`、订单和锁码为 `upstream_unavailable`；auto 解析为 Direct，日期为 `upstream_changed`、订单为 `upstream_unavailable`。
- 脚本逐项继续执行并返回首个失败码；本轮未改变 URL、参数、解析或错误策略，未执行任何真实写操作。Cgyy 实时硬门禁仍未满足。

## 2026-08-29 三路线全量只读复测

- Direct：User、Schedule、Exam、Grades、Classroom、SPOC、Judge（课程/任务/详情）、Signin、Ygdk、LibBook、Bykc、Evaluation 均成功；Cgyy 站点成功（4 个），日期和订单为 `upstream_unavailable`，聚合退出 5。
- WebVPN：上述非 Cgyy 能力均成功，Judge 详情语义通过；Cgyy 站点成功（4 个），日期和订单为 `upstream_unavailable`，聚合退出 5。
- auto：解析为 Direct，上述非 Cgyy 能力均成功；Cgyy 站点成功（4 个），日期为 `upstream_changed`、订单为 `upstream_unavailable`，聚合退出 6。
- 结果与冻结实现的请求和解析行为一致但实时上游不可用的项仅作记录，不修改协议或错误策略；仅执行读操作，未执行真实写接口。

## 2026-08-29 Cgyy 场馆包装展开

- 冻结 `LocalCgyyClient.getVenueSites` 调用 `asVenueSiteArray`，将场馆对象的 `siteList` 展开并继承场馆名称与校区；当前解析器原先把场馆对象误当作站点。
- 新增旧版包装的脱敏测试，先复现站点 ID 被误读为场馆 ID，再实现展开并通过；同时保留扁平数组和 `content` 包装。
- 未改变请求、签名、路由、会话或实时错误策略，未执行真实写操作。

## 2026-08-29 LibBook 座位排序

- 冻结 `LocalLibBookApi.getSeats` 在 DTO 映射后执行 `sortedBy { it.no }`；Rust `parse_seats` 原先保留响应顺序。
- 新增逆序座位号脱敏测试先失败后通过，并在 Core 中按字符串座位号升序排序；未改变请求协议或实时路由行为。

## 2026-08-29 LibBook 预约总数回退

- 冻结 `LocalLibBookApi.getBookings` 在响应缺少 `total` 时使用当前预约列表条数；Rust 原解析固定回退为 0。
- 新增缺少 `total` 的脱敏分页测试先失败后通过，Core 现按冻结语义回退；未改变请求协议或实时路由行为。

## 2026-08-29 LibBook 分区编号回退

- 冻结 `LocalLibBookApi.mapAreaDetail(areaId, raw)` 在上游区域对象缺少 ID 时回退请求参数 `areaId`；原 Core 解析器没有请求上下文并返回空 ID。
- 新增缺少区域 ID 的脱敏测试先失败后通过，增加带请求 ID 的解析入口并由查询调用；未改变请求协议或实时路由行为。

## 2026-08-29 Bykc 签到配置严格解析

- 冻结证据：`ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalBykcApi.kt` 的 `parseSignConfig` 通过序列化器解析 `LocalBykcSignConfig`；签到点 `lat/lng` 为必填，单点解码异常会使 `runCatching` 返回空配置。
- 原 Core 使用 `filter_map` 丢弃坏点并保留配置，与冻结错误语义不一致。新增无效坐标脱敏测试先失败，再改为列表与点字段整体严格校验。
- `examples/buaa-api` 无等价 Bykc 签到配置协议，不参与字段或错误推断；未执行真实写操作。

## 2026-08-29 Ygdk 记录时间戳

- 冻结证据：`ubaa_old/.../LocalYgdkApi.kt` 的记录字段 `startTime/endTime` 为 `Long?`，映射时调用 `timestampToDateTimeText`，使用固定 `LOCAL_YGDK_TIME_ZONE`（东八区）输出分钟精度文本。
- 原 Core 仅读取字符串，数值时间会变为空。新增数值时间脱敏测试先失败，再增加固定东八区转换；未从 `examples/buaa-api` 借用协议。

## 2026-08-29 Ygdk 记录图片字段

- 冻结证据：`LocalYgdkApi.kt` 的 `extractRecordImages` 对 `images_fmt` 的 `JsonPrimitive` 非空内容直接返回单元素列表；只有数组字符串才尝试 JSON 数组解析。
- 原 Core 将所有字符串当作数组 JSON，合法单地址会变为空列表。新增单字符串脱敏测试先失败，再保留非空字符串作为单地址；未执行真实写操作。

## 2026-08-29 Ygdk 数字字符串时间戳

- 冻结证据：`LocalYgdkApi.kt` 的 `JsonObject.long` 对 JSON primitive 的文本执行 `toLongOrNull`，数字字符串会进入时间戳格式化。
- 原 Core 遇到任意字符串即原样返回。新增数字字符串时间戳测试先失败，再仅对可解析整数执行东八区转换；未改变非数字文本路径。

## 2026-08-29 LibBook 原语字段兼容

- 冻结证据：`LocalLibBookApi.kt` 的 `JsonObject.string` 读取 `jsonPrimitive.contentOrNull`，其语义覆盖字符串、数字和布尔原语。
- 原 Core `text` 仅接受 JSON 字符串，数字座位标识/状态会清空。新增数字字段脱敏测试先失败，再扩展原语文本化；未执行真实写操作。

## 2026-08-29 三路线全量只读复测

- Direct 全量首个失败为 Cgyy 业务阶段 `upstream_unavailable`（退出 5）；其余功能及 Judge 详情语义通过。
- WebVPN 记录 Grades `parse_error`、Judge `invalid_semantics`，以及 Cgyy 日期/订单/锁码 `upstream_unavailable`（退出 6）；站点和其他可用功能仍按逐操作结果记录。
- auto 解析为 Direct，Grades 为 `upstream_changed`，Cgyy 后续业务阶段为 `upstream_unavailable`（退出 6）；Judge 详情通过。
- 本轮没有新的 URL、参数、重定向或字段证据；按用户约定，对与冻结旧版一致但实时上游不可用的项只记录并继续推进，未执行真实写操作。

## 2026-08-29 Cgyy 原语字段兼容

- 冻结证据：`LocalCgyyApi.kt` 的 `JsonObject.string` 返回 `jsonPrimitive.contentOrNull`，不限定 JSON 字符串类型。
- 原 Core `string` 仅接受 `as_str`，数字场馆名称等合法原语会清空。新增脱敏站点测试先失败，再统一支持字符串、数字和布尔原语；未执行真实写操作。

## 2026-08-29 Signin 写响应状态兼容

- 冻结证据：`LocalSigninApi.kt` 的 `jsonStringValue` 读取 primitive 文本，`int` 随后执行 `toIntOrNull`；签到写响应的 `STATUS`/`stuSignStatus` 因此接受数字或数字字符串。
- 原 Core 写响应仅使用 `Value::as_i64`，数字字符串会回退为零/未完成。新增脱敏状态测试先失败，再增加整数兼容辅助；未执行真实写操作。

## 2026-08-29 Evaluation 任务 `yhdm` 身份来源

- 证据：冻结 `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalEvaluationService.kt` 的 `fetchTasks` 明确发送 `authSession.user.schoolid.ifBlank { authSession.username }`。
- 原差异：Rust `features/evaluation.rs::get_all` 曾固定发送空 `yhdm`，无法保持同一请求构造。
- 决策：登录成功后仅在运行时内存记录 `UserProfile.school_id`，缺失时记录 `username`；评教任务请求使用该值，既有无资料会话保持空值。未从 Cookie、实时响应或示例项目猜测身份字段，也未执行真实写操作。

## 2026-08-29 Ygdk 文本原语

- 证据：冻结 `LocalYgdkApi.kt` 的 `JsonObject.string` 读取 `jsonPrimitive.contentOrNull`，因此数字和布尔原语也会得到文本内容。
- 原差异：Rust Ygdk `string` 只调用 `Value::as_str`，合法原语字段会被当作缺失。
- 决策：统一将字符串、数字、布尔映射为文本并保留空文本过滤；未借用非等价示例协议，未执行真实写操作。

## 2026-08-29 Evaluation 文本原语

- 证据：冻结评教 DTO 映射使用 `JsonPrimitive.contentOrNull`，其文本读取不限定 JSON 字符串类型。
- 原差异：Rust Evaluation `string` 只接受字符串和整数，布尔/浮点字段会被当作缺失；新增布尔字段测试先失败。
- 决策：扩展为字符串、整数、浮点、布尔的文本化并保留空值语义；未从示例项目类比协议，未执行真实写操作。

## 2026-08-29 三路线逐操作实时证据

- Direct 全量：非 Cgyy 功能全部通过；Cgyy 站点通过，日期 `upstream_unavailable`。
- WebVPN 全量：非 Cgyy 功能全部通过；Cgyy 日期 `invalid_semantics`、锁码 `upstream_unavailable`。
- auto 全量：解析到 Direct；非 Cgyy 功能全部通过；Cgyy 日期/详情 `upstream_unavailable`。
- 这些实时失败没有提供足以证明新 URL、参数或字段的证据；与冻结实现一致的项不改协议，仅保留稳定错误分类并继续其它迁移。所有命令均未调用真实业务写操作，输出未包含凭据、Cookie、令牌、原始响应或完整个人数据。

## 2026-08-29 认证资料持久化冲突

- 冻结证据：`ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalConnectionAuth.kt` 的 `LocalAuthSession` 包含 `username` 和 `user.schoolid`，并由 `LocalAuthSessionStore` 持久化。
- 当前约束：`docs/contracts/connection-and-session.md` 与合同安全边界要求 `session.json` 不保存 username、密码或用户资料。
- 决策：不为追求表面 parity 写入个人身份资料；登录成功后仅在 Core 运行时内存使用 `school_id/username`，跨进程加载会话时身份参数缺失按安全契约处理。该边界可能使部分旧版依赖身份查询的上游在重启后不可用，若未来要改变必须另立安全与存储决策，不能从实时失败猜测协议。
## 2026-08-29 三路线逐操作实时复测（认证领域拆分后）

- Direct：User、Schedule、Exam、Grades、Classroom、SPOC、Judge（课程/任务/详情）、Signin、Ygdk、LibBook、Bykc、Evaluation 均成功；Cgyy 站点成功（7 个），日期与锁码均返回 `upstream_unavailable`，聚合退出码 5。
- WebVPN：上述非 Cgyy 功能均成功；Cgyy 站点成功（7 个），日期返回 `invalid_semantics`、锁码返回 `upstream_unavailable`，聚合退出码 1。
- auto：解析为 Direct；上述非 Cgyy 功能均成功；Cgyy 站点成功（7 个），日期返回 `invalid_semantics`、订单返回 `upstream_unavailable`，聚合退出码 1。
- 本轮只执行认证和读操作，未调用任何选课、退选、签到、预约、取消、提交或上传接口。失败项没有提供新的 URL、参数、重定向、字段或加密证据；其本地逻辑与冻结实现一致但实时上游不可用/返回不满足语义，按约定只记录并继续，不猜测修改协议。
## 2026-08-29 认证领域拆分后实时只读矩阵

- Direct：User、Schedule、Exam、Grades、Classroom、SPOC、Judge、Signin、Ygdk、LibBook、Bykc、Evaluation 逐项成功；Cgyy 站点返回 7 个站点，日期和锁码均为 `upstream_unavailable`，聚合退出 5。
- WebVPN：非 Cgyy 功能逐项成功；Cgyy 站点返回 7 个站点，日期为 `invalid_semantics`、锁码为 `upstream_unavailable`，聚合退出 1。
- auto：路由解析为 Direct；非 Cgyy 功能逐项成功；Cgyy 站点返回 7 个站点，日期为 `invalid_semantics`、订单为 `upstream_unavailable`，聚合退出 1。
- 本轮只读验证未调用任何选课、退选、签到、预约、取消、提交或上传接口。失败项未提供新协议证据，按冻结逻辑与实时上游状态分别记录，不猜测修改 URL、参数、字段或错误语义。

## 2026-08-29 Direct 全量验证的聚合登录边界

- `feature=auth route=direct` 单独验证成功，输出为 `auth_status` 成功。
- `feature=all route=direct` 在业务操作前的聚合登录语义校验失败，返回 `login`/`invalid_semantics`；未执行任何业务读请求。
- 该差异来自 `all` 验证路径要求双路线聚合登录，不足以证明 Direct 单路线认证或任一业务协议缺失；保持冻结认证逻辑和验证器边界，不猜测修改实现。所有真实业务写操作仍未调用。

## 2026-08-29 WebVPN/auto 全量实时复测

- WebVPN 全量逐操作：User、Schedule、Exam、Grades、Classroom、SPOC、Judge、Signin、Ygdk、LibBook、Bykc 与 Cgyy 站点成功；Cgyy 日期阶段返回 `invalid_semantics`，依赖订单/锁码未调用。
- auto 全量解析到 Direct：User、Schedule、Exam、Grades、Classroom、SPOC、Judge、Signin 成功；Ygdk 阶段返回 `timeout`，后续功能未调用。
- 失败项没有提供新的 URL、参数、字段或加密证据；按冻结实现保留现状并记录实时上游不稳定性。全程未调用真实业务写接口。
