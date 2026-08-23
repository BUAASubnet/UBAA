# Route Policy Contract

Status: implemented with deterministic DNS/config/session coverage; live feature evidence is recorded in `docs/migration/readonly-feature-matrix.md`.

`RoutePolicy` is the host-facing choice (`auto`, `direct`, or `webvpn`). `ConnectionMode` is the internal resolved route. Ordinary CLI help does not expose `--mode`; the hidden override is retained only for deterministic tests, live verification, and diagnostics.

## Configuration

`config.toml` is owner-readable and contains no account, password, Cookie, CAS execution, captcha, token, or response body:

```toml
schema_version = 1

[route]
default = "auto"

[route.features]
schedule = "auto"
exam = "auto"
grades = "auto"
classroom = "auto"
spoc = "auto"
judge = "auto"
```

Unknown fields, feature names, versions other than `1`, and route values outside the three registered values are rejected as `invalid_input`. A missing file uses `auto`.

## DNS resolution

`SystemDnsProbe` resolves `gw.buaa.edu.cn` with a 500 ms bound. At least one resolved address is `Campus`, an authoritative no-record result is `OffCampus`, and timeout or other resolver failure is `Unknown`. The current-process cache is 60 seconds and is injectable in tests. No IP range is hard-coded and no credential is read by the probe.

`Campus` resolves `auto` to Direct; `OffCampus` resolves it to WebVPN. `Unknown` uses the feature row's `unknown_default` and remains visible in `RouteDiagnostic`. All six feature rows currently use this common mapping with `unknown_default=Direct`; fresh campus live evidence now proves Judge on Direct as well as WebVPN, so no feature-specific auto override remains. Explicit routes do not fallback.

The initial matrix sets both ready-route and network-error fallback to false for every operation. This is deliberate: a feature may be retried on the other route only after its frozen implementation and live evidence establish that the operation is idempotent and safe to replay.

Schema-v2 read-only CLI successes and post-resolution errors expose the same safe diagnostic
metadata: `routePolicy`, `networkState`, `initialRoute`, `resolvedRoute`, `usedFallback`, and
`feature`. Explicit Direct/WebVPN policies do not run the DNS probe, so their `networkState` is
`unknown`; this means "not probed or indeterminate", not off-campus. The host passes the immutable
`RouteResolution` into rendering, while the facade remains responsible only for business DTOs and
the concrete route it used.

## Session slots

`session.json` schema version 2 stores independent `direct` and `webvpn` slots under one file lock and revision CAS. `RouteSessionStore` gives each runtime a route-local view while preserving the shared revision. A legacy single snapshot migrates only to its recorded `mode` slot; Cookies are never copied to the other slot. Challenge/execution state remains in memory.

`DualUbaaClient` prepares and submits Direct then WebVPN with independent `AuthWorkflow` and Cookie/runtime state. A failed second route produces a `partial` `LoginOutcome` and leaves the first slot intact. Aggregate JSON exposes only route state, stable error fields, challenge ID, and image availability.
