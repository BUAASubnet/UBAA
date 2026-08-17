# Architecture Overview

The current product boundary is a platform-independent Rust Core plus a Rust CLI host. The concrete `UbaaClient` facade owns a private authentication workflow and private runtime. The runtime owns one connection mode, transport port, Cookie jar, persistence port, and session timestamps. Direct and WebVPN URL strategy is applied before every upstream request; the raw transport never follows redirects or owns a global Cookie store.

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

The CLI host, actual-envelope JSON schema validation, interactive captcha lifecycle, redacted presentation, platform-owned session location, and captcha-capable local verifier are implemented. Direct and WebVPN live authentication both passed on 2026-08-17; deterministic tests and live evidence remain separate gates. Flutter, MCP, server relay, and business APIs are not implemented.
