# Read-Only Feature Evidence Matrix

This matrix separates source evidence from real upstream evidence. `fixture` and `mock` prove deterministic behavior only. A route stays `unverified` until a real business request and parser succeed on that route.

| Feature / operation | Unknown default | Direct | WebVPN | Auto | Latest live evidence |
|---|---|---|---|---|---|
| Schedule terms/weeks/current/today | Direct | Failed: `authentication_required` at `schedule_terms` (exit 3) | Failed: `authentication_required` at `schedule_terms` (exit 3) | Failed: `authentication_required` at `schedule_terms` (exit 3) | Account must have undergraduate portal capability; rerun Direct/WebVPN/auto schedule commands. |
| Exam arrangement | Direct | Failed: shared `schedule_terms` `authentication_required` (exit 3) | Failed: shared `schedule_terms` `authentication_required` (exit 3) | Failed: shared `schedule_terms` `authentication_required` (exit 3) | Rerun Direct/WebVPN/auto with a supported undergraduate account. |
| Grades list | Direct | Failed: shared `schedule_terms` `authentication_required` (exit 3) | Failed: shared `schedule_terms` `authentication_required` (exit 3) | Failed: shared `schedule_terms` `authentication_required` (exit 3) | Rerun Direct/WebVPN/auto with a supported term and score portal. |
| Empty classroom search | Direct | Success: 158 parsed results, 2026-08-18 | Success: 158 parsed results, 2026-08-18 | Success: 158 parsed results for 2026-08-18 | Direct, WebVPN and auto all verified for the current campus/date; rerun if that input changes. |
| SPOC assignment list/detail | Direct | Success: empty list | Success: empty list | Success: empty list, `result_count=0` | Empty real result is recorded on all three routes; rerun with an assignment-bearing account to exercise detail. |
| Judge list/single/batch details | Direct | Failed: `upstream_unavailable` (exit 5) | Failed: `upstream_changed` (exit 6) | Failed: `upstream_unavailable` (exit 5) | Restore Judge TLS/upstream availability/course access and rerun Direct/WebVPN/auto. |

All six rows currently disallow ready-route and network-error fallback. This is deterministic and intentional until frozen/live evidence proves an idempotent replay contract. The verifier never writes raw bodies, Cookies, tokens, captcha images, complete names, IDs, phones, email addresses, or credentials.
