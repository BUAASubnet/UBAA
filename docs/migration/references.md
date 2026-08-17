# Frozen References

| Reference | Remote | Fixed commit | Purpose |
|---|---|---|---|
| `ubaa_old/` | `https://github.com/BUAASubnet/UBAA.git` | `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e` | Current Kotlin local Direct/WebVPN authentication, parser, Cookie, DTO, and tests |
| `examples/buaa-api/` | `https://github.com/fontlos/buaa-api.git` | `efb7976bf513f38364b88aeb83d704586cff9b2a` | Independent Rust SSO, User Center, request, Cookie, credential, and error evidence |

Both directories are local, ignored, nested Git repositories. Read them at the fixed commits; do not modify, stage, tag, or copy credentials from them. Run `just refs` to clone missing references or fail if an existing reference is dirty, has another origin, or is at another commit. There is no `ubaa-v1-reference` tag, and this repository does not invent one.

Source priority is live upstream evidence, frozen UBAA v1 implementation/tests, fixed `buaa-api`, then architecture documents. Conflicts are recorded in `decision-log.md` before implementation.

