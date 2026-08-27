# Source Parity Matrix

Updated: 2026-08-26

This is an operation-by-operation behavior audit. `old` means frozen
`ubaa_old/` commit `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`;
`example` means pinned `examples/buaa-api/` commit
`efb7976bf513f38364b88aeb83d704586cff9b2a`. Every cell records both sources
and the UBAA 2 decision. A source marked non-equivalent supplies no URL, field,
crypto or error by analogy. Live evidence may supersede a frozen protocol fact
only when its sanitized observation is recorded in the decision log.

The nine columns below are mandatory for every authentication or read-only
operation before production code changes.

The frozen WebVPN codec uses gateway `d.buaa.edu.cn`, the key/IV text
`wrdvpnisthebest!`, AES-128-CFB without padding, and the
`scheme[-port]/encrypted-host/path` layout. UBAA 2 matches those wire values.
For exact edge behavior, empty query/fragment separators are omitted like the
frozen Kotlin implementation; an explicit root slash remains preserved by the
Rust URL/runtime path representation so route request and final-URL semantics
do not change. Cookie matching itself remains against the gateway URL. Both
decisions are covered by sanitized connection tests. No redirect host is added
from this comparison: the current allowlist remains evidence-gated by live
observations.

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

## Prepare/login (captcha unsupported in UBAA2)

| bootstrap/service URL | redirect/final URL | cookie/session scope | method and exact parameters | headers/body encoding | crypto constants | DTO/parser fields | caching/concurrency | error/exit semantics |
|---|---|---|---|---|---|---|---|---|
| **old:** GET/POST `https://sso.buaa.edu.cn/login`, followed by User Center activation at `https://uc.buaa.edu.cn/api/login?target=...`; the frozen old flow may also expose `config.captcha` and fetch `/captcha?captchaId=...`. **example:** SSO `/login`; no equivalent captcha protocol. **decision:** preserve the ordinary login and activation sequence independently on Direct and WebVPN, but deliberately do not implement the optional interactive verification branch. | **old:** manual absolute/protocol-relative/root/path redirects; one password-risk `ignoreAndContinue`; UC status proves activation. **example:** reqwest follows redirects; `verify_url` is UC or gateway root. **decision:** route-lock every redirect and require allowed HTTP(S) hosts/final UC validation. | **old:** mode-scoped Cookie store; execution is in-memory request state. **example:** one shared context Cookie/credential store. **decision:** independent route Cookie jars and transient execution state; never persist execution or interactive verification material. | **old:** form mirrors hidden inputs and adds `username`, `password`, `execution`, `_eventId=submit`, `submit=登录`, `type=username_password`; the old captcha branch additionally sends `captcha`/`captchaResponse`. **example:** same ordinary basic fields and risk form. **decision:** send only the ordinary evidence-backed form. A page containing `config.captcha` is rejected as `upstream_changed` before image fetch or credential POST. | **old/example:** form URL encoding. **decision:** preserve hidden-field semantics and form encoding; no form values in logs/errors. | **old/example:** no additional login encryption. **decision:** none; WebVPN URL host codec is separate connection evidence. | **old:** execution input, `config.captcha {type,id}`, tip/error text, `UserInfoResponse code/data`. **example:** execution and risk-page marker only; captcha unsupported. **decision:** expose only stable profile/error DTOs; no challenge ID, image availability or verification bytes are public. | **old:** each route backend holds its own preparation through its Cookie store. **example:** no captcha generation. **decision:** each route retains only its own prepared execution; no cross-route or cross-process verification state exists. | **old:** missing captcha can raise captcha-required; bad credentials/risk/activation have user-facing errors. **example:** missing execution/server and login failure errors. **decision:** any interactive verification marker is `upstream_changed` with no retry or prompt; ordinary authentication, network and parser errors retain their stable classifications. |

The current classifier additionally rejects any extra visible input, `textarea`/`select`,
the frozen captcha field names `captcha`/`captchaResponse`, or deny-only `config.*`
markers named `captcha`, `mfa`, `otp`, `verification`, `verify`, or `challenge`.
This is a closed-world safety boundary derived from the ordinary frozen input parser;
it prevents credentials from being posted to unknown verification UI without claiming
that a new upstream field or marker is part of the protocol.

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

## SPOC safe diagnostics

