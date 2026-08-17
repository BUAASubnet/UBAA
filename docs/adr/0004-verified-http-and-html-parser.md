# ADR 0004: Verified HTTP and HTML Parsing Dependencies

Date: 2026-08-17

Status: accepted

`reqwest` is the production raw HTTP transport because the fixed Rust reference already uses it and it provides TLS verification, bounded timeouts, request headers and response status/body access. Automatic redirects and its Cookie store are disabled so Core policy remains auditable. The default TLS verifier is never bypassed.

`scraper` parses CAS HTML selectors for hidden fields, checkbox state, button filtering, errors, and execution. `regex` is limited to the observed JavaScript `config.captcha` declaration because that value is not an HTML element. `base64` creates the ephemeral captcha image data URL required by `LoginChallenge`; it is never written to a session file. `tokio` supplies the async timer/runtime compatibility used by host tests and the transport ecosystem.
