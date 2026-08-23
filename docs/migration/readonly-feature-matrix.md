# Read-Only Feature Evidence Matrix

This matrix separates source evidence from real upstream evidence. `fixture` and `mock` prove deterministic behavior only. A route stays `unverified` until a real business request and parser succeed on that route.

| Feature / operation | Unknown default | Direct | WebVPN | Auto | Latest live evidence |
|---|---|---|---|---|---|
| Schedule terms/weeks/current/today | Direct | 2026-08-23: exit 0; all four reads parsed | 2026-08-23: exit 0; all four reads parsed | 2026-08-23: exit 0; all four reads parsed | AAS activation and form encoding are evidenced in `bc45882`; rerun when term/week data changes. |
| Exam arrangement | Direct | 2026-08-23: exit 0 | 2026-08-23: exit 0 | 2026-08-23: exit 0 | Term discovery and exam parse succeeded on all three policies. |
| Grades list | Direct | 2026-08-23: exit 0 | 2026-08-23: exit 0 | 2026-08-23: exit 0 | Legacy local score protocol and returned term parsed on all three policies. |
| Empty classroom search | Direct | 2026-08-23: exit 0, 158 results | 2026-08-23: exit 0, 158 results | 2026-08-23: exit 0, 158 results | Verified with campus `1` and Asia/Shanghai date `2026-08-23`; rerun when campus/date changes. |
| SPOC assignment list/detail | Direct | 2026-08-23: exit 0, empty list | 2026-08-23: exit 0, empty list | 2026-08-23: exit 0, empty list | Empty real result is recorded on all three routes; rerun with an assignment-bearing account to exercise detail. |
| Judge list/single/batch details | Direct | 2026-08-23: exit 0, 65 assignments plus one detail | 2026-08-23: exit 0, 17 assignments plus one detail | 2026-08-23: exit 0, 65 assignments plus one detail | Fresh campus evidence proves both routes; `auto` follows Campus -> Direct. Historical `upstream_unavailable`/`upstream_changed` runs remain documented only as rerun volatility. |

All six rows currently disallow ready-route and network-error fallback. Each `auto` row follows Campus -> Direct, OffCampus -> WebVPN, and Unknown -> Direct. The verifier never writes raw bodies, Cookies, tokens, captcha images, complete names, IDs, phones, email addresses, or credentials. The latest required aggregate passed.
