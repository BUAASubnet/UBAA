# Migration Status

Updated: 2026-08-19

## Conclusion

阶段 7-12 的代码、确定性测试和文档骨架已经落地，但本合同不能标记为完成：六类业务要求至少一条真实可用路线且 `auto` 验收通过，目前空闲教室、SPOC 和 Judge 的 `auto` 均达到真实成功，Judge 的显式 WebVPN 也已重复验证；课表、考试和成绩仍被本科门户能力阻断。没有用 fixture、Mock 或认证成功替代业务验收。

## Baseline

- Branch: `ubaa2`.
- Frozen `ubaa_old/` HEAD: `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`.
- Frozen `examples/buaa-api/` HEAD: `efb7976bf513f38364b88aeb83d704586cff9b2a`.
- `just refs` verifies both clean reference worktrees and fixed HEADs.
- `.env.local` was checked for the two required variable names and non-empty values; values were never printed, logged, staged, or persisted.
- The user-edited `goal.md` remains outside implementation commits.

## Phase Status

| Phase | Status | Evidence or remaining gate |
|---|---|---|
| 0-6 baseline | Preserved | Existing commits and reference checks remain intact. |
| 7 route policy | Implemented and deterministic-tested | Three DNS states, 60-second cache, strict TOML v1 config, six matrix rows, hidden CLI override, and the live-evidence Judge `auto -> WebVPN` feature override. Remaining live gaps are recorded below. |
| 8 dual sessions | Implemented and deterministic-tested | Schema-v2 two-slot persistence, legacy migration, per-route auth/challenge state, partial login, aggregate status, logout of both routes, revision CAS. |
| 9a schedule/exam/grades | Implemented with sanitized fixture and facade Mock coverage | Every schedule/exam read, schedule/exam route-specific Referer, grades activation GET and `xq/year` POST are asserted. Real auto requests still stop at the undergraduate portal probe with `authentication_required`. |
| 9b classroom | Implemented with sanitized fixture and facade Mock coverage; real-verified on Direct/WebVPN/auto | The CAS sync, query URL and required headers are asserted. All three live routes succeeded with 158 parsed classrooms for the 2026-08-19 default date. |
| 9c SPOC | Implemented with sanitized fixture/Mock coverage; real empty result on Direct/WebVPN/auto | CAS token/role, known AES-CBC vector, one business-auth refresh, pagination, Asia/Shanghai time mapping, detail/submission read and HTML/status mapping pass deterministic tests. All three routes returned a valid empty list; no detail was available to exercise live. |
| 9d Judge | Implemented with sanitized fixture/Mock coverage and four-worker bounds; real-verified on WebVPN/auto | Business-page redirects use the route-locked redirect helper; workers filter Judge-scoped cookies and independently activate before course selection; detail/batch reads remain bounded at four workers. Explicit WebVPN and auto both produced real successful list/detail responses. |
| 10 CLI/JSON | Implemented and contract-tested | Ordinary help hides `--mode`; feature success/errors use schema v2 with effective policy, DNS state, initial/final route and fallback diagnostics; aggregate login/status expose safe route states. |
| 11 live matrix | Partially improved; still blocked by live business evidence | Judge WebVPN and auto have real successes after the redirect/session fix; schedule/exam/grades remain account-blocked. |
| 12 handoff/gates | Deterministic gates passed; live handoff blocked | Earlier independent rounds through `22b8d6f`, followed by `a177960` (Judge redirect/session isolation, route matrix and verifier sample), `880b002` (live evidence/status docs), and `7584811` (route decision record), are independently committed; live feature hard gates are still failed. |

## Live Authentication

| Command | Result |
|---|---|
| `just verify-live feature=auth route=direct` | Exit 0; `auth_status`, parsed user present; summary exposed only name prefix `李` and school-id suffix `04`. |
| `just verify-live feature=auth route=webvpn` | Exit 0; `auth_status`, parsed user present; summary exposed only name prefix `李` and school-id suffix `04`. |

These prove only the two authentication routes. They do not prove any business endpoint.

## Read-Only Live Matrix

| Feature | Implemented state | Direct | WebVPN | Auto result | Failure or rerun condition |
|---|---|---|---|---|---|
| Schedule (terms/weeks/current/today) | Core facade, DTOs, portal probe, parsers, CLI and adaptive verifier implemented | Failed: `authentication_required` at `schedule_terms` (exit 3) | Failed: `authentication_required` at `schedule_terms` (exit 3) | `authentication_required` at `schedule_terms` (exit 3) | Account must have a valid undergraduate portal session/capability; rerun Direct/WebVPN/auto schedule commands. |
| Exam arrangement | Facade/parser/CLI implemented; term is selected from schedule response | Failed: shared `schedule_terms` `authentication_required` (exit 3) | Failed: shared `schedule_terms` `authentication_required` (exit 3) | `authentication_required` at shared `schedule_terms` (exit 3) | Same undergraduate portal requirement; rerun Direct/WebVPN/auto exam commands. |
| Grades | Strict `yyyy-yyyy-semester` parser, activation GET, `xq/year` POST, DTO/CLI implemented | Failed: shared `schedule_terms` `authentication_required` (exit 3) | Failed: shared `schedule_terms` `authentication_required` (exit 3) | `authentication_required` at shared `schedule_terms` (exit 3) | Provide a supported term and score-portal account; rerun Direct/WebVPN/auto grades commands. |
| Empty classroom | CAS sync, route-locked headers/query, empty-map parser and CLI implemented | Success, 158 results, exit 0, date `2026-08-19` | Success, 158 results, exit 0, date `2026-08-19` | Success, `result_count=158`, exit 0, date `2026-08-19` | Direct, WebVPN and auto are verified for the current campus/date; rerun with a different campus/date when needed. |
| SPOC assignments/details | CAS token/role, encrypted paginated list, detail, submission status and HTML text implemented | Success, empty list, exit 0 | Success, empty list, exit 0 | Success, `result_count=0`, exit 0 | Empty lists are valid real results on all three routes. A non-empty account should rerun to exercise one detail request. |
| Judge assignments/details | SSO activation, route-locked redirects, isolated workers, HTML parsers, cutoff/cache and detail/batch facade implemented | `upstream_unavailable` (exit 5) | Success: exit 0, `result_count=17` on 2026-08-19; repeated upstream timeouts also observed | Repeated success: latest formal run exit 0, `result_count=17`; earlier successful runs returned `65` standalone and `161` in aggregate. All resolved to WebVPN and completed one latest-assignment detail | WebVPN and auto are verified. Direct remains unavailable; live counts are response-dependent and an intervening aggregate attempt returned `upstream_changed` at detail. |

