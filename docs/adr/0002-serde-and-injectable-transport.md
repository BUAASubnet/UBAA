# ADR 0002: Serde Contracts and Injectable Raw Transport

Date: 2026-08-17

Status: accepted

The Core contract uses `serde` and `serde_json` because the frozen User Center protocol is a JSON `code/data` wrapper and the CLI must expose a versioned JSON envelope. Rust field names stay idiomatic while explicit camelCase renames preserve the CLI contract and `schoolid` is retained as a compatibility alias from the legacy DTO.

Authentication code consumes an injectable raw `HttpTransport` instead of a client with implicit redirects or cookies. This lets tests assert exact request URLs and response shapes while the Core owns redirect policy, Cookie filtering, and session invalidation. `async-trait` keeps the port object-safe for CLI and deterministic Mock transports. The production transport is added in the connection phase.
