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
