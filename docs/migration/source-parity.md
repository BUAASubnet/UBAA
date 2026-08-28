# Source Parity Matrix

Updated: 2026-08-29

This is an operation-by-operation behavior audit. `old` means frozen
`ubaa_old/` commit `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`;
`example` means pinned `examples/buaa-api/` commit
`efb7976bf513f38364b88aeb83d704586cff9b2a`. Every cell records both sources
and the UBAA 2 decision. A source marked non-equivalent supplies no URL, field,
crypto or error by analogy. Live evidence may supersede a frozen protocol fact
only when its sanitized observation is recorded in the decision log.

2026-08-29 验证边界：`verify-live` 对 User、Signin、Ygdk、LibBook、Bykc、Cgyy 和
Evaluation 均按独立 CLI 子操作执行；依赖上游返回标识的详情请求仅在存在脱敏标识时
继续。真实验证仍严格只读，失败类别按各操作单独保留，不由 `all` 聚合结果覆盖。

Bykc 已选课程解析修复：冻结 `LocalBykcApi` 的 `queryChosenCourse` 返回
`data.courseList` 对象包装，而不是直接数组。Rust 现同时接受该冻结包装和既有数组
兼容形状；`features/bykc.rs` 单元测试先复现旧实现失败，再验证 `id`、`courseInfo.id`
和列表长度。2026-08-29 Direct、WebVPN、auto 的 Bykc 逐项复测均退出 0。

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
| **旧版：**先访问 `https://iclass.buaa.edu.cn:8346/?type=jumpMyCenter`，再调用 8347 的 `app/user/login.action` 和 `app/course/get_stu_course_sched.action`。**示例：**等价 Class 模块在固定提交中将登录更新为 8346 的 `eschool/app/user/login_buaa.do`，今日查询仍使用 8347 的 `app/course/get_stu_course_sched.action`。**决定：**2026-08-28 Direct 真实运行证明旧登录入口返回 `upstream_changed`，采用示例中更晚且等价的登录入口；查询入口保持旧版。 | **旧版：**最多跟随 8 次跳转，从最终 URL 或 `Location` 中提取大小写不敏感的 `loginName`，并进行百分号解码；Direct/WebVPN 始终保持当前路线。**示例：**登录前同样从 8346 跳转结果提取 `loginName`。**决定：**使用 Core 的手动、允许主机列表跳转，不接受未知主机。 | **旧版：**主认证 Cookie 与 iClass `id/sessionId` 分离；业务会话按学生标识缓存。**示例：**同样维护独立 Class 凭据。**决定：**iClass 会话是每个路线/客户端的进程内状态，不能写入 `session.json`，也不能跨路线复用。 | **旧版：**登录 GET 参数为 `password=""`、`phone=loginName`、`userLevel=1`、`verificationType=2`、`verificationUrl=""`；今日查询 GET 参数为 `id=userId`、`dateStr=yyyyMMdd`。**示例：**登录和查询参数与旧版一致。**决定：**保持完整参数和值，不增加字段。 | **旧版：**今日查询使用 `sessionId` 请求头；请求无正文。**示例：**使用等价会话值作为 `Sessionid`，查询为 POST 并将 `dateStr` 放在 query；**决定：**本轮仅由真实失败证明登录入口变化，查询方法仍保持冻结旧版 GET，除非后续真实证据要求调整。 | **旧版/示例：**无加密。**决定：**不得引入自定义加密或签名。 | **旧版：**`STATUS` 接受字符串或整数；成功值为 `0`、`200`、`success`。课堂字段为 `id`、`courseName`、`classBeginTime`、`classEndTime`、`stuSignStatus`，状态兼容字符串或整数。**示例：**`STATUS=2` 表示空列表。**决定：**公共 DTO 仅暴露对应稳定字段，不暴露包装、业务会话或原始响应；空列表语义需以真实响应确认。 | **旧版：**按学生标识缓存业务会话；会话失效后最多刷新一次。**示例：**Class 凭据独立缓存。**决定：**使用路线内登录锁和失效代数，主会话清理时同步清除；并发失效后旧任务不得重新写入。 | **旧版：**未认证返回认证错误；iClass 登录失败时查询退化为空成功，这是旧 UI 的容错行为。**示例：**业务失败上抛。**决定：**Core 不伪造空成功；无法建立业务会话返回稳定上游错误，业务会话失效只清除签到状态，只有 User Center 明确失效才清除主认证。 |

