# Review Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repair the review findings while preserving the live-verified Direct/WebVPN authentication contract and making the repository safer to extend.

**Architecture:** Keep `UbaaClient` as the only host-facing facade, move mutable transport/session state into a private runtime, and let `auth` and `features/user` own protocol workflows. Sensitive public types use redacted formatting; persistence and live verification receive explicit safety boundaries.

**Tech Stack:** Rust 1.95, Tokio, reqwest, serde, scraper, Bash, just, GitHub Actions.

---

### Task 1: Redacted public diagnostics

**Files:**
- Modify: `crates/ubaa-core/src/ports/mod.rs`
- Modify: `crates/ubaa-core/src/domain/mod.rs`
- Modify: `crates/ubaa-core/src/session.rs`
- Modify: `crates/ubaa-core/src/error/mod.rs`
- Modify: `crates/ubaa-core/src/auth/mod.rs`
- Modify: `crates/ubaa-core/src/output.rs`
- Modify: `apps/ubaa-cli/src/lib.rs`
- Test: `crates/ubaa-core/tests/contracts.rs`, `apps/ubaa-cli/src/lib.rs`

- [x] Write tests that format requests, responses, login input, challenge, profile, stored cookie, session snapshot, and errors containing sentinel secrets, and assert none of the sentinel values occur.
- [x] Run the focused contract and CLI tests and confirm they fail because derived `Debug` exposes the sentinels.
- [x] Replace derived formatting with redacted implementations or remove unnecessary `Debug`; redact URLs, bodies, header values, Cookie values, captcha image/answer, profile fields, and pending login HTML.
- [x] Run the focused tests, then `cargo test --locked -p ubaa-core -p ubaa-cli`.
- [x] Commit as `fix: redact sensitive diagnostics`.

### Task 2: Protocol classification and exit semantics

**Files:**
- Modify: `crates/ubaa-core/src/features/user.rs`
- Modify: `crates/ubaa-core/src/error/mod.rs`
- Test: `crates/ubaa-test-support/tests/auth.rs`, `crates/ubaa-core/tests/contracts.rs`

- [x] Add a test for lowercase and mixed-case HTML User Center responses that expects `authentication_required` and cleared persisted state.
- [x] Add a test that expects `PasswordRiskConfirmationFailed` to use the authentication exit category.
- [x] Run both focused tests and observe the current implementation fail.
- [x] Match the frozen Kotlin `ignoreCase=true` classification and map password-risk failure to exit 3 without changing its machine code.
- [x] Run the focused tests and the complete authentication test module.
- [x] Commit as `fix: align auth classification and exits`.

### Task 3: Private client runtime and facade delegation

**Files:**
- Create: `crates/ubaa-core/src/runtime.rs`
- Modify: `crates/ubaa-core/src/lib.rs`
- Modify: `crates/ubaa-core/src/facade/mod.rs`
- Modify: `crates/ubaa-core/src/auth/mod.rs`
- Modify: `crates/ubaa-core/src/features/user.rs`
- Modify: `apps/ubaa-cli/src/lib.rs`
- Test: existing `crates/ubaa-test-support/tests/auth.rs` and `crates/ubaa-core/tests/session.rs`

- [x] Add a compile-level/API test proving `UbaaClient` is a concrete host-facing type while `with_transport` still accepts deterministic test ports.
- [x] Run the focused test and record the current generic facade/API shape as the expected failure.
- [x] Introduce a private runtime holding mode, boxed transport/store, Cookie jar, timestamps, URL conversion, request execution, persistence, and cleanup; move authentication workflow into `auth` and User Center operations into `features/user`.
- [x] Keep all existing request ordering, redirect policy, cookie behavior, and error codes unchanged; run all existing auth tests after each extraction.
- [x] Update host trait bounds and docs to consume the concrete facade.
- [x] Commit as `refactor: separate client runtime from facade workflows`.

### Task 4: Response and session persistence hardening

**Files:**
- Modify: `crates/ubaa-core/Cargo.toml`, `Cargo.lock`
- Modify: `crates/ubaa-core/src/ports/mod.rs`
- Modify: `crates/ubaa-core/src/session.rs`
- Test: `crates/ubaa-core/tests/session.rs`, `crates/ubaa-test-support/tests/support.rs`
- Modify: `docs/adr/0003-url-crypto-cookie-session.md`

