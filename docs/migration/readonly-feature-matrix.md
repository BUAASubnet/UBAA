# Read-Only Feature Evidence Matrix

This matrix separates source evidence from real upstream evidence. `fixture` and `mock` prove deterministic behavior only. A route stays `unverified` until a real business request and parser succeed on that route.

| Feature / operation | Unknown default | Direct | WebVPN | Auto | Latest live evidence |
|---|---|---|---|---|---|
| Schedule terms/weeks/current/today | Direct | Success: exit 0; all four reads parsed | Success: exit 0; all four reads parsed | Success: exit 0; all four reads parsed | AAS activation and form encoding are now evidenced in `bc45882`; rerun when refreshing term/week data. |
| Exam arrangement | Direct | Success: exit 0 | Success: exit 0 | Success: exit 0 | Term discovery and exam parse succeeded on all three policies. |
| Grades list | Direct | Success: exit 0 | Success: exit 0 | Success: exit 0 | Legacy local score protocol and returned term parsed on all three policies. |
| Empty classroom search | Direct | Success: 158 parsed results, 2026-08-19 | Success: 158 parsed results, 2026-08-19 | Success: 158 parsed results for 2026-08-19 | Direct, WebVPN and auto all verified for the current campus/date; rerun if that input changes. |
| SPOC assignment list/detail | Direct | Success: empty list | Success: empty list | Success: empty list, `result_count=0` | Empty real result is recorded on all three routes; rerun with an assignment-bearing account to exercise detail. |
| Judge list/single/batch details | WebVPN auto override | Not verified; earlier explicit Direct attempt was `upstream_unavailable` (exit 5) | Real list/detail success exists | Latest required run exit 0 with list plus one detail; aggregate auto exit 0 | Direct remains unverified. Re-run only when Direct evidence is needed; never infer success from a prior count or fixture. |

All six rows currently disallow ready-route and network-error fallback. Judge uses a matrix route override, not fallback: the operation starts on WebVPN under `auto`. This is deterministic and intentional until frozen/live evidence proves an idempotent replay contract. The verifier never writes raw bodies, Cookies, tokens, captcha images, complete names, IDs, phones, email addresses, or credentials. The latest required aggregate passed; Judge Direct remains unverified.