当前实现证据：`crates/ubaa-core/tests/signin.rs` 已覆盖冻结响应的字符串/整数状态解析及独立 iClass 会话；Core facade 和 `signin today` CLI 已接入。固定 `examples/buaa-api` 的 Class 模块进一步证明业务登录应使用 8346 的 `eschool/app/user/login_buaa.do`，查询请求使用 POST、`Sessionid` 头并将 `id/dateStr` 放在 query；`STATUS=2` 表示今日无课程的合法空结果。2026-08-28 Direct 与 WebVPN 实时验证均通过并返回空列表。

## 阳光打卡只读查询

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：** OAuth 入口为 `https://app.buaa.edu.cn/uc/api/oauth/index`，交换地址为 `https://ygdk.buaa.edu.cn/api/Front/Clockin/User/campusAppLogin`；**示例：**无等价模块；**决定：**仅采用冻结旧版证据。 | **旧版：**最多跟随 10 次跳转，从 query 或 fragment query 提取并解码 `code`；**决定：**仅允许已记录的 BUAA 主机。 | **旧版：**按学生标识缓存独立 `uid/token`，不复用主认证 Cookie；**决定：**挂在路线隔离的业务会话状态中，不持久化敏感令牌。 | **旧版：**先分类、项目、汇总/学期，再记录查询；记录使用 `page`、`limit`、`classify_id`、`user_id`，概览固定 `page=1`、`limit=1000`；**决定：**保持分页与体育分类选择语义。 | **旧版：**POST `application/x-www-form-urlencoded`，所有请求附加 `uid/token` 和 `X-Requested-With: XMLHttpRequest`；**决定：**不记录令牌值。 | **旧版/示例：**无加密；**决定：**不引入签名或自定义加密。 | **旧版：**概览包含学期汇总、分类、默认项目和项目列表；记录包含记录标识、项目、时间、地点、图片、状态及分页字段；时间按上海时区格式化。 | **旧版：**按学生标识缓存业务会话，认证失效时清除并重试一次；**决定：**使用路线内单飞登录与失效代数。 | **旧版：**外层 `code=1` 成功，`-98` 清会话并认证失败，其余使用 `msg` 映射上游错误；非法分页参数为输入错误；**决定：**禁止把失败伪装为空结果。 |

当前实现证据：`crates/ubaa-core/tests/ygdk.rs` 已覆盖概览、记录分页和令牌业务会话，Core facade 与 `ygdk overview`/`ygdk records` CLI 已接入；`ygdk submit` 现已接入照片 multipart 上传和固定字段表单提交，要求 CLI 显式 `--confirm-write`，实时验证永不调用。OAuth code 同时从普通 query 与 `#/home?code=...` fragment query 提取；项目和记录参数按冻结实现同时发送至 query 与表单正文；业务 token 作为单独 URL 值解码，`-98` 会清除业务凭据并完整重登一次。上传正文的 `uid`、`token`、`file` 字段、固定边界、文件名和 MIME 已有确定性向量测试。`examples/buaa-api` 没有等价实现，不能从其模块类比 URL、字段或令牌流程。2026-08-28 Direct/WebVPN 实时验证均通过并解析到 11 个项目。实时验证永不调用写操作。

## 图书馆座位只读查询

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：**业务基址 `https://booking.lib.buaa.edu.cn/v4/`；**示例：**无等价模块；**决定：**只采用冻结旧版。 | **旧版：**SSO 最多 8 跳，从最终 URL、Location 或 fragment 提取 `cas`；**决定：**手动跟随并限制已知主机。 | **旧版：**独立图书馆 token，不复用教务 Cookie；**决定：**路线内存储，禁止持久化令牌。 | **旧版：**所有查询 POST JSON：`space/pcTopFor`、`space/pick`、`Space/map`、`Space/seat`、`member/seat`，参数含日期、区域、时段和分页；**决定：**保持原始 JSON 字段。 | **旧版：**Authorization、Origin、Referer、固定 UA、`X-Requested-With`；**决定：**不输出 token。 | **旧版：**AES 仅用于预约写操作；**决定：**只读查询不引入加密。 | **旧版：**图书馆、楼层、区域、时段、座位及预约分页 DTO；座位 `status == 1` 表示可用。 | **旧版：**token 按用户缓存，失效后清理并重试一次；**决定：**路线隔离状态。 | **旧版：**业务 code 0/1 成功，其他映射错误；**决定：**区分上游错误、未找到和座位不可用，不伪造空结果。 |

