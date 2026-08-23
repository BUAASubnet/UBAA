# UBAA 2 Correctness Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repair every audited routing, session, CLI-contract, Classroom, SPOC, Judge, documentation, and verification defect while preserving reference-derived behavior and sensitive-data boundaries.

**Architecture:** The public Core facade owns route policy, a cached gateway reachability probe, two private route clients, one atomic dual-session coordinator, and route-scoped feature state. CLI code only parses and renders. Every protocol change is preceded by a nine-dimension frozen-source comparison and a focused failing test, then validated deterministically before live Direct/WebVPN/auto checks.

**Tech Stack:** Rust 1.95/edition 2024, Tokio, reqwest, scraper, serde/serde_json, clap, JSON Schema, shell verification scripts, frozen Kotlin `ubaa_old`, pinned Rust `examples/buaa-api`.

---

## File Structure

- `crates/ubaa-core/src/session.rs`: atomic dual snapshot/revision persistence and coordinator primitives.
- `crates/ubaa-core/src/runtime.rs`: one route's HTTP/Cookie/auth state plus route-owned feature state.
- `crates/ubaa-core/src/facade/mod.rs`: aggregate host API, dual authentication, Core-owned route resolution, diagnostics.
- `crates/ubaa-core/src/connection.rs`: WebVPN conversion plus `GatewayProbe` and 60-second cache.
- `crates/ubaa-core/src/config.rs`: strict route policy parsing and hardened atomic persistence.
- `crates/ubaa-core/src/features/state.rs`: Classroom, SPOC, and Judge route-scoped mutable state.
- `crates/ubaa-core/src/features/{user,classroom,spoc,judge}.rs`: reference-backed behavior repairs.
- `crates/ubaa-core/src/{domain/mod.rs,output.rs}`: public safe DTOs and schema-v2 envelopes.
- `apps/ubaa-cli/src/{main.rs,lib.rs}`: facade-only command dispatch and schema-v2 rendering.
- `crates/ubaa-core/tests`, `crates/ubaa-test-support/tests`, `apps/ubaa-cli/tests`: RED/GREEN behavior and binary contracts.
- `fixtures/readonly`: sanitized structural fixtures only; no live body or personal data.
- `docs/migration/source-parity.md`: operation-by-operation nine-dimension evidence.
- `docs/migration/{decision-log,status,readonly-feature-matrix}.md`: conflicts and current evidence.
- `docs/contracts`, `docs/runbooks`, `goal.md`: final public and execution contracts.
- `scripts/{verify-live.sh,test-verify-live.sh}`: semantic live gates without sensitive output.

### Task 1: Correct The Active Contract And Evidence Ledger

**Files:**
- Modify: `goal.md`
- Modify: `docs/migration/source-parity.md`
- Modify: `docs/migration/status.md`
- Modify: `docs/contracts/route-policy.md`
- Modify: `docs/contracts/connection-and-session.md`
- Modify: `docs/contracts/auth-and-user.md`
- Modify: `docs/contracts/readonly-features.md`
- Modify: `docs/migration/decision-log.md`

- [x] **Step 1: Re-run immutable-reference and worktree checks**

Run:

```bash
git status --short --branch
just refs
```

Expected: branch `ubaa2`; only known in-scope changes are present; both pinned reference commits verify.

- [x] **Step 2: Replace the obsolete product decisions in `goal.md`**

Use one consistent contract:

```text
auto probe = TCP connect gw.buaa.edu.cn:80
total deadline = 500 ms including resolution and every address attempt
success = Campus -> Direct
resolution/connect failure or timeout = OffCampus -> WebVPN
internal probe failure = Unknown -> operation unknown_default
cache = process-local 60 seconds
CLI JSON = schema version 2 only
```

Remove the DNS/NXDOMAIN authority language, `DNS` fallback wording, schema-v1 output allowance, and any claim that the CLI owns route resolution. Preserve session/config on-disk migration versions.

- [x] **Step 3: Expand source parity before production edits**

Create separate operation sections for `gateway probe`, `dual load/save/logout`, `prepare/login captcha`, `user show`, `Classroom sync`, `Classroom query`, `SPOC auth`, `SPOC list`, `SPOC detail`, `Judge list`, `Judge detail`, `Judge batch/cache`, and `CLI/config`. Each section must contain these exact columns:

