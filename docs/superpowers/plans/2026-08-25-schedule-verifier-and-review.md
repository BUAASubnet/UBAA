# Schedule Verifier And Review Fix Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the live schedule verifier accept the frozen schedule DTO's observed academic-year code, clear the current Clippy gate, and apply an independent review before final verification.

**Architecture:** Keep Core parsing aligned with the frozen `WeeklySchedule` DTO. Change only the live verifier's semantic assertion so it validates a non-empty string and does not invent equality between the response display code and the requested term. Refactor the CLI contract test without changing behavior.

**Tech Stack:** Rust 2024, Cargo/Clippy, Bash, jq, sanitized fixtures, frozen `ubaa_old/` and `examples/buaa-api/` references.

---

### Task 1: Lock the observed schedule contract

**Files:**
- Modify: `scripts/test-verify-live.sh`
- Inspect: `scripts/verify-live.sh:264-277,766-776`
- Evidence: frozen `ubaa_old/.../LocalScheduleApi.kt` and `.../model/dto/Schedule.kt`

- [x] **Step 1: Write the failing regression case**

Add a valid `schedule_current` envelope whose `data.code` is a non-empty academic-year code distinct from the requested semester term, while preserving the frozen `arrangedList`, `code`, and `name` fields.

- [x] **Step 2: Run the verifier regression and observe the expected failure**

Run: `bash ./scripts/test-verify-live.sh`

Expected: the new case is rejected by the current exact-term assertion.

- [x] **Step 3: Implement the smallest verifier change**

Replace the exact `.data.code == $term` assertion with a shape/type/non-empty check. Keep term selection and the actual request parameters unchanged; do not modify the Rust DTO or parser.

- [x] **Step 4: Run the focused verifier test**

Run: `bash ./scripts/test-verify-live.sh`

Expected: the academic-year-code case is accepted and all existing unsafe/contradictory cases remain rejected.

### Task 2: Clear the Clippy gate without behavior changes

**Files:**
- Modify: `apps/ubaa-cli/tests/cli_contract.rs:926-1077`

- [x] **Step 1: Refactor the oversized assertion helper**

Split `assert_schema_rejects_invalid_routed_data` into focused helpers with the same assertions and call order.

- [x] **Step 2: Remove the one-element loop**

Assert the username sentinel directly while preserving the redaction assertion and diagnostic message.

- [x] **Step 3: Run focused tests and Clippy**

Run: `cargo test --locked -p ubaa-cli --test cli_contract` and `cargo clippy --locked --workspace --all-targets --all-features -- -D warnings`.

Expected: both pass with no warning suppression.

### Task 3: Review and follow-up fixes

**Files:**
- Review: all modified production/test/script files in the current worktree
- Update if needed: `docs/migration/source-parity.md`, `docs/migration/decision-log.md`, `docs/migration/status.md`

- [x] **Step 1: Dispatch an independent code review**

Review the verifier contract, route isolation, sensitive-output checks, and test coverage against `AGENTS.md` and `goal.md`.

- [x] **Step 2: Fix every Critical/Important finding with a new failing test first**

Do not weaken security or source-parity assertions to make live output pass.

- [x] **Step 3: Run final deterministic gates**

Run: `just refs`, `just check-sensitive`, `just check`, CLI E2E, and `./scripts/test-verify-live.sh`.

- [x] **Step 4: Re-run live schedule and the required matrix**

Use an ephemeral digest salt and record only safe route, stage, count, and stable error summaries. Keep the project incomplete if any hard gate fails.

Review follow-up: the corrected Direct/auto aggregate runs passed. WebVPN
aggregate attempts recorded strict `judge_cutoff` failures caused by changing
upstream list snapshots, and each immediate complete rerun passed. The verifier
assertions remain strict.
