# Live Authentication Verification

Status: local-only verifier implemented; Direct and WebVPN both verified on 2026-08-17.

Live verification loads only the two required variable names from the ignored `.env.local`, passes the password through standard input, uses a mode-0700 temporary configuration directory, logs in, fetches the User Center profile, and validates `auth status`. It records only mode, outcome, duration, error code, and the first character/last two characters of the parsed name and school ID. The script keeps command output in memory and removes its temporary directory on exit; it never retains raw responses, Cookie headers, captcha images, or complete profile fields.

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

If the initial JSON login returns exit code 4, the verifier automatically starts one fresh human login in the same controlling terminal. The password still comes from `.env.local` through standard input. If the fresh preparation still requires captcha, the CLI prints the path of a mode-0600 temporary image and reads a non-empty answer from `/dev/tty`; if it no longer requires captcha, the verifier detects the completed CLI instead of waiting for an unused answer. Human profile output is suppressed and the image is deleted when the command ends. The verifier then resumes JSON `user show` and `auth status` checks. It never prints or records the password, captcha answer, image, or complete profile.

Run the live verifier from an interactive terminal. When no readable and writable `/dev/tty` exists, captcha returns exit 4 with `captcha_required_noninteractive`; start the same command in a terminal rather than piping or logging an answer.
