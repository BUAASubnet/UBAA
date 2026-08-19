# Migration Status

Updated: 2026-08-19

## Conclusion

阶段 7-12 的代码、确定性测试、双源对标文档和当前真实矩阵已落地；在 2026-08-19 的最新重跑中，六类单项 `auto` 与聚合 `all/auto` 均 exit 0。Judge Direct 仍未验证，按合同保留为未验证路线；没有用 fixture、Mock 或认证成功替代业务验收。

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
| 9a schedule/exam/grades | Implemented with sanitized fixture and facade Mock coverage; real-verified on Direct/WebVPN/auto | AAS service activation, schedule/exam Referer, weekly form encoding, grades activation GET and `xq/year` POST are asserted. Current required auto runs and explicit Direct/WebVPN exam/grades runs succeeded. |
| 9b classroom | Implemented with sanitized fixture and facade Mock coverage; real-verified on Direct/WebVPN/auto | The CAS sync, query URL and required headers are asserted. All three live routes succeeded with 158 parsed classrooms for the 2026-08-19 default date. |
| 9c SPOC | Implemented with sanitized fixture/Mock coverage; real empty result on Direct/WebVPN/auto | CAS token/role, known AES-CBC vector, one business-auth refresh, pagination, Asia/Shanghai time mapping, detail/submission read and HTML/status mapping pass deterministic tests. All three routes returned a valid empty list; no detail was available to exercise live. |
| 9d Judge | Implemented with sanitized fixture/Mock coverage and four-worker bounds; live route remains volatile | Business-page redirects use the route-locked redirect helper; workers filter Judge-scoped cookies and independently activate before course selection; detail/batch reads remain bounded at four workers. Earlier WebVPN/auto list/detail successes remain evidence, while the latest required auto attempts failed at detail with `upstream_changed`. |
| 10 CLI/JSON | Implemented and contract-tested | Ordinary help hides `--mode`; feature success/errors use schema v2 with effective policy, DNS state, initial/final route and fallback diagnostics; aggregate login/status expose safe route states. |
| 11 live matrix | Live matrix passed on latest required rerun | Auth Direct/WebVPN; schedule/exam/grades/classroom/SPOC/Judge auto; aggregate `all/auto`; and explicit schedule/exam/grades Direct/WebVPN all have exit-0 evidence. Judge Direct remains unverified and is not required as the feature's only successful route. |
| 12 handoff/gates | Ready pending final deterministic gate rerun | Code fix `bc45882`, verifier fix, source-parity audit, current status/matrix, and decision records are present. Final `just refs`, `just check-sensitive`, and `just check` must be rerun after documentation changes. |

## Live Authentication

| Command | Result |
|---|---|
| `just verify-live feature=auth route=direct` | Exit 0; `auth_status` parsed user present; no personal fields persisted in this report. |
| `just verify-live feature=auth route=webvpn` | Exit 0; `auth_status` parsed user present; no personal fields persisted in this report. |

These prove only the two authentication routes. They do not prove any business endpoint.

## Read-Only Live Matrix

| Feature | Implemented state | Direct | WebVPN | Auto result | Failure or rerun condition |
|---|---|---|---|---|---|
| Schedule (terms/weeks/current/today) | Core facade, DTOs, AAS portal activation, parsers, CLI and adaptive verifier implemented | Success: exit 0; terms, weeks, current and today parsed | Success: exit 0; terms, weeks, current and today parsed | Success: exit 0; terms, weeks, current and today parsed | Re-run when refreshing term/week evidence; the prior failure was the missing AAS activation/form header and is fixed in `bc45882`. |
| Exam arrangement | Facade/parser/CLI implemented; term is selected from schedule response | Success: exit 0 | Success: exit 0 | Success: exit 0 | Re-run with the same verifier prerequisites; no unsupported-account state observed. |
| Grades | Strict `yyyy-yyyy-semester` parser, activation GET, form `xq/year` POST, DTO/CLI implemented | Success: exit 0 | Success: exit 0 | Success: exit 0 | Re-run with the returned term; no unsupported-account state observed. |
| Empty classroom | CAS sync, route-locked headers/query, empty-map parser and CLI implemented | Success, 158 results, exit 0, date `2026-08-19` | Success, 158 results, exit 0, date `2026-08-19` | Success, `result_count=158`, exit 0, date `2026-08-19` | Direct, WebVPN and auto are verified for the current campus/date; rerun with a different campus/date when needed. |
| SPOC assignments/details | CAS token/role, encrypted paginated list, detail, submission status and HTML text implemented | Success, empty list, exit 0 | Success, empty list, exit 0 | Success, `result_count=0`, exit 0 | Empty lists are valid real results on all three routes. A non-empty account should rerun to exercise one detail request. |
| Judge assignments/details | SSO activation, route-locked redirects, isolated workers, HTML parsers, cutoff/cache and detail/batch facade implemented | Not verified; earlier explicit Direct attempt was `upstream_unavailable` (exit 5) | Success evidence exists from explicit WebVPN runs | Latest required auto run exit 0, list plus one detail parsed; aggregate auto also exit 0 | Direct remains unverified/unavailable. Re-run only when Direct evidence is needed; do not treat a list-only or fixture result as completion. |

