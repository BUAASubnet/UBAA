# Source Parity Matrix

Updated: 2026-08-19

This is a behavior audit, not a list of similar names. Each row must be checked across the full request lifecycle. The frozen local implementation and tests are the primary compatibility source for local read-only APIs; `examples/buaa-api` is supplemental evidence only when it implements the same upstream protocol. Live responses have priority for current behavior and are recorded in `docs/migration/status.md` without storing raw bodies.

## Required comparison fields

For every operation, the implementation review must answer all of these questions:

1. Which business CAS/bootstrap URL and service/redirect parameter establishes the session?
2. Which redirects are followed, what final URL proves activation, and how are Direct/WebVPN URLs transformed?
3. Which Cookie jar, session slot, token, execution, captcha, and cache scope is used?
4. What exact HTTP method, URL parameters, form/query/body fields, and ordering are sent?
5. Which headers, Referer, User-Agent, content type, and body encoding are required?
6. Is any encryption/signature used? If so, where are the algorithm, key, IV, padding, and encoding proven?
7. Which DTO fields and scalar types are accepted, and how are empty/missing/unknown fields parsed?
8. What cache, mutex, semaphore, refresh, pagination, or cutoff behavior is required?
9. Which status, authentication, unsupported-account, empty-result, parse, and upstream errors map to stable Core errors and CLI exits?

An operation is not parity-reviewed until every item is either evidence-backed or explicitly marked `not applicable` with a source citation.

## Authentication and User Center

| Dimension | `ubaa_old/` evidence | `buaa-api` evidence | Rust behavior / decision |
|---|---|---|---|
| Bootstrap and redirect | `LocalConnectionAuth.kt`, `AuthApi.kt`; SSO login, UC login/status/userinfo and logout URLs | `api/sso/auth.rs`, `api/user/auth.rs`, `api/user/opt.rs` | `upstream` constants and `auth` state machine use the frozen SSO/UC URLs; redirects are host-allow-listed and route-locked. |
| Cookies/session | `LocalConnectionAuth.kt` and cookie tests: host/domain/path/Secure/expiry/replacement, route-scoped stores | `store/cookies.rs`, `context.rs` | Core keeps independent Direct/WebVPN jars and schema-v2 slots; CAS revision and file lock prevent stale save/logout. |
| Method/body/headers | CAS form fields, execution, username/password, captcha and one risk continuation in old auth code/tests | `request.rs`, SSO auth form and credential store | Forms are built from parsed fields; password/captcha/execution never leave the route slot or public output. |
| Encryption | No unproven extra login encryption in local flow | No extra login encryption in pinned SSO flow | No invented encryption; WebVPN host codec is separately proven by `LocalWebVpnSupport.kt`/`VpnCipher.kt`. |
| DTO/parser/errors | Old auth/user DTOs and user-facing error classification | `error.rs` and user response parsing | Stable redacted facade DTOs and error/exit contract; live auth Direct/WebVPN both passed. |

## Schedule and Exam

| Dimension | `ubaa_old/` evidence | `buaa-api` evidence | Rust behavior / decision |
|---|---|---|---|
| Business bootstrap | `LocalScheduleApi.kt::withLocalUndergradPortalAccess` probes `currentUser.do` before each read; graduate portal is unsupported | `api/aas/core.rs` explicitly activates `sso.buaa.edu.cn/login?service=<byxt index>` and verifies the AAS landing URL | Core probes first, then performs the AAS-specific CAS activation when the probe is an SSO page, verifies the final AAS URL, and probes again. This was required by live evidence and is tested for both routes. |
| Redirect/final URL | Old local URL conversion and SSO classification | `aas/core.rs` `login_url` and `verify_url` | All redirects are resolved within the selected route; WebVPN never sends a Direct URL. |
| Methods/parameters/headers | Terms/weeks/today/exam GET query; week schedule POST form (`termCode`, `type=week`, `week`); schedule/exam Referers in old code/tests | AAS week POST uses query payload including `termCode`, `campusCode`, `type`, `week`; `currentUser` is GET | Rust preserves old local method and form semantics. The form helper now sends `Content-Type: application/x-www-form-urlencoded`, proven by a failing request-contract test and live `schedule_current` success. `campusCode` is not added without local/live evidence. |
| Encryption | None | None | Not applicable. |
| DTO/parser | `Schedule.kt` term/week/course/today DTOs and wrapper code; old parser ignores unknown fields | `aas/data.rs` accepts `arrangedList` plus `notArrangeList`, parses credit/time/day types | Rust stable DTOs follow the local contract for requested operations; parser changes require a sanitized fixture for any newly observed shape. |
| Cache/concurrency/errors | Per-call portal probe and old SSO/unsupported/unavailable classification | AAS credential expiry and login refresh | Core preserves route lock, authentication/unsupported/upstream/parse codes; no cross-route fallback is invented. |

## Grades

