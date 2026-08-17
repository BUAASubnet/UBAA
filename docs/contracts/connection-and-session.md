# Connection and Session Contract

Status: implemented and fixture-tested in phase 2; live verification remains pending.

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

Each client stores one `SessionSnapshot` in `<config-dir>/session.json`: connection mode, filtered cookies, authentication timestamp and last-activity timestamp. It does not persist username or password. On Unix the directory is mode 0700 and the file is mode 0600; other platforms use the platform filesystem access model and require a platform-specific permission audit before release.

Cookie values are sensitive runtime state even though they are required in the session file. They are never returned from public formatting, errors or logs. Logout and explicit invalidation remove the file.