```text
bootstrap/service URL | redirect/final URL | cookie/session scope |
method and exact parameters | headers/body encoding | crypto constants |
DTO/parser fields | caching/concurrency | error/exit semantics
```

For Classroom and Judge, record `examples/buaa-api = N/A/non-equivalent`. For SPOC, record that its list/auth protocols are non-equivalent and cite only matching crypto/token/detail facts. Remove the existing assertion that both SPOC references share endpoints, headers, and pagination.

- [x] **Step 4: Mark invalid live conclusions as unverified**

In `status.md`, replace “valid empty SPOC list” with “unverified until the global empty-`kcid` query is observed”. Mark Judge detail semantics and the Direct 65/WebVPN 17 difference unresolved. Do not delete historical command evidence; label its limitation.

- [x] **Step 5: Validate and commit the contract phase**

Run:

```bash
rg -n 'NXDOMAIN|DNS-only|schema version 1|compatibility output remains v1' goal.md docs
git diff --check
just check-sensitive
```

Expected: no active contract retains obsolete behavior; sensitive gate passes.

Commit only the contract/evidence files:

```bash
git add goal.md docs/contracts docs/migration
git diff --cached --check
git commit -m "docs: correct remediation contracts and parity"
```

### Task 2: Make Dual Session Mutation Atomic And Add User Preflight

**Files:**
- Modify: `crates/ubaa-core/src/session.rs`
- Modify: `crates/ubaa-core/src/runtime.rs`
- Modify: `crates/ubaa-core/src/features/user.rs`
- Modify: `crates/ubaa-core/src/facade/mod.rs`
- Test: `crates/ubaa-core/tests/session.rs`
- Test: `crates/ubaa-test-support/tests/auth.rs`
- Test: `crates/ubaa-test-support/tests/readonly.rs`
- Modify: `docs/migration/source-parity.md`

- [x] **Step 1: Add RED tests for atomicity and zero-request preflight**

Add these exact tests and assertions:

```text
dual_versioned_load_returns_snapshot_and_revision_from_one_lock_epoch
  loaded snapshot equals the body protected by loaded revision
  a CAS using that revision either applies to that snapshot or reports conflict

stale_aggregate_logout_preserves_both_newer_slots
  returned error is retryable InternalError
  persisted Direct and WebVPN cookies equal the external writer's candidates

successful_aggregate_logout_advances_revision_once
  final snapshot is absent
  final revision equals initial revision + 1

user_info_without_local_session_makes_zero_requests
  error code is AuthenticationRequired
  MockTransport observer request list is empty
```

Run:

```bash
cargo test --locked -p ubaa-core --test session dual_versioned_load_never_pairs_a_snapshot_with_a_later_revision -- --exact
cargo test --locked -p ubaa-test-support --test auth stale_aggregate_logout_preserves_both_newer_slots -- --exact
cargo test --locked -p ubaa-test-support --test auth user_info_without_local_session_makes_zero_requests -- --exact
```

Expected: failures demonstrate split-lock load, revision adoption/two-CAS logout, and user HTTP before preflight.

- [x] **Step 2: Load dual state under one lock**

Refactor `FileSessionStore` so the body migration/parse and lock revision are read in one critical section:

```rust
pub fn load_dual_versioned(&self) -> Result<VersionedDualSession> {
    let mut lock = self.acquire_lock()?;
    let revision = read_revision(&mut lock.file)?;
    let snapshot = self.load_or_migrate_dual_unlocked(&mut lock.file, revision)?;
    Ok(VersionedDualSession { snapshot, revision })
}
```

The migration helper must update and return the resulting revision in the same call rather than re-locking.

- [x] **Step 3: Introduce one shared coordinator**

Add a private coordinator with the only mutable persisted snapshot/file revision and route-local logical CAS revisions:

```rust
pub(crate) struct DualSessionCoordinator {
    state: Arc<Mutex<DualSessionState>>,
}

struct DualSessionState {
    store: FileSessionStore,
    snapshot: DualSessionSnapshot,
    file_revision: u64,
    direct_revision: u64,
    webvpn_revision: u64,
    conflicted: bool,
}
```

