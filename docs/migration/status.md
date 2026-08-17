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
| 3. SSO and User Center | Complete | `feat: implement direct and webvpn sso authentication` |
| 4. CLI host | Not implemented | Pending |
| 5. Live Direct/WebVPN verification | Not run | Pending |
| 6. Continuous-development readiness | Not implemented | Pending |

## Capability status

The repository foundation, public contracts/test support, Direct/WebVPN connection, Cookie/session runtime, SSO state machine, captcha handling, risk continuation, User Center status/profile parsing, and logout are complete and fixture-tested. The CLI host and live evidence remain pending.

Flutter, MCP, server relay, Ktor/JWT/Redis, schedule, exams, grades, sign-in, SPOC, Judge, evaluation, classrooms, reservations, and all other business modules remain outside this contract.

## Next slice

Phase 4 builds the CLI over `ubaa-core/src/facade`, with JSON/exit behavior fixed by `goal.md` sections 6 and 7. It must not expose `upstream` or password values.