The latest required aggregate `just verify-live feature=all route=auto` run exited 0: schedule, exam, grades, classroom, SPOC and Judge each succeeded, and Judge completed one detail. Earlier attempts failed at Judge list/detail with `timeout` or `upstream_changed`; those failures remain historical evidence, while this required exit-0 run closes the aggregate gate.

The individual required command summaries were:

```text
schedule auto: exit 0 terms/weeks/current/today parsed
exam auto: exit 0 term selected and exam response parsed
grades auto: exit 0 term selected and score response parsed
classroom auto: exit 0 result_count=158 date=2026-08-19
spoc auto: exit 0 result_count=0
judge auto: latest formal exit 0 result_count=17; auto resolved to webvpn and completed one detail
```

Additional explicit-route failure checks:

```text
schedule direct/webvpn: exit 0 terms/weeks/current/today parsed on both routes
exam direct/webvpn: exit 0 on both routes
grades direct/webvpn: exit 0 on both routes
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
judge auto in latest aggregate: exit 0, list plus one detail parsed; resolved route WebVPN
```

The matrix never treats authentication success, an empty fixture, or a Mock response as business-route evidence. Each explicit success above comes from a real verifier business response. The real SPOC empty list is valid empty-result evidence; Judge Direct remains explicitly unverified.

## Deterministic Gates

The latest focused runs passed:

- `cargo test --locked --workspace` (all workspace tests passed, including the 21-test read-only suite and verifier regression).
- `cargo clippy --locked --workspace --all-targets -- -D warnings`.
- `cargo test --locked -p ubaa-cli --test binary_e2e` (10 passed).
- `cargo test --locked -p ubaa-test-support --test readonly` (19 passed).
- `cargo test --locked -p ubaa-test-support --test support` (8 passed).
- `./scripts/test-verify-live.sh`.

The final required deterministic gate sequence passed on 2026-08-19 after the AAS/form, Judge verifier and documentation changes:

```bash
just refs
just check-sensitive
just check
```

`just refs` exit 0 verified both frozen HEADs; `just check-sensitive` exit 0 scanned 100 repository files; `just check` exit 0 covered locked metadata, format, Clippy, all workspace tests, the synthetic verifier, build, Rustdoc and diff checks.

The required live command sequence was also run on 2026-08-19. Auth Direct and WebVPN exited 0. The first aggregate attempt exposed Judge sampling volatility, so the verifier was covered by a failing shell test, fixed to choose the first returned assignment, and rerun. The final required results were:

```text
feature=auth route=direct: exit 0
feature=auth route=webvpn: exit 0
feature=all route=auto: exit 0; schedule/exam/grades/classroom/spoc/judge all succeeded
feature=schedule route=auto: exit 0
feature=exam route=auto: exit 0
feature=grades route=auto: exit 0
feature=classroom route=auto: exit 0
feature=spoc route=auto: exit 0; real empty list
feature=judge route=auto: exit 0; list plus one detail
```

Additional explicit-route evidence after the AAS fix: schedule, exam and grades each exited 0 on both Direct and WebVPN. Classroom and SPOC retain earlier explicit-route successes. Judge Direct remains an explicitly unverified route after an upstream-unavailable attempt; the matrix has a real WebVPN route and an auto WebVPN override.

CI remains deterministic-only: it does not read `.env.local` or contact live accounts. Sensitive scans must continue to reject passwords, Cookies, tokens, captcha images, raw bodies, and complete personal data.

## Remaining Gaps

- The required aggregate `all/auto` hard gate passed on the latest run. Judge Direct remains unverified after an earlier `upstream_unavailable` result; WebVPN and auto have real list/detail success. Classroom and SPOC have real success on both explicit routes and `auto`.
- Schema-v2 JSON carries effective policy, DNS state, initial/final route and fallback diagnostics; human output continues to show the concrete route without exposing internal protocol details.
- Judge list and batch-detail queries now use route-locked read-only workers with an actual four-request semaphore; each worker filters Judge-scoped Cookies, independently activates the route, and never persists authentication state.
- No write operations were migrated: submission/upload, answers, reservations, attendance, grading changes, or other side effects remain out of scope.
- Windows owner-only directory ACL enforcement remains a release-audit item from the phase 0-6 baseline.

## Rerun Handoff

1. Re-run `just refs`, `just check-sensitive`, and `just check` from a clean implementation tree.
2. Re-run schedule, exam and grades Direct/WebVPN/auto commands when refreshing evidence; record only exit/code/count summaries here.
3. Re-run classroom on a requested campus/date if the existing 158-result Direct/WebVPN/auto evidence is stale.
4. Re-run SPOC with an account that has an assignment to exercise the detail path; the current Direct/WebVPN/auto runs are valid empty-list evidence.
5. Re-run Judge WebVPN/auto when refreshing evidence; record both list and one current detail, and do not infer success from an empty fixture or a stale ID.
6. Re-run `just verify-live feature=all route=auto` when refreshing the complete matrix; the latest required run already passed.
7. Keep Judge Direct marked unverified until a real Direct list plus detail run succeeds; this does not invalidate the currently verified WebVPN/auto route.
