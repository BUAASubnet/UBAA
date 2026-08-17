# Decision Log

## 2026-08-17: Execute the authentication contract from frozen evidence

The active design is `goal.md`. The old and example repositories match their required HEAD and origins and are clean. No protocol conflict has been identified during the initial inventory. Unknown upstream behavior will not be guessed; it will be recorded here with evidence before a decision.

## 2026-08-17: Preserve verified HTTP redirect compatibility

Fixed SSO and User Center entry points remain HTTPS and TLS verification remains enabled. Redirect resolution continues to accept both `http://` and `https://` only for the authentication host allow-list. This follows `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalConnectionAuth.kt::resolveRedirectUrl`, which explicitly recognizes both schemes, and the frozen WebVPN URL codec/tests that preserve HTTP protocol segments. Rejecting HTTP would be an unevidenced protocol change. Secure-cookie filtering still prevents Secure cookies from being sent over HTTP.

The scheme and host checks are both mandatory. Non-HTTP schemes such as `ftp` are rejected even when their host is otherwise allowed, and WebVPN conversion never encodes them.

## 2026-08-17: Keep the public facade concrete and runtime private

Hosts consume the non-generic `UbaaClient`; injected transport and session ports are boxed inside private `ClientRuntime`. Authentication and User Center workflows live in `auth` and `features/user`, while `facade` delegates stable DTO operations. `upstream` is crate-private, and the CLI uses `UbaaClient::open` rather than inspecting `FileSessionStore`. This keeps host APIs independent of upstream and storage implementation types without removing deterministic port injection.

## 2026-08-17: Add bounded buffering and locked session replacement

Authentication/User Center response bodies are capped at 8 MiB and persisted session JSON at 1 MiB. These are conservative UBAA 2 memory/file safety budgets, not upstream protocol facts. Session operations reject symlink/non-regular targets, open final files without following links, restore owner-only Unix permissions, use a sidecar OS lock and unique exclusive temporary files, synchronize writes, and preserve the existing `session.json` schema.

The sidecar lock also stores a synchronized monotonic revision. A runtime loads the snapshot and revision atomically, then compare-exchanges every save, invalidation, mode-mismatch clear, and logout clear. The revision is advanced and synchronized before replacing or deleting `session.json`; a crash may cause a conservative conflict but cannot authorize a stale writer. This prevents snapshot-equality ABA and ensures an old process cannot recreate a cleared session or delete a newer one. Windows inherits the selected directory ACL; explicit owner-only ACL enforcement remains a release audit item.

## 2026-08-17: Preserve JSON captcha non-interactivity

JSON login still returns `captcha_required` with exit 4 before credential submission and without image data. The local live verifier handles that result by starting a fresh human CLI in the same controlling terminal, feeding only the environment password through a private FIFO, polling `/dev/tty` only while that CLI is alive, suppressing human profile stdout, and resuming redacted JSON checks. It disables terminal echo for the complete captcha interaction, restores the original terminal state on every exit path, closes and removes the FIFO, and terminates/waits the child on HUP/INT/TERM with a bounded KILL fallback. This also handles the evidenced case where the fresh preparation no longer requires captcha. No cross-process challenge persistence was invented.

## 2026-08-17: Preserve remote-first logout while protecting local revisions

Both `LocalConnectionAuth.kt::logout` and the remote-backed `AuthApi.kt::logout` attempt remote logout before clearing local state. UBAA 2 preserves that evidenced order and always clears the current client's in-memory Cookie/login state. The persisted clear is revision-conditional so a stale process cannot delete a newer local session. Frozen code and current live evidence do not define whether a stale process's remote logout can invalidate a concurrently created upstream session, so future long-lived hosts must serialize logout for a shared account rather than inventing a remote concurrency guarantee.

## 2026-08-17: Require locked dependency resolution in deterministic gates

`just check`, macOS/Windows CI, the live verifier, and documented user commands use `--locked` for every Cargo command that resolves dependencies. `just check` first runs `cargo metadata --locked --no-deps --format-version 1`; a cross-platform binary test uses the Git index to scan tracked Markdown, `justfile`, workflow, and shell command sources so later edits cannot silently remove the lock contract. `cargo fmt` is exempt because it does not resolve the dependency graph.
