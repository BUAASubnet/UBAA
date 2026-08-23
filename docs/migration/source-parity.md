# Source Parity Matrix

Updated: 2026-08-24

This is an operation-by-operation behavior audit. `old` means frozen
`ubaa_old/` commit `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`;
`example` means pinned `examples/buaa-api/` commit
`efb7976bf513f38364b88aeb83d704586cff9b2a`. Every cell records both sources
and the UBAA 2 decision. A source marked non-equivalent supplies no URL, field,
crypto or error by analogy. Live evidence may supersede a frozen protocol fact
only when its sanitized observation is recorded in the decision log.

The nine columns below are mandatory for every authentication or read-only
operation before production code changes.

## Gateway probe

| bootstrap/service URL | redirect/final URL | cookie/session scope | method and exact parameters | headers/body encoding | crypto constants | DTO/parser fields | caching/concurrency | error/exit semantics |
|---|---|---|---|---|---|---|---|---|
| **old:** N/A; no campus probe exists. **example:** `utils/net.rs` targets `gw.buaa.edu.cn:80`. **decision:** use exactly that host and port, not an IP range. | **old/example:** N/A; this is not HTTP. **decision:** no redirects or final URL. | **old/example:** no Cookie or credential. **decision:** process-local probe state only. | **example:** `ToSocketAddrs`, then `TcpStream::connect_timeout` until one succeeds. **decision:** one 500ms total deadline includes resolution and all address attempts. | **old/example:** no headers or body. **decision:** send TCP connect only, no HTTP/TLS payload. | **old/example:** N/A. **decision:** no encryption/signature. | **example:** Boolean campus result. **decision:** `Campus` on any success; ordinary resolution/no-address/connect/timeout is `OffCampus`; only internal/injected probe failure is `Unknown`. | **example:** no cache and 500ms per address. **decision:** the product contract narrows this to one total budget and adds a process-local 60s cache with injectable clock/probe. | **example:** all ordinary failures return false. **decision:** `OffCampus -> WebVPN`; `Unknown -> operation unknown_default`; probe does not itself emit a CLI failure. |

Deterministic implementation evidence on 2026-08-24: `route_policy` covers the fixed 500ms
budget, all three states, explicit-policy zero probing, cache expiry and concurrent miss
single-flight behavior; `facade` covers facade-owned caching, default-versus-feature policy,
successful diagnostics and zero-request missing-session errors. The CLI binary boundary test
forbids config/probe/resolver ownership in `main.rs`. These tests do not establish live campus
reachability or any business endpoint result.

## Dual load/save/logout

| bootstrap/service URL | redirect/final URL | cookie/session scope | method and exact parameters | headers/body encoding | crypto constants | DTO/parser fields | caching/concurrency | error/exit semantics |
|---|---|---|---|---|---|---|---|---|
| **old:** remote logout is `https://sso.buaa.edu.cn/logout`; persistence has no URL. **example:** no equivalent dual logout. **decision:** each route uses its transformed SSO logout URL; storage operations are local only. | **old:** remote-first logout then local clear; no final-URL assertion. **example:** N/A. **decision:** remote calls are best effort and cannot authorize persisted deletion. | **old:** `ModeScopedSessionStore` isolates auth/Cookies by mode, but switching/reset clears all scopes. **example:** one shared `cookies.json` plus `cred.json`, not dual. **decision:** one dual snapshot with independent route slots and route-owned feature state. | **old:** settings get/put/remove; no CAS. **example:** separate truncate-and-write files. **decision:** load snapshot+revision under one lock; route save and aggregate clear each perform one full-snapshot CAS. | **old/example:** JSON persistence; no HTTP body for local operations. **decision:** schema-v2 `session.json`; legacy single-route reader only; unique atomic temp writes and owner-only permissions. | **old/example:** N/A. **decision:** no crypto is invented for local persistence. | **old:** username/user/timestamps plus Cookie records. **example:** Cookies and credential/token expiry. **decision:** persist only route, filtered Cookies and timestamps; never username/password/execution/challenge/business token. | **old:** per-store mutexes but no cross-file transaction; reset clears caches. **example:** atomic cells in-process, no file lock/CAS. **decision:** one coordinator owns dual snapshot+revision; never reload/adopt an external revision after conflict; clear all route feature state on local invalidation/logout. | **old:** remote error still clears local state. **example:** ordinary I/O/parse errors. **decision:** stale CAS is retryable `internal_error`, clears this process only and preserves both newer slots; aggregate logout advances revision once on success. |

