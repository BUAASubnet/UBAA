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
| Serialized schema checks, cross-platform CI, and locked resolution | `6921562`, `9e4b8e5`, `9cc06f6`, `4388b58` |

## Final verification evidence

The final behavior and test verification target was repository HEAD `4388b58876218f92adf0aa984726386a00bde803`. This status synchronization follows that target as a documentation-only commit. Immediately before the report edit, `git status --short --branch` printed only `## ubaa2` with no changed paths.

| Command | Actual output summary |
|---|---|
| `just refs` | Exit 0; `ubaa_old` verified at `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`; `examples/buaa-api` verified at `efb7976bf513f38364b88aeb83d704586cff9b2a` |
| `just check-sensitive` | Exit 0; 70 tracked repository files passed the sensitive-data scan |
| `just check` | Exit 0; locked metadata, rustfmt, Clippy with warnings denied, 79 Rust tests, one compile-fail doctest, the synthetic live-verifier contract, workspace build, Rustdoc, and diff check passed |
| `cargo test --locked --workspace --all-targets` | Exit 0; 79 passed, 0 failed |
| `cargo test --locked -p ubaa-cli --test binary_e2e` | Exit 0; 9 passed, 0 failed, including tracked-path case and repository command-lock contracts |
| `just verify-live mode=direct` | Exit 0; reached `auth_status`, parsed a user, name prefix `李`, school ID suffix `04` |
| `just verify-live mode=webvpn` | Exit 0; reached `auth_status`, parsed a user, name prefix `李`, school ID suffix `04` |

| Evidence layer | Status | Evidence summary |
|---|---|---|
| Unit and contract | Passed | `ubaa-core` unit/contract/connection/cookie/facade/session suites: 36 passed |
| Sanitized fixture and parser | Passed | Synthetic fixture sentinel checks and CAS/User Center parser cases passed; no live body became a fixture |
| Mock integration | Passed | Authentication workflow: 16 passed; test-support transport/session contracts: 7 passed |
| CLI | Passed | CLI unit: 2 passed; JSON/human contract: 9 passed; real-process binary E2E: 9 passed |
| Live Direct | Passed | Fresh local login, User Center profile parse, and persisted `auth status` passed |
| Live WebVPN | Passed | Fresh local login, User Center profile parse, and persisted `auth status` passed |

The final live runs did not request captcha. The captcha/FIFO/terminal/signal paths passed the deterministic shell contract instead. `.env.local` remained ignored and untracked, and no password, Cookie, raw response, captcha, or complete profile field was recorded.

## Capability status

The repository foundation, public contracts/test support, Direct/WebVPN connection, Cookie/session runtime, SSO state machine, captcha handling, risk continuation, User Center status/profile parsing, logout, and CLI host are complete and deterministic-tested. Coverage includes sensitive `Debug` boundaries, case-insensitive invalidation, HTTP(S)-only redirects, response/session limits, no-follow file access, revision-based stale-writer rejection, actual serialized JSON envelopes, JSON argument failures, facade-only host access, synthetic captcha terminal/signal lifecycle, saved-session binary logout, locked dependency resolution, and macOS/Windows Rust CI.

Two boundaries remain explicit. Windows owner-only ACL enforcement for custom configuration directories requires a release audit. Local revision CAS prevents a stale long-lived client from replacing or deleting a newer session file, but the frozen implementation performs best-effort remote SSO logout before local cleanup and provides no evidence for concurrent remote-session semantics. The CLI loads the snapshot and current revision together when each command opens its client; future long-lived hosts must serialize logout for a shared account until live or frozen evidence supports a stronger contract.

On 2026-08-17, both required live commands passed against the final behavior target with independent temporary sessions. The redacted evidence is recorded above; no complete profile field, password, Cookie, captcha, or raw response was retained.

Flutter, MCP, server relay, Ktor/JWT/Redis, schedule, exams, grades, sign-in, SPOC, Judge, evaluation, classrooms, reservations, and all other business modules remain outside this contract.

## Next slice

The recommended next contract is schedule/exam read support. Begin with the frozen interfaces and implementation in `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/ScheduleApi.kt` and `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalScheduleApi.kt`, map only the fields evidenced by `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/model/dto/Schedule.kt` and `Exam.kt`, and port the behavioral cases from `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalScheduleApiBackendTest.kt` before adding a facade or CLI command.

The old WebVPN login's CGYY-only Direct SSO side session remains intentionally unimplemented. Reassess it only when a CGYY-backed feature is in scope, using `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalConnectionAuth.kt` and `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalAuthServiceBackendTest.kt` as the starting evidence.
