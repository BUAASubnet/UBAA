# UBAA2 Engineering Standards

This document is the repository-wide contract for Rust Core and CLI work. Core owns
protocol facts, routing, session/cookie scope, crypto, parsing, caching and concurrency.
Hosts call only the facade and may not inspect upstream responses or session storage.

Every direct operation must have a source-parity row covering bootstrap and service URLs,
redirect/final URL rules, cookie/session scope, method and exact parameters, headers/body,
crypto/signatures, DTO/parser fields, caching/concurrency, and error/exit semantics. Evidence
order is live upstream observation, frozen `ubaa_old`, then pinned `examples/buaa-api`.
Conflicts are recorded in `docs/migration/decision-log.md`; fields are never guessed.

Feature changes use a failing sanitized fixture or Mock request first, then the smallest
implementation, focused tests, `just check-sensitive`, and `just check`. Sensitive inputs
(`ubaa_old`, `examples`, `.env.local`, sessions, cookies, tokens, captcha images and live
bodies) are read-only and never staged, logged or persisted.

Read operations must be verifiable independently on Direct, WebVPN and auto routes. Live
verification never invokes a write. Every write has deterministic request/parser evidence and
is blocked by default at the CLI with an explicit `--confirm-write` gate; confirmation does
not bypass Core validation or route/session ownership checks.

Stable CLI output is schema version 2: JSON goes only to stdout, diagnostics to stderr, and
exit codes are limited to the documented taxonomy. Human output must not expose credentials,
cookies, raw upstream bodies, complete HTML or captcha data.

Code is organized by domain, ports, connection, session, auth, features, facade, commands,
execution and render. New logic belongs in the smallest owning module; do not extend a
multi-thousand-line host file when a feature module or command helper is appropriate.
