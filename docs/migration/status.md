# Migration Status

Updated: 2026-08-23

## Conclusion

阶段 7-12 的代码、确定性测试、双源对标文档和真实矩阵已落地；在 2026-08-23 校园网环境的最新重跑中，认证 Direct/WebVPN、六类单项 `auto`、聚合 `all/auto`，以及六类功能的显式 Direct/WebVPN 均 exit 0。SPOC 在三条路线均为真实空列表；没有用 fixture、Mock 或认证成功替代业务验收。此前 Judge 的不可用/上游变化只作为历史失败与重跑条件保留。

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
| 7 route policy | Implemented and deterministic-tested | Three DNS states, 60-second cache, strict TOML v1 config, six matrix rows, hidden CLI override, and common Campus -> Direct / OffCampus -> WebVPN / Unknown -> Direct mapping. Fresh Judge Direct evidence removed the former temporary auto override. |
| 8 dual sessions | Implemented and deterministic-tested | Schema-v2 two-slot persistence, legacy migration, per-route auth/challenge state, partial login, aggregate status, logout of both routes, revision CAS. |
| 9a schedule/exam/grades | Implemented with sanitized fixture and facade Mock coverage; real-verified on Direct/WebVPN/auto | AAS service activation, schedule/exam Referer, weekly form encoding, grades activation GET and `xq/year` POST are asserted. Current required auto runs and explicit Direct/WebVPN exam/grades runs succeeded. |
| 9b classroom | Implemented with sanitized fixture and facade Mock coverage; real-verified on Direct/WebVPN/auto | The CAS sync, query URL and required headers are asserted. All three live routes succeeded with 158 parsed classrooms for the 2026-08-23 default date. |
| 9c SPOC | Implemented with sanitized fixture/Mock coverage; real empty result on Direct/WebVPN/auto | CAS token/role, known AES-CBC vector, one business-auth refresh, pagination, Asia/Shanghai time mapping, detail/submission read and HTML/status mapping pass deterministic tests. All three routes returned a valid empty list; no detail was available to exercise live. |
| 9d Judge | Implemented with sanitized fixture/Mock coverage and four-worker bounds; real-verified on Direct/WebVPN/auto | Business-page redirects use the route-locked redirect helper; workers filter Judge-scoped cookies and independently activate before course selection; detail/batch reads remain bounded at four workers. Campus Direct, WebVPN, and campus `auto` list/detail checks passed on 2026-08-23. |
| 10 CLI/JSON | Implemented and contract-tested | Ordinary help hides `--mode`; feature success/errors use schema v2 with effective policy, DNS state, initial/final route and fallback diagnostics; aggregate login/status expose safe route states. |
| 11 live matrix | Passed on 2026-08-23 campus rerun | Auth Direct/WebVPN; schedule/exam/grades/classroom/SPOC/Judge auto; aggregate `all/auto`; and all six features on explicit Direct/WebVPN have exit-0 evidence. |
| 12 handoff/gates | Ready; final deterministic gates passed | Code fixes `bc45882` and the Judge route correction, verifier fix, source-parity audit, current status/matrix, and decision records are present. Post-commit `just refs`, `just check-sensitive`, and `just check` all exited 0. |

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
| Empty classroom | CAS sync, route-locked headers/query, empty-map parser and CLI implemented | Success, 158 results, exit 0, date `2026-08-23` | Success, 158 results, exit 0, date `2026-08-23` | Success, `result_count=158`, exit 0, date `2026-08-23` | Direct, WebVPN and auto are verified for campus `1` and the current Asia/Shanghai date; rerun with a different campus/date when needed. |
| SPOC assignments/details | CAS token/role, encrypted paginated list, detail, submission status and HTML text implemented | Success, empty list, exit 0 | Success, empty list, exit 0 | Success, `result_count=0`, exit 0 | Empty lists are valid real results on all three routes. A non-empty account should rerun to exercise one detail request. |
| Judge assignments/details | SSO activation, route-locked redirects, isolated workers, HTML parsers, cutoff/cache and detail/batch facade implemented | 2026-08-23 exit 0, 65 assignments plus one detail | 2026-08-23 exit 0, 17 assignments plus one detail | 2026-08-23 exit 0, 65 assignments plus one detail; campus auto resolved to Direct | Historical Direct `upstream_unavailable` and detail `upstream_changed` are retained as failed commands; rerun if upstream list volatility recurs and record the stage. |

The latest required aggregate `just verify-live feature=all route=auto` run on 2026-08-23 exited 0: schedule, exam, grades, classroom, SPOC and Judge each succeeded, and Judge completed one detail. The aggregate used the campus auto route, which now follows Direct for all six features. Earlier attempts failed at Judge list/detail with `timeout` or `upstream_changed`; those failures remain historical rerun evidence, not current route status.

