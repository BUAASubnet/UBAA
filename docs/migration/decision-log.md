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

## 2026-08-17: Preserve JSON captcha non-interactivity

JSON login still returns `captcha_required` with exit 4 before credential submission and without image data. The local live verifier handles that result by starting a fresh human CLI in the same controlling terminal, feeding only the environment password through a private FIFO, polling `/dev/tty` only while that CLI is alive, suppressing human profile stdout, and resuming redacted JSON checks. It disables terminal echo for the complete captcha interaction, restores the original terminal state on every exit path, closes and removes the FIFO, and terminates/waits the child on HUP/INT/TERM with a bounded KILL fallback. This also handles the evidenced case where the fresh preparation no longer requires captcha. No cross-process challenge persistence was invented.

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

## 2026-08-23: Bind aggregate captcha answers before credential submission

The frozen implementation keeps each captcha ID with one mode-scoped login state; the pinned example does not implement captcha. UBAA 2 therefore keeps raw upstream captcha IDs and CAS execution values inside each route's `AuthWorkflow`, while the aggregate facade exposes process-local opaque IDs bound to one route and preparation generation. Identical upstream IDs on Direct and WebVPN produce distinct public IDs.

Every supplied answer is checked as a complete set before either route sends a credential POST. Empty values, duplicate public IDs, multiple answers for one route, unknown IDs, previous-generation IDs, and bindings whose raw ID or execution no longer matches the current route state return `invalid_input`. Valid answers are consumed once. A missing answer preserves that route's pending challenge, and a sibling preparation failure does not invalidate a challenge already returned in the same generation. A failed route preparation is retained as that generation's result rather than retried invisibly during submission. When callers invoke aggregate login without a separate prepare call, any newly discovered captcha is returned in `LoginOutcome`.

Preparing a new generation clears the old workflow before network access, and authentication invalidation, supplied-answer failure, successful login, logout, or terminal session conflict clears the applicable mapping. A successful prepare that finds an existing SSO session retains a one-use, in-memory authenticated-ready marker; aggregate login consumes it by reading User Center profile data and cannot enter SSO preparation again behind the already-built public challenge list. A cached no-captcha preparation is reusable only while the corresponding `AuthWorkflow` is still prepared; if post-submit User Center validation clears that workflow, the next aggregate login re-prepares the route and exposes any newly discovered opaque challenge before another credential POST. Public serialization contains only `route`, opaque `challengeId`, and `imageAvailable`; raw IDs, execution values, answers and image data remain in-process and are never serialized or persisted. Deterministic transports cover empty fields, unknown, duplicate, same-route, stale, consumed, post-logout and post-conflict IDs and prove that rejection never adds a credential POST.

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