| bootstrap/service URL | redirect/final URL | cookie/session scope | method and exact parameters | headers/body encoding | crypto constants | DTO/parser fields | caching/concurrency | error/exit semantics |
|---|---|---|---|---|---|---|---|---|
| **old:** no diagnostic API; it always reaches the same current-term/global-list operations above. **example:** no equivalent global-list diagnostic. **decision:** diagnostics add no URL or request. | **old:** same route-locked SPOC flow. **example:** non-equivalent list. **decision:** reuse the ordinary final-URL and raw-SSO checks. | **old:** same route Cookie/token/role state. **example:** no equivalent. **decision:** expose no credential/session state. | **old:** same encrypted page POSTs with `kcid=""`; no diagnostic parameter. **example:** non-equivalent per-course GET. **decision:** ordinary and diagnostic reads share one operation; no evidence-only request is sent. | **old:** same JSON/XHR/Token/RoleCode headers and encrypted body. **example:** non-equivalent. **decision:** unchanged. | **old:** same local AES-CBC operation. **example:** constants only. **decision:** unchanged. | **old:** no diagnostic DTO. **example:** N/A. **decision:** return exactly `globalPageCount` and the ordinary `result`; the count increments only for successfully parsed authoritative global pages, so a value of at least one distinguishes a real empty page from a skipped request. No raw page, parameter, token or new assignment field is exposed. | **old:** ordinary serialized route state and pagination. **example:** no equivalent. **decision:** reuse the same sequence and state; diagnostics add no cache or concurrency behavior. | **old:** global-page auth/upstream/parse failures remain failures. **example:** N/A. **decision:** use the same routed error; count metadata alone never establishes live success. |

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
| **old:** SSO `https://sso.buaa.edu.cn/login?service=http%3A%2F%2Fjudge.buaa.edu.cn%2F`, then `judge.buaa.edu.cn/courselist.jsp?courseID=0`. **example:** N/A/non-equivalent; pinned tree has no Judge module. **decision:** old is the only frozen protocol source. | **old:** one activation redirect is resolved then route-transformed; SSO pages trigger reactivation up to 3 retries. **example:** N/A. **decision:** route-lock all redirects/URLs. | **old:** per-user/per-mode client; isolated workers fork non-Judge parent Cookies and keep Judge cookies local. **example:** N/A. **decision:** route/client-owned state; no global cache/cookie mixing. | **old:** GET courses; GET `courselist.jsp?courseID=<id>` to select; GET `assignment/index.jsp`; `includeExpired` affects local cutoff, not an upstream parameter. **example:** N/A. | **old:** browser `Accept`, `Accept-Language: zh-CN,zh;q=0.9`, exact Chrome 58 UA; no body. **example:** N/A. **decision:** preserve. | **old/example:** N/A. | **old:** parse course links excluding course 0; assignment links by `assignID`, excluding `problemContent` and `judgeDetails`; dedupe IDs. **example:** N/A. **decision:** exact filter required before live parity. | **old:** list caches keyed user+route, assignment work bounded at 4, 5-minute list TTL; six-month cutoff/historical course store unless includeExpired. **example:** N/A. **decision:** state is owned and cleared by route client/session lifecycle. | **old:** missing local auth, SSO reactivation failure, non-200, no permission/not found map to stable errors. After Judge business authentication retries are exhausted, old code validates UC and clears the primary session only for explicit Invalid; Valid, 5xx, network, or inconclusive UC results preserve it and return a business failure. **example:** N/A. **decision:** implement the same top-level arbitration with `upstream_unavailable` for preserved-session failures; list exit 0/count alone does not prove parser parity; Direct/WebVPN count divergence remains unresolved. |

## Judge safe diagnostics

