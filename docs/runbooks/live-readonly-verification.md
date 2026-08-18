# Live Read-Only Verification

Prerequisites: the fixed reference worktrees pass `just refs`, `.env.local` contains non-empty `UBAA_TEST_USERNAME` and `UBAA_TEST_PASSWORD`, `jq` is installed, and the command is run from a terminal when a captcha fallback is needed. The environment file is ignored and is never copied or printed.

Run the required matrix commands:

```bash
just verify-live feature=auth route=direct
just verify-live feature=auth route=webvpn
just verify-live feature=all route=auto
just verify-live feature=schedule route=auto
just verify-live feature=exam route=auto
just verify-live feature=grades route=auto
just verify-live feature=classroom route=auto
just verify-live feature=spoc route=auto
just verify-live feature=judge route=auto
```

The verifier builds with `--locked`, uses stdin for the password, and creates a temporary owner-only config/session directory. `route=auto` writes only the non-secret `config.toml`; login attempts both route slots. Schedule selects one returned `selected=true` term when unique, otherwise the first valid `itemCode`; weeks use one unique `curWeek=true` serial, otherwise the first valid `serialNumber`. Exam and grades reuse that term. Classroom defaults to campus `1` and the `Asia/Shanghai` current date; `UBAA_VERIFY_CAMPUS_ID` and `UBAA_VERIFY_DATE` can override those values.

Output is a redacted one-line summary containing feature, policy/route, stage, stable error code, timing, and counts or presence flags. A real empty list/map is success with count zero. `unsupported_portal`, an undergraduate-incompatible account, a captcha without a controlling terminal, and upstream network/protocol failures are nonzero outcomes and must be recorded in `docs/migration/status.md` with the exact command and rerun condition. A fixture or mock result cannot be copied into this matrix as live evidence.

The historical compatibility form `just verify-live mode=direct|webvpn` remains available for the phase 5 authentication shell contract.