## Prepare/login captcha

| bootstrap/service URL | redirect/final URL | cookie/session scope | method and exact parameters | headers/body encoding | crypto constants | DTO/parser fields | caching/concurrency | error/exit semantics |
|---|---|---|---|---|---|---|---|---|
| **old:** GET/POST `https://sso.buaa.edu.cn/login`, GET `/captcha?captchaId=...`, then UC activation `https://uc.buaa.edu.cn/api/login?target=...`. **example:** SSO `/login`; VPN has its own gateway service URL. **decision:** perform the evidenced sequence independently on Direct then WebVPN. | **old:** manual absolute/protocol-relative/root/path redirects; one password-risk `ignoreAndContinue`; UC status proves activation. **example:** reqwest follows redirects; `verify_url` is UC or gateway root. **decision:** route-lock every redirect and require allowed HTTP(S) hosts/final UC validation. | **old:** mode-scoped Cookie store; execution/captcha are in-memory request state. **example:** one shared context Cookie/credential store; no captcha. **decision:** independent route Cookie jars and pending generations; never persist execution/challenge/password. | **old:** form mirrors hidden inputs and adds `username`, `password`, optional `captcha`/`captchaResponse`, `execution`, `_eventId=submit`, `submit=登录`, `type=username_password`; risk form has `execution`, `_eventId=ignoreAndContinue`. **example:** same non-captcha basic fields and risk form. | **old/example:** form URL encoding. **decision:** preserve hidden-field semantics and form encoding; no form values in logs/errors. | **old/example:** no additional login encryption. **decision:** none; WebVPN URL host codec is separate connection evidence. | **old:** execution input, `config.captcha {type,id}`, tip/error text, `UserInfoResponse code/data`. **example:** execution and risk-page marker only; captcha unsupported. **decision:** public challenge serializes only route, opaque generation-bound `challengeId`, and `imageAvailable`; raw upstream ID, execution and image stay private. | **old:** each route backend holds its own preparation through its Cookie store; no aggregate collision defense. **example:** no captcha generation. **decision:** every explicit prepare clears the old workflow and invalidates the previous generation; public IDs differ across routes even if upstream IDs match; raw ID plus execution matching is exact and answers are one-use; a failed route preparation is not silently retried during submission; an existing-session prepare retains a one-use authenticated-ready state; cached no-captcha state is reused only while that route state remains prepared. | **old:** missing captcha raises captcha-required; bad credentials/risk/activation have user-facing errors. **example:** missing execution/server and login failure errors. **decision:** unknown, duplicate, stale or cross-route answer is `invalid_input` before any credential POST; missing answer keeps that route `captcha_required`; one route failure preserves the other; login without a separate prepare returns any newly discovered public challenge in its outcome; existing-session readiness is consumed by profile retrieval without re-entering SSO; post-submit auth invalidation forces re-prepare before another credential POST. |

## User show