| Dimension | `ubaa_old/` evidence | `buaa-api` evidence | Rust behavior / decision |
|---|---|---|---|
| Bootstrap | `LocalGradeApi.kt` activates `https://app.buaa.edu.cn/buaascore/wap/default/index` before query | `api/app/*` is a mini-program App protocol and does not implement this local score endpoint | Use only the old Local Grade evidence. The App example is explicitly non-equivalent and cannot supply fields or routes for grades. |
| Methods/parameters/headers | Activation GET; query POST form `xq` and `year`, JSON/XHR Referer | No equivalent grades operation | Rust `post_form` and grade parser match the old local sequence. |
| Encryption/cache | No grade-request encryption; old score cache is a separate local storage concern | No equivalent | No invented encryption or cache semantics in the Core read path. |
| DTO/parser/errors | `BuaaScoreResponse` `e/m/d`, scalar `JsonElement` mapping and `yyyy-yyyy-semester` parser | No equivalent | Rust accepts the proven `e/m/d` shape, maps values safely, and rejects invalid term syntax/parse/nonzero code deterministically. |

## Empty Classroom

| Dimension | `ubaa_old/` evidence | `buaa-api` evidence | Rust behavior / decision |
|---|---|---|---|
| Bootstrap and session | `LocalClassroomApi.kt` SSO sync followed by free-classroom query; old backend test checks request shape | `api/class/*` is an iClass course/check-in protocol on `iclass.buaa.edu.cn`, not the free-classroom endpoint | Do not substitute iClass URLs, `Sessionid`, or course DTOs. Rust uses only the local classroom protocol. |
| Methods/parameters/headers | GET query `xqid`, empty `floorid`, ISO `date`; User-Agent/XHR/Referer and route conversion | No equivalent operation | Rust matches the local query and headers; Direct/WebVPN/auto live evidence returned valid parsed results. |
| Encryption/cache | None in local free-classroom flow | iClass URL port/gateway rules are unrelated | Not applicable; no cross-protocol encryption or cache is copied. |
| DTO/parser/errors | Local `e/m/d` list-of-floors/rooms and valid empty map behavior | No equivalent | Rust preserves empty-result success and stable invalid-date/auth/upstream errors. |

## SPOC Assignments

| Dimension | `ubaa_old/` evidence | `buaa-api` evidence | Rust behavior / decision |
|---|---|---|---|
| Bootstrap/redirect | `LocalSpocApi.kt` CAS token redirect, `sys/casLogin`, role/token setup | `api/spoc/core.rs` and `opt.rs` CAS and request flow | Route-locked CAS bootstrap; token and role are kept in the operation runtime and never persisted as public data. |
| Methods/parameters/headers | Current term/course GETs; encrypted paginated list POST; detail/submission GET; `Token: Inco-*`, `RoleCode`, XHR | Same SPOC endpoints, request headers and pagination evidence | Rust preserves endpoints, headers, pagination termination, and one forced refresh on business auth failure. |
| Encryption | `LocalSpocSupport.kt` AES-CBC/no-padding and fixed vectors | `spoc/*` crypto/data evidence | Rust AES implementation has the frozen vector test; no key/IV is inferred from another feature. |
| DTO/parser | Old raw assignment/course/detail/submission fields, status/date/HTML normalization | `spoc/data.rs` response types | Stable summaries/detail DTOs preserve empty, unknown status, plain-text HTML and Shanghai time semantics. |
| Cache/concurrency/errors | Per-user client cache, login mutex, page loop, optional submission read | Credential/token refresh and response errors | Rust uses route-scoped runtime state, bounded pagination and deterministic auth/parse/upstream errors; no write API. |

## Judge Assignments

| Dimension | `ubaa_old/` evidence | `buaa-api` evidence | Rust behavior / decision |
|---|---|---|---|
| Bootstrap/redirect | `LocalJudgeApi.kt`, `LocalJudgeRealIntegrationTest.kt`: SSO service to Judge, course list, selected course and assignment pages | No Judge API/module in pinned `examples/buaa-api` | The old local implementation is the only protocol source; absence in examples is recorded, not filled by analogy. |
| Methods/headers/session | Browser GETs, route-local redirects, Judge browser headers; isolated worker Cookie storage and course-selection mutex | Not applicable | Rust follows old Judge URLs/headers, route-locks redirects, isolates worker cookies, and never shares the parent gateway service cookie. |
| Encryption | None | Not applicable | Not applicable. |
| DTO/parser | Old HTML link/detail parsing, submission state and assignment DTOs | Not applicable | Rust sanitized HTML fixtures cover multi-line links, details, missing items and status mapping. |
| Cache/concurrency/cutoff | Per-user/route caches, four-worker bound, six-month historical cutoff, batch order and reactivation tests | Not applicable | Rust keeps these semantics and exposes only read operations. Live WebVPN/auto list/detail evidence exists; Direct remains unavailable. |

## Review rule

Any code review that changes a URL, form field, header, redirect, crypto constant, parser field/type, cache key, concurrency bound, or error mapping must update this matrix and add a source citation or a decision-log conflict. A passing fixture alone cannot close a parity item, and a successful login cannot close a feature item.
