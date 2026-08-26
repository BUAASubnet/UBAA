# Core Boundaries

- `domain`: serializable DTOs and value objects only; no HTTP or filesystem access.
- `error`: stable machine codes, categories, retry flags, and safe messages.
- `ports`: raw request/response transport. `ReqwestTransport` uses TLS verification, no automatic redirect, and bounded body collection.
- `connection`: Direct/WebVPN conversion, host allow-list, redirect resolution, the bounded gateway TCP probe, and process-local probe caching.
- `session`: the persistence port, Cookie filtering, no-follow file access, revision compare-exchange, atomically replaced schema-v2 dual-slot `session.json`, legacy migration, and invalidation policy.
- `upstream` (private): frozen SSO/User Center URLs, HTML form parser, unsupported-interactive-step detector, and JSON wrapper parser.
- `runtime` (private): mode, boxed transport/store ports, Cookie jar, timestamps/revision, URL conversion, request execution, persistence, and cleanup.
- `auth`: per-route CAS login, unsupported-interactive-step rejection, risk/activation/logout workflow, and pending execution state.
- `features/user`: User Center status/profile operations and authentication-response classification; `features/*` contains the six read-only services.
- `facade`: aggregate `UbaaClient`, containing configuration, route resolution, the two private runtimes, the shared dual-session coordinator, and stable host-facing delegation. `RouteClient` is route-locked and diagnostic/test-only.

Hosts must not call `upstream` or mutate a Cookie jar directly. Future modules follow the same direction and expose stable DTOs through the facade.
