# Authentication and User Contract

Status: implementation, deterministic coverage, and live Direct/WebVPN verification complete on 2026-08-17.

`UbaaClient` is the route-locked compatibility facade; production opening uses a route-scoped view over schema-v2's shared Direct/`WebVPN` file. `DualUbaaClient` is the ordinary aggregate login facade: it prepares and submits Direct then `WebVPN` with independent Cookie, CAS and captcha state, and returns `all_ready`, `partial`, or `none_ready` without discarding a successful slot.

Stable DTOs and error codes are defined by `goal.md` section 6. The CLI JSON contract uses camelCase profile fields, schema version 1, stable error codes, and redacted sensitive values. Passwords never enter persisted sessions or normal output.

The public facades expose authentication and the six read-only feature methods while keeping transports, session stores, and upstream parsers private to Core. `open` selects an explicit route or a configured/diagnosed route slot; hosts never inspect storage internals. The `auth` module owns the CAS form, captcha, one-time password-risk continuation, activation, redirect, and logout workflow; `features/user` owns User Center status/profile operations and invalidation classification. `WebVPN` mode applies URL conversion to every authentication request and redirect.

Every runtime persistence mutation compare-exchanges the loaded revision. A conflict clears that client's in-memory Cookie and pending login state, leaves the newer persisted session untouched, and returns retryable `internal_error` so a long-lived host can rebuild the client from current state. Best-effort remote logout remains before local cleanup because that order is evidenced by the frozen implementation. Hosts sharing one account across long-lived clients must serialize logout; no unsupported remote-session concurrency guarantee is implied.

The WebVPN login does not establish the old CGYY-only direct SSO side session. CGYY is outside this contract; the omission is recorded for a future feature slice.

## CLI host

The `ubaa` binary exposes authentication, User Center, and all six read-only command groups. Ordinary `auth login` attempts both routes; the hidden `--mode` override remains only for tests/live diagnostics. Human mode can prompt for the username, uses hidden password entry unless `--password-stdin` is selected, and writes a captcha image to a mode-0600 temporary file that is deleted after non-empty input is collected in the same process. JSON mode never performs hidden interaction; a missing route captcha returns schema-v2 aggregate `captcha_required` with only challenge ID/image availability and exit code 4.

`--json` writes exactly one versioned envelope to stdout for command success, command failure, or argument-parse failure; help and version retain their normal text behavior. Invalid argument text is reduced to the safe `invalid_input` envelope rather than echoed with caller-supplied values. Phone and identity-document values are masked before human or JSON rendering. `--config-dir` selects the directory containing `session.json`; otherwise the platform user configuration directory is used. Commands that require authentication reject a missing local session before making a network request, while `auth status` still validates an existing session against User Center before reporting success.

The stable exit categories are 0 for success, 2 for invalid input, 3 for authentication (including rejected password-risk continuation), 4 for captcha required, 5 for network/availability errors, 6 for upstream contract or parsing changes, and 7 for internal failures. `docs/contracts/cli-json.schema.json` is exercised against actual serialized success and failure envelopes.
