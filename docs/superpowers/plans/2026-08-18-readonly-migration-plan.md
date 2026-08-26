# UBAA 2 Readonly Migration Implementation Plan

Status: superseded by `2026-08-23-correctness-remediation.md`. This file is a historical execution record and must not be used as the current live acceptance matrix.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the verified authentication baseline with hidden route policy, isolated Direct/WebVPN sessions, six read-only feature facades and CLI commands, live verification evidence, and handoff documentation required by `goal.md`.

**Architecture:** Keep `UbaaClient` as the only host-facing API. Add route/config/probe decisions above the existing route-scoped runtime, then add evidence-backed upstream parsers and stable DTOs below the facade. Each feature is introduced by a failing fixture/mock test, implemented minimally, and exposed through a schema-versioned CLI envelope.

**Tech Stack:** Rust 2024, Tokio, Reqwest, Serde, TOML, scraper/regex, Clap, existing injectable HTTP/session ports, deterministic fixtures and shell live verifier.

Execution note: Tasks 1-5 and the deterministic portions of Task 6 are implemented in
independent commits. The live matrix was rerun on 2026-08-19; classroom and SPOC passed,
while schedule/exam/grades and Judge remain hard-gated by live upstream/account failures.

---

### Task 1: Confirm frozen evidence and route-policy contract

**Files:**
- Modify: `docs/migration/status.md`
- Modify: `docs/migration/decision-log.md`
- Create: `docs/contracts/route-policy.md`
- Create: `docs/migration/readonly-feature-matrix.md`
- Test: `crates/ubaa-core/tests/route_policy.rs`

- [ ] Read the required frozen Kotlin interfaces/DTOs/tests and fixed examples commit; record only observed paths, fields, and unsupported cases.
- [ ] Write failing tests for DNS probe states/cache, config defaults/rejection, Campus/OffCampus/Unknown resolution, and hidden route override semantics.
- [ ] Run `cargo test --locked -p ubaa-core --test route_policy`; observe the expected missing API failures.
- [ ] Implement the smallest `RoutePolicy`, `NetworkState`, injectable probe, TOML config parser, feature matrix and diagnostic resolution types.
- [ ] Run focused tests, `just check-sensitive`, and `just check`; update status/decision evidence.
- [ ] Commit `feat: add feature route policy and campus probe`.

### Task 2: Upgrade session persistence to isolated dual slots

**Files:**
- Modify: `crates/ubaa-core/src/session.rs`
- Modify: `crates/ubaa-core/src/runtime.rs`
- Modify: `crates/ubaa-core/src/auth/mod.rs`
- Modify: `crates/ubaa-core/src/facade/mod.rs`
- Test: `crates/ubaa-core/tests/session.rs`
- Test: `crates/ubaa-test-support/tests/auth.rs`

- [ ] Add failing tests for schema-v2 dual-slot round trips, legacy single-slot migration, invalid mode/corrupt input, per-route challenge/execution isolation, partial login, aggregated status and two-route logout CAS.
- [ ] Run the focused tests and verify failures are caused by missing dual-slot behavior.
- [ ] Implement dual-slot snapshot/migration and route-scoped runtime state without copying cookies or persisting login workflow secrets.
- [ ] Implement ordered Direct/WebVPN prepare/login orchestration and safe partial-success/error mapping.
- [ ] Run focused tests, `just check-sensitive`, and `just check`.
- [ ] Commit `feat: persist isolated direct and webvpn sessions`.

### Task 3: Migrate schedule, exam and grades read-only core APIs

**Files:**
- Create: `crates/ubaa-core/src/features/schedule.rs`
- Create: `crates/ubaa-core/src/features/exam.rs`
- Create: `crates/ubaa-core/src/features/grades.rs`
- Create: `fixtures/readonly/schedule/*`, `fixtures/readonly/exam/*`, `fixtures/readonly/grades/*`
- Modify: `crates/ubaa-core/src/domain/mod.rs`, `src/upstream/mod.rs`, `src/facade/mod.rs`
- Test: `crates/ubaa-core/tests/readonly_schedule.rs`, `readonly_exam.rs`, `readonly_grades.rs`

- [ ] Add one failing fixture/parser/Mock test per operation using only fields and parameters observed in frozen evidence.
- [ ] Implement DTOs, term/week selection semantics, portal support/unsupported classification, and route-locked requests.
- [ ] Verify empty results, malformed wrappers, authentication HTML, 5xx and timeout classifications.
- [ ] Run focused tests, `just check-sensitive`, and `just check`; commit `feat: migrate schedule exam and grade read APIs`.

### Task 4: Migrate classroom, SPOC and Judge read-only core APIs

**Files:**
- Create: `crates/ubaa-core/src/features/classroom.rs`, `spoc.rs`, `judge.rs`
- Create: `fixtures/readonly/classroom/*`, `spoc/*`, `judge/*`
- Modify: `crates/ubaa-core/src/domain/mod.rs`, `src/upstream/mod.rs`, `src/facade/mod.rs`
- Test: `crates/ubaa-core/tests/readonly_classroom.rs`, `readonly_spoc.rs`, `readonly_judge.rs`

- [ ] Add failing tests for classroom date/campus requests, SPOC pagination/detail/token flow, and Judge list/single/batch/history/link parsing.
- [ ] Implement the minimum evidence-backed read-only parsers and route locks; reject all write operations.
- [ ] Verify empty/no-data, unsupported portal, auth refresh, invalid inputs and upstream failures without leaking bodies/tokens.
- [ ] Run focused tests, `just check-sensitive`, and `just check`; commit `feat: migrate judge readonly assignments` (or split only if repository scope requires it).

### Task 5: Expose feature CLI and JSON schema v2

**Files:**
- Modify: `apps/ubaa-cli/src/lib.rs`, `src/main.rs`
- Modify: `apps/ubaa-cli/tests/cli_contract.rs`, `tests/binary_e2e.rs`
- Modify: `docs/contracts/cli-json.schema.json`
- Modify: `README.md`, `docs/development/commands.md`

- [ ] Add failing CLI parser, help-surface, envelope/schema, exit-code, masking and command behavior tests for all required commands.
- [ ] Implement config-dir loading, auto route resolution, feature commands, aggregated auth output, hidden internal route override and no plaintext password option.
- [ ] Validate actual serialized JSON against schema positive and negative cases.
- [ ] Run focused CLI tests, binary E2E, `just check-sensitive`, and `just check`; commit `feat: expose readonly feature cli and json contracts`.

### Task 6: Run live matrix and complete handoff gates

**Files:**
- Modify: `scripts/verify-live.sh`, `justfile`
- Create: `docs/runbooks/live-readonly-verification.md`
- Modify: `docs/migration/status.md`, `docs/architecture/*.md`, `AGENTS.md`

- [ ] Add failing shell tests for `feature=... route=...`, safe stdin credentials, adaptive term/week/campus/date selection, redacted summaries and nonzero unsupported/failure behavior.
- [ ] Implement the verifier and route evidence matrix updates; never persist raw live data.
- [ ] Run `just refs`, `just check-sensitive`, `just check`, CLI binary E2E, and every required direct/webvpn/auto command from `goal.md`.
- [ ] Record each feature's implemented state, verified/unverified routes, empty/unsupported account result, failed command and rerun condition. Keep the final conclusion `未完成` if any hard gate fails.
- [ ] Commit `test: verify automatic routes and readonly features live` and `docs: complete readonly migration and route handoff` as separate phase commits.