Each route adapter first compares the caller's route-local logical revision, then constructs one
full candidate and calls `compare_exchange_dual(file_revision, Some(&candidate))`. This preserves
the `SessionStore` stale-writer contract while allowing a legitimate sibling route mutation to
advance the shared file revision. Aggregate clear calls `compare_exchange_dual(file_revision,
None)` even when the loaded snapshot was empty. Update revisions and snapshot only on `Applied`.
On an external `Conflict`, clear the complete current-facade memory, stop sibling I/O, mark the
coordinator terminally conflicted and require reopening it; never reload/adopt the external
revision. Delete `ClientRuntime::refresh_revision` and any reload-after-conflict path.

- [x] **Step 4: Split remote logout from persistent cleanup**

Make `AuthWorkflow` expose a best-effort remote step and a local clear step. Aggregate logout calls both remote steps, clears both route memories, then calls `coordinator.clear_both()` exactly once. Single-route diagnostic logout updates only its slot through the same coordinator.

- [x] **Step 5: Put session preflight before user HTTP**

At the beginning of both user queries:

```rust
if !runtime.has_local_session() {
    return Err(authentication_required());
}
```

Do this before URL construction or `runtime.request`.

- [x] **Step 6: Run focused and full gates, then commit**

Run:

```bash
cargo test --locked -p ubaa-core --test session
cargo test --locked -p ubaa-test-support --test auth
cargo test --locked -p ubaa-test-support --test auth user_info_without_local_session_makes_zero_requests -- --exact
just check-sensitive
just check
```

Expected: all pass; no `refresh_revision` remains.

Commit:

```bash
git add crates/ubaa-core/src/session.rs crates/ubaa-core/src/runtime.rs \
  crates/ubaa-core/src/features/user.rs crates/ubaa-core/src/facade/mod.rs \
  crates/ubaa-core/tests/session.rs crates/ubaa-test-support/tests/auth.rs \
  crates/ubaa-test-support/tests/readonly.rs docs/migration/source-parity.md
git commit -m "fix: make dual session mutations atomic"
```

### Task 3: Bind Captcha Answers To Route And Generation

**Files:**
- Modify: `crates/ubaa-core/src/domain/mod.rs`
- Modify: `crates/ubaa-core/src/facade/mod.rs`
- Modify: `crates/ubaa-core/src/auth/mod.rs`
- Test: `crates/ubaa-test-support/tests/auth.rs`
- Test: `apps/ubaa-cli/tests/cli_contract.rs`
- Modify: `docs/migration/source-parity.md`

- [x] **Step 1: Add RED tests for colliding and stale upstream IDs**

Use identical `captchaId=captcha-fixture` pages on both routes and assert:

```rust
assert_ne!(preparation.challenges[0].challenge_id, preparation.challenges[1].challenge_id);
assert_eq!(client.login(answer_for_direct_only).await?.routes[1].state,
           RouteLoginState::CaptchaRequired);
assert_eq!(client.login(unknown_answer).await.unwrap_err().code, ErrorCode::InvalidInput);
assert_eq!(client.login(duplicate_answer).await.unwrap_err().code, ErrorCode::InvalidInput);
```

Also prepare twice and prove the first generation's public ID is rejected before any POST.

Run the new tests and retain the expected current cross-route reuse/silent-ignore failures.

- [x] **Step 2: Add opaque per-prepare mappings**

Keep raw IDs in `AuthWorkflow`; expose only facade-generated IDs:

```rust
struct PublicChallenge {
    public_id: String,
    route: ConnectionMode,
    generation: u64,
    upstream_id: String,
}
```

Generate IDs from random process-local bytes or a monotonically unique nonce encoded without embedding execution/upstream ID. Clear mappings on each prepare, successful consume, auth clear, relogin, and logout.

- [x] **Step 3: Validate every answer before route processing**

Reject empty IDs/values, duplicates, unknown IDs, old generations, and IDs not present in the current preparation. Convert only the matched route's answer to the private `LoginInput.captcha`; do not send any POST until validation succeeds.

- [x] **Step 4: Re-run auth and CLI captcha contracts**

Run:

```bash
cargo test --locked -p ubaa-test-support --test auth
cargo test --locked -p ubaa-cli --test cli_contract
just check-sensitive
just check
```

Commit the focused files as `fix: isolate captcha challenges by route`.

