# Core Boundaries

- `domain`: serializable DTOs and value objects only; no HTTP or filesystem access.
- `error`: stable machine codes, categories, retry flags, and safe messages.
- `ports`: raw request/response transport and persistence interfaces. `ReqwestTransport` uses TLS verification and no automatic redirect.
- `connection`: Direct/WebVPN conversion, host allow-list, and redirect resolution.
- `session`: Cookie filtering, restricted `session.json`, and invalidation policy.
- `upstream`: frozen SSO/User Center URLs, HTML form parser, captcha detector, and JSON wrapper parser.
- `auth`: per-client pending execution/challenge state.
- `features/user`: User Center authentication-response classification.
- `facade`: `UbaaClient`, the only host-facing service entry point.

Hosts must not call `upstream` or mutate a Cookie jar directly. Future modules follow the same direction and expose stable DTOs through the facade.