当前实现证据：UBAA2 Core 已完成五类图书馆只读查询及独立路线内 token 会话，CLI 已接入五个对应子命令，并有 Mock/CAS 回归测试。预约、取消现已接入 Core/CLI，并以冻结 golden 向量覆盖日期派生 AES-128-CBC、PKCS#7 和固定 IV；CLI 写入口要求显式确认，verify-live 永不调用。`examples/buaa-api` 没有等价实现。Direct/WebVPN 真实路线验证仍未完成。

补充证据（`24acd8b`）：`crates/ubaa-core/tests/libbook.rs` 的 Mock 端到端测试按冻结顺序调用预约确认和取消接口，断言 `aesjson` 非空、取消请求携带预约标识，并复用路线内 bearer 会话。测试仅使用合成会话与脱敏响应，不产生真实预约或取消。

## Review rule

## UBAA2 直接写操作与评教（2026-08-28）

### Cgyy 预约提交

取消操作的直接 Facade 证据：`RouteClient::cgyy_cancel_order` 已补齐正数订单校验，并通过合成传输断言 `/api/orders/new/cancel/{id}` 的 POST 签名请求；不跨路线复用令牌，也不执行真实取消。

取消操作的直接 Facade 证据：`RouteClient::cgyy_cancel_order` 已补齐正数订单校验，并通过合成传输断言 `/api/orders/new/cancel/{id}` 的 POST 签名请求；不跨路线复用令牌，也不执行真实取消。

冻结 `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalCgyyApi.kt` 的 `submitReservation` 要求先读取 `/api/reservation/day/info`，取得预约上下文 `token`，校验所有选择属于同一空间且时段可预约，再以表单 POST `/api/reservation/order/info` 创建订单上下文。验证码获取与校验分别使用 `/api/captcha/get`、`/api/captcha/check`，旧实现由注入的验证码求解器提供 `pointJson` 和 `captchaVerification`，失败最多重试三次。最终表单 POST `/api/reservation/order/submit`，字段为 `venueSiteId`、`reservationDate`、`reservationOrderJson`、`weekStartDate`、`phone`、`theme`、`purposeType`、`joinerNum`、`activityContent`、`joiners`、`isPhilosophySocialSciences`、`isOffSchoolJoiner`、`captchaVerification`、`token`。Rust Core 已实现上下文创建、选择校验、受控图片求解和最终表单构造；CLI 与 live 验收仍禁止调用该写操作。`examples/buaa-api` 未提供同一场馆预约协议，未借用其 URL、字段或错误语义。

Signin perform 已由 Rust Core 和 CLI 暴露。冻结的本地顺序为：取得 iClass 业务会话，GET `app/common/get_timestamp.action`，再向 `eschool/app/course/stu_scan_sign.action` 发送带 `id` 的表单，并携带 `courseSchedId`、`timestamp` 查询参数和 `sessionId` 请求头。CLI 要求 `--confirm-write`，verify-live 永远不会调用它。响应必须同时满足冻结成功状态和 `result.stuSignStatus=1`；畸形或非成功响应映射为稳定的上游错误。

补充证据：`crates/ubaa-core/tests/signin.rs` 的合成传输按上述四步顺序返回脱敏响应，并断言最终 URL、表单和会话头；测试不会访问真实 iClass，也不持久化业务会话材料。

Ygdk 写入口的输入边界也已固定：照片必须存在且非空，开始和结束时间必须同时提供；这些检查发生在 OAuth/业务令牌请求之前。`features/ygdk.rs` 单元测试使用禁止网络的传输验证无效请求直接返回 `invalid_input`。

`crates/ubaa-core/tests/ygdk.rs` 进一步以合成传输验证完整写链顺序：OAuth code、`campusAppLogin`、分类/项目/统计/学期概览、`Upload/File/post` multipart 和 `Clockin/clockin` 表单；断言 `uid`、业务 token、文件元数据及打卡字段均按冻结协议发送，且不产生真实副作用。

The following rows are the required parity boundary for the remaining direct upstream
operations. `ubaa_old` is authoritative at the commit recorded in `references.md`;
`examples/buaa-api` is explicitly non-equivalent for all rows except Evaluation's SPOC
endpoints. No row authorizes a live write during migration verification.

