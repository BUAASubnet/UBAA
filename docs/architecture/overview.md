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

Phase 3 is the first usable authentication loop. The CLI, JSON schema validation, and live Direct/WebVPN evidence are separate gates. Flutter, MCP, server relay, and business APIs are not implemented.
