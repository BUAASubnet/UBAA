# Authentication and User Contract

Status: phases 1 through 4 implemented and fixture-tested; live Direct/WebVPN evidence remains phase 5.

Each `UbaaClient` owns one Direct or WebVPN session. It prepares a CAS login, submits credentials once, surfaces captcha challenges, follows audited allowed redirects, continues one recognized password-risk form, activates User Center, validates `uc/status`, parses `uc/userinfo`, and clears local state on logout or explicit invalidation.

Stable DTOs and error codes are defined by `goal.md` section 6. The CLI JSON contract uses camelCase profile fields, schema version 1, stable error codes, and redacted sensitive values. Passwords never enter persisted sessions or normal output.

Phase 1 provides `ConnectionMode`, `LoginInput`, `LoginChallenge`, `UserProfile`, `UserInfoResponse`, `SecretValue`, stable `UbaaError`/`ErrorCode`/`ExitCode`, and `JsonEnvelope<T>`. Phase 3 adds the `UbaaClient` facade, `prepare_login`, `login`, `auth_status`, `get_user_info`, and `logout` over an injectable raw transport. The state machine follows the frozen CAS form, captcha config, one-time password-risk continuation, manual redirects, User Center activation, status validation, and profile `code/data` parsing. WebVPN mode applies URL conversion to every authentication request and redirect.

The WebVPN login does not establish the old CGYY-only direct SSO side session. CGYY is outside this contract; the omission is recorded for a future feature slice.

## CLI host

The `ubaa` binary exposes `auth login`, `auth status`, `auth logout`, and `user show`. Login requires an explicit Direct or WebVPN mode. Human mode can prompt for the username, uses hidden password entry unless `--password-stdin` is selected, and writes a captcha image to a mode-0600 temporary file that is deleted after input. JSON mode never performs hidden interaction; a missing captcha returns `captcha_required` with no image data and exit code 4.

`--json` writes exactly one versioned envelope to stdout for command success or failure. Phone and identity-document values are masked before human or JSON rendering. `--config-dir` selects the directory containing `session.json`; otherwise the platform user configuration directory is used. Commands that require authentication reject a missing local session before making a network request, while `auth status` still validates an existing session against User Center before reporting success.

The stable exit categories are 0 for success, 2 for invalid input, 3 for authentication, 4 for captcha required, 5 for network/availability errors, 6 for upstream contract or parsing changes, and 7 for internal failures. `docs/contracts/cli-json.schema.json` is exercised by CLI contract tests.
