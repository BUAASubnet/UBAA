# Connection and Session Contract

Status: implemented and deterministic-tested; live Direct/WebVPN authentication passed on 2026-08-17.

## Evidence map

| Behavior | Frozen evidence | Rust coverage |
|---|---|---|
| Direct URLs remain direct | `LocalWebVpnSupport.kt::localUpstreamUrl` | `tests/connection.rs` |
| WebVPN gateway is `d.buaa.edu.cn` | `LocalWebVpnSupport.kt`, `VpnCipher.kt`, `examples/buaa-api/src/api/sso/auth.rs` | `tests/connection.rs` |
| Protocol segment is scheme for no/default port, otherwise `scheme-port` | `LocalWebVpnSupport.kt::toWebVpnUrl` and `VpnCipher.kt::toVpnUrl` | HTTP, HTTPS, default and custom-port tests |
| Host encoding uses AES/CFB/NoPadding with protocol constant `wrdvpnisthebest!` as key and IV | `LocalWebVpnSupport.kt`, platform AES implementations, `VpnCipher.kt` | URL round-trip tests |
| Path, query and fragment are retained | both frozen WebVPN implementations and tests | path/query/fragment round-trip tests |
| Already wrapped URLs are unchanged | both frozen WebVPN implementations | idempotence test |
| Absolute, protocol-relative, root-relative and path-relative redirects resolve from the current URL | `LocalConnectionAuth.kt::resolveRedirectUrl` | redirect table tests |
| Authentication redirects are restricted to SSO, User Center and gateway hosts | `goal.md` security contract plus observed auth URLs | rejection tests for unverified hosts |
| Authentication redirects accept only HTTP or HTTPS after host validation | `LocalConnectionAuth.kt::resolveRedirectUrl`, WebVPN protocol-segment tests | non-HTTP allowed-host rejection tests |
| Cookie filters include host/domain, path, Secure, expiration and replacement | `LocalConnectionAuth.kt::PersistentLocalCookieStorage`, `LocalCookieStoreTest.kt`, `examples/buaa-api/src/store/cookies.rs` | `tests/cookies.rs` |
| Explicit invalidation clears a session; timeout/5xx preserve it | `validateLocalConnectionSession` and `getAuthStatus` | `tests/session.rs` policy test |

## Persistence

Each client stores one `SessionSnapshot` in `<config-dir>/session.json`: connection mode, filtered cookies, authentication timestamp and last-activity timestamp. It does not persist username or password. The sidecar `.session.lock` serializes access and stores a fixed-width monotonic revision; the session JSON schema remains unchanged. Loads return the snapshot and revision under one lock. Saves and clears compare-exchange that revision, advance and synchronize it before mutating `session.json`, and reject stale processes instead of overwriting or deleting newer state.

Writes use unique exclusively-created same-directory temporary files and synchronize before replacement. Session, lock, and configuration targets reject symlink/non-regular entries; final session/lock opens use no-follow platform flags. Session reads are capped at 1 MiB. On Unix the directory is mode 0700 and existing or new session/lock files are restricted to mode 0600. Windows uses inherited directory ACLs; owner-only ACL enforcement for custom configuration directories remains a release audit item.

The raw HTTP transport keeps TLS verification and manual redirects, and caps fully buffered authentication/User Center bodies at 8 MiB. Both limits are internal safety budgets rather than inferred upstream protocol facts. Fixed authentication endpoints are HTTPS. Redirects preserve the frozen client's compatibility with `http` and `https` only after host-policy validation; Secure cookies are never sent over HTTP.

Cookie values are sensitive runtime state even though they are required in the session file. They are never returned from public formatting, errors or logs. Logout and explicit invalidation remove the file only when the runtime still owns the loaded revision; a conflict clears that runtime's memory and leaves newer persisted state intact.
