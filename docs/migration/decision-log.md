# Decision Log

## 2026-08-17: Execute the authentication contract from frozen evidence

The active design is `goal.md`. The old and example repositories match their required HEAD and origins and are clean. No protocol conflict has been identified during the initial inventory. Unknown upstream behavior will not be guessed; it will be recorded here with evidence before a decision.

## 2026-08-17: Preserve verified HTTP redirect compatibility

Fixed SSO and User Center entry points remain HTTPS and TLS verification remains enabled. Redirect resolution continues to accept both `http://` and `https://` only for the authentication host allow-list. This follows `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalConnectionAuth.kt::resolveRedirectUrl`, which explicitly recognizes both schemes, and the frozen WebVPN URL codec/tests that preserve HTTP protocol segments. Rejecting HTTP would be an unevidenced protocol change. Secure-cookie filtering still prevents Secure cookies from being sent over HTTP.

## 2026-08-17: Keep the public facade concrete and runtime private

Hosts consume the non-generic `UbaaClient`; injected transport and session ports are boxed inside private `ClientRuntime`. Authentication and User Center workflows live in `auth` and `features/user`, while `facade` delegates stable DTO operations. This keeps host APIs independent of upstream and storage implementation types without removing deterministic port injection.

## 2026-08-17: Add bounded buffering and locked session replacement

Authentication/User Center response bodies are capped at 8 MiB and persisted session JSON at 1 MiB. These are conservative UBAA 2 memory/file safety budgets, not upstream protocol facts. Session operations reject symlink/non-regular targets, use a sidecar OS lock and unique exclusive temporary files, synchronize writes, and preserve the existing JSON schema. Windows inherits the selected directory ACL; explicit owner-only ACL enforcement remains a release audit item.

## 2026-08-17: Preserve JSON captcha non-interactivity

JSON login still returns `captcha_required` with exit 4 before credential submission and without image data. The local live verifier handles that result by starting a fresh human CLI in the same controlling terminal, feeding only the environment password through stdin, reading the captcha answer from `/dev/tty`, suppressing human profile stdout, and resuming redacted JSON checks. No cross-process challenge persistence was invented.