### Task 4: Move Route Resolution Into The Aggregate Core Facade

**Files:**
- Modify: `crates/ubaa-core/src/connection.rs`
- Modify: `crates/ubaa-core/src/facade/mod.rs`
- Modify: `crates/ubaa-core/src/domain/mod.rs`
- Modify: `crates/ubaa-core/src/lib.rs`
- Modify: `apps/ubaa-cli/src/main.rs`
- Modify: `apps/ubaa-cli/src/lib.rs`
- Test: `crates/ubaa-core/tests/route_policy.rs`
- Test: `crates/ubaa-core/tests/facade.rs`
- Test: `apps/ubaa-cli/tests/binary_e2e.rs`
- Modify: `docs/migration/source-parity.md`

- [x] **Step 1: Add RED policy and facade tests**

Rename the test vocabulary from DNS to gateway reachability and cover:

```rust
impl GatewayProbe for ProbeResult {
    fn probe(&self, budget: Duration) -> NetworkState { self.0 }
}

assert_eq!(resolve(NetworkState::Campus, RoutePolicy::Auto), ConnectionMode::Direct);
assert_eq!(resolve(NetworkState::OffCampus, RoutePolicy::Auto), ConnectionMode::WebVpn);
assert_eq!(resolve(NetworkState::Unknown, RoutePolicy::Auto), ConnectionMode::Direct);
assert_eq!(explicit_probe_calls.load(Ordering::SeqCst), 0);
assert_eq!(cached_probe_calls.load(Ordering::SeqCst), 1);
assert_eq!(user_result.meta.route_policy, config.default);
assert_eq!(schedule_result.meta.route_policy, config.feature(ReadonlyFeature::Schedule));
```

Add a binary test showing fresh `--json auth login` opens the aggregate facade even when `config.toml` does not exist; it may fail on network, but must not emit the previous startup invalid-input/v1 path.

- [x] **Step 2: Implement the bounded TCP probe**

Replace `DnsProbe/SystemDnsProbe/CachingDnsProbe` with:

```rust
pub trait GatewayProbe: Send + Sync {
    fn probe(&self, budget: Duration) -> NetworkState;
}

pub struct SystemGatewayProbe;
pub struct CachingGatewayProbe<P> { inner: P, ttl: Duration, cached: Mutex<Option<(Instant, NetworkState)>> }
```

The system implementation starts one worker for blocking resolution/connection, shares an `Instant` deadline, connects to `gw.buaa.edu.cn:80`, passes only remaining time to each attempt, returns OffCampus for ordinary network failure, and lets the caller stop waiting at 500 ms. Do not log addresses or spawn unbounded workers per call.

- [x] **Step 3: Promote the aggregate client to the public facade**

Make `UbaaClient` own `RouteConfig`, cached probe, both private route clients, and the shared session coordinator. Add one internal resolver:

```rust
fn resolve_operation(&self, operation: Operation) -> RouteResolution;

pub struct Routed<T> {
    pub data: T,
    pub resolution: RouteResolution,
}

pub async fn get_user_info(&mut self) -> Result<Routed<UserProfile>>;
pub async fn schedule_terms(&mut self) -> Result<Routed<Vec<Term>>>;
pub async fn schedule_weeks(&mut self, term: &str) -> Result<Routed<Vec<Week>>>;
pub async fn schedule_week(&mut self, term: &str, week: i32) -> Result<Routed<WeeklySchedule>>;
pub async fn schedule_today(&mut self) -> Result<Routed<Vec<TodayClass>>>;
pub async fn exam_arrangement(&mut self, term: &str) -> Result<Routed<ExamArrangement>>;
pub async fn grades(&mut self, term: &str) -> Result<Routed<GradeData>>;
pub async fn classroom_search(&mut self, campus_id: i32, date: &str) -> Result<Routed<ClassroomQuery>>;
pub async fn spoc_assignments(&mut self) -> Result<Routed<SpocAssignments>>;
pub async fn spoc_assignment(&mut self, assignment_id: &str) -> Result<Routed<SpocAssignmentDetail>>;
pub async fn judge_assignments(&mut self, include_expired: bool) -> Result<Routed<Vec<JudgeAssignmentSummary>>>;
pub async fn judge_assignment(&mut self, course_id: &str, assignment_id: &str) -> Result<Routed<JudgeAssignmentDetail>>;
pub async fn judge_assignment_details(&mut self, keys: &[JudgeAssignmentKey]) -> Result<Routed<Vec<JudgeAssignmentDetail>>>;
```

