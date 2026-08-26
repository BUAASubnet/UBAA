# Architecture Overview

The current product boundary is a platform-independent Rust Core plus a Rust CLI host. `UbaaClient` is the ordinary aggregate facade: it owns validated route configuration, the cached gateway-reachability probe, independent Direct and WebVPN runtimes, and one atomic dual-session coordinator. `UbaaClient::open` loads both slots from one revisioned schema-v2 snapshot without exposing the session store to hosts. `RouteClient` is a route-locked diagnostic/test entry point, not the ordinary host API. Direct and WebVPN URL strategy is applied before every upstream request; the raw transport never follows redirects or owns a global Cookie store.

```text
CLI / future bindings
        |
  concrete facade
        |
 auth + features/user
        |
 private runtime + session
        |
 upstream parsers and verified URLs
        |
 connection + ports (HTTP, persistence)
```

The CLI host reaches Core only through the facade; the `upstream` parser/URL module is crate-private. Actual-envelope JSON schema validation, aggregate schema-v2 login output, argument-error envelopes, explicit rejection of unsupported interactive login steps, redacted presentation, atomic revisioned dual sessions, Core-owned TCP route diagnostics, and the non-interactive local verifier are implemented. The six business parsers and facade methods have deterministic fixture coverage; current Direct/WebVPN/auto evidence remains a separate live gate. Flutter, MCP, server relay, and write APIs are not implemented.
