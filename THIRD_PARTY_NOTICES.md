# Third-Party Notices

UBAA 2 uses the MIT-licensed `buaa-api` project as a frozen protocol reference:

- Copyright (c) 2025 Fq
- Source: `https://github.com/fontlos/buaa-api.git`
- Fixed commit: `efb7976bf513f38364b88aeb83d704586cff9b2a`
- License: MIT, available in the local reference at `examples/buaa-api/License`

The implementation consulted these `buaa-api` files for behavioral evidence:

- `src/api/sso/auth.rs`: Direct/WebVPN SSO entry points, execution form fields, and the one-time password-risk continuation.
- `src/api/user/auth.rs` and `src/api/user/opt.rs`: User Center activation/status endpoints and response intent.
- `src/store/cookies.rs`: host/domain, path, Secure, and replacement concepts; UBAA 2 independently adds expiry and persistence hardening.
- `src/api/class/data.rs`: independent evidence that WebVPN protocol segments distinguish HTTP and HTTPS.

Protocol behavior is also compared with the frozen UBAA v1 repository at commit `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`, especially its authentication, WebVPN codec, Cookie/session, DTO, and test files listed in `docs/migration/references.md`. UBAA 2 does not copy source text from either reference; it independently implements the evidenced behavior behind its own contracts and records protocol/security decisions in `docs/migration/decision-log.md`.

Rust dependency license metadata is governed by each dependency's published license. The final lockfile is the authoritative dependency inventory.