| bootstrap/service URL | redirect/final URL | cookie/session scope | method and exact parameters | headers/body encoding | crypto constants | DTO/parser fields | caching/concurrency | error/exit semantics |
|---|---|---|---|---|---|---|---|---|
| **old:** UC activation is part of login; query is `https://uc.buaa.edu.cn/api/uc/userinfo`. **example:** `api/user` activates UC but exposes only status, not the same userinfo operation. **decision:** use the old userinfo endpoint on the facade-resolved route. | **old:** SSO/final HTML indicates expired session. **example:** UC activation follows redirects. **decision:** WebVPN conversion and redirects remain route-locked; no cross-route retry. | **old:** current mode's Cookie/auth session; `getUserInfo` itself lacks the desired local preflight. **example:** shared context. **decision:** selected route slot only; `authenticated_at` from a validated/persisted login is the local proof, while prepare-page Cookies alone never authorize a business request. | **old:** GET `/api/uc/userinfo`, no parameters. **example:** non-equivalent GET `/api/uc/status?selfTimestamp=...`. **decision:** do not substitute status for profile. | **old:** default GET. **example:** default GET. **decision:** no invented request body/header. | **old/example:** N/A. | **old:** `code`, optional `data`; profile fields `idCardType`, `idCardTypeName`, `phone`, `schoolid`, `name`, `idCardNumber`, `email`, `username`. **example:** returns raw status text, non-equivalent. **decision:** stable optional profile DTO; mask sensitive display fields. | **old/example:** no profile cache. **decision:** route resolution and preflight occur in aggregate facade; zero HTTP requests without a validated local slot, including after prepare and before login. | **old:** 401/SSO HTML clears current local session; nonzero/missing data is `user_info_failed`. **decision:** missing slot is `authentication_required`; explicit invalidation clears only selected route; transient 5xx/timeout preserves both. |

## Classroom sync

| bootstrap/service URL | redirect/final URL | cookie/session scope | method and exact parameters | headers/body encoding | crypto constants | DTO/parser fields | caching/concurrency | error/exit semantics |
|---|---|---|---|---|---|---|---|---|
| **old:** exact SSO service URL in `LocalClassroomApi.kt::classroomSyncUrl`, including encoded `a_buaa/api/cas/index`, redirect, `from=wap`, `login_from=` and `noAutoRedirect=1`. **example:** `api/class/*` targets iClass and is N/A/non-equivalent. **decision:** use only the old free-classroom bootstrap. | **old:** shared redirect-following client; any 200..399 marks sync. **example:** N/A. **decision:** route-transform the complete URL; preserve old acceptance until live evidence says otherwise. | **old:** selected mode Cookie jar; `sessionSynced` belongs to one backend. **example:** `Sessionid` iClass token is unrelated. **decision:** one sync state per route/client, never global or cross-route. | **old:** GET exact service URL. **example:** N/A/non-equivalent. | **old:** exact long Android/WeCom `User-Agent`, no body. **example:** N/A. **decision:** preserve exact old UA. | **old/example:** N/A. | **old:** only HTTP status drives sync flag. **example:** N/A. **decision:** no response DTO exposed. | **old:** double-checked `Mutex`; once per backend until `clearCache`/session reset. **example:** N/A. **decision:** reproduce once-per-route synchronization and clear it on invalidation/logout/re-login. | **old:** exceptions are swallowed by `runCatching`; query proceeds and later classifies auth/upstream. **example:** N/A. **decision:** preserve this best-effort sync boundary; never report sync alone as feature success. |

## Classroom query

