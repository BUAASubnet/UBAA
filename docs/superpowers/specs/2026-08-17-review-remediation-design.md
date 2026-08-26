# Review Remediation Design

Status: implemented historical baseline; superseded for current execution by `2026-08-23-correctness-remediation-design.md` and `goal.md`.

The historical captcha-capable verifier described below is superseded by the
2026-08-25 decision in `docs/migration/decision-log.md`; current code must not
restore challenge, image, prompt, or captcha-specific exit behavior.

## Scope

This change repairs the findings from the post-`goal.md` review without changing verified BUAA protocol facts. Live upstream evidence remains authoritative, followed by the frozen `ubaa_old/` implementation and tests, then `examples/buaa-api/` at the commits in `docs/migration/references.md`.

The historical work covered sensitive formatting, authentication-response classification, Core ownership boundaries, deterministic CLI coverage, session and HTTP hardening, cross-platform CI, error mapping, and documentation consistency. Its former captcha-capable verifier branch is superseded and is not an active requirement.

## Security Boundaries

Types containing credentials, captcha material, cookies, raw HTTP data, or complete profile fields will not expose those values through `Debug`. Custom implementations will report only safe metadata such as field presence, status, lengths, and redacted URLs. Regression tests will format representative values and assert that sentinel secrets are absent.

HTTP response collection will enforce a conservative authentication-response size limit while retaining the existing timeout and TLS behavior. Session persistence will reject unsafe file types, serialize access, use unique exclusively-created temporary files, flush data before replacement, and preserve current-user permissions where the platform supports them.

## Captcha Verification (superseded; historical only)

The requirements in this section belong to the superseded captcha-capable design. They are retained only to explain the frozen baseline; current code must not implement `captcha_required`, challenge/image state, prompts, or a `/dev/tty` fallback. The active contract is the 2026-08-25 non-interactive `upstream_changed` boundary in `goal.md` and `docs/migration/decision-log.md`.

Any older implementation notes below this heading are historical and are not acceptance criteria.

## Core Boundaries

`UbaaClient` remains the only host-facing service. A private client runtime will own connection mode, transport, Cookie jar, persisted session metadata, URL conversion, request execution, and cleanup. Authentication operations will move to `auth`; User Center status/profile operations will move to `features/user`; the facade will delegate and expose stable DTOs.

The public `UbaaClient` type will no longer expose transport and store types as struct generics. Its injected constructor may remain generic for tests, but the concrete facade type will own boxed ports internally.

## Compatibility Decisions

Unauthenticated HTML detection will match the frozen Kotlin implementation with ASCII case-insensitive `DOCTYPE` and `html` prefix checks. Password-risk confirmation failures will use the authentication exit category rather than internal-failure exit 7.

Authentication endpoints remain fixed HTTPS URLs. Redirect resolution will continue accepting the `http` behavior explicitly present in the frozen implementation instead of inventing a new protocol restriction; this compatibility choice will be recorded in the decision log. Secure cookies remain filtered from non-HTTPS requests.

## Tests And CI

Each historical behavioral repair started with a focused failing test. The retained baseline coverage includes redacted formatting, case-insensitive HTML invalidation, password-risk exit mapping, response-size rejection, session file safety, saved-session binary logout, and validation of actual serialized CLI envelopes against the JSON Schema. Interactive verification is now covered only by the non-interactive no-POST rejection contract.

CI will retain deterministic reference and sensitive-data gates on Linux and add Rust build/test coverage for macOS and Windows. Live authentication remains local-only. Setup documentation will list `jq` and terminal requirements for the live verifier.

## Documentation And Delivery

Authentication, connection/session, architecture, testing, runbook, migration status, decision log, and third-party notices will be updated to describe current facts. Changes will be committed in reviewable groups, followed by `just refs`, `just check-sensitive`, `just check`, CLI end-to-end tests, and both live verification modes.