| operation | bootstrap/service URL | redirect/final URL | cookie/session scope | method and exact parameters | headers/body encoding | crypto/signature constants | DTO/parser fields | caching/concurrency | error/exit semantics |
|---|---|---|---|---|---|---|---|---|---|
| Bykc select | CAS `bykc.buaa.edu.cn/sscv/cas/login`, API `/sscv/choseCourse` | same CAS token redirect and route wrapping as reads | route-local BYKC token | POST encrypted JSON `{courseId}` | encrypted body, `auth_token`/`authtoken`, `ak`,`sk`,`ts`, JSON content type | AES-128-ECB PKCS7; RSA PKCS#1 v1.5; SHA-1 digest; frozen public key in `LocalBykcCrypto.kt` | `BykcSuccessResponse.message` from envelope | login single-flight; retry after expired token | invalid input is local; upstream non-success is a stable write error |
| Bykc deselect | same | same | same | POST encrypted JSON `{id}` to `/sscv/delChosenCourse` | same | same | success message | same | same |
| Bykc sign/sign-out | same | same | same | POST encrypted JSON `{courseId,lat,lng,signType}` to `/sscv/signCourseByUser`; `signType` 1 or 2 | same | same | success message | selected-course/sign-config lookup precedes write; no global cache | missing course/location or unavailable window is input/upstream error |
| Signin perform | iClass center `?type=jumpMyCenter`; business login `8347/app/user/login.action` | bounded allow-list redirect; extract decoded `loginName` | route-local `{userId,sessionId}`; one retry after login expiry | timestamp GET `app/common/get_timestamp.action`, then POST form `app/course/stu_scan_sign.action` with `id`, query `courseSchedId`,`timestamp` | `sessionId` header; URL-encoded form | none | `{code,success,message}`; success requires `STATUS` success and `result.stuSignStatus=1` | per-student single-flight session | never silently succeeds; failed status maps to stable write result/error |
| Ygdk submit | OAuth index then `campusAppLogin` | bounded code extraction from query/fragment | route-local `{uid,token}` | multipart `Upload/File/post` (`uid`,`token`,`file`), then form `Clockin/clockin` with `start_time,end_time,place_type,place,isopen,form_time_fmt,images,classify_id,item_id,item_name,uid,token` | multipart photo, then `application/x-www-form-urlencoded` plus `X-Requested-With` | none | `{success,message,recordId,summary}` | session single-flight; no persisted token | `-98` clears/retries once; upload/clockin failure is write failure |
| LibBook reserve | CAS service `booking.lib.buaa.edu.cn/v4/login/cas` then `/v4/login/user` | bounded SSO redirect and `cas` extraction | route-local bearer token | POST JSON `{aesjson}` to `/v4/space/confirm`; AES plaintext is reserve request `{areaId,seatId,day,segment,startTime,endTime}` | Authorization `bearer<token>`, Origin/Referer/X-Requested-With | frozen `LocalLibBookCrypto.encryptReserveRequest` AES constants | `{success,message,booking?}` | token single-flight; expired token clears and retries once | non-success envelope is stable write error |
| LibBook cancel | same | same | same | POST JSON `{id}` to `/v4/space/cancel` | same | no additional crypto beyond request wrapper | `{success,message}` | same | invalid booking and expired session remain distinguishable |
| Cgyy lock code | SSO `manageLogin`, then `/api/login` | bounded route-local redirects | route-local `cgAuthorization` access token | GET `/api/orders/lock/code` | signed query/header used by existing Cgyy client | existing Cgyy MD5 signature constants | opaque lock-code JSON data | token single-flight | envelope code/message determines stable error |
| Cgyy submit | same | same | same | POST `/api/reservation/order/info`; captcha GET `/api/captcha/get`, POST `/api/captcha/check`; POST form `/api/reservation/order/submit` with `venueSiteId,reservationDate,reservationOrderJson,weekStartDate,phone,theme,purposeType,joinerNum,activityContent,joiners,isPhilosophySocialSciences,isOffSchoolJoiner,captchaVerification,token` | URL-encoded forms and JSON selection list | existing Cgyy request signature; captcha solver input is never persisted | `{success,message,order?}` | no write cache; captcha retries bounded at 3 | invalid slot/input is local; captcha exhaustion and upstream failures are stable write errors |
| Cgyy cancel | same | same | same | POST `/api/orders/new/cancel/{id}` | signed request, empty body | existing signature | action message/order | token single-flight | explicit write confirmation required by CLI |
| Evaluation list/pending | GET `spoc/pjxt/cas`, then task/list, questionnaire list, required reviews | bounded route-local SPOC redirects | route-local SPOC cookies/session | GET task params `yhdm,pageNum=1,pageSize=10`; questionnaire `rwid`; courses `wjid`; topic fields are sent exactly from `EvaluationCourse` | JSON envelope, GET query; revise pattern is best-effort JSON POST | none | task/questionnaire/course fields from frozen `EvaluationModel.kt`; pending filters `!isEvaluated` | activation mutex; course map key `${rwid}_${wjid}_${kcdm}_${bpdm}` | malformed envelope/upstream auth is stable error; empty result is only valid when upstream says success |
| Evaluation submit | same | same | same | best-effort POST `/reviseQuestionnairePattern` `{rwid,wjid,msid}`, GET topic, POST `/submitSaveEvaluation` `{pjidlist:[],pjjglist:[...],pjzt:"1"}` | JSON | no additional crypto; payload fields follow frozen `LocalEvaluationService.kt` | per-course `EvaluationResult`; payload preserves `pjdf=93`, question IDs/options and teacher/course IDs | bounded sequential per-course submission; no cache | submit response code/message maps per-course success/failure; CLI confirmation is mandatory |

