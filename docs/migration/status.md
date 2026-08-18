# Migration Status

Updated: 2026-08-18

## Conclusion

阶段 7-12 的代码、确定性测试和文档骨架已经落地，但本合同不能标记为完成：六类业务要求至少一条真实可用路线且 `auto` 验收通过，目前空闲教室和 SPOC 的 `auto` 达到真实成功，课表、考试、成绩和 Judge 仍有真实失败或未证实路线。没有用 fixture、Mock 或认证成功替代业务验收。

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
| 7 route policy | Implemented and deterministic-tested | Three DNS states, 60-second cache, strict TOML v1 config, six matrix rows, hidden CLI override. Live feature rows remain unverified below. |
| 8 dual sessions | Implemented and deterministic-tested | Schema-v2 two-slot persistence, legacy migration, per-route auth/challenge state, partial login, aggregate status, logout of both routes, revision CAS. |
| 9a schedule/exam/grades | Implemented and parser/Mock-tested | Real auto requests stop at the undergraduate portal probe with `authentication_required`. |
| 9b classroom | Implemented, parser/Mock-tested and real-verified via auto | Real auto query succeeded with 158 parsed classrooms for the 2026-08-18 default date. |
| 9c SPOC | Implemented, parser/Mock-tested, real empty result | CAS token/role, AES-CBC, pagination, detail/submission read and HTML text mapping pass deterministic tests. Auto list succeeds with `result_count=0`; no detail was available to exercise live. |
| 9d Judge | Implemented, parser/Mock-tested | Course selection, detail reads, six-month cutoff, route/session-scoped caches and bounded query constant are implemented. Real auto request fails with `upstream_unavailable`. |
| 10 CLI/JSON | Implemented and contract-tested | Ordinary help hides `--mode`; feature success/errors use schema v2; aggregate login/status expose safe route states. |
| 11 live matrix | Blocked by live business evidence | Required commands were run; failures are recorded in the feature table. |
| 12 handoff/gates | Deterministic gates passed; live handoff blocked | Independent commits `4c4e4f6`, `b4df5cb`, `ad81009`, and `35a3571` contain the route/session, readonly, verifier/docs, and SPOC detail-metadata rounds; live feature hard gates are still failed/unverified. |

## Live Authentication

| Command | Result |
|---|---|
| `just verify-live feature=auth route=direct` | Exit 0; `auth_status`, parsed user present; summary exposed only name prefix `李` and school-id suffix `04`. |
| `just verify-live feature=auth route=webvpn` | Exit 0; `auth_status`, parsed user present; summary exposed only name prefix `李` and school-id suffix `04`. |

These prove only the two authentication routes. They do not prove any business endpoint.

## Read-Only Live Matrix

| Feature | Implemented state | Direct | WebVPN | Auto result | Failure or rerun condition |
|---|---|---|---|---|---|
| Schedule (terms/weeks/current/today) | Core facade, DTOs, portal probe, parsers, CLI and adaptive verifier implemented | Unverified | Unverified | `authentication_required` at `schedule_terms` (exit 3) | Account must have a valid undergraduate portal session/capability; rerun `just verify-live feature=schedule route=auto`. |
| Exam arrangement | Facade/parser/CLI implemented; term is selected from schedule response | Unverified | Unverified | `authentication_required` at shared `schedule_terms` (exit 3) | Same undergraduate portal requirement; rerun `just verify-live feature=exam route=auto`. |
| Grades | Strict `yyyy-yyyy-semester` parser, activation GET, `xq/year` POST, DTO/CLI implemented | Unverified | Unverified | `authentication_required` at shared `schedule_terms` (exit 3) | Provide a supported term and score-portal account; rerun `just verify-live feature=grades route=auto`. |
| Empty classroom | CAS sync, route-locked headers/query, empty-map parser and CLI implemented | Unverified | Unverified | Success, `result_count=158`, exit 0, date `2026-08-18` | Auto is verified for the current network/default campus and date; explicit Direct/WebVPN remain unverified. |
| SPOC assignments/details | CAS token/role, encrypted paginated list, detail, submission status and HTML text implemented | Unverified | Unverified | Success, `result_count=0`, exit 0 | Empty list is a valid real result. A non-empty account should rerun the same command to exercise one detail request; direct/WebVPN remain unverified. |
| Judge assignments/details | SSO activation, course selection, HTML parsers, cutoff/cache and detail/batch facade implemented | Unverified | Unverified | `upstream_unavailable` at `judge` (exit 5) | Requires an available Judge upstream and course access; rerun `just verify-live feature=judge route=auto`. |

Required aggregate command `just verify-live feature=all route=auto` exited 3 with the same per-feature summaries and final `one_or_more_features_failed`.

The individual required command summaries were:

```text
schedule auto: exit 3 authentication_required at schedule_terms
exam auto: exit 3 authentication_required at schedule_terms
grades auto: exit 3 authentication_required at schedule_terms
classroom auto: exit 0 result_count=158 date=2026-08-18
spoc auto: exit 0 result_count=0
judge auto: exit 5 upstream_unavailable
```

Direct and WebVPN columns stay `unverified` unless an explicit route command produces a successful business response. The matrix never treats authentication success, an empty fixture, or a Mock response as business-route evidence.

## Deterministic Gates

The latest focused runs passed:

- `cargo test --locked --workspace`, including 93 tests after the SPOC/Judge Mock additions.
- `cargo clippy --locked --workspace --all-targets -- -D warnings`.
- `cargo test --locked -p ubaa-cli --test binary_e2e` (9 passed).
- `cargo test --locked -p ubaa-test-support --test readonly` (3 passed).
- `./scripts/test-verify-live.sh`.

The final required gate sequence passed on 2026-08-18:

```bash
just refs
just check-sensitive
just check
```

`just refs` exit 0 verified both frozen HEADs; `just check-sensitive` exit 0 scanned 84 repository files; `just check` exit 0 covered locked metadata, format, Clippy, 93 workspace tests, synthetic verifier, build, Rustdoc and diff checks.

CI remains deterministic-only: it does not read `.env.local` or contact live accounts. Sensitive scans must continue to reject passwords, Cookies, tokens, captcha images, raw bodies, and complete personal data.

## Remaining Gaps

- The live hard gate for schedule, exam, grades and Judge is not passed; this is an external protocol/account/network blocker, not a fixture gap.
- Direct and WebVPN business routes are unverified for all six features; classroom and SPOC have real `auto` success.
- `auto` route diagnostics are available inside Core but are not yet included in every human/JSON feature metadata field.
- Judge query execution is serialized by the route-owned runtime; the old concurrency limit is retained as a four-query bound constant, but no parallel transport pool is exposed because Cookie mutation must remain route-locked.
- No write operations were migrated: submission/upload, answers, reservations, attendance, grading changes, or other side effects remain out of scope.
- Windows owner-only directory ACL enforcement remains a release-audit item from the phase 0-6 baseline.

## Rerun Handoff

1. Re-run `just refs`, `just check-sensitive`, and `just check` from a clean implementation tree.
2. With a user known to have undergraduate portal access, rerun schedule, exam and grades auto commands first; record only exit/code/count summaries here.
3. Re-run classroom on explicit Direct/WebVPN routes if those route columns are needed; retain only count/date summaries.
4. Re-run SPOC with an account that has an assignment to exercise the detail path, then test explicit Direct/WebVPN routes.
5. Re-run Judge after confirming upstream availability and course access; do not infer success from an empty fixture.
6. Only after every feature has at least one successful real route and auto evidence should phase 11/12 be marked complete.