| bootstrap/service URL | redirect/final URL | cookie/session scope | method and exact parameters | headers/body encoding | crypto constants | DTO/parser fields | caching/concurrency | error/exit semantics |
|---|---|---|---|---|---|---|---|---|
| **old:** requires classroom sync; GET `https://app.buaa.edu.cn/buaafreeclass/wap/default/search1`. **example:** iClass query is N/A/non-equivalent. **decision:** use old free-classroom endpoint only. | **old:** query uses a no-redirect client; SSO Location/HTML is session expiry. **example:** N/A. **decision:** disable redirects for this request on both routes. | **old:** current route Cookie jar and local auth preflight. **example:** N/A. **decision:** selected route slot and route-owned sync state. | **old:** GET query `xqid=<int>`, `floorid=""`, `date=yyyy-mm-dd`. **example:** N/A. **decision:** preserve exact parameters. | **old:** exact long UA, `Accept: application/json, text/javascript, */*; q=0.01`, route-transformed Referer `https://app.buaa.edu.cn/site/classRoomQuery/index`, `X-Requested-With: XMLHttpRequest`; no body. **example:** N/A. | **old/example:** N/A. | **old:** required `e:int`, `m:string`, `d`, required `d.list: Map<String,List<ClassroomInfo>>`; room requires string `id`, `floorid`, `name`, `kxsds`. **example:** N/A. **decision:** missing `d/list` is parse error, not empty success; genuine empty map remains success. | **old:** no result cache; sync mutex as above. **example:** N/A. **decision:** same. | **old:** missing auth, SSO/401 invalidation, non-200 upstream, parse failure; date validation is host API concern. **decision:** stable `invalid_input`, `authentication_required`, upstream, parse codes; no fallback unless matrix later permits it. |

Deterministic implementation evidence on 2026-08-24: parser tests reject every missing required
`e/m/d/list` layer and non-string room field while preserving a genuine empty map. Transport tests
assert the frozen complete mobile `User-Agent`, XHR/Accept headers, route-transformed Referer,
once-per-client and route-isolated synchronization, best-effort failure followed by retry, and one
no-follow business request. Raw SSO Location, 401, and login HTML return
`authentication_required`, clear the selected persisted route and its feature state, and successful
session replacement forces a later synchronization. A state-level concurrency test proves the
double-checked async mutex runs one synchronization. The pinned example Classroom API remains
non-equivalent and supplied no protocol values to this implementation.

## SPOC auth

| bootstrap/service URL | redirect/final URL | cookie/session scope | method and exact parameters | headers/body encoding | crypto constants | DTO/parser fields | caching/concurrency | error/exit semantics |
|---|---|---|---|---|---|---|---|---|
| **old:** GET `https://spoc.buaa.edu.cn/spocnewht/cas`, then POST `/spocnewht/sys/casLogin`. **example:** GET `/spocnewht/cas` only; no `sys/casLogin`/role setup, so auth is partially non-equivalent. **decision:** old local flow is authoritative. | **old:** manually follows at most 8 route-transformed redirects and extracts token only from `/spocnew/cas?token=...&refreshToken=...`; raw SSO redirect from `sys/casLogin` is expired authentication. **example:** follows client redirects and reads the first `token` query pair. **decision:** preserve old bound and classify the no-follow raw SSO Location before status parsing. | **old:** route Cookie jar; in-memory token and role code keyed by cached client username. **example:** shared Cookie store and 3h credential token. **decision:** token/role/login mutex live in route-owned client feature state and are cleared with that session. | **old:** GET CAS; POST JSON `{token}` to `sys/casLogin`. **example:** no equivalent role POST. | **old:** JSON, `X-Requested-With: XMLHttpRequest`, `Token: Inco-<token>`; later calls add `RoleCode`. **example:** `Token: Inco-<token>` only. **decision:** preserve old RoleCode establishment. | **old/example:** no crypto for CAS login itself. | **old:** token/optional refreshToken from URL; `code/content` role fields `jsdm`, `rolecode`, `jsdmList`; null content or no resolvable role is authentication failure. **example:** token only. **decision:** role is required; no field inferred from example. | **old:** login mutex, reuse token/role, one forced refresh after business auth failure. **example:** credential expiry refresh. **decision:** once-per-route serialized login and exactly one refresh/retry. Optional course/submission callers retain their old `runCatching` boundary. | **old:** after required business authentication is exhausted, `resolveLocalBusinessAuthenticationFailure` validates UC: only explicit Invalid clears the selected primary session; Valid, transient, or inconclusive validation preserves it and returns `spoc_error`. **example:** no equivalent primary-session arbitration. **decision:** required operations perform the same UC validation; only `authentication_required` clears the selected route, while every other validation result returns retryable `upstream_unavailable` without clearing it. |

