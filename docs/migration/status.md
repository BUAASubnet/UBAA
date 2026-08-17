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
| 0. Repository foundation | Complete | `chore: establish ubaa2 repository foundation` |
| 1. Contracts and test support | Not implemented | Pending |
| 2. Connection and session runtime | Not implemented | Pending |
| 3. SSO and User Center | Not implemented | Pending |
| 4. CLI host | Not implemented | Pending |
| 5. Live Direct/WebVPN verification | Not run | Pending |
| 6. Continuous-development readiness | Not implemented | Pending |

## Capability status

The repository foundation is complete and its phase gates pass. Authentication, Direct/WebVPN runtime behavior, captcha handling, risk continuation, persisted sessions, User Center profile retrieval, CLI commands, and live evidence are not yet implemented.

Flutter, MCP, server relay, Ktor/JWT/Redis, schedule, exams, grades, sign-in, SPOC, Judge, evaluation, classrooms, reservations, and all other business modules remain outside this contract.

## Next slice

Phase 1 derives DTO and error behavior from `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/model/dto/Auth.kt`, `UserInfo.kt`, and the public contract in `goal.md`, then introduces sanitized fixtures and test transport support before production behavior.