`Operation::User` uses `config.default`; feature operations use `config.feature(feature)`. Keep `ConnectionMode` out of normal host method parameters. A hidden diagnostic constructor fixes one mode and bypasses probing for live tests.

- [x] **Step 4: Remove route logic from CLI**

Delete CLI imports and functions for `RouteConfig`, probe types, `resolve_feature_route`, `route_feature`, and concrete `ConnectionMode` selection. Always open the aggregate facade for ordinary auth/user/read commands and render the diagnostic returned by Core.

- [x] **Step 5: Verify facade ownership**

Run:

```bash
rg -n 'RouteConfig|GatewayProbe|resolve_feature_route|SystemGatewayProbe|ConnectionMode' apps/ubaa-cli/src/main.rs
cargo test --locked -p ubaa-core --test route_policy
cargo test --locked -p ubaa-core --test facade
cargo test --locked -p ubaa-cli --test binary_e2e
just check-sensitive
just check
```

Expected: the grep has no route-policy ownership in CLI; all tests pass.

Commit as `refactor: centralize route resolution in core facade`.

### Task 5: Harden Route Config And Unify Schema Version 2

**Files:**
- Modify: `crates/ubaa-core/src/config.rs`
- Modify: `crates/ubaa-core/src/output.rs`
- Modify: `crates/ubaa-core/src/domain/mod.rs`
- Modify: `apps/ubaa-cli/src/lib.rs`
- Modify: `docs/contracts/cli-json.schema.json`
- Test: `crates/ubaa-core/tests/route_policy.rs`
- Test: `crates/ubaa-core/tests/contracts.rs`
- Test: `apps/ubaa-cli/tests/cli_contract.rs`
- Test: `apps/ubaa-cli/tests/binary_e2e.rs`
- Modify: `docs/migration/source-parity.md`

- [ ] **Step 1: Add RED filesystem and schema tests**

On Unix, prove load/save reject a symlinked `config.toml` without changing its target. Add eight concurrent saves while a directory occupies `.config.toml.tmp`, then assert one complete valid config and no unique-temp leftovers.

Add JSON Schema negatives for v1, aggregate one/three route items, reversed route order, duplicate routes, simultaneous `resolvedRoute`/`resolvedRoutes`, execution/challenge image fields, and legacy `connectionMode`. Add positives for every command family.

- [ ] **Step 2: Reuse the session store's safe file pattern**

Implement no-follow regular-file validation, unique exclusive temp creation, owner-only mode, write+flush, and atomic rename in `config.rs`. Keep TOML schema version 1 because it is the on-disk config version, not CLI JSON.

- [ ] **Step 3: Delete the v1 output type**

Remove `JsonMeta`, `JsonEnvelope`, and `JSON_SCHEMA_VERSION`. Use a single `CLI_JSON_SCHEMA_VERSION: u32 = 2` and two constrained envelope variants:

```rust
pub enum CliEnvelope<T> {
    Routed(RoutedJsonEnvelope<T>),
    Aggregate(AggregateJsonEnvelope<T>),
}
```

Ensure aggregate route arrays are constructed internally as `[Direct, WebVpn]`, not arbitrary `Vec`s. Captcha errors expose only `route`, `challengeId`, and `imageAvailable`.

- [ ] **Step 4: Replace every renderer and regression expectation**

Fresh JSON login, auth status, logout (including no session), user show, all read-only successes/failures, argument errors, and hidden diagnostic mode must serialize version 2. No code path emits execution, image data, v1 meta, or an unvalidated envelope.

- [ ] **Step 5: Run schema and binary gates, then commit**

Run:

```bash
cargo test --locked -p ubaa-core --test contracts
cargo test --locked -p ubaa-cli --test cli_contract
cargo test --locked -p ubaa-cli --test binary_e2e
rg -n 'schemaVersion.*1|JSON_SCHEMA_VERSION|JsonEnvelope|connectionMode|execution' crates apps docs/contracts
just check-sensitive
just check
```

Review grep hits; only config/session version 1 and private auth execution code may remain. Commit as `fix: unify cli output on schema v2`.

