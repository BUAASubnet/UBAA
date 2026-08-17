# UBAA 2

UBAA 2 is a Rust core plus host applications for Beijing University of Aeronautics and Astronautics services. The current contract builds the authentication and User Center foundation for Direct and WebVPN access, with a CLI as the first host.

## Current state

The Rust Core and CLI authentication path are implemented, deterministic-tested, and verified against both live Direct and WebVPN modes. The current redacted evidence and remaining platform audit item are recorded in `docs/migration/status.md`.

## Setup

```bash
just refs
cargo build --locked --workspace
cargo install --locked --path apps/ubaa-cli
```

Run the CLI during development with `cargo run --locked -p ubaa-cli -- --help`.

```bash
# Interactive password entry; no password is accepted as an argument.
cargo run --locked -p ubaa-cli -- auth login --mode direct --username YOUR_USERNAME
cargo run --locked -p ubaa-cli -- auth login --mode webvpn --username YOUR_USERNAME

# Reuse and validate the persisted session.
cargo run --locked -p ubaa-cli -- auth status
cargo run --locked -p ubaa-cli -- user show
cargo run --locked -p ubaa-cli -- auth logout

# Automation reads one password line from stdin and emits one JSON envelope.
printf '%s\n' "$UBAA_TEST_PASSWORD" |
  cargo run --locked -p ubaa-cli -- --json auth login --mode direct \
    --username "$UBAA_TEST_USERNAME" --password-stdin
```

The default session location is the operating system's per-user configuration directory. Use `--config-dir <path>` for isolated tests. The output contract is documented in `docs/contracts/auth-and-user.md` and `docs/contracts/cli-json.schema.json`.

After a session has been saved, a later `auth login` may omit `--mode` to reuse that session's Direct or WebVPN strategy. A first login must specify the mode explicitly.

## Verification

```bash
just check
just verify-live mode=direct
just verify-live mode=webvpn
```

Live verification requires an ignored `.env.local` containing `UBAA_TEST_USERNAME` and `UBAA_TEST_PASSWORD`. It never accepts the password as a command-line argument.

## Scope

This repository currently targets authentication, session management, and User Center profile retrieval. Human and JSON output mask phone and identity-document numbers. Flutter, MCP, server relay, schedule, exams, grades, and all other campus services are not migrated.