The latest aggregate `just verify-live feature=all route=auto` run completed Judge list/detail with `result_count=161`, then exited 3 because schedule, exam and grades returned `authentication_required`; classroom and SPOC also succeeded. An immediately preceding aggregate run reached Judge detail but returned `upstream_changed`, demonstrating the live list/detail volatility without changing the verified WebVPN route.

The individual required command summaries were:

```text
schedule auto: exit 3 authentication_required at schedule_terms
exam auto: exit 3 authentication_required at schedule_terms
grades auto: exit 3 authentication_required at schedule_terms
classroom auto: exit 0 result_count=158 date=2026-08-19
spoc auto: exit 0 result_count=0
judge auto: latest formal exit 0 result_count=17; auto resolved to webvpn and completed one detail
```

Additional explicit-route failure checks:

```text
schedule direct/webvpn: exit 3 authentication_required at schedule_terms
exam direct/webvpn: exit 3 authentication_required at schedule_terms
grades direct/webvpn: exit 3 authentication_required at schedule_terms
judge direct: exit 5 upstream_unavailable
judge webvpn: exit 0 result_count=17 (reverified 2026-08-19); intermittent timeout attempts were also recorded
```

Additional explicit-route business checks:

```text
classroom direct: exit 0 result_count=158 date=2026-08-19
classroom webvpn: exit 0 result_count=158 date=2026-08-19
spoc direct: exit 0 result_count=0
spoc webvpn: exit 0 result_count=0
judge webvpn: exit 0 result_count=17 with list and detail in one verifier run
judge auto: latest formal exit 0 result_count=17 with list and detail; earlier standalone success returned 65; resolved route WebVPN
judge auto in latest aggregate: exit 0 result_count=161 with list and detail; resolved route WebVPN
```

The matrix never treats authentication success, an empty fixture, or a Mock response as business-route evidence. Each explicit success above comes from a real verifier business response; Judge WebVPN remains valid evidence even though later upstream attempts timed out.

## Deterministic Gates

The latest focused runs passed:

- `cargo test --locked --workspace`, including 114 tests after the complete read-only fixture/Mock, route/error-contract, SPOC semantics, Judge redirect/session isolation and route-matrix additions.
- `cargo clippy --locked --workspace --all-targets -- -D warnings`.
- `cargo test --locked -p ubaa-cli --test binary_e2e` (10 passed).
- `cargo test --locked -p ubaa-test-support --test readonly` (19 passed).
- `cargo test --locked -p ubaa-test-support --test support` (8 passed).
- `./scripts/test-verify-live.sh`.

The final required gate sequence passed on 2026-08-19 after the Judge fix and evidence-documentation commits:

```bash
just refs
just check-sensitive
just check
```

`just refs` exit 0 verified both frozen HEADs; `just check-sensitive` exit 0 scanned 99 repository files; `just check` exit 0 covered locked metadata, format, Clippy, 114 workspace tests, synthetic verifier, build, Rustdoc and diff checks.

CI remains deterministic-only: it does not read `.env.local` or contact live accounts. Sensitive scans must continue to reject passwords, Cookies, tokens, captcha images, raw bodies, and complete personal data.

## Remaining Gaps

- The live hard gate for schedule, exam and grades is not passed because of account capability failures. This is not a fixture gap.
- Judge explicit WebVPN and auto now have real list/detail successes; Direct remains unavailable. Classroom and SPOC have real success on both explicit routes and `auto`.
- Schema-v2 JSON carries effective policy, DNS state, initial/final route and fallback diagnostics; human output continues to show the concrete route without exposing internal protocol details.
- Judge list and batch-detail queries now use route-locked read-only workers with an actual four-request semaphore; each worker filters Judge-scoped Cookies, independently activates the route, and never persists authentication state.
- No write operations were migrated: submission/upload, answers, reservations, attendance, grading changes, or other side effects remain out of scope.
- Windows owner-only directory ACL enforcement remains a release-audit item from the phase 0-6 baseline.

## Rerun Handoff

1. Re-run `just refs`, `just check-sensitive`, and `just check` from a clean implementation tree.
2. With a user known to have undergraduate portal access, rerun schedule, exam and grades Direct/WebVPN/auto commands first; record only exit/code/count summaries here.
3. Re-run classroom on a requested campus/date if the existing 158-result Direct/WebVPN/auto evidence is stale.
4. Re-run SPOC with an account that has an assignment to exercise the detail path; the current Direct/WebVPN/auto runs are valid empty-list evidence.
5. Re-run Judge WebVPN/auto when refreshing evidence; record both list and a current latest-assignment detail, and do not infer success from an empty fixture or a stale first list item.
6. Only after schedule, exam and grades obtain a successful real route and auto evidence should phase 11/12 be marked complete.
