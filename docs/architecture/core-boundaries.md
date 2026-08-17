# Core Boundaries

- `domain`: serializable DTOs and value objects only; no HTTP or filesystem access.
- `error`: stable machine codes, categories, retry flags, and safe messages.
- `ports`: raw request/response transport. `ReqwestTransport` uses TLS verification, no automatic redirect, and bounded body collection.
- `connection`: Direct/WebVPN conversion, host allow-list, and redirect resolution.
- `session`: the persistence port, Cookie filtering, no-follow file access, revision compare-exchange, atomically replaced `session.json`, and invalidation policy.
- `upstream` (private): frozen SSO/User Center URLs, HTML form parser, captcha detector, and JSON wrapper parser.
- `runtime` (private): mode, boxed transport/store ports, Cookie jar, timestamps/revision, URL conversion, request execution, persistence, and cleanup.
- `auth`: per-client CAS login/captcha/risk/activation/logout workflow and pending challenge state.
- `features/user`: User Center status/profile operations and authentication-response classification.
- `facade`: the concrete `UbaaClient`, containing only construction, persisted-mode opening, and stable host-facing delegation.

Hosts must not call `upstream` or mutate a Cookie jar directly. Future modules follow the same direction and expose stable DTOs through the facade.