## SPOC list

| bootstrap/service URL | redirect/final URL | cookie/session scope | method and exact parameters | headers/body encoding | crypto constants | DTO/parser fields | caching/concurrency | error/exit semantics |
|---|---|---|---|---|---|---|---|---|
| **old:** authenticated current term POST `/inco/ht/queryOne`; optional course metadata GET `/jxkj/queryKclb`; authoritative global assignment POST `/inco/ht/queryListByPage`. **example:** current-week/course APIs differ and assignment list is per-course GET `/kczy/queryXsZyList`; list protocol is non-equivalent. **decision:** use old global list even when course lookup fails/returns empty. | **old:** route-transformed, no cross-route redirect/replay. **example:** ordinary same-host requests. **decision:** lock entire term/list sequence to one route. | **old:** same token/RoleCode and route Cookie state; course metadata failure is optional. **example:** shared token state. **decision:** route-owned SPOC state. | **old:** queryOne POST JSON fixed encrypted `param`; courses GET `kcmc=""`, `xnxq`; list POST JSON `{param}` whose plaintext fields, in order, are `pageSize=15`, `pageNum`, fixed `sqlid=1713252980496efac7d5d9985e81693116d3e8a52ebf2b`, `xnxq`, `kcid=""`, `yzwz=""`. **example:** GET `flag=1`, `sflx=2`, `sskcid=<course>`, non-equivalent. | **old:** JSON plus XHR, `Token`, `RoleCode`. **example:** query plus `Token`, no RoleCode. **decision:** old exact encoding/headers. | **old:** AES-128-CBC with zero padding and Base64, key `inco12345678ocni`, IV `ocni12345678inco`; aligned plaintext receives no extra block; fixed vector in `LocalSpocSupportTest`. **example:** confirms the AES constants but always appends 1-16 zero bytes, including a full block for aligned plaintext. **decision:** preserve the applicable frozen local no-extra-block behavior and test both aligned and unaligned inputs; the example remains supplemental. | **old:** current term `dqxq/mrxq`; page integer `total/pageNum/pageSize/pages`, Boolean `hasNextPage`, list; frozen defaults are `0/1/15/1`, false, and empty; assignment requires string `zyid/zymc`, with optional string `tjzt/zyjzsj/zykssj/sskcid/xnxq/mf/kcmc`; course metadata is optional. **example:** different per-course `Homework` fields. **decision:** preserve defaults/optionality but reject every present field of the wrong type. | **old:** pages from 1 until `!hasNextPage`, page limit reached, or empty list; cached route client; course lookup `runCatching`. **example:** caller loops courses, no equivalent global pagination. **decision:** old pagination and optional metadata; empty courses must still issue global list request. | **old:** business auth triggers one refresh; its malformed-JSON branch scans raw text and can treat the word `token` as authentication. **example:** typed JSON errors, no equivalent global list. **decision:** active contract forbids replaying parse/unknown failures, so malformed JSON is always `parse_error`; valid evidenced auth envelopes still refresh once. Genuine global empty page remains success. |

## SPOC detail

