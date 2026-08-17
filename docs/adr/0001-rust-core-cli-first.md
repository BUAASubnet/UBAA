# ADR 0001: Rust Core and CLI First

Date: 2026-08-17

Status: accepted

UBAA 2 places protocol correctness in a platform-independent Rust core and uses a Rust CLI as the first host and integration harness. The KMP application and Ktor relay remain frozen references, not runtime dependencies. This keeps Direct/WebVPN authentication, Cookie handling, redirects, parsing, and stable errors consistent across future hosts.

Flutter bindings, MCP, server relay, and business APIs are deferred. A host consumes stable facade DTOs and does not reach into upstream implementation modules.