For the pinned `examples/buaa-api`, the Evaluation module (`src/api/tes`) confirms the
same SPOC task/form/submit URLs but is not evidence for the other feature URLs, fields,
or crypto. Where old local code uses random answer selection, Core exposes an explicit
deterministic answer policy for tests and never performs live submission in verification.

## 博雅课程只读查询

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：**CAS 登录服务为 `https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fbykc.buaa.edu.cn%2Fsscv%2Fcas%2Flogin`；业务接口位于 `https://bykc.buaa.edu.cn/sscv/`。**示例：**`examples/buaa-api/src/api/boya` 提供同一业务端点的交叉证据，但不替代旧版加密实现。 | **旧版：**登录后从 `cas-login?token=` 重定向提取令牌；必须手动限制允许主机和跳转次数。**WebVPN：**先把最终地址及 `Location` 还原为直连语义，再解析相对跳转、校验 `sso/bykc` 主机，发请求时重新按当前路线包装。 | **旧版：**按用户缓存独立业务令牌，不复用主认证 Cookie；**决定：**令牌仅保存在路线内存状态，不写入 `session.json`。 | **旧版五项只读：**`getUserProfile {}`、`queryStudentSemesterCourseByPage {pageNumber,pageSize}`、`queryCourseById {id}`、`getAllConfig {}` 后接 `queryChosenCourse {startDate,endDate}`、`queryStatisticByUserId {}`。已选课程的公开接口不接收日期：先选择首个包含当前时间的学期，否则按可解析的结束时间选择最新学期；空列表或选中项缺少起止时间均报“无法获取当前学期信息”。`all=false` 时只在本地过滤状态为“已过期”或“选课结束”的当前页项目，`all=true` 时保留全部项目，请求参数和上游分页统计均不改变。**示例：**同样请求课程分页和学期配置，但其配置包装只取首项，学期选择顺序仍以冻结旧版为准。 | **旧版：**所有接口 POST JSON 外层加密；请求携带 `auth_token`/`authtoken` 及 `ak`、`sk`、`ts` 头；不得记录密文、令牌或请求体。 | **旧版：**随机 AES-128-ECB 加密正文，RSA PKCS#1 v1.5 加密 AES key 与 SHA-1 正文摘要；公钥来自冻结 `LocalBykcCrypto.kt`。**决定：**实现前必须逐常量添加向量测试，禁止凭示例代码猜测。 | **旧版 DTO：**用户资料、课程分页/状态、课程详情、已选课程和统计；列表课程包含课程、选课与退选时间及稳定状态；状态顺序固定为已过期、已选、选课结束、人数已满、预告、可选。必填字段与时间/枚举兼容规则以 `Bykc.kt` 及冻结测试为准，公共层不得暴露原始密文或上游包装。 | **旧版：**业务令牌按用户缓存；课程详情/已选课程需要学期配置，查询失败不得写入空缓存；并发登录只能产生一个有效路线令牌。 | **旧版：**CAS/令牌失效清理业务状态并最多刷新一次；非零业务码、解密失败、字段缺失分别映射稳定上游/解析错误；不得把失败伪装为空列表。**实时证据：**2026-08-28 Direct 与 WebVPN 均通过并解析到 1 条课程。 |