| bootstrap/service URL | redirect/final URL | cookie/session scope | method and exact parameters | headers/body encoding | crypto constants | DTO/parser fields | caching/concurrency | error/exit semantics |
|---|---|---|---|---|---|---|---|---|
| **old:** first resolves summary from the authoritative list; GET `/kczy/queryKczyInfoByid`; optional GET `/kczy/queryXsSubmitKczyInfo`. **example:** matching detail GET exists; submission read is only noted, not implemented. **decision:** old full sequence is authoritative; example corroborates detail endpoint/fields only. | **old/example:** same-host route-transformed GET; SSO HTML is auth failure. **decision:** one route for list/detail/submission. | **old:** route SPOC token/role/Cookies; submission failure is optional. **example:** token only. **decision:** route-owned state, no public raw HTML. | **old:** detail query `id=<assignmentId>`; submission query `kczyid=<assignmentId>`. **example:** matching detail `id`; no implemented submission request. | **old:** XHR, `Token`, `RoleCode`; GET query. **example:** `Token` only. **decision:** preserve old headers. | **old/example:** none for these GETs. | **old:** detail requires string `id` and `zymc`; `zynr/zykssj/zyjzsj/zyfs/sskcid` are optional strings; optional submission has `tjzt/tjsj`; detail score/time fall back to list summary; the old public DTO exposes both raw `contentHtml` and derived `contentPlainText`. **example:** corroborates required `zynr` plus other non-equivalent detail fields, but has no submission/fallback. **decision:** strictly parse the frozen identity fields, keep the list identity authoritative, preserve summary fallback, convert HTML internally, and expose plain text only. | **old:** reuses list/auth client; optional submission under same call; one auth refresh. **example:** token expiry only. **decision:** route-owned state and one refresh, no global cache. | **old:** missing summary is not found; submission failure does not fail detail; unknown status remains explicit. **example:** parser errors only. **decision:** stable not-found/auth/parse errors; remove public `contentHtml`. |

Deterministic SPOC implementation evidence on 2026-08-24: the CAS bootstrap follows at most eight
no-follow, allow-listed redirects, accepts a token only from an HTTPS `spoc.buaa.edu.cn` terminal
on the exact `/spocnew/cas` path, and requires the terminal representation to match Direct or
WebVPN routing. It does not request the token landing URL. Primitive and array role forms follow
the frozen `JsonPrimitive` behavior. Credentials are serialized and cached only inside one route
state, are redacted from `Debug`, cannot be repopulated after a state-generation invalidation, and
each individual business call performs at most one authentication refresh. A second auth failure
from a required term/page/detail operation validates the primary UC session: explicit invalidation
clears only the selected route, while valid or unavailable UC preserves both primary state and the
sibling slot and returns a non-authentication SPOC availability error. A raw business `Location`
resolving to SSO triggers that same bounded refresh despite the no-follow transport. Raw SSO
Location, null content, and missing role during `sys/casLogin` enter the same primary-session
arbitration. Course metadata remains optional even after its own retry is exhausted.
The frozen client's standalone `权限` authentication marker conflicts with the active no-permission-
retry contract; UBAA 2 records that conflict in the decision log and does not replay code-403
permission envelopes.

List transport tests capture the actual page-one and page-two JSON POST bodies, test-side decrypt
their Base64 AES-CBC `param`, and assert the complete ordered plaintext including empty `kcid` and
`yzwz`. They also prove one pagination sequence for multiple courses and continued paging when
course metadata is empty or unavailable. Parser tests cover integer page metadata, optional string
`xnxq`, required string detail `zymc`, optional string `sskcid`, and malformed JSON containing
`token` without any hidden relogin. Detail tests retain upstream-ID validation, summary fallbacks,
optional submission enrichment, plain-text decoding, and omission of raw HTML. These are
deterministic protocol results only; current Direct/WebVPN/auto live evidence remains open.

## Judge list