| bootstrap/service URL | redirect/final URL | cookie/session scope | method and exact parameters | headers/body encoding | crypto constants | DTO/parser fields | caching/concurrency | error/exit semantics |
|---|---|---|---|---|---|---|---|---|
| **old:** no diagnostic API; it uses the same Judge list bootstrap above. **example:** N/A/non-equivalent. **decision:** diagnostics add no upstream request or URL. | **old:** same list activation and bounded reactivation. **example:** N/A. **decision:** reuse the exact list chain and route resolution. | **old:** same per-user/per-mode client and isolated workers. **example:** N/A. **decision:** expose counts only through the facade; never expose worker/session state. | **old:** same course, selection, assignment-list and detail GETs; no diagnostic parameter. **example:** N/A. **decision:** ordinary and diagnostic reads share one request/cache path. | **old:** same browser headers and empty bodies. **example:** N/A. | **old/example:** N/A. | **old:** its parser first matches numeric `assignID` anchors, then excludes `problemContent`/`judgeDetails`, rejects blank titles and deduplicates assignment IDs; it has no count DTO. **example:** N/A. **decision:** `courseCount` is the parsed course count before historical-course skipping; `rawAnchorCount` sums numeric `assignID` `a[href]` matches from assignment-list entries reached by the operation, whether freshly fetched or cache-backed, before exclusion/title filtering/deduplication; historical courses skipped before worker creation contribute neither raw nor filtered counts; `filteredUniqueCount` sums the final nonblank unique assignment lists; `summaries` is exactly the ordinary `includeExpired` result. No raw HTML, new IDs, titles beyond existing summaries, Cookies or tokens are added. | **old:** list TTL is 5 minutes and empty assignment lists are not cached. **example:** N/A. **decision:** cache the two safe counts atomically with each nonempty parsed assignment list so an ordinary read followed by diagnostics does not refetch or infer counts; retain the same four-worker bound and lifecycle invalidation. | **old:** list authentication/upstream errors are unchanged. **example:** N/A. **decision:** diagnostic facade returns the same error and route semantics as ordinary Judge list; counts are evidence metadata, not proof of live success by themselves. |

## Judge detail

| bootstrap/service URL | redirect/final URL | cookie/session scope | method and exact parameters | headers/body encoding | crypto constants | DTO/parser fields | caching/concurrency | error/exit semantics |
|---|---|---|---|---|---|---|---|---|
| **old:** after activation/course selection, GET `assignment/index.jsp?assignID=<id>`. **example:** N/A/non-equivalent. | **old:** SSO page reactivates and retries; route remains fixed. **example:** N/A. | **old:** selected course mutex and isolated worker Cookie state. **example:** N/A. **decision:** same route/client scope. | **old:** GET with exact numeric/string course and assignment IDs discovered from list. **example:** N/A. | **old:** Judge browser headers; no body. **example:** N/A. | **old/example:** N/A. | **old:** parses start/due, max/own score, total/submitted count, nested/top-level problem tables, per-problem score/max/status, `PARTIAL`, fallback submitted counts and plain text. **example:** N/A. **decision:** all fields/status semantics are required; fixed empty `problems`/`myScore` is non-parity. | **old:** course selection mutex; detail cache 2 minutes keyed user+route+course+assignment. **example:** N/A. **decision:** no global cache and clear on session reset. | **old:** missing assignment/course is not found; auth page reactivates; non-200/auth exhaustion stable failures. After terminal business authentication failure, old code validates UC before deciding whether the primary session is invalid. **decision:** the same arbitration must wrap the top-level detail operation, not each internal request; historical detail exit 0 is unverified semantic evidence until complete parser assertions pass. |

## Judge batch/cache

| bootstrap/service URL | redirect/final URL | cookie/session scope | method and exact parameters | headers/body encoding | crypto constants | DTO/parser fields | caching/concurrency | error/exit semantics |
|---|---|---|---|---|---|---|---|---|
| **old:** reuses Judge activation/list/detail endpoints; no separate batch upstream API. **example:** N/A/non-equivalent. | **old:** each worker activates and remains on its route. **example:** N/A. | **old:** cache scope is `(mode,username)`; worker cookies isolate Judge session; reset clears `LocalJudgeApiCache`. **example:** N/A. **decision:** runtime-owned `RouteFeatureState`, never process-global. | **old:** normalizes nonblank `(courseId,assignmentId)` keys, deduplicates, groups by course and performs the same GET detail sequence. **example:** N/A. | **old:** same browser headers. **example:** N/A. | **old/example:** N/A. | **old:** grouped traversal returns complete detail DTO plus public `historicalCutoffCourseIds`; empty normalized input returns empty details. **example:** N/A. **decision:** UBAA 2 keeps cutoff IDs internal to route state and restores the normalized caller key order after grouped work. | **old:** max 4 concurrent course workers; list TTL 5m, detail TTL 2m; no empty assignment-list cache; six-month cutoff retaining local time of day; reset clears all. **example:** N/A. **decision:** reproduce bounds/cache keys/lifecycle inside the owning facade, preserve time of day and clamp the target month day. | **old:** one missing course/assignment fails batch as not found; auth/upstream errors are not hidden. Terminal business authentication failures still pass through old UC arbitration before primary-session cleanup. **example:** N/A. **decision:** top-level batch operations share the Judge arbitration boundary; no stale/global reuse after logout or account/route change. |

