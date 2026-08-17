# Live Authentication Verification

Status: local-only verifier implemented; Direct and WebVPN both verified on 2026-08-17.

Live verification loads only the two required variable names from the ignored `.env.local`, passes the password through standard input, uses a mode-0700 temporary configuration directory, logs in, fetches the User Center profile, and validates `auth status`. It records only mode, outcome, duration, error code, and the first character/last two characters of the parsed name and school ID. The script keeps command output in memory and removes its temporary directory on exit; it never writes raw responses, Cookie headers, captcha images, or complete profile fields.

Run each mode explicitly:

```bash
just verify-live mode=direct
just verify-live mode=webvpn
```

Never attach raw output, session files, cookies, captcha images, or complete profile fields to an issue or commit.

## Evidence log

| Mode | Status | Evidence |
|---|---|---|
| Direct | Real verification passed on 2026-08-17 | Exit 0; profile parsed; `auth status` passed in 77 ms; name prefix `李`; school ID suffix `04` |
| WebVPN | Real verification passed on 2026-08-17 | Exit 0; profile parsed; `auth status` passed in 190 ms; name prefix `李`; school ID suffix `04` |

Exit code 4 means the upstream requires a captcha. JSON mode deliberately stops before credential submission; rerun in human mode in a terminal to provide the image answer without recording it.
