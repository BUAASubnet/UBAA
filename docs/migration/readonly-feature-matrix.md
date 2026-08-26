# Read-Only Feature Evidence Matrix

Updated: 2026-08-26

This matrix separates source/deterministic evidence from real upstream evidence. Fixtures, Mock transports, parser tests, and verifier-harness tests do not prove current upstream behavior. The 2026-08-23 rows below are pre-remediation history; the current rows record only corrected verifier runs from 2026-08-26.

## Current acceptance state

| Feature / operation | Unknown default | Direct | WebVPN | Auto | Required current evidence |
|---|---|---|---|---|---|
| Schedule terms/weeks/current/today | Direct | Passed (aggregate) | Passed (explicit) | Passed (aggregate; resolved Direct) | All four operations return schema v2 and one consistent resolved route; term/week are selected from live data. |
| Exam arrangement | Direct | Passed (aggregate) | Passed (explicit) | Passed (aggregate; resolved Direct) | Live schedule term discovery plus arranged/not-arranged parse on the same resolved route. |
| Grades list | Direct | Passed (aggregate) | Passed (explicit) | Passed (aggregate; resolved Direct) | Live strict `yyyy-yyyy-semester` term and matching returned `termCode`. |
| Empty classroom search | Direct | Passed (aggregate) | Passed (explicit) | Passed (aggregate; resolved Direct) | Authoritative strict wrapper/room parse for the chosen campus/date; a real empty map is allowed. |
| SPOC assignment list/detail | Direct | Passed (aggregate; global page observed) | Passed (explicit; global page observed) | Passed (aggregate; global page observed) | Hidden diagnostic proves at least one authoritative global page; a non-empty list also proves one detail. |
| Judge list/single detail (batch is deterministic-only) | Direct | Passed (aggregate; 5/88/83/65/18, detail yes) | Passed on latest aggregate; one transient `judge_cutoff` retained (5/77/57/17/40) | Passed (aggregate; 5/88/83/65/18, detail yes) | Safe course/raw-anchor/filtered/current/cutoff counts, one semantic detail when available, and comparable salted digests. |

The corrected 2026-08-26 live runs accepted `feature=all` on Direct and on
`route=auto` (which resolved to Direct). Classroom returned 158 rows, SPOC
reported one authoritative global page with an empty assignment result, and
Judge reported the safe counts shown above. Every explicit feature passed on
both routes, including standalone Judge list/detail checks. The first complete
WebVPN aggregate attempt failed only at the strict Judge `judge_cutoff` check;
an immediate rerun passed with a different safe snapshot (`5/77/57/17/40`).
A later final verification attempt showed the same strict failure followed by
another passing immediate rerun. These failures are retained as upstream list
volatility evidence, not hidden by weakening the subset/cutoff assertion.

## Historical pre-remediation observations

On 2026-08-23, schedule, exam, grades, and classroom commands exited 0 on Direct, WebVPN, and auto; classroom reported 158 items for campus `1` and date `2026-08-23`. SPOC reported empty on all three policies, but the verifier did not prove that the authoritative empty-`kcid` global operation ran. Judge reported 65 assignments on Direct, 17 on WebVPN, and 65 on auto plus one sampled detail, but the old verifier did not prove complete problem/score/status semantics. These values are retained only to guide reruns and investigate route divergence; they do not pass any current cell.

All six rows disallow ready-route and network-error fallback. Each `auto` row follows the Core facade's TCP result: Campus -> Direct, OffCampus -> WebVPN, and Unknown -> Direct. The verifier requires the same resolved route for every request in one feature run. It never writes raw bodies, Cookies, tokens, captcha images, complete profile fields, assignment identifiers/titles, or credentials; Judge comparison prints only a salted in-memory digest. Direct, auto, and the latest WebVPN aggregate runs are accepted; future reruns may still need to repeat a strict Judge aggregate when upstream snapshots drift.
