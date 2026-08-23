# Connection and Session Contract

Status: target contract; the aggregate atomic coordinator and stale-writer logout behavior require remediation before this contract is complete. The 2026-08-17 live authentication result is historical protocol evidence only.

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

Each aggregate facade stores one schema-v2 dual snapshot in `<config-dir>/session.json`, with independent Direct and WebVPN slots containing filtered cookies, route, authentication timestamp and last-activity timestamp. It does not persist username, password, CAS execution, captcha state, challenge identifiers, risk pages or business tokens. A legacy single-route snapshot migrates only into its recorded route slot.

The sidecar `.session.lock` serializes access and stores a fixed-width monotonic revision. Initial dual snapshot and revision are loaded in one critical section. One shared coordinator owns the in-memory dual snapshot and revision; every route replacement and aggregate clear constructs a complete candidate and performs exactly one compare-exchange. A stale process returns a safe retryable conflict and never reloads/adopts an external revision in order to retry. Aggregate logout performs both best-effort remote requests, clears both in-memory runtimes and route feature state, then attempts one dual persisted clear. A conflict preserves both newer persisted slots.

Writes use unique exclusively-created same-directory temporary files and synchronize before replacement. Session, lock, and configuration targets reject symlink/non-regular entries; final session/lock opens use no-follow platform flags. Session reads are capped at 1 MiB. On Unix the directory is mode 0700 and existing or new session/lock files are restricted to mode 0600. Windows uses inherited directory ACLs; owner-only ACL enforcement for custom configuration directories remains a release audit item.

The raw HTTP transport keeps TLS verification and manual redirects, and caps fully buffered authentication/User Center bodies at 8 MiB. Both limits are internal safety budgets rather than inferred upstream protocol facts. Fixed authentication endpoints are HTTPS. Redirects preserve the frozen client's compatibility with `http` and `https` only after host-policy validation; Secure cookies are never sent over HTTP.

Cookie values are sensitive runtime state even though they are required in the session file. They are never returned from public formatting, errors or logs. Explicit single-route invalidation replaces only that slot through the shared coordinator. Aggregate logout removes the file only when the facade still owns the loaded revision; a conflict clears current-process memory and leaves the complete newer persisted snapshot intact.