| bootstrap/service URL | redirect/final URL | cookie/session scope | method and exact parameters | headers/body encoding | crypto constants | DTO/parser fields | caching/concurrency | error/exit semantics |
|---|---|---|---|---|---|---|---|---|
| **old:** SSO `https://sso.buaa.edu.cn/login?service=http%3A%2F%2Fjudge.buaa.edu.cn%2F`, then `judge.buaa.edu.cn/courselist.jsp?courseID=0`. **example:** N/A/non-equivalent; pinned tree has no Judge module. **decision:** old is the only frozen protocol source. | **old:** one activation redirect is resolved then route-transformed; SSO pages trigger reactivation up to 3 retries. **example:** N/A. **decision:** route-lock all redirects/URLs. | **old:** per-user/per-mode client; isolated workers fork non-Judge parent Cookies and keep Judge cookies local. **example:** N/A. **decision:** route/client-owned state; no global cache/cookie mixing. | **old:** GET courses; GET `courselist.jsp?courseID=<id>` to select; GET `assignment/index.jsp`; `includeExpired` affects local cutoff, not an upstream parameter. **example:** N/A. | **old:** browser `Accept`, `Accept-Language: zh-CN,zh;q=0.9`, exact Chrome 58 UA; no body. **example:** N/A. **decision:** preserve. | **old/example:** N/A. | **old:** parse course links excluding course 0; assignment links by `assignID`, excluding `problemContent` and `judgeDetails`; dedupe IDs. **example:** N/A. **decision:** exact filter required before live parity. | **old:** list caches keyed user+route, assignment work bounded at 4, 5-minute list TTL; six-month cutoff/historical course store unless includeExpired. **example:** N/A. **decision:** state is owned and cleared by route client/session lifecycle. | **old:** missing local auth, SSO reactivation failure, non-200, no permission/not found map to stable errors. **example:** N/A. **decision:** list exit 0/count alone does not prove parser parity; Direct/WebVPN count divergence remains unresolved. |

## Judge detail

| bootstrap/service URL | redirect/final URL | cookie/session scope | method and exact parameters | headers/body encoding | crypto constants | DTO/parser fields | caching/concurrency | error/exit semantics |
|---|---|---|---|---|---|---|---|---|
| **old:** after activation/course selection, GET `assignment/index.jsp?assignID=<id>`. **example:** N/A/non-equivalent. | **old:** SSO page reactivates and retries; route remains fixed. **example:** N/A. | **old:** selected course mutex and isolated worker Cookie state. **example:** N/A. **decision:** same route/client scope. | **old:** GET with exact numeric/string course and assignment IDs discovered from list. **example:** N/A. | **old:** Judge browser headers; no body. **example:** N/A. | **old/example:** N/A. | **old:** parses start/due, max/own score, total/submitted count, nested/top-level problem tables, per-problem score/max/status, `PARTIAL`, fallback submitted counts and plain text. **example:** N/A. **decision:** all fields/status semantics are required; fixed empty `problems`/`myScore` is non-parity. | **old:** course selection mutex; detail cache 2 minutes keyed user+route+course+assignment. **example:** N/A. **decision:** no global cache and clear on session reset. | **old:** missing assignment/course is not found; auth page reactivates; non-200/auth exhaustion stable failures. **decision:** historical detail exit 0 is unverified semantic evidence until complete parser assertions pass. |

## Judge batch/cache

| bootstrap/service URL | redirect/final URL | cookie/session scope | method and exact parameters | headers/body encoding | crypto constants | DTO/parser fields | caching/concurrency | error/exit semantics |
|---|---|---|---|---|---|---|---|---|
| **old:** reuses Judge activation/list/detail endpoints; no separate batch upstream API. **example:** N/A/non-equivalent. | **old:** each worker activates and remains on its route. **example:** N/A. | **old:** cache scope is `(mode,username)`; worker cookies isolate Judge session; reset clears `LocalJudgeApiCache`. **example:** N/A. **decision:** runtime-owned `RouteFeatureState`, never process-global. | **old:** normalizes nonblank `(courseId,assignmentId)` keys, deduplicates, groups by course and performs the same GET detail sequence. **example:** N/A. | **old:** same browser headers. **example:** N/A. | **old/example:** N/A. | **old:** grouped traversal returns complete detail DTO plus public `historicalCutoffCourseIds`; empty normalized input returns empty details. **example:** N/A. **decision:** UBAA 2 keeps cutoff IDs internal to route state and restores the normalized caller key order after grouped work. | **old:** max 4 concurrent course workers; list TTL 5m, detail TTL 2m; no empty assignment-list cache; six-month cutoff retaining local time of day; reset clears all. **example:** N/A. **decision:** reproduce bounds/cache keys/lifecycle inside the owning facade, preserve time of day and clamp the target month day. | **old:** one missing course/assignment fails batch as not found; auth/upstream errors are not hidden. **example:** N/A. **decision:** no stale/global reuse after logout or account/route change. |

