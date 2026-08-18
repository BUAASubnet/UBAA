# Architecture Overview

The current product boundary is a platform-independent Rust Core plus a Rust CLI host. `DualUbaaClient` owns independent Direct and `WebVPN` authentication workflows; the route-locked `UbaaClient` facade remains available for diagnostics and feature calls. `UbaaClient::open` selects a route-scoped view over one atomically locked schema-v2 snapshot/revision pair without exposing the session store to hosts. Direct and `WebVPN` URL strategy is applied before every upstream request; the raw transport never follows redirects or owns a global Cookie store.

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

The CLI host reaches Core only through the facade; the `upstream` parser/URL module is crate-private. Actual-envelope JSON schema validation, aggregate schema-v2 login output, argument-error envelopes, interactive captcha lifecycle, redacted presentation, platform-owned revisioned dual sessions, route policy/DNS diagnostics, and the captcha-capable local verifier are implemented. The six business parsers and facade methods have deterministic fixture coverage; real feature evidence remains a separate gate. Flutter, MCP, server relay, and write APIs are not implemented.
