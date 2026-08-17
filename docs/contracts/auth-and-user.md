# Authentication and User Contract

Status: design contract; implementation proceeds in phases 1 through 4.

Each `UbaaClient` owns one Direct or WebVPN session. It prepares a CAS login, submits credentials once, surfaces captcha challenges, follows audited allowed redirects, continues one recognized password-risk form, activates User Center, validates `uc/status`, parses `uc/userinfo`, and clears local state on logout or explicit invalidation.

Stable DTOs and error codes are defined by `goal.md` section 6. The CLI JSON contract uses camelCase profile fields, schema version 1, stable error codes, and redacted sensitive values. Passwords never enter persisted sessions or normal output.

