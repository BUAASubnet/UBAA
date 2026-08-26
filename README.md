# UBAA 2

UBAA 2 is a Rust core plus host applications for Beijing University of Aeronautics and Astronautics services. This slice provides automatic Direct/WebVPN routing, dual-route authentication, User Center, and six read-only campus features.

## Current state

Authentication, Core-owned route policy, the atomic dual-session coordinator, CLI schema v2, and the six read-only implementations are covered by deterministic tests. The corrected 2026-08-26 HEAD passed fresh Direct/WebVPN authentication plus the auto, Direct, and latest WebVPN six-feature live aggregates. Strict WebVPN Judge verification also recorded transient upstream list-snapshot drift before an immediate complete rerun passed. The safe evidence and rerun conditions are tracked in `docs/migration/status.md`; fixture, Mock, or verifier-harness success is not live protocol evidence.

## Setup

```bash
just refs
cargo build --locked --workspace
cargo install --locked --path apps/ubaa-cli
```

Run the CLI during development with `cargo run --locked -p ubaa-cli -- --help`.

```bash
# Interactive password entry; ordinary login prepares both internal routes.
cargo run --locked -p ubaa-cli -- auth login --username YOUR_USERNAME

# Reuse and validate the persisted session.
cargo run --locked -p ubaa-cli -- auth status
cargo run --locked -p ubaa-cli -- user show
cargo run --locked -p ubaa-cli -- auth logout

# Automation reads one password line from stdin and emits one JSON envelope.
printf '%s\n' "$UBAA_TEST_PASSWORD" |
  cargo run --locked -p ubaa-cli -- --json auth login \
    --username "$UBAA_TEST_USERNAME" --password-stdin
```

The default session location is the operating system's per-user configuration directory. Use `--config-dir <path>` for isolated tests. The output contract is documented in `docs/contracts/auth-and-user.md` and `docs/contracts/cli-json.schema.json`.

`config.toml` controls `auto|direct|webvpn` policy per feature. For `auto`, the Core facade performs a process-cached TCP reachability probe to `gw.buaa.edu.cn:80` with one 500 ms total budget, then resolves Campus to Direct and OffCampus to WebVPN. Ordinary users do not choose an internal connection mode; tests and the live verifier use hidden diagnostic-only commands and route overrides.

Every JSON success or failure is one schema-v2 envelope. `config.toml` format version 1 and `session.json` format version 2 are separate on-disk contracts, not CLI schema versions.

Read-only examples:

```bash
cargo run --locked -p ubaa-cli -- schedule terms
cargo run --locked -p ubaa-cli -- grades list --term 2025-2026-1
cargo run --locked -p ubaa-cli -- classroom search --campus 1 --date 2026-09-01
cargo run --locked -p ubaa-cli -- judge assignments
```

## Verification

```bash
just refs
just check-sensitive
just check
just verify-live feature=auth route=direct
just verify-live feature=auth route=webvpn

# Required for Judge/all route-comparison digests; do not persist it.
export UBAA_VERIFY_DIGEST_SALT="$(openssl rand -hex 16)"
just verify-live feature=all route=auto
unset UBAA_VERIFY_DIGEST_SALT
```

Live verification requires an ignored `.env.local` containing `UBAA_TEST_USERNAME` and `UBAA_TEST_PASSWORD`, plus `UBAA_VERIFY_DIGEST_SALT` for `feature=judge|all`. It never accepts the password as a command-line argument, and the verifier prints only safe route, timing, count, presence, and salted-digest summaries. See the two live runbooks before running the complete matrix.

## Scope

This slice targets authentication, session management, User Center, and read-only schedule, exam, grades, classroom, SPOC, and Judge access. Human and JSON output mask phone and identity-document numbers. Flutter, MCP, server relay, and all write operations remain out of scope.
