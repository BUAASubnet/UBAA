# ADR 0004: Verified HTTP and HTML Parsing Dependencies

Date: 2026-08-17

Status: accepted

`reqwest` is the production raw HTTP transport because the fixed Rust reference already uses it and it provides TLS verification, bounded timeouts, request headers and response status/body access. Automatic redirects and its Cookie store are disabled so Core policy remains auditable. The default TLS verifier is never bypassed.

`scraper` parses CAS HTML selectors for hidden fields, checkbox state, button filtering, errors, and execution. `regex` is used only for small, evidence-backed business-page patterns (for example Judge links and SPOC score text); it is not used to implement an interactive login protocol. `base64` is retained for the frozen SPOC read-only request protocol, not authentication or image material. `tokio` supplies the async timer/runtime compatibility used by host tests and the transport ecosystem.
