# UBAA 2

UBAA 2 is a Rust core plus host applications for Beijing University of Aeronautics and Astronautics services. The current contract builds the authentication and User Center foundation for Direct and WebVPN access, with a CLI as the first host.

## Current state

Repository foundation is being established. Authentication behavior is not complete until both live modes pass the gates recorded in `docs/migration/status.md`.

## Setup

```bash
just refs
cargo build --workspace
```

Run the CLI during development with `cargo run -p ubaa-cli -- --help`. The final authentication commands and output contract are documented in `docs/contracts/auth-and-user.md`.

## Verification

```bash
just check
just verify-live mode=direct
just verify-live mode=webvpn
```

Live verification requires an ignored `.env.local` containing `UBAA_TEST_USERNAME` and `UBAA_TEST_PASSWORD`. It never accepts the password as a command-line argument.

## Scope

This repository currently targets authentication, session management, and User Center profile retrieval. Flutter, MCP, server relay, schedule, exams, grades, and all other campus services are not migrated.

