# Live Authentication Verification

Status: not runnable until phase 5.

Live verification loads the two required variables from the ignored `.env.local`, passes the password through standard input, uses a temporary configuration directory, logs in, fetches the User Center profile, and validates `auth status`. It records only mode, outcome, duration, error code, and masked proof that name and school ID exist.

Run each mode explicitly:

```bash
just verify-live mode=direct
just verify-live mode=webvpn
```

Never attach raw output, session files, cookies, captcha images, or complete profile fields to an issue or commit.