### Task 6: Add Route-Owned Feature State And Repair Classroom

**Files:**
- Create: `crates/ubaa-core/src/features/state.rs`
- Modify: `crates/ubaa-core/src/features/mod.rs`
- Modify: `crates/ubaa-core/src/runtime.rs`
- Modify: `crates/ubaa-core/src/features/classroom.rs`
- Test: `crates/ubaa-core/tests/readonly_parsers.rs`
- Test: `crates/ubaa-test-support/tests/readonly.rs`
- Modify: `docs/migration/source-parity.md`

- [ ] **Step 1: Add RED tests for state ownership and exact Classroom behavior**

Cover complete mobile WeChat headers (including routed Referer), sequential and concurrent calls synchronizing once, sync failure followed by successful query and later retry, query 302 not followed, SSO HTML clearing sync, missing `m`/`d`/`list` parse failure, and a complete empty map success.

- [ ] **Step 2: Add private route state**

Implement:

```rust
pub(crate) struct RouteFeatureState {
    pub(crate) classroom: ClassroomState,
    pub(crate) spoc: SpocState,
    pub(crate) judge: JudgeState,
}

impl RouteFeatureState { pub(crate) fn clear(&self); }
```

`ClientRuntime` owns `Arc<RouteFeatureState>`; read-worker forks clone it only for the same route. `clear_memory`, auth invalidation, successful relogin/session identity replacement, and logout call `state.clear()`.

- [ ] **Step 3: Port the frozen Classroom lifecycle**

Use the exact UA from `LocalClassroomApi.kt`. Guard synchronization with the route state's async mutex and set `synced=true` only after success. Ignore sync failure for the current query, but leave it false. Send the business query once with redirects disabled by transport/request policy; classify Location to SSO as authentication required. Make the serde envelope fields mandatory.

- [ ] **Step 4: Run focused tests and commit**

Run:

```bash
cargo test --locked -p ubaa-core --test readonly_parsers classroom
cargo test --locked -p ubaa-test-support --test readonly classroom
just check-sensitive
just check
```

Commit as `fix: scope feature state and align classroom flow`.

### Task 7: Repair SPOC Authentication, Global Pagination, And Detail Fallback

**Files:**
- Modify: `crates/ubaa-core/src/features/state.rs`
- Modify: `crates/ubaa-core/src/features/spoc.rs`
- Modify: `crates/ubaa-core/src/domain/mod.rs`
- Modify: `fixtures/readonly/spoc-page.json`
- Modify: `fixtures/readonly/spoc-detail.json`
- Test: `crates/ubaa-core/tests/readonly_parsers.rs`
- Test: `crates/ubaa-test-support/tests/readonly.rs`
- Test: `apps/ubaa-cli/tests/cli_contract.rs`
- Modify: `docs/migration/source-parity.md`

- [ ] **Step 1: Add RED tests for every frozen SPOC gap**

Test that empty or failing course metadata still issues one global page request; multiple courses do not duplicate pagination; decrypted page JSON has exact empty `kcid`/`yzwz`; submission failure preserves summary score/start/due; `{}` submission maps `Unknown`; business auth errors refresh exactly once; a second auth error stops; sequential operations reuse token/role; token comes from matching `/spocnew/cas` Location without GET; wrong path is rejected; primitive and array roles parse; code `0` is rejected absent evidence; detail ID is required; serialized CLI data has no HTML field.

- [ ] **Step 2: Implement route-owned SPOC credentials**

Store token/role behind one async login mutex. Add:

```rust
async fn with_spoc_auth_retry<T>(runtime: &mut ClientRuntime,
    operation: impl AsyncFn(&mut ClientRuntime, &SpocCredential) -> Result<T>) -> Result<T>;
```

Reuse cached credentials; on a specifically recognized business authentication envelope, clear and relogin once, then return the second error unchanged. Never retry parse/permission/unknown errors by analogy.

- [ ] **Step 3: Separate optional enrichment from global pages**

Fetch course metadata with recoverable error handling into a lookup map. Independently page the encrypted global assignment endpoint using a serializable request struct whose field order and values match the frozen JSON. Merge optional course fields after parsing; stop only on verified page termination.

- [ ] **Step 4: Make submission optional and remove raw HTML**