- [x] Add focused tests for rejecting an oversized response, refusing session-directory/file symlinks or non-regular files, and safe repeated/concurrent saves.
- [x] Run them and confirm the current unbounded body and fixed temporary filename behavior fails the tests.
- [x] Add bounded streaming response collection, an exclusively-created unique temporary file, serialized session access, flush/sync before replacement, Unix permission enforcement, and a documented Windows access-control audit while preserving the JSON format.
- [x] Run session and transport tests on the current platform and document the chosen bound/locking dependency in the ADR.
- [x] Commit as `fix: harden response and session persistence`.

### Task 5: Captcha-aware live verifier and process coverage

**Files:**
- Modify: `scripts/verify-live.sh`
- Modify: `docs/runbooks/live-auth-verification.md`
- Modify: `docs/development/setup.md`, `docs/development/commands.md`
- Modify: `apps/ubaa-cli/tests/binary_e2e.rs`
- Test: `apps/ubaa-cli/tests/binary_e2e.rs`

- [x] Add a shell-testable branch for exit code 4 and a binary test for saved-session logout/session cleanup.
- [x] Run the focused tests and show the current verifier exits immediately on captcha and the binary suite lacks the success-adjacent path.
- [x] Add `jq`/TTY preflight, human fallback that feeds the environment password through stdin while forwarding captcha input from `/dev/tty`, suppress human profile stdout, and preserve redacted JSON summaries.
- [x] Add the deterministic binary session test without introducing a production localhost override or changing the fixed upstream URLs.
- [x] Run CLI unit, contract, and binary tests.
- [x] Commit as `test: cover captcha verifier and binary session flow`.

### Task 6: Cross-platform CI and contract-driven schema checks

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `apps/ubaa-cli/tests/cli_contract.rs`
- Modify: `docs/development/testing.md`, `docs/development/setup.md`

- [x] Add a test that serializes real success and failure envelopes and validates those bytes against `docs/contracts/cli-json.schema.json`.
- [x] Run it and confirm the current hand-authored-only schema test does not exercise serialization.
- [x] Add the serialization test and a macOS/Windows Rust matrix for format, clippy, test, build, and docs; retain Linux-only refs/sensitive/live exclusions where shell tooling is required.
- [x] Run all local deterministic checks and validate workflow YAML syntax.
- [x] Commit as `ci: broaden deterministic verification coverage`.

### Task 7: Documentation, evidence, and decisions

**Files:**
- Modify: `docs/contracts/auth-and-user.md`
- Modify: `docs/contracts/connection-and-session.md`
- Modify: `docs/architecture/overview.md`, `docs/architecture/core-boundaries.md`
- Modify: `docs/migration/status.md`, `docs/migration/decision-log.md`
- Modify: `docs/runbooks/live-auth-verification.md`
- Modify: `docs/development/testing.md`, `THIRD_PARTY_NOTICES.md`

- [x] Add the frozen-evidence decision for preserving HTTP redirect compatibility and list adapted evidence files/scope.
- [x] Update all phase/live status labels, actual commit hashes, current verification summaries, and the next-slice boundary without recording secrets.
- [x] Document the new runtime/module boundaries, captcha fallback, platform caveats, and deterministic-vs-live evidence levels.
- [x] Run `git diff --check` and inspect all staged files for sensitive content.
- [x] Commit as `docs: synchronize remediation contracts and evidence`.

### Task 8: Final verification and handoff

**Files:**
- Verify: repository-wide

- [ ] Run `just refs`.
- [ ] Run `just check-sensitive`.
- [ ] Run `just check`.
- [ ] Run `cargo test --locked --workspace --all-targets` and the CLI binary tests explicitly.
- [ ] Run `just verify-live mode=direct` and `just verify-live mode=webvpn`; if captcha is requested, exercise the documented human fallback without recording the answer or image.
- [ ] Confirm `git status --short --branch`, staged-content inspection, and the migration report match the final repository state.
