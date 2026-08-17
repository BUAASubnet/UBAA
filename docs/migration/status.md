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
| HTTP(S)-only authentication redirects and JSON argument envelopes | `c6a7f6a`, `c04914d` |
| Concrete facade, private runtime/upstream, and workflow ownership | `deb5d9d`, `ee8a3d5`, `63db7d3` |
| Bounded HTTP responses, no-follow session access, and revision CAS | `b2f2bfd`, `01ef2b8`, `bd11829` |
| Captcha-capable verifier, terminal lifecycle, and binary logout coverage | `4452a16`, `10ca988`, `ec5be94`, `a892e47` |
| Serialized schema checks, cross-platform CI, and locked resolution | `6921562`, `9e4b8e5` |

## Capability status

The repository foundation, public contracts/test support, Direct/WebVPN connection, Cookie/session runtime, SSO state machine, captcha handling, risk continuation, User Center status/profile parsing, logout, and CLI host are complete and deterministic-tested. Coverage includes sensitive `Debug` boundaries, case-insensitive invalidation, HTTP(S)-only redirects, response/session limits, no-follow file access, revision-based stale-writer rejection, actual serialized JSON envelopes, JSON argument failures, facade-only host access, synthetic captcha terminal/signal lifecycle, saved-session binary logout, locked dependency resolution, and macOS/Windows Rust CI.

Two boundaries remain explicit. Windows owner-only ACL enforcement for custom configuration directories requires a release audit. Local revision CAS prevents a stale long-lived client from replacing or deleting a newer session file, but the frozen implementation performs best-effort remote SSO logout before local cleanup and provides no evidence for concurrent remote-session semantics. The CLI loads the snapshot and current revision together when each command opens its client; future long-lived hosts must serialize logout for a shared account until live or frozen evidence supports a stronger contract.

On 2026-08-17, both required live commands passed with independent temporary sessions. Direct returned exit 0, parsed a User Center profile, and passed `auth status`; the redacted proof was name prefix `李` and school ID suffix `04`. WebVPN returned the same required success signals and independently passed `auth status`; its proof used the same redacted values. No complete profile field, password, Cookie, captcha, or raw response was retained.

Flutter, MCP, server relay, Ktor/JWT/Redis, schedule, exams, grades, sign-in, SPOC, Judge, evaluation, classrooms, reservations, and all other business modules remain outside this contract.

## Next slice

The recommended next contract is schedule/exam read support. Begin with the frozen interfaces and implementation in `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/ScheduleApi.kt` and `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalScheduleApi.kt`, map only the fields evidenced by `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/model/dto/Schedule.kt` and `Exam.kt`, and port the behavioral cases from `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalScheduleApiBackendTest.kt` before adding a facade or CLI command.

The old WebVPN login's CGYY-only Direct SSO side session remains intentionally unimplemented. Reassess it only when a CGYY-backed feature is in scope, using `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalConnectionAuth.kt` and `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalAuthServiceBackendTest.kt` as the starting evidence.