Require detail; attempt submission as optional enrichment. Derive status from submission object presence, then fall back score/time to summary. Keep HTML local to the parser, expose only `content_text`, and remove `content_html` from `SpocAssignmentDetail` and every renderer/schema fixture.

- [ ] **Step 5: Run focused and full gates, then commit**

Run:

```bash
cargo test --locked -p ubaa-core --test readonly_parsers spoc
cargo test --locked -p ubaa-test-support --test readonly spoc
cargo test --locked -p ubaa-cli --test cli_contract spoc
just check-sensitive
just check
```

Commit as `fix: align spoc reads with frozen global protocol`.

### Task 8: Port Complete Judge Parsing, Batch, Date, And Cache Semantics

**Files:**
- Modify: `crates/ubaa-core/src/features/state.rs`
- Modify: `crates/ubaa-core/src/features/judge.rs`
- Modify: `fixtures/readonly/judge-assignments.html`
- Modify: `fixtures/readonly/judge-detail.html`
- Test: `crates/ubaa-core/tests/readonly_parsers.rs`
- Test: `crates/ubaa-test-support/tests/readonly.rs`
- Modify: `docs/migration/source-parity.md`

- [ ] **Step 1: Add sanitized RED fixtures and parser tests**

Fixtures must contain a ghost `assignID` link, valid `problemContent` and `judgeDetails` links, nested/script tables, 4-cell and 2-cell rows, mixed submitted/unsubmitted problems, explicit and derived total scores, HTML entities, and `HH:MM` timestamps. Assert exact `problems`, `my_score`, `total_problems`, and `Partial/Submitted/Unsubmitted` outputs.

- [ ] **Step 2: Add RED service tests**

Assert same-course multi-key batch fetches the assignment list once and preserves input order; at most four course workers run; two clients/routes never share cache; logout/relogin/auth invalidation causes refetch; expired entries are removed; Aug 31 cutoff becomes the valid final day of February rather than Feb 31.

- [ ] **Step 3: Port the frozen DOM algorithm**

Use `scraper` selectors for anchors, top-level tables/rows/cells, excluding nested tables and script/style text. Filter assignment URLs before dedupe/title selection. Implement small pure helpers for score/status/time extraction and entity-clean text. Derive totals in frozen priority order and set `Partial` when problem states differ.

- [ ] **Step 4: Group batch work by course**

Build an indexed request map, run one worker per course under the four-worker semaphore, fetch/select/list once per course, fetch requested details, then restore the original input order and stable per-key errors.

- [ ] **Step 5: Replace the global cache**

Delete `JUDGE_CACHE`, `cache_scope_key`, and cookie-hash scoping. Store bounded timestamped maps in `RouteFeatureState.judge`; prune expired entries on access and clear all entries through the route-state lifecycle.

- [ ] **Step 6: Inject and clamp the cutoff date**

Move cutoff calculation to a pure function taking `(year, month, day)` for tests. Subtract six months and clamp `day` using the existing calendar helper before formatting.

- [ ] **Step 7: Run focused and full gates, then commit**

Run:

```bash
cargo test --locked -p ubaa-core --test readonly_parsers judge
cargo test --locked -p ubaa-test-support --test readonly judge
just check-sensitive
just check
```

Commit as `fix: complete judge read semantics and cache lifecycle`.

### Task 9: Strengthen Live Verification And Reconcile Documentation

**Files:**
- Modify: `scripts/verify-live.sh`
- Modify: `scripts/test-verify-live.sh`
- Modify: `docs/runbooks/live-auth-verification.md`
- Modify: `docs/runbooks/live-readonly-verification.md`
- Modify: `docs/migration/status.md`
- Modify: `docs/migration/readonly-feature-matrix.md`
- Modify: `docs/migration/decision-log.md`
- Modify: `docs/migration/source-parity.md`
- Modify: `docs/contracts/auth-and-user.md`
- Modify: `docs/contracts/connection-and-session.md`
- Modify: `docs/contracts/readonly-features.md`
- Modify: `docs/contracts/route-policy.md`
- Modify: `README.md`
- Modify: `AGENTS.md` only if commands or ownership guidance changed

- [ ] **Step 1: Add deterministic verifier RED cases**

Extend the fake CLI harness so `test-verify-live.sh` proves the verifier rejects:

