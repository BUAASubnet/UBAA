# Read-Only Route Diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Emit the effective route policy and complete DNS/route/fallback diagnostics in every post-resolution schema-v2 read-only CLI success and error.

**Architecture:** `main.rs` remains the owner of configuration and DNS resolution and passes an immutable `ReadonlyRouteContext` into the CLI renderer. The Core facade remains business-only. The schema-v2 renderer uses the same context for success, business errors, and missing-session errors.

**Tech Stack:** Rust 1.95, Tokio, Clap, Serde, JSON Schema draft 2020-12, Cargo tests.

---

## File Structure

- Modify `crates/ubaa-core/src/connection.rs`: serialize `NetworkState` with stable snake-case names.
- Modify `crates/ubaa-core/src/output.rs`: extend `ReadonlyJsonMeta` with the route diagnostic fields.
- Modify `apps/ubaa-cli/src/lib.rs`: define `ReadonlyRouteContext`, thread it through rendering, and add a schema-v2 startup-error renderer.
- Modify `apps/ubaa-cli/src/main.rs`: retain `RouteResolution` and pass it to all read-only render paths.
- Modify `apps/ubaa-cli/tests/cli_contract.rs`: cover explicit-policy success/error metadata and schema acceptance/rejection.
- Modify `apps/ubaa-cli/tests/binary_e2e.rs`: cover missing-session schema-v2 output from the production host.
- Modify `docs/contracts/cli-json.schema.json`: require and constrain the new metadata.
- Modify `docs/contracts/route-policy.md` and `docs/migration/status.md`: document the completed diagnostics contract.

### Task 1: Route Context And Read-Only Rendering

**Files:**
- Modify: `apps/ubaa-cli/tests/cli_contract.rs`
- Modify: `crates/ubaa-core/src/connection.rs`
- Modify: `crates/ubaa-core/src/output.rs`
- Modify: `apps/ubaa-cli/src/lib.rs`

- [ ] **Step 1: Write failing success and business-error tests**

Add a `ReadonlyRouteContext` fixture with explicit Direct policy and assert both envelopes contain:

```rust
assert_eq!(value["meta"]["routePolicy"], "direct");
assert_eq!(value["meta"]["networkState"], "unknown");
assert_eq!(value["meta"]["initialRoute"], "direct");
assert_eq!(value["meta"]["resolvedRoute"], "direct");
assert_eq!(value["meta"]["usedFallback"], false);
```

- [ ] **Step 2: Run the focused tests and observe RED**

Run:

```bash
cargo test --locked -p ubaa-cli --test cli_contract readonly_route -- --nocapture
```

Expected: compilation failure because `ReadonlyRouteContext` and the route-aware runner do not exist, or assertion failure because metadata is missing/fixed to `auto`.

- [ ] **Step 3: Implement the minimal route context and renderer plumbing**

Use these stable shapes:

```rust
pub struct ReadonlyRouteContext {
    pub policy: RoutePolicy,
    pub network: NetworkState,
    pub initial_route: ConnectionMode,
    pub resolved_route: ConnectionMode,
    pub used_fallback: bool,
}

pub struct ReadonlyJsonMeta {
    pub route_policy: RoutePolicy,
    pub network_state: NetworkState,
    pub initial_route: ConnectionMode,
    pub resolved_route: ConnectionMode,
    pub used_fallback: bool,
    pub feature: String,
}
```

Add `run_with_backend_with_route` for production and explicit tests. Preserve `run_with_backend` as a compatibility wrapper that creates an Auto/Unknown/no-fallback context for injected tests.

- [ ] **Step 4: Run the focused tests and observe GREEN**

Run:

```bash
cargo test --locked -p ubaa-cli --test cli_contract readonly_route -- --nocapture
```

Expected: all matching tests pass.

### Task 2: Missing Session Uses Schema V2

**Files:**
- Modify: `apps/ubaa-cli/tests/binary_e2e.rs`
- Modify: `apps/ubaa-cli/src/lib.rs`
- Modify: `apps/ubaa-cli/src/main.rs`

- [ ] **Step 1: Write the failing binary test**

Create a temporary config with an explicit Direct route, run `ubaa --json ... schedule terms` without a session, and assert:

```rust
assert_eq!(value["schemaVersion"], 2);
assert_eq!(value["error"]["code"], "authentication_required");
assert_eq!(value["meta"]["routePolicy"], "direct");
assert_eq!(value["meta"]["networkState"], "unknown");
```

- [ ] **Step 2: Run the binary test and observe RED**

Run:

```bash
cargo test --locked -p ubaa-cli --test binary_e2e binary_json_readonly_without_session -- --nocapture
```

Expected: failure because the current host emits schema version 1 with no read-only metadata.

- [ ] **Step 3: Implement post-resolution startup rendering**

Retain the `RouteResolution` returned in `main.rs`, convert it to `ReadonlyRouteContext`, and use:

```rust
render_readonly_startup_error(
    json_mode,
    feature.as_str(),
    route_context,
    authentication_required(),
    &mut stdout,
    &mut stderr,
)
```

Pass the same context to `run_with_backend_with_route` for normal success/business-error paths.

- [ ] **Step 4: Run binary and CLI contract tests and observe GREEN**

Run:

```bash
cargo test --locked -p ubaa-cli --test binary_e2e binary_json_readonly_without_session -- --nocapture
cargo test --locked -p ubaa-cli --test cli_contract
```

Expected: both commands pass.

### Task 3: JSON Schema, Documentation, And Gates

**Files:**
- Modify: `apps/ubaa-cli/tests/cli_contract.rs`
- Modify: `docs/contracts/cli-json.schema.json`
- Modify: `docs/contracts/route-policy.md`
- Modify: `docs/migration/status.md`

- [ ] **Step 1: Add a failing schema positive/negative test**

Serialize a valid read-only envelope, assert it validates, remove `networkState`, and assert the modified value is rejected.

- [ ] **Step 2: Run the schema test and observe RED**

Run:

```bash
cargo test --locked -p ubaa-cli --test cli_contract serialized_envelopes_match_the_cli_json_schema -- --nocapture
```

Expected: failure because the checked-in schema neither requires nor defines all diagnostic fields.

- [ ] **Step 3: Update schema and contract docs**

Require `routePolicy`, `networkState`, `initialRoute`, `resolvedRoute`, `usedFallback`, and `feature`. Constrain network state to `campus|off_campus|unknown`, routes to `direct|webvpn`, and fallback to boolean. Record that explicit policies report `unknown` because DNS was not queried.

- [ ] **Step 4: Run focused and repository gates**

Run:

```bash
cargo test --locked -p ubaa-cli --test cli_contract
cargo test --locked -p ubaa-cli --test binary_e2e
just refs
just check-sensitive
just check
```

Expected: all commands exit 0.

- [ ] **Step 5: Inspect and commit**

Run:

```bash
git diff --check
git status --short
```

Stage only the listed implementation/test/docs files, inspect the staged diff for sensitive material, and commit as:

```bash
git commit -m "feat: expose readonly route diagnostics"
```
