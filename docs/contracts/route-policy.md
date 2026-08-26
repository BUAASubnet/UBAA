# Route Policy Contract

Status: implemented deterministically; current Direct/WebVPN/auto live evidence is tracked separately in `docs/migration/status.md`.

`RoutePolicy` is the host-facing choice (`auto`, `direct`, or `webvpn`). `ConnectionMode` is the internal resolved route. Ordinary CLI help does not expose `--mode`; the hidden override is retained only for deterministic tests, live verification, and diagnostics.

## Configuration

`config.toml` is owner-readable and contains no account, password, Cookie, CAS execution, interactive verification material, token, or response body:

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

Config load/save rejects symlink and non-regular targets. Writes use unique exclusively-created same-directory temporary files and atomic replacement; Unix deterministic tests cover concurrent writers and owner-only directory/file modes. This is local safety evidence and does not establish a live route.

## Gateway reachability

The injectable production probe tests TCP connectivity to `gw.buaa.edu.cn:80`. One 500 ms deadline covers hostname resolution and every resolved-address connection attempt; the implementation must pass only the remaining budget to each attempt. Any successful connection is `Campus`. Resolution failure, no addresses, refused/unreachable connections, and ordinary timeout are `OffCampus`. Only an internal probe failure, including a deliberately injected diagnostic failure, is `Unknown`.

The result is single-flight cached by the aggregate Core facade for 60 seconds in the current process; the probe, clock, and cache behavior are injectable in tests. The CLI owns no resolver or cache. The probe sends no HTTP or TLS request, reads no credential, and hard-codes neither an address nor an IP range. This target/port/duration comes from `examples/buaa-api/src/utils/net.rs`; the single total budget and `Unknown` boundary are UBAA 2 product constraints.

`Campus` resolves `auto` to Direct; `OffCampus` resolves it to WebVPN. `Unknown` uses the feature row's `unknown_default` and remains visible in `RouteDiagnostic`. All six feature rows use this common mapping with `unknown_default=Direct`; historical Judge commands reached both routes, so no feature-specific auto override is justified, but their count/detail semantic difference remains unresolved. Explicit routes do not fallback.

The initial matrix sets both ready-route and network-error fallback to false for every operation. This is deliberate: a feature may be retried on the other route only after its frozen implementation and live evidence establish that the operation is idempotent and safe to replay. The corrected 2026-08-26 live matrix passed its latest complete aggregates, but it does not establish safe cross-route replay and therefore authorizes neither fallback nor a feature override.

Schema-v2 read-only CLI successes and post-resolution errors expose the same safe diagnostic
metadata: `routePolicy`, `networkState`, `initialRoute`, `resolvedRoute`, `usedFallback`, and
`feature`. Explicit Direct/WebVPN policies do not run the gateway probe, so their `networkState` is
`unknown`; this means "not probed or indeterminate", not off-campus. The host passes the immutable
diagnostic returned by the facade into rendering. The Core facade owns config loading, probe caching,
route resolution, readiness preflight and business execution; a host cannot reconstruct or override
ordinary route selection. The hidden explicit mode remains a separate diagnostic/test entry point.
Hidden SPOC/Judge diagnostic commands also call the facade and expose only the safe metadata
documented in `readonly-features.md`; they do not move route ownership back to the CLI.

## Session slots

`session.json` schema version 2 stores independent `direct` and `webvpn` slots under one file lock and revision CAS. One aggregate coordinator owns the complete snapshot and revision while private runtimes receive route-local state. A legacy single snapshot migrates only to its recorded `mode` slot; Cookies are never copied to the other slot. Execution and other transient login state remain in memory.

The ordinary `UbaaClient` aggregate facade prepares and submits Direct then WebVPN with independent private `AuthWorkflow` and Cookie/runtime state. A failed second route produces a `partial` `LoginOutcome` and leaves the first slot intact. Aggregate JSON exposes only route state and stable error fields. Interactive verification pages produce `upstream_changed`; no challenge or image is exposed.