```text
schemaVersion != 2
wrong aggregate route length/order
SPOC success lacking a proven list-query marker
Judge detail with absent problem semantics
route result whose resolved route contradicts explicit/auto expectation
any output containing execution/cookie/token/raw HTML sentinel
```

- [ ] **Step 2: Validate semantics without persisting personal data**

Parse JSON in memory. For each feature assert schema v2, correct feature/policy metadata, expected route, and feature-specific structural invariants. For Judge record only course/raw-anchor/filtered-unique/detail-success/cutoff-skip counts and a salted in-memory digest when comparing routes; never write IDs, titles, bodies, or profile fields. For SPOC distinguish a real empty global page from “no request made”.

- [ ] **Step 3: Remove stale docs and make evidence honest**

Update every active document from DNS to TCP reachability, CLI routing to facade routing, v1 to v2, one-snapshot session wording to atomic dual coordinator, and symlink claims to the tested implementation. Mark live results only after running them in this task; retain failed/unverified stages explicitly.

- [ ] **Step 4: Run deterministic final gates**

Run:

```bash
just refs
just check-sensitive
just check
cargo test --locked -p ubaa-cli --test binary_e2e
git status --short
```

Expected: all deterministic gates pass; only intended documentation/live-evidence changes remain.

- [ ] **Step 5: Commit verifier and documentation**

Inspect staged files for `.env.local`, session data, live bodies, cookies, tokens, captcha material, or personal fields, then commit as `test: enforce semantic live verification`.

### Task 10: Run The Real Matrix And Perform An Independent Final Audit

**Files:**
- Modify only if evidence changes: `docs/migration/status.md`
- Modify only if a real conflict is resolved: `docs/migration/decision-log.md`
- Modify only if protocol evidence changes: `docs/migration/source-parity.md`

- [ ] **Step 1: Load credentials without printing them**

Use the existing verifier, which reads `.env.local` internally. Do not run `cat`, `env`, `set -x`, or commands that echo variable values.

- [ ] **Step 2: Run authentication and feature matrix**

Run:

```bash
just verify-live feature=auth route=direct
just verify-live feature=auth route=webvpn
just verify-live feature=all route=auto
for feature in schedule exam grades classroom spoc judge; do
  just verify-live feature="$feature" route=direct
  just verify-live feature="$feature" route=webvpn
done
```

Expected: safe summaries only. A captcha may require the documented same-process human flow. Do not claim a failed route passed.

- [ ] **Step 3: Investigate only actual upstream contradictions**

If a deterministic-reference-backed request fails on both routes or route semantics differ, first inspect safe request/response metadata already exposed by the verifier. Use Playwright/browser tracing with `.env.local` only when that cannot resolve the conflict. Never save raw HAR, screenshots with personal data, captcha images, cookies, or response bodies. Record only sanitized URLs/field names/status/final-route facts in the decision log, add a sanitized failing fixture, then repeat RED/GREEN and the matrix.

- [ ] **Step 4: Audit against every original finding**

Search and verify:

```bash
rg -n 'SystemDnsProbe|DnsProbe|refresh_revision|JUDGE_CACHE|content_html|JSON_SCHEMA_VERSION|schemaVersion.*1|connectionMode' crates apps docs
rg -n 'RouteConfig|resolve_feature_route|ConnectionMode' apps/ubaa-cli/src/main.rs
git diff --check
just refs
just check-sensitive
just check
```

Every remaining hit must be an intentional historical note, on-disk v1 migration, private auth execution handling, or explicitly documented diagnostic API.

- [ ] **Step 5: Request independent code review and fix findings**

Use `superpowers:requesting-code-review` against the design, this plan, `goal.md`, and the full diff since `e280843`. Review must prioritize behavioral regressions, reference-parity omissions, sensitive output, concurrent session loss, false live claims, and missing tests. Resolve every finding with another RED/GREEN cycle.

- [ ] **Step 6: Commit final evidence and verify clean handoff**

Commit only sanitized evidence/documentation as `docs: record corrected live verification`. Then run:

```bash
git status --short --branch
git log --oneline -12
just refs
just check-sensitive
just check
```

Expected: clean worktree, pinned references, all deterministic gates green, and status documentation distinguishing every live verified/unverified route.
