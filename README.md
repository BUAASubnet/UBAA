# UBAA 2

UBAA 2 is a Rust core plus host applications for Beijing University of Aeronautics and Astronautics services. This slice provides automatic Direct/WebVPN routing, dual-route authentication, User Center, and six read-only campus features.

## Current state

Authentication, route policy, dual-slot sessions, and read-only parsers are deterministic-tested. Real route and feature evidence is tracked separately in `docs/migration/status.md`; parser or Mock success is not live protocol evidence.

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

`config.toml` controls `auto|direct|webvpn` policy per feature. Ordinary users do not choose an internal connection mode; tests and the live verifier use a hidden diagnostic override.

Read-only examples:

```bash
cargo run --locked -p ubaa-cli -- schedule terms
cargo run --locked -p ubaa-cli -- grades list --term 2025-2026-1
cargo run --locked -p ubaa-cli -- classroom search --campus 1 --date 2026-09-01
cargo run --locked -p ubaa-cli -- judge assignments
```

## Verification

```bash
just check
just verify-live mode=direct
just verify-live mode=webvpn
just verify-live feature=all route=auto
```

Live verification requires an ignored `.env.local` containing `UBAA_TEST_USERNAME` and `UBAA_TEST_PASSWORD`. It never accepts the password as a command-line argument.

## Scope

This slice targets authentication, session management, User Center, and read-only schedule, exam, grades, classroom, SPOC, and Judge access. Human and JSON output mask phone and identity-document numbers. Flutter, MCP, server relay, and all write operations remain out of scope.
