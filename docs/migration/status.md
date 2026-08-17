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
| 6. Continuous-development readiness | Complete; docs, CI, baseline and sensitive gates added | `docs: make ubaa2 ready for continuous development` |

## Capability status

The repository foundation, public contracts/test support, Direct/WebVPN connection, Cookie/session runtime, SSO state machine, captcha handling, risk continuation, User Center status/profile parsing, logout, and CLI host are complete and fixture-tested. CLI tests cover human/JSON redaction, stable exits, captcha JSON and same-process human input behavior, saved-mode reuse, secure temporary captcha cleanup, command help, and missing-session binary paths.

On 2026-08-17, both required live commands passed with independent temporary sessions. Direct returned exit 0, parsed a User Center profile, and passed `auth status`; the redacted proof was name prefix `李` and school ID suffix `04`. WebVPN returned the same required success signals and independently passed `auth status`; its proof used the same redacted values. No complete profile field, password, Cookie, captcha, or raw response was retained.

Flutter, MCP, server relay, Ktor/JWT/Redis, schedule, exams, grades, sign-in, SPOC, Judge, evaluation, classrooms, reservations, and all other business modules remain outside this contract.

## Next slice

The recommended next contract is schedule/exam read support. Begin with the frozen interfaces and implementation in `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/ScheduleApi.kt` and `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalScheduleApi.kt`, map only the fields evidenced by `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/model/dto/Schedule.kt` and `Exam.kt`, and port the behavioral cases from `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalScheduleApiBackendTest.kt` before adding a facade or CLI command.

The old WebVPN login's CGYY-only Direct SSO side session remains intentionally unimplemented. Reassess it only when a CGYY-backed feature is in scope, using `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalConnectionAuth.kt` and `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalAuthServiceBackendTest.kt` as the starting evidence.
