# Authentication and User Contract

Status: implementation, deterministic coverage, and live Direct/WebVPN verification complete on 2026-08-17.

Each `UbaaClient` owns one Direct or WebVPN session. It prepares a CAS login, submits credentials once, surfaces captcha challenges, follows audited allowed redirects, continues one recognized password-risk form, activates User Center, validates `uc/status`, parses `uc/userinfo`, and clears local state on logout or explicit invalidation.

Stable DTOs and error codes are defined by `goal.md` section 6. The CLI JSON contract uses camelCase profile fields, schema version 1, stable error codes, and redacted sensitive values. Passwords never enter persisted sessions or normal output.

The public `UbaaClient` is a concrete facade with `open`, `prepare_login`, `login`, `auth_status`, `get_user_info`, and `logout`. `open` selects an explicit mode or the mode in the atomically loaded persisted session, so hosts never inspect storage internals. Its private runtime owns the injected transport/session ports, connection mode, Cookie jar, timestamps, and loaded session revision. The `auth` module owns the CAS form, captcha, one-time password-risk continuation, activation, redirect, and logout workflow; `features/user` owns User Center status/profile operations and invalidation classification. WebVPN mode applies URL conversion to every authentication request and redirect.

Every runtime persistence mutation compare-exchanges the loaded revision. A conflict clears that client's in-memory Cookie and pending login state, leaves the newer persisted session untouched, and returns retryable `internal_error` so a long-lived host can rebuild the client from current state. Best-effort remote logout remains before local cleanup because that order is evidenced by the frozen implementation. Hosts sharing one account across long-lived clients must serialize logout; no unsupported remote-session concurrency guarantee is implied.

The WebVPN login does not establish the old CGYY-only direct SSO side session. CGYY is outside this contract; the omission is recorded for a future feature slice.

## CLI host

The `ubaa` binary exposes `auth login`, `auth status`, `auth logout`, and `user show`. Login uses an explicit Direct or WebVPN mode, or reuses the mode from an existing persisted session; when neither exists it returns `invalid_input` before a network request. Human mode can prompt for the username, uses hidden password entry unless `--password-stdin` is selected, and writes a captcha image to a mode-0600 temporary file that is deleted after non-empty input is collected in the same process. JSON mode never performs hidden interaction; a missing captcha returns `captcha_required` with no image data and exit code 4.

`--json` writes exactly one versioned envelope to stdout for command success, command failure, or argument-parse failure; help and version retain their normal text behavior. Invalid argument text is reduced to the safe `invalid_input` envelope rather than echoed with caller-supplied values. Phone and identity-document values are masked before human or JSON rendering. `--config-dir` selects the directory containing `session.json`; otherwise the platform user configuration directory is used. Commands that require authentication reject a missing local session before making a network request, while `auth status` still validates an existing session against User Center before reporting success.

The stable exit categories are 0 for success, 2 for invalid input, 3 for authentication (including rejected password-risk continuation), 4 for captcha required, 5 for network/availability errors, 6 for upstream contract or parsing changes, and 7 for internal failures. `docs/contracts/cli-json.schema.json` is exercised against actual serialized success and failure envelopes.