## CLI/config

| bootstrap/service URL | redirect/final URL | cookie/session scope | method and exact parameters | headers/body encoding | crypto constants | DTO/parser fields | caching/concurrency | error/exit semantics |
|---|---|---|---|---|---|---|---|---|
| **old:** host UI chooses `ConnectionMode`; no equivalent UBAA 2 CLI/config. **example:** library context only, no CLI/config/schema. **decision:** N/A to upstream URLs; aggregate Core facade owns ordinary routing. | **old/example:** no equivalent CLI redirect contract. **decision:** hosts receive only facade results. | **old:** mode-scoped settings but switching clears sessions. **example:** caller-managed `cookies.json`/`cred.json`. **decision:** Core loads strict `config.toml` format version `1` and dual `session.json`; CLI never reads storage internals. | **old/example:** no equivalent commands. **decision:** CLI parses documented commands/arguments, invokes facade methods without `ConnectionMode`, and renders; hidden mode is diagnostic/test-only. | **old/example:** no envelope. **decision:** one JSON value on stdout, diagnostics only on stderr, no sensitive values/raw upstream data. | **old/example:** N/A. | **old/example:** no equivalent schema. **decision:** CLI output is schema version 2 only; config/session on-disk versions remain independent. Aggregate route arrays are exactly Direct then WebVPN; `all_ready`/`partial` require a complete profile while `none_ready` forbids one. Route failures contain only stable safe errors; no challenge/image fields or captcha error code exist. Single-route envelopes cannot carry aggregate fields, and pre-resolution failures carry only the feature. | **old:** global mode/runtime. **example:** caller-owned context. **decision:** config/probe cache/routing/session/feature state are facade-owned; CLI has no routing cache. Config writes reject symlinks/non-regular files and use unique atomic temp files. | **old/example:** no equivalent exit taxonomy. **decision:** stable exits 0/2/3/5/6/7; a fresh config directory must support JSON login; an interactive verification page maps to `upstream_changed` (exit 6), and missing local user/feature session fails before network. |

Config persistence evidence on 2026-08-24: Unix tests prove load and save reject a
symlinked `config.toml` without reading or changing its target. Eight concurrent saves publish one
complete parseable configuration using unique exclusive temporary files, leave no temporary file,
and retain directory/file modes `0700`/`0600`. This is local filesystem evidence only.

Verifier evidence on 2026-08-24 is likewise deterministic only. The shell harness rejects CLI
schema versions other than 2, unsafe stable errors, aggregate route arrays not exactly Direct then
WebVPN, route/error state that exposes unsupported interactive verification fields, a claimed empty SPOC result without an
authoritative global page, incomplete, causally inconsistent or unmasked profiles, fractional or
out-of-range Rust integer fields, cross-request schedule/grade term drift, SPOC detail identity or
frozen status-text drift,
contradictory Judge ID/problem/count/score/status semantics, resolved-route contradictions,
incomplete or extra business DTO fields, duplicate Judge keys, and output containing credential,
session or raw-response aliases, obvious complete HTML documents or CAS forms. Arbitrary
angle-bracket text is not used to infer provenance; exact DTO closure and deterministic parser tests
prove that raw HTML fields are absent. The production verifier requires one resolved
route for every request in a feature run, supplies full Judge comparison JSON to jq only through
stdin, and exposes only safe counts, timing, stable errors and a salted Judge digest. The shell
contract also fixes the mandatory salt and digest-stability semantics. These checks do not establish
any live Direct, WebVPN or auto result until the corrected real matrix runs.

## Unchanged schedule/exam evidence