当前实现证据：UBAA2 已实现 Bykc Core、路线独立会话、facade 和 CLI 五项只读查询，并完成 Direct/WebVPN 真实验证。已选课程按冻结 `courseInfo` 嵌套结构展开课程标识、名称、地点、教师、时间、分类、考勤、考核、签到配置、作业与备注；缺失课程信息沿用旧版的标识零值和“未知课程”，签到可用性按考核状态、考勤状态和时间窗口计算。旧版 DTO 虽保留作业附件名称与路径，但本地实现没有从该只读响应赋值，因此 UBAA2 同样返回空值。`examples/buaa-api` 仅作端点交叉证据，不能替代冻结旧版的 AES、RSA、SHA-1 常量和错误语义。选课、退选、签到及附件写请求已接入 Core/CLI，并由显式确认保护；实时验证永不调用。

Bykc 写链 Mock 证据：`crates/ubaa-core/tests/bykc.rs` 按冻结顺序返回 CAS token，并依次校验 `/sscv/choseCourse`、`/sscv/delChosenCourse`、`/sscv/signCourseByUser` 的非空加密正文、`auth_token`/`authtoken` 和 `ak`/`sk`/`ts` 头。测试不记录密文内容、不使用真实会话。

Any change to a URL, service value, redirect, Cookie/session scope, method,
parameter, header, body encoding, crypto constant, DTO field/type, cache key,
concurrency bound or error mapping must update the corresponding operation row
before production code changes. A fixture alone cannot close live parity, an
authentication success cannot close a business operation, and an exit-zero
list cannot prove detail/parser semantics.

## 场馆预约只读查询