## CLI/config

| bootstrap/service URL | redirect/final URL | cookie/session scope | method and exact parameters | headers/body encoding | crypto constants | DTO/parser fields | caching/concurrency | error/exit semantics |
|---|---|---|---|---|---|---|---|---|
| **old:** host UI chooses `ConnectionMode`; no equivalent UBAA 2 CLI/config. **example:** library context only, no CLI/config/schema. **decision:** N/A to upstream URLs; aggregate Core facade owns ordinary routing. | **old/example:** no equivalent CLI redirect contract. **decision:** hosts receive only facade results. | **old:** mode-scoped settings but switching clears sessions. **example:** caller-managed `cookies.json`/`cred.json`. **decision:** Core loads strict `config.toml` format version `1` and dual `session.json`; CLI never reads storage internals. | **old/example:** no equivalent commands. **decision:** CLI parses documented commands/arguments, invokes facade methods without `ConnectionMode`, and renders; hidden mode is diagnostic/test-only. | **old/example:** no envelope. **decision:** one JSON value on stdout, diagnostics only on stderr, no sensitive values/raw upstream data. | **old/example:** N/A. | **old/example:** no equivalent schema. **decision:** CLI output is schema version 2 only; config/session on-disk versions remain independent. Aggregate route arrays are exactly Direct then WebVPN, single-route envelopes cannot carry aggregate fields, pre-resolution failures carry only the feature, and captcha output is limited to route/opaque ID/image availability. | **old:** global mode/runtime. **example:** caller-owned context. **decision:** config/probe cache/routing/session/feature state are facade-owned; CLI has no routing cache. Config writes reject symlinks/non-regular files and use unique atomic temp files. | **old/example:** no equivalent exit taxonomy. **decision:** stable exits 0/2/3/4/5/6/7; a fresh config directory must support JSON login; missing local user/feature session fails before network. |

Config persistence evidence on 2026-08-24: Unix tests prove load and save reject a
symlinked `config.toml` without reading or changing its target. Eight concurrent saves publish one
complete parseable configuration using unique exclusive temporary files, leave no temporary file,
and retain directory/file modes `0700`/`0600`. This is local filesystem evidence only.

## Unchanged schedule/exam evidence

`LocalScheduleApi.kt` probes `currentUser.do`; `Schedule.kt` and
`LocalScheduleApiBackendTest.kt` prove the terms/weeks/today/exam GETs and the
weekly schedule form fields `termCode`, `type=week`, `week`. Pinned
`api/aas/core.rs` proves the same AAS service-specific CAS activation and final
landing URL. Pinned `api/aas/opt.rs` uses a different query payload including
`campusCode`; UBAA 2 does not borrow that extra field without local/live
evidence. No encryption is involved. Route locking, unsupported-undergraduate
classification and sanitized parser fixtures remain required.

## Unchanged grades evidence

`LocalGradeApi.kt` proves activation at
`https://app.buaa.edu.cn/buaascore/wap/default/index`, then a form POST with
`xq` and `year`; `Grade.kt` proves the `e/m/d` wrapper and scalar mapping. The
pinned App module is N/A/non-equivalent and supplies no local score URL, DTO or
error. The separate old grade score cache is not evidence for an upstream
request cache. UBAA 2 retains strict `yyyy-yyyy-semester` parsing and stable
invalid-input/upstream/parse errors.

## Review rule

Any change to a URL, service value, redirect, Cookie/session scope, method,
parameter, header, body encoding, crypto constant, DTO field/type, cache key,
concurrency bound or error mapping must update the corresponding operation row
before production code changes. A fixture alone cannot close live parity, an
authentication success cannot close a business operation, and an exit-zero
list cannot prove detail/parser semantics.