`LocalScheduleApi.kt` probes `currentUser.do`; `Schedule.kt` and
`LocalScheduleApiBackendTest.kt` prove the terms/weeks/today/exam GETs and the
weekly schedule form fields `termCode`, `type=week`, `week`. Pinned
`api/aas/core.rs` proves the same AAS service-specific CAS activation and final
landing URL. Pinned `api/aas/opt.rs` uses a different query payload including
`campusCode`; UBAA 2 does not borrow that extra field without local/live
evidence. No encryption is involved. Route locking, unsupported-undergraduate
classification and sanitized parser fixtures remain required.

The 2026-08-25 Direct and WebVPN live shape check returned a successful
`WeeklySchedule` envelope with the frozen `arrangedList`, `code`, and `name`
fields; the list was empty and `data.code` was a non-empty string different
from the selected semester term. The frozen DTO/parser only decodes
`WeeklyScheduleResponse.datas` and does not assert that equality. The live
verifier therefore validates that `data.code` is a non-empty string while the
request term remains selected from the terms response and is sent unchanged;
it must not invent an equality rule unsupported by either frozen source.

## Unchanged grades evidence

`LocalGradeApi.kt` proves activation at
`https://app.buaa.edu.cn/buaascore/wap/default/index`, then a form POST with
`xq` and `year`; `Grade.kt` proves the `e/m/d` wrapper and scalar mapping. The
pinned App module is N/A/non-equivalent and supplies no local score URL, DTO or
error. The separate old grade score cache is not evidence for an upstream
request cache. UBAA 2 retains strict `yyyy-yyyy-semester` parsing and stable
invalid-input/upstream/parse errors.

## 课堂签到今日查询

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：**先访问 `https://iclass.buaa.edu.cn:8346/?type=jumpMyCenter`，再调用 8347 的 `app/user/login.action` 和 `app/course/get_stu_course_sched.action`。**示例：**没有等价 iClass 模块。**决定：**只采用冻结旧版 URL，不从其他业务类比。 | **旧版：**最多跟随 8 次跳转，从最终 URL 或 `Location` 中提取大小写不敏感的 `loginName`，并进行百分号解码；Direct/WebVPN 始终保持当前路线。**示例：**不适用。**决定：**使用 Core 的手动、允许主机列表跳转，不接受未知主机。 | **旧版：**主认证 Cookie 与 iClass `id/sessionId` 分离；业务会话按学生标识缓存。**示例：**不适用。**决定：**iClass 会话是每个路线/客户端的进程内状态，不能写入 `session.json`，也不能跨路线复用。 | **旧版：**登录 GET 参数为 `password=""`、`phone=loginName`、`userLevel=1`、`verificationType=2`、`verificationUrl=""`；今日查询 GET 参数为 `id=userId`、`dateStr=yyyyMMdd`。**决定：**保持完整参数和值，不增加字段。 | **旧版：**今日查询使用 `sessionId` 请求头；请求无正文。**决定：**保持该请求头，禁止输出或日志记录其值。 | **旧版/示例：**无加密。**决定：**不得引入自定义加密或签名。 | **旧版：**`STATUS` 接受字符串或整数；成功值为 `0`、`200`、`success`。课堂字段为 `id`、`courseName`、`classBeginTime`、`classEndTime`、`stuSignStatus`，状态兼容字符串或整数。**决定：**公共 DTO 仅暴露对应稳定字段，不暴露包装、业务会话或原始响应。 | **旧版：**按学生标识缓存业务会话；会话失效后最多刷新一次。**决定：**使用路线内登录锁和失效代数，主会话清理时同步清除；并发失效后旧任务不得重新写入。 | **旧版：**未认证返回认证错误；iClass 登录失败时查询退化为空成功，这是旧 UI 的容错行为。**决定：**Core 不伪造空成功；无法建立业务会话返回稳定上游错误，业务会话失效只清除签到状态，只有 User Center 明确失效才清除主认证。 |

当前实现证据：`crates/ubaa-core/tests/signin.rs` 已覆盖冻结响应的字符串/整数状态解析；独立 iClass 会话、facade、CLI 和真实路线验证尚未完成。因此该行只证明解析基础，不证明完整功能可用。

## Review rule

Any change to a URL, service value, redirect, Cookie/session scope, method,
parameter, header, body encoding, crypto constant, DTO field/type, cache key,
concurrency bound or error mapping must update the corresponding operation row
before production code changes. A fixture alone cannot close live parity, an
authentication success cannot close a business operation, and an exit-zero
list cannot prove detail/parser semantics.
