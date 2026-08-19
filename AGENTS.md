# UBAA 2 Agent Guide

## Authority

`goal.md` is the active execution contract. `UBAA2.md` describes the longer migration roadmap. Authentication protocol facts must come from live upstream evidence, then the frozen `ubaa_old/` implementation and tests, then `examples/buaa-api/` at the commits recorded in `docs/migration/references.md`.

## Safety boundaries

- Treat `ubaa_old/`, `examples/`, `.env.local`, runtime sessions, captcha images, and live responses as read-only sensitive inputs.
- Never commit credentials, cookies, tokens, raw live bodies, complete personal data, or captcha images.
- Never disable TLS verification or infer an upstream field or URL without evidence.
- Do not expose `upstream` internals to hosts; hosts use the `facade` API.

## Development loop

1. Run `git status --short --branch` and `just refs`.
2. Update `docs/migration/status.md` and decision records with current facts.
3. Add one failing behavior test and observe the expected failure.
4. Implement the smallest change, run the focused test, then `just check`.
5. Inspect staged files for sensitive material and keep each phase in a separate commit.

## Project map

- `crates/ubaa-core`: domain, ports, session, connection, authentication, upstream parsing, and facade.
- `crates/ubaa-test-support`: sanitized fixtures and deterministic test transports.
- `apps/ubaa-cli`: human and JSON command-line host.
- `fixtures/auth`: sanitized protocol fixtures only.
- `docs/contracts`: stable public and CLI contracts.
- `docs/migration`: evidence, status, and decision history.
- `scripts`: reference and live-verification gates.

## Completion gate

Run `just refs`, `just check-sensitive`, `just check`, CLI end-to-end tests, `just verify-live mode=direct`, and `just verify-live mode=webvpn`. Fixture or mock success does not establish live protocol success. CI runs the deterministic gates only and never receives live credentials.

## Mandatory source-parity gate

Every authentication or read-only feature change must be behaviorally compared against both frozen sources before production code is changed:

- `ubaa_old/` at the commit in `docs/migration/references.md`, including its API interface, DTO, local implementation, and tests;
- `examples/buaa-api/` at the pinned commit, including the nearest equivalent API module, request/redirect code, data model, crypto, cookie/credential store, and error handling.

The comparison must be recorded in `docs/migration/source-parity.md` or a linked decision record. It must cover, separately for each operation: business CAS/bootstrap URL and service parameter, redirect and final-URL rules, Cookie/session scope, HTTP method and exact parameters, headers and body encoding, encryption/signature constants, DTO and parser fields/types, caching/concurrency, and error/exit semantics. “Authentication succeeded” or “the endpoint looks similar” is not evidence for any omitted column.

If one reference does not implement the same upstream protocol, record that fact and do not borrow its URL, fields, encryption, or errors by analogy. If sources conflict, stop the implementation at that boundary, capture the concrete files/commits and live observation in `docs/migration/decision-log.md`, then choose only the behavior supported by live evidence or the applicable frozen local implementation. Never fill an unproven field or parameter from memory.

The required TDD loop for parity gaps is: add a sanitized fixture/Mock request or parser test that fails for the missing behavior, run it and retain the failure evidence, implement the smallest reference-backed change, rerun the focused test, then run `just check-sensitive` and `just check` before the phase commit. Do not stage `ubaa_old/`, `examples/`, `.env.local`, raw responses, cookies, tokens, captcha data, or personal data while recording the comparison.
