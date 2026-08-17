# Migration Status

Updated: 2026-08-17

## Baseline

- New repository branch: `ubaa2`; no pre-existing commit at phase 0 start.
- UBAA v1 reference: `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`.
- `buaa-api` reference: `efb7976bf513f38364b88aeb83d704586cff9b2a`.
- Both reference worktrees were clean and matched their expected origins.

## Phase status

| Phase | Status | Commit |
|---|---|---|
| 0. Repository foundation | Complete | `dbc3acb` |
| 1. Contracts and test support | Complete | `f9640b0` |
| 2. Connection and session runtime | Complete | `ff99b57` |
| 3. SSO and User Center | Complete | `90fb1ef` |
| 4. CLI host | Complete; fixture and binary-tested | `a27fdf0` |
| 5. Live Direct/WebVPN verification | Complete; real verification passed | `ed085f2` |
| 6. Continuous-development readiness | Complete; docs, CI, baseline and sensitive gates added | `a81c3d6` |

## Review remediation

The post-goal review was resolved in independently auditable commits:

| Area | Commit |
|---|---|
| Sensitive runtime and CLI diagnostics | `048c4fd`, `016b6a9` |
| Authentication classification and exit semantics | `cdc150a` |
| Concrete facade, private runtime, and workflow ownership | `deb5d9d`, `ee8a3d5` |
| Bounded HTTP responses and hardened session persistence | `b2f2bfd` |
| Captcha-capable live verifier and binary logout process coverage | `4452a16`, `10ca988` |
| Serialized schema checks and macOS/Windows Rust CI | `6921562` |

## Capability status

The repository foundation, public contracts/test support, Direct/WebVPN connection, Cookie/session runtime, SSO state machine, captcha handling, risk continuation, User Center status/profile parsing, logout, and CLI host are complete and deterministic-tested. Coverage includes sensitive `Debug` boundaries, case-insensitive invalidation, response/session limits, symlink and concurrent-save safety, actual serialized JSON envelopes, synthetic captcha fallback, saved-session binary logout, and macOS/Windows Rust CI. The Windows owner-only ACL audit for custom configuration directories remains explicit rather than silently claimed complete.

On 2026-08-17, both required live commands passed with independent temporary sessions. Direct returned exit 0, parsed a User Center profile, and passed `auth status`; the redacted proof was name prefix `李` and school ID suffix `04`. WebVPN returned the same required success signals and independently passed `auth status`; its proof used the same redacted values. No complete profile field, password, Cookie, captcha, or raw response was retained.

Flutter, MCP, server relay, Ktor/JWT/Redis, schedule, exams, grades, sign-in, SPOC, Judge, evaluation, classrooms, reservations, and all other business modules remain outside this contract.

## Next slice

The recommended next contract is schedule/exam read support. Begin with the frozen interfaces and implementation in `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/ScheduleApi.kt` and `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalScheduleApi.kt`, map only the fields evidenced by `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/model/dto/Schedule.kt` and `Exam.kt`, and port the behavioral cases from `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalScheduleApiBackendTest.kt` before adding a facade or CLI command.

The old WebVPN login's CGYY-only Direct SSO side session remains intentionally unimplemented. Reassess it only when a CGYY-backed feature is in scope, using `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalConnectionAuth.kt` and `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalAuthServiceBackendTest.kt` as the starting evidence.
