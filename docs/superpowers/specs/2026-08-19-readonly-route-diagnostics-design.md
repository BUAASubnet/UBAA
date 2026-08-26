# Read-Only Route Diagnostics Design

Date: 2026-08-19

Status: superseded by `2026-08-23-correctness-remediation-design.md`. This file preserves the historical design record; its CLI-owned DNS resolver is not an active contract.

## Scope

Complete the route-diagnostic portion of the existing schema-v2 CLI contract. This change does
not alter route selection, fallback policy, authentication, upstream URLs, request fields, or
business DTOs.

## Ownership

The CLI host owns route diagnostics because it loads `config.toml`, invokes the DNS probe, and
calls `resolve_feature_route`. The Core facade continues to return only the parsed business DTO
and the concrete route used. Putting policy or DNS state in `FeatureResult` would make the facade
invent host-owned facts, while global state would break concurrent command and test isolation.

## Stable Metadata

Every schema-v2 read-only success or error contains:

- `routePolicy`: the effective feature policy after configuration fallback;
- `networkState`: `campus`, `off_campus`, or `unknown`;
- `initialRoute`: the route selected before any permitted fallback;
- `resolvedRoute`: the route actually used or required for the request;
- `usedFallback`: whether another ready route replaced the initial route;
- `feature`: the stable read-only feature name.

Explicit `direct` and `webvpn` policies do not execute DNS, so their `networkState` is `unknown`.
The value means "not probed or indeterminate" and must not be interpreted as off-campus.

## Data Flow

`main.rs` resolves one feature to `RouteResolution` and converts it to an immutable CLI route
context. The context is passed with the parsed command into the existing CLI runner. Success and
post-resolution errors are rendered from the same context. If the selected session slot is
missing, the host renders a schema-v2 read-only error with that context instead of falling back to
the legacy schema-v1 startup envelope.

Injected CLI tests may construct a route context directly. Legacy authentication and user-info
commands retain their current envelopes because this design is limited to the six read-only
features.

## Error Handling

Route resolution/configuration failures that occur before a valid resolution exists retain the
safe startup error contract; they cannot report an invented route diagnostic. Once resolution
succeeds, all later read-only failures use schema v2 and contain the verified context. No error
includes Cookies, credentials, response bodies, URLs, tokens, captcha bytes, or personal data.

## Schema And Compatibility

The schema-v2 read-only branch requires all six metadata fields. Existing schema-v1 authentication
compatibility remains unchanged. Aggregate authentication metadata remains unchanged because it
represents two routes and has no single feature DNS decision.

## Tests

Tests must first fail against the current implementation, then cover:

1. A read-only success reports a non-auto explicit policy and all diagnostic fields.
2. A read-only business error reports the same diagnostic fields.
3. A resolved feature with no selected session emits schema v2 rather than schema v1.
4. JSON Schema accepts the new valid envelopes and rejects missing or invalid diagnostic fields.
5. Existing CLI, schema, route-policy, sensitive-output, and binary E2E suites remain green.

## Non-Goals

- Adding fallback behavior not already supported by `FeatureRouteConfig`.
- Changing the six feature matrix rows or their evidence status.
- Modifying authentication envelopes or exposing internal URLs.
- Treating DNS `unknown` as proof of either campus or off-campus connectivity.
