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
| 1. Contracts and test support | Complete | `feat: define core auth contracts and test fixtures` |
| 2. Connection and session runtime | Complete | `feat: add connection and session runtime` |
| 3. SSO and User Center | Not implemented | Pending |
| 4. CLI host | Not implemented | Pending |
| 5. Live Direct/WebVPN verification | Not run | Pending |
| 6. Continuous-development readiness | Not implemented | Pending |

## Capability status

The repository foundation, public contracts/test support, and Direct/WebVPN connection, Cookie and session runtime are complete and fixture-tested. SSO requests, captcha handling, risk continuation, User Center profile retrieval, CLI commands, and live evidence are not yet implemented.

Flutter, MCP, server relay, Ktor/JWT/Redis, schedule, exams, grades, sign-in, SPOC, Judge, evaluation, classrooms, reservations, and all other business modules remain outside this contract.

## Next slice

Phase 3 derives the SSO state machine and User Center behavior from `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalConnectionAuth.kt`, `ubaa_old/server/src/main/kotlin/cn/edu/ubaa/auth/upstream/CasParser.kt`, their auth tests, and `examples/buaa-api/src/api/sso/auth.rs` plus `src/api/user/auth.rs`.