| 操作 | bootstrap/service URL | redirect/final URL | cookie/session scope | method and exact parameters | headers/body encoding | crypto constants | DTO/parser fields | caching/concurrency | error/exit semantics |
|---|---|---|---|---|---|---|---|---|---|
| 场馆站点 | **old:** 先 GET `https://cgyy.buaa.edu.cn/venue-zhjs-server/sso/manageLogin`，再 POST `/api/login`，最后 GET `/api/front/website/venues?page=-1&size=-1&reservationRoleId=3`。**example:** 无等价场馆接口。**decision:** 仅采用旧实现 URL。 | **old:** `manageLogin` 使用跟随跳转的客户端；业务请求若最终落到 SSO、返回 401 或登录表单即判定业务认证失效。**example:** N/A。**decision:** 跳转仅允许 SSO 与场馆主机；WebVPN 主路线只负责解析和会话预检，业务请求按冻结实现改用独立 Direct transport。 | **old:** 从基址 Cookie `sso_buaa_zhjs_token` 取值，以 `Sso-Token` 头调用 `/api/login`，再从 `data.token.access_token` 取得业务令牌；令牌按用户缓存。**example:** N/A。**decision:** Direct 业务 runtime 使用 Direct 路线槽位的独立 Cookie/令牌，不从 WebVPN 槽位复制；令牌不写入 `session.json`。 | **old:** 业务登录为无表单字段 POST；站点为 GET，固定 `page=-1`、`size=-1`、`reservationRoleId=3`；所有 GET 自动增加当前毫秒 `nocache`。**example:** N/A。**decision:** 保留全部参数、名称与类型。 | **old:** 所有调用带 `Accept: application/json, text/plain, */*`、场馆移动预约页 `Referer`、`app-key`、`timestamp`、`sign`；业务查询另带 `cgAuthorization`；POST 使用表单编码。**example:** N/A。**decision:** 保持这些头和编码，禁止记录 Cookie、令牌与签名原文。 | **old:** `app-key=8fceb735082b5a529312040b58ea780b`；签名为 `MD5(prefix + 规范化路径 + 按键名排序的原始标量参数 + timestamp + 空格 + prefix)`，其中 `prefix=c640ca392cd45fb3a55b00a63a86c618`；空字符串、集合及审计字段不参与签名。**example:** N/A。**decision:** 以冻结向量测试固定算法，不增加其他加密。 | **old:** `data` 可能是场馆对象数组，旧版递归将每个对象的 `siteList` 展开为扁平站点并继承 `venueName/campusName`；扁平数组也可直接映射。响应信封 `code/data` 且所有 `requestJson` 响应严格要求 `code=200`。**example:** N/A。**decision:** 公共 DTO 仅映射这些冻结字段，缺失或非 200 代码拒绝成功。 | **old:** 登录使用互斥锁，令牌复用；业务认证失效时清令牌并且最多强制刷新一次。**example:** N/A。**decision:** Direct 业务 runtime 的路线状态内单飞，失效后只刷新当前 Direct 业务会话一次。 | **old:** 缺少主会话、SSO Cookie 或访问令牌均为认证失败；业务 `code != 200`、非 JSON 与网络错误分别映射上游/解析错误。**example:** N/A。**decision:** 只有 User Center 明确失效才能清主会话，业务失败不能伪装为空成功；WebVPN 站点复测已通过，后续操作仍逐项保留实时错误。 |
| 用途类型 | **old:** GET `/api/codes`，从树形数据递归提取用途；旧实现已有主会话时对动态请求或解析异常均使用固定用途回退。**example:** 无等价接口。**decision:** 保留递归提取与已验证静态回退。 | 与站点相同；失效后最多重登并重放一次。 | 与站点相同，复用当前路线的 `access_token`。 | GET，无业务参数，自动加入 `nocache`。 | 与站点相同，无请求体。 | 与站点相同的 MD5 签名。 | 用途 `key/name`；空响应、请求失败或解析异常按旧回退规则处理。 | 与场馆会话同域；不单独缓存跨用户数据。 | 主会话缺失仍为认证错误；已有主会话后的动态请求/解析失败回退静态列表并成功返回，不伪造上游数据。 |
| 日期可用性 | **old:** GET `/api/reservation/day/info?searchDate=<日期>&venueSiteId=<站点>`。**example:** 无等价接口。**decision:** 保留查询参数名称与编码。 | 与站点相同；失效后最多重登并重放一次。 | 与站点相同，复用当前路线的 `access_token`。 | GET，`searchDate` 与 `venueSiteId` 均必填，并自动加入 `nocache`。 | 与站点相同，无请求体。 | 与站点相同，查询参数与 `nocache` 均参与 MD5 签名。 | 日期信息包含时间段、空间及槽位状态；状态非 `1`、已有流水号/订单号或占用标志均判定不可预约；旧版对每个空间的槽位按 `timeId` 升序输出。 | 路线会话内请求；不跨日期缓存。 | 参数缺失为 `invalid_input`；业务认证失效只刷新业务令牌；响应结构错误为 `upstream_changed`。 |
| 我的订单 | **old:** GET `/api/orders/mine`。**example:** 无等价接口。**decision:** 仅采用旧实现接口。 | 与站点相同；失效后最多重登并重放一次。 | 与站点相同，复用当前路线的 `access_token`。 | GET，精确参数 `page`、`size`，自动加入 `nocache`。 | 与站点相同，无请求体。 | 与站点相同，分页参数与 `nocache` 均参与签名。 | 分页 `content`、`totalElements`、`totalPages`、`size`、`number`；订单字段按冻结 `Cgyy.kt` 映射；成功信封 `data=null` 按旧版映射为空页。 | 不缓存订单结果。 | 页码小于 0 或每页数量不为正数是 `invalid_input`；主会话/业务认证失败仍返回认证错误，成功信封的空数据才回退为空页。 |
| 订单详情 | **old:** GET `/api/orders/{id}`。**example:** 无等价接口。**decision:** 仅采用旧实现接口。 | 与站点相同；失效后最多重登并重放一次。 | 与站点相同，复用当前路线的 `access_token`。 | GET，订单 ID 只进入路径，自动加入 `nocache`。 | 与站点相同，无请求体。 | 与站点相同，规范化详情路径和 `nocache` 参与签名。 | 单个订单字段按冻结 `Cgyy.kt` 映射；成功信封 `data=null` 按旧版映射为空对象 DTO，数组/标量仍拒绝。 | 不缓存详情结果。 | 非正订单 ID 是 `invalid_input`；业务认证失败保持认证错误；仅成功信封空数据按冻结旧实现映射默认字段。 |
| 锁码 | **old:** 先完成 `manageLogin`/`api/login`，再 GET `/api/orders/lock/code`；**example:** 无等价接口。**decision:** 仅采用冻结旧实现 URL。 | 与站点相同，允许路线内重定向和最终 URL 校验。 | 复用当前路线业务令牌；WebVPN 主路线按冻结语义使用独立 Direct 业务 transport，绝不跨槽位复制 Cookie。 | GET，无业务参数，自动加入 `nocache`。 | 与站点相同的签名头和空请求体。 | 与站点相同的 MD5 签名；不增加加密。 | **old:** `data` 可空且不透明；Core `CgyyLockCode.rawData` 保留原值供受控 facade，CLI 仅投影 `{available: boolean}`，不输出锁码内容。 | 业务令牌路线内单飞，锁码结果不缓存。 | 缺少会话/令牌、网络或非成功 envelope 保持认证/上游错误；CLI 验证只校验安全摘要，不把敏感原始 data 视为公共输出。 |

