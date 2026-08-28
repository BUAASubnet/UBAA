# Decision Log

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
