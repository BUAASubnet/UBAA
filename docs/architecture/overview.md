# Architecture Overview

The current product boundary is a platform-independent Rust Core plus a Rust CLI host. `UbaaClient` owns one connection mode, Cookie jar, persistence port, and CAS login state. Direct and WebVPN URL strategy is applied before every upstream request; the raw transport never follows redirects or owns a global Cookie store.

```text
CLI / future bindings
        |
     facade
        |
 auth + features/user + session
        |
 upstream parsers and verified URLs
        |
 connection + ports (HTTP, persistence)
```

Phase 4 provides the CLI host, JSON schema validation, interactive captcha lifecycle, redacted presentation, and platform-owned session location. Live Direct/WebVPN evidence remains a separate phase 5 gate. Flutter, MCP, server relay, and business APIs are not implemented.
