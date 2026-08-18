# Read-Only Feature Evidence Matrix

This matrix separates source evidence from real upstream evidence. `fixture` and `mock` prove deterministic behavior only. A route stays `unverified` until a real business request and parser succeed on that route.

| Feature / operation | Unknown default | Direct | WebVPN | Auto | Latest live evidence |
|---|---|---|---|---|---|
| Schedule terms/weeks/current/today | Direct | Unverified | Unverified | Failed: `authentication_required` at `schedule_terms` (exit 3) | Account must have undergraduate portal capability; rerun `just verify-live feature=schedule route=auto`. |
| Exam arrangement | Direct | Unverified | Unverified | Failed: shared `schedule_terms` `authentication_required` (exit 3) | Rerun with a supported undergraduate account: `just verify-live feature=exam route=auto`. |
| Grades list | Direct | Unverified | Unverified | Failed: shared `schedule_terms` `authentication_required` (exit 3) | Rerun with a supported term and score portal: `just verify-live feature=grades route=auto`. |
| Empty classroom search | Direct | Unverified | Unverified | Success: 158 parsed results for 2026-08-18 | Auto is verified for the current network/default campus/date; explicit routes remain unverified. |
| SPOC assignment list/detail | Direct | Unverified | Unverified | Success: empty list, `result_count=0` | Empty real result is recorded; rerun with an assignment-bearing account to exercise detail. |
| Judge list/single/batch details | Direct | Unverified | Unverified | Failed: `upstream_unavailable` (exit 5) | Restore Judge upstream availability/course access and rerun `just verify-live feature=judge route=auto`. |

All six rows currently disallow ready-route and network-error fallback. This is deterministic and intentional until frozen/live evidence proves an idempotent replay contract. The verifier never writes raw bodies, Cookies, tokens, captcha images, complete names, IDs, phones, email addresses, or credentials.
