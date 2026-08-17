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
| 4. CLI host | Complete; fixture and binary-tested | `feat: add ubaa authentication cli` |
| 5. Live Direct/WebVPN verification | Not run | Pending |
| 6. Continuous-development readiness | Not implemented | Pending |

## Capability status

The repository foundation, public contracts/test support, Direct/WebVPN connection, Cookie/session runtime, SSO state machine, captcha handling, risk continuation, User Center status/profile parsing, logout, and CLI host are complete and fixture-tested. CLI tests cover human/JSON redaction, stable exits, captcha JSON behavior, secure temporary captcha cleanup, command help, and the missing-session binary path. Live Direct and WebVPN evidence remains pending.

Flutter, MCP, server relay, Ktor/JWT/Redis, schedule, exams, grades, sign-in, SPOC, Judge, evaluation, classrooms, reservations, and all other business modules remain outside this contract.

## Next slice

Phase 5 adds a local-only live verifier, then proves both Direct and WebVPN login, User Center parsing, and persisted-session validation using ignored credentials without retaining sensitive output.