The individual required command summaries were:

```text
schedule auto: exit 0 terms/weeks/current/today parsed
exam auto: exit 0 term selected and exam response parsed
grades auto: exit 0 term selected and score response parsed
classroom auto: exit 0 result_count=158 date=2026-08-23
spoc auto: exit 0 result_count=0
judge auto: exit 0 result_count=65; campus auto resolved to direct and completed one detail
```

Additional explicit-route failure checks:

```text
schedule direct/webvpn: exit 0 terms/weeks/current/today parsed on both routes
exam direct/webvpn: exit 0 on both routes
grades direct/webvpn: exit 0 on both routes
judge direct: exit 0 result_count=65 with list and detail (2026-08-23)
judge webvpn: exit 0 result_count=17 with list and detail (2026-08-23); intermittent timeout/upstream_changed attempts remain historical
```

Additional explicit-route business checks:

```text
classroom direct: exit 0 result_count=158 date=2026-08-23
classroom webvpn: exit 0 result_count=158 date=2026-08-23
spoc direct: exit 0 result_count=0
spoc webvpn: exit 0 result_count=0
judge direct: exit 0 result_count=65 with list and detail in one verifier run
judge webvpn: exit 0 result_count=17 with list and detail in one verifier run
judge auto: exit 0 result_count=65 with list and detail; campus resolved route Direct
judge auto in latest aggregate: exit 0, list plus one detail parsed; campus resolved route Direct
```

The matrix never treats authentication success, an empty fixture, or a Mock response as business-route evidence. Each explicit success above comes from a real verifier business response. The real SPOC empty list is valid empty-result evidence, and Judge now has current Direct, WebVPN, and campus auto list/detail evidence.

## Deterministic Gates

The latest focused runs passed:

- `cargo test --locked --workspace` (all workspace tests passed, including the 21-test read-only suite and verifier regression).
- `cargo clippy --locked --workspace --all-targets -- -D warnings`.
- `cargo test --locked -p ubaa-cli --test binary_e2e` (10 passed).
- `cargo test --locked -p ubaa-test-support --test readonly` (19 passed).
- `cargo test --locked -p ubaa-test-support --test support` (8 passed).
- `./scripts/test-verify-live.sh`.

The final required deterministic gate sequence passed on 2026-08-23 after the AAS/form, Judge route, verifier and documentation changes:

```bash
just refs
just check-sensitive
just check
```

`just refs` exit 0 verified both frozen HEADs; `just check-sensitive` exit 0 scanned 100 repository files; `just check` exit 0 covered locked metadata, format, Clippy, all workspace tests, the synthetic verifier, build, Rustdoc and diff checks.

The required live command sequence was run again on 2026-08-23 after moving Judge back to the common auto route. Auth Direct and WebVPN exited 0. The prior aggregate attempts exposed Judge sampling volatility, so the verifier was covered by a failing shell test, fixed to choose the first returned assignment, and the current aggregate and each individual feature command now pass. The current required results are:

```text
feature=auth route=direct: exit 0
feature=auth route=webvpn: exit 0
feature=all route=auto: exit 0; schedule/exam/grades/classroom/spoc/judge all succeeded; campus auto resolved to Direct
feature=schedule route=auto: exit 0
feature=exam route=auto: exit 0
feature=grades route=auto: exit 0
feature=classroom route=auto: exit 0
feature=spoc route=auto: exit 0; real empty list
feature=judge route=auto: exit 0; result_count=65, list plus one detail; campus auto resolved to Direct
```

Additional explicit-route evidence after the AAS and Judge route fixes: schedule, exam, grades, classroom, SPOC, and Judge each exited 0 on both Direct and WebVPN on 2026-08-23. SPOC returned a valid empty list on each route. Judge Direct and WebVPN each completed one detail; `auto` follows Direct in the current campus DNS state.

CI remains deterministic-only: it does not read `.env.local` or contact live accounts. Sensitive scans must continue to reject passwords, Cookies, tokens, captcha images, raw bodies, and complete personal data.

## Remaining Gaps

- The required aggregate `all/auto` hard gate passed on the latest 2026-08-23 run. All six features have current real list/detail or valid empty-result evidence on Direct, WebVPN, and campus `auto`.
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
6. Re-run `just verify-live feature=all route=auto` when refreshing the complete matrix; the latest required run passed on 2026-08-23.
7. If Judge detail again returns `upstream_changed` or `timeout`, record the exact failed stage and rerun only with a newly returned list item; never reuse a stale assignment ID or fall back across routes.
