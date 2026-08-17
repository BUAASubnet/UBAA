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
| 5. Live Direct/WebVPN verification | Complete; real verification passed | `test: verify live direct and webvpn authentication` |
| 6. Continuous-development readiness | Not implemented | Pending |

## Capability status

The repository foundation, public contracts/test support, Direct/WebVPN connection, Cookie/session runtime, SSO state machine, captcha handling, risk continuation, User Center status/profile parsing, logout, and CLI host are complete and fixture-tested. CLI tests cover human/JSON redaction, stable exits, captcha JSON behavior, secure temporary captcha cleanup, command help, and the missing-session binary path.

On 2026-08-17, both required live commands passed with independent temporary sessions. Direct returned exit 0, parsed a User Center profile, and passed `auth status`; the redacted proof was name prefix `李` and school ID suffix `04`. WebVPN returned the same required success signals and independently passed `auth status`; its proof used the same redacted values. No complete profile field, password, Cookie, captcha, or raw response was retained.

Flutter, MCP, server relay, Ktor/JWT/Redis, schedule, exams, grades, sign-in, SPOC, Judge, evaluation, classrooms, reservations, and all other business modules remain outside this contract.

## Next slice

Phase 6 completes the development/CI documentation, adds deterministic sensitive-data and reference-baseline gates, and reruns the full `just check` plus both live commands before the final report.
