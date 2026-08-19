# Migration Status

Updated: 2026-08-19

## Conclusion

阶段 7-12 的代码、确定性测试和文档骨架已经落地，但本合同不能标记为完成：六类业务要求至少一条真实可用路线且 `auto` 验收通过，目前空闲教室和 SPOC 的 Direct/WebVPN/`auto` 均达到真实成功，课表、考试、成绩和 Judge 仍有真实失败或未证实路线。没有用 fixture、Mock 或认证成功替代业务验收。

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
| 7 route policy | Implemented and deterministic-tested | Three DNS states, 60-second cache, strict TOML v1 config, six matrix rows, hidden CLI override. Remaining live gaps are recorded below. |
| 8 dual sessions | Implemented and deterministic-tested | Schema-v2 two-slot persistence, legacy migration, per-route auth/challenge state, partial login, aggregate status, logout of both routes, revision CAS. |
| 9a schedule/exam/grades | Implemented with sanitized fixture and facade Mock coverage | Every schedule/exam read, schedule/exam route-specific Referer, grades activation GET and `xq/year` POST are asserted. Real auto requests still stop at the undergraduate portal probe with `authentication_required`. |
| 9b classroom | Implemented with sanitized fixture and facade Mock coverage; real-verified on Direct/WebVPN/auto | The CAS sync, query URL and required headers are asserted. All three live routes succeeded with 158 parsed classrooms for the 2026-08-19 default date. |
| 9c SPOC | Implemented with sanitized fixture/Mock coverage; real empty result on Direct/WebVPN/auto | CAS token/role, known AES-CBC vector, one business-auth refresh, pagination, Asia/Shanghai time mapping, detail/submission read and HTML/status mapping pass deterministic tests. All three routes returned a valid empty list; no detail was available to exercise live. |
| 9d Judge | Implemented with sanitized fixture/Mock coverage and four-worker bounds | Course selection, one business-page reactivation, detail reads, WebVPN batch gateway routing, six-month cutoff/skip and include-expired recovery, empty batch, stable not-found errors, route/session-scoped caches and actual four-worker course/detail query bounds are implemented. Real routes remain blocked by Judge upstream errors. |
| 10 CLI/JSON | Implemented and contract-tested | Ordinary help hides `--mode`; feature success/errors use schema v2 with effective policy, DNS state, initial/final route and fallback diagnostics; aggregate login/status expose safe route states. |
| 11 live matrix | Blocked by live business evidence | Required commands were run; failures are recorded in the feature table. |
| 12 handoff/gates | Deterministic gates passed; live handoff blocked | Independent commits `4c4e4f6`, `b4df5cb`, `ad81009`, `35a3571`, `014bf24`, `8425d2c`, `a5f76bf`, `ef99b57`, and `034fcde` contain the route/session, readonly, verifier/docs, SPOC detail-metadata, bounded Judge worker, route-diagnostic, fixture/Mock, route/error-contract, and SPOC-semantics rounds; live feature hard gates are still failed. |

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
| Judge assignments/details | SSO activation, course selection, HTML parsers, cutoff/cache and detail/batch facade implemented | `upstream_unavailable` (exit 5) | `upstream_changed` (exit 6) | `upstream_unavailable` at `judge` (exit 5) | Requires Judge TLS/upstream availability and course access; rerun Direct/WebVPN/auto Judge commands. |

Required aggregate command `just verify-live feature=all route=auto` exited 3 with the same per-feature summaries and final `one_or_more_features_failed`.

The individual required command summaries were:

```text
schedule auto: exit 3 authentication_required at schedule_terms
exam auto: exit 3 authentication_required at schedule_terms
grades auto: exit 3 authentication_required at schedule_terms
classroom auto: exit 0 result_count=158 date=2026-08-19
spoc auto: exit 0 result_count=0
judge auto: exit 5 upstream_unavailable
```

Additional explicit-route failure checks:

```text
schedule direct/webvpn: exit 3 authentication_required at schedule_terms
exam direct/webvpn: exit 3 authentication_required at schedule_terms
grades direct/webvpn: exit 3 authentication_required at schedule_terms
judge direct: exit 5 upstream_unavailable
judge webvpn: exit 6 upstream_changed
```

Additional explicit-route business checks:

```text
classroom direct: exit 0 result_count=158 date=2026-08-19
classroom webvpn: exit 0 result_count=158 date=2026-08-19
spoc direct: exit 0 result_count=0
spoc webvpn: exit 0 result_count=0
```

Direct and WebVPN columns stay `unverified` unless an explicit route command produces a successful business response. The matrix never treats authentication success, an empty fixture, or a Mock response as business-route evidence. Classroom and SPOC explicit-route summaries above are from real verifier runs.

## Deterministic Gates

The latest focused runs passed:

- `cargo test --locked --workspace`, including 110 tests after the complete read-only fixture/Mock, route/error-contract, SPOC semantics and Judge boundary additions.
- `cargo clippy --locked --workspace --all-targets -- -D warnings`.
- `cargo test --locked -p ubaa-cli --test binary_e2e` (10 passed).
- `cargo test --locked -p ubaa-test-support --test readonly` (16 passed).
- `cargo test --locked -p ubaa-test-support --test support` (8 passed).
- `./scripts/test-verify-live.sh`.

The final required gate sequence passed on 2026-08-19:

```bash
just refs
just check-sensitive
just check
```

`just refs` exit 0 verified both frozen HEADs; `just check-sensitive` exit 0 scanned 99 repository files; `just check` exit 0 covered locked metadata, format, Clippy, 110 workspace tests, synthetic verifier, build, Rustdoc and diff checks.

CI remains deterministic-only: it does not read `.env.local` or contact live accounts. Sensitive scans must continue to reject passwords, Cookies, tokens, captcha images, raw bodies, and complete personal data.

## Remaining Gaps

- The live hard gate for schedule, exam, grades and Judge is not passed; this is an external protocol/account/network blocker, not a fixture gap.
- Direct and WebVPN business routes have failed evidence for schedule, exam, grades and Judge; classroom and SPOC have real success on both explicit routes and `auto`.
- Schema-v2 JSON carries effective policy, DNS state, initial/final route and fallback diagnostics; human output continues to show the concrete route without exposing internal protocol details.
- Judge list and batch-detail queries now use route-locked read-only workers with an actual four-request semaphore; each worker copies the route Cookie jar and never persists authentication state.
- No write operations were migrated: submission/upload, answers, reservations, attendance, grading changes, or other side effects remain out of scope.
- Windows owner-only directory ACL enforcement remains a release-audit item from the phase 0-6 baseline.

## Rerun Handoff

1. Re-run `just refs`, `just check-sensitive`, and `just check` from a clean implementation tree.
2. With a user known to have undergraduate portal access, rerun schedule, exam and grades Direct/WebVPN/auto commands first; record only exit/code/count summaries here.
3. Re-run classroom on a requested campus/date if the existing 158-result Direct/WebVPN/auto evidence is stale.
4. Re-run SPOC with an account that has an assignment to exercise the detail path; the current Direct/WebVPN/auto runs are valid empty-list evidence.
5. Re-run Judge Direct/WebVPN/auto after confirming Judge TLS/upstream availability and course access; do not infer success from an empty fixture.
6. Only after every feature has at least one successful real route and auto evidence should phase 11/12 be marked complete.
