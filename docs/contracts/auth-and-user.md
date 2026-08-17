# Authentication and User Contract

Status: phases 1 through 3 implemented and fixture-tested; CLI host remains phase 4 and live evidence remains phase 5.

Each `UbaaClient` owns one Direct or WebVPN session. It prepares a CAS login, submits credentials once, surfaces captcha challenges, follows audited allowed redirects, continues one recognized password-risk form, activates User Center, validates `uc/status`, parses `uc/userinfo`, and clears local state on logout or explicit invalidation.

Stable DTOs and error codes are defined by `goal.md` section 6. The CLI JSON contract uses camelCase profile fields, schema version 1, stable error codes, and redacted sensitive values. Passwords never enter persisted sessions or normal output.

Phase 1 provides `ConnectionMode`, `LoginInput`, `LoginChallenge`, `UserProfile`, `UserInfoResponse`, `SecretValue`, stable `UbaaError`/`ErrorCode`/`ExitCode`, and `JsonEnvelope<T>`. Phase 3 adds the `UbaaClient` facade, `prepare_login`, `login`, `auth_status`, `get_user_info`, and `logout` over an injectable raw transport. The state machine follows the frozen CAS form, captcha config, one-time password-risk continuation, manual redirects, User Center activation, status validation, and profile `code/data` parsing. WebVPN mode applies URL conversion to every authentication request and redirect.

The WebVPN login does not establish the old CGYY-only direct SSO side session. CGYY is outside this contract; the omission is recorded for a future feature slice.