`examples/buaa-api` 在锁定提交中未实现 `venue-zhjs-server` 场馆预约协议，因此没有提供 URL、字段、令牌或错误语义；以上所有协议值均来自冻结 `ubaa_old/shared/.../CgyyApi.kt`、`LocalCgyyApi.kt`、`LocalCgyySigner.kt` 及对应服务测试。取消、锁码和预约提交已分别接入 Core/CLI 或 Core；预约提交现在还会按冻结协议 POST `/api/captcha/check`，发送 `pointJson` 与验证码挑战 `token`，并要求响应 `data.success=true` 后才提交最终表单。验证码挑战 GET 的 `captchaType=blockPuzzle`、`clientUid=slider-<毫秒时间>`、`ts=<毫秒时间>` 参数及 `secretKey/token/originalImageBase64/jigsawImageBase64` 解析已固化测试；受控图像求解器已迁移到 Core，实时验证永不调用写操作。锁码原始 `data` 仍由 Core facade 保留为不透明值，CLI 仅输出 `{available: boolean}`，避免打印或持久化锁码内容。

验证码位移凭据的加密已由 Core 提供：输入冻结挑战 `secretKey`、`token` 和外部图像求解器得到的横向位移，输出 AES-ECB/PKCS#7 的 `pointJson` 与 `captchaVerification`；确定性 golden 向量已覆盖 16 字节密钥。Rust 现已使用受控 PNG/JPEG 解码复刻旧版灰度、边缘、掩码和滑动匹配算法，挑战缺失或图片解析失败会失败关闭；预约链最多获取并校验三次，禁止默认位移。此前段落中的“求解端口尚未迁移”仅为历史记录，当前实现已完成该 Core 算法；WebVPN 独立业务 runtime 仍未解决。

### Signin 时间戳解析校正

冻结 `LocalSigninApi.kt` 在 GET `app/common/get_timestamp.action` 响应 JSON 中读取字符串字段 `timestamp`；空字段或非 JSON 响应均映射为上游错误，随后将该值作为签到请求查询参数。Rust Core 已严格解析该字段，并以脱敏测试覆盖非 JSON 拒绝。`examples/buaa-api` 未实现 iClass 签到协议，因此未借用其响应结构。

Signin 提交请求的表单构造已单独覆盖：冻结 `stu_scan_sign.action` 只发送 `id` 用户标识，`courseSchedId` 与 `timestamp` 位于查询参数，`sessionId` 位于请求头；测试断言表单不会增加其他字段。

### Evaluation 评教提交信封

冻结 `LocalEvaluationService.kt` 最终向 `evaluationMethodSix/submitSaveEvaluation` 发送 JSON 正文：`pjidlist` 固定为空数组、`pjjglist` 为逐课程结果列表、`pjzt` 固定为字符串 `"1"`，响应按业务 `code` 和消息字段判定成功。Rust Core 已迁移该 URL、JSON 编码、请求头和非空列表校验，并提供 `build_submit_body` 脱敏向量测试。自动提交链会按旧版顺序对每门待评课程执行 `reviseQuestionnairePattern`（失败按冻结实现继续）、读取问卷题目、展开 `wjzblist[].tklist[]`，按题型构造答案后提交最终信封；选择题的第二个选项只在随机选中的一题使用，随机源保留在 Core 内且不写入日志。CLI 提供 `evaluation submit-pending --confirm-write`，未确认时在读取课程前拒绝；实时验证永不调用写操作。`examples/buaa-api` 无等价评教提交协议。

空 `pjjglist` 现在在会话建立前返回 `invalid_input`；单元测试使用禁止网络的传输验证该边界，确保无效评教提交不会访问上游。

逐请求证据：`crates/ubaa-core/tests/evaluation.rs` 通过 `RouteClient::evaluation_submit` 使用合成会话调用冻结 `submitSaveEvaluation`，断言 JSON 信封中的空 `pjidlist`、`pjzt="1"` 和课程结果字段，以及固定请求头；不记录原始响应或个人数据。

自动链证据：同一测试文件以单门脱敏课程调用 `evaluation_submit_courses`，严格断言 CAS 激活、revise（`rwid/wjid/msid`）、题目 GET 和最终提交四步顺序，并校验最终结果保留 `pjdf=93`。Mock 响应不包含真实课程或人员数据。

LibBook 座位排序补充：冻结 `LocalLibBookApi.getSeats` 在 DTO 映射后执行 `sortedBy { it.no }`；Core `parse_seats` 同样按座位号字符串升序输出，并由逆序脱敏测试固定该行为。
