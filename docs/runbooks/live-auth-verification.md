# Live Authentication Verification

Status: local-only verifier implemented and deterministically tested. Fresh Direct and WebVPN authentication checks passed on the corrected 2026-08-26 HEAD; older 2026-08-17 and 2026-08-23 results remain historical observations only.

Live verification loads only the two required variable names from the ignored `.env.local`, builds with locked dependencies, passes username and password through standard input, uses a mode-0700 temporary configuration directory, logs in, fetches the User Center profile, and validates `auth status`. Every parsed CLI value must be a schema-v2 envelope with closed metadata. Profile checks require the complete stable eight-field DTO, nonempty name/school ID, and an already-masked or absent phone/identity number. Aggregate `all_ready` or `partial` output must contain that profile, while `none_ready` must omit it. Failed routes must carry a stable safe error, ready routes must omit errors, and no route result may contain challenge or image fields. If the upstream login page requires an interactive verification step, Core returns `upstream_changed`; the verifier records the safe failure and does not prompt, fetch an image, or retry. Known credential, session, request and response key aliases are rejected independently of their value. It records only policy/route, outcome, duration, stable error code, and whether required profile fields were parsed. The script keeps command output in memory and removes its temporary directory on exit; it never retains raw responses, Cookie headers, verification material, or profile fields.

Run each mode explicitly:

```bash
just verify-live feature=auth route=direct
just verify-live feature=auth route=webvpn
```

These explicit commands use the hidden route-locked diagnostic entry point to establish each route independently. The historical `mode=direct|webvpn` form remains only as a compatibility alias. Read-only and `auto` verification instead performs aggregate login and requires the atomic Direct/WebVPN coordinator to make both slots ready.

Never attach raw output, session files, cookies, upstream verification material, or complete profile fields to an issue or commit.

## Evidence log

| Mode | Status | Evidence |
|---|---|---|
| Direct | Passed on corrected 2026-08-26 HEAD | Fresh `auth_status` verification exited 0 and parsed the user on Direct |
| WebVPN | Passed on corrected 2026-08-26 HEAD | Fresh `auth_status` verification exited 0 and parsed the user on WebVPN |

There is no human fallback. The verifier permanently disables inherited shell xtrace before reading `.env.local`; it never prints or records the password, digest salt, Judge payload, upstream verification material, or complete profile. An `upstream_changed` login result is a hard evidence failure for that route and must be recorded with the exact rerun condition rather than worked around interactively.
