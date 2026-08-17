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
| Cookie filters include host/domain, path, Secure, expiration and replacement | `LocalConnectionAuth.kt::PersistentLocalCookieStorage`, `LocalCookieStoreTest.kt`, `examples/buaa-api/src/store/cookies.rs` | `tests/cookies.rs` |
| Explicit invalidation clears a session; timeout/5xx preserve it | `validateLocalConnectionSession` and `getAuthStatus` | `tests/session.rs` policy test |

## Persistence

Each client stores one `SessionSnapshot` in `<config-dir>/session.json`: connection mode, filtered cookies, authentication timestamp and last-activity timestamp. It does not persist username or password. Access is serialized by a sidecar file lock; writes use unique exclusively-created same-directory temporary files, synchronize before replacement, and reject symlink/non-regular targets. Session reads are capped at 1 MiB. On Unix the directory is mode 0700 and the session/lock files are mode 0600. Windows uses inherited directory ACLs; owner-only ACL enforcement for custom configuration directories remains a release audit item.

The raw HTTP transport keeps TLS verification and manual redirects, and caps fully buffered authentication/User Center bodies at 8 MiB. Both limits are internal safety budgets rather than inferred upstream protocol facts. Fixed authentication endpoints are HTTPS. Redirects preserve the frozen client's compatibility with `http` and `https` only after host-policy validation; Secure cookies are never sent over HTTP.

Cookie values are sensitive runtime state even though they are required in the session file. They are never returned from public formatting, errors or logs. Logout and explicit invalidation remove the file.
