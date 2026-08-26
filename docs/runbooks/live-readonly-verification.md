# Live Read-Only Verification

Prerequisites: the fixed reference worktrees pass `just refs`, `.env.local` contains non-empty `UBAA_TEST_USERNAME` and `UBAA_TEST_PASSWORD`, and `jq` and `openssl` are installed. The environment file is ignored and is never copied or printed.

Run the required matrix commands:

```bash
export UBAA_VERIFY_DIGEST_SALT="$(openssl rand -hex 16)"

just verify-live feature=auth route=direct
just verify-live feature=auth route=webvpn
just verify-live feature=all route=auto
for feature in schedule exam grades classroom spoc judge; do
  just verify-live feature="$feature" route=direct
  just verify-live feature="$feature" route=webvpn
done

unset UBAA_VERIFY_DIGEST_SALT
```

The verifier builds with `--locked`, uses stdin for the password, and creates a temporary owner-only config/session directory. Every read-only run uses aggregate login and requires both Direct and WebVPN slots; `route=auto` writes only the non-secret `config.toml`, then the Core facade probes `gw.buaa.edu.cn:80` with one 500 ms total TCP budget and resolves the feature route. All requests belonging to one feature run must report the same resolved route or verification fails. Schedule selects one returned `selected=true` term when unique, otherwise the first valid `itemCode`; every returned week must name that same term, while the current-schedule wrapper must only provide the frozen `arrangedList`, non-empty `code`, and `name` shape. The current wrapper's display `code` is independent of the requested semester term. Exam and grades reuse the selected term, and grades must return it. Classroom defaults to campus `1` and the `Asia/Shanghai` current date; `UBAA_VERIFY_CAMPUS_ID` and `UBAA_VERIFY_DATE` can override those values.

Output is a redacted one-line summary containing feature, policy and resolved route, stage, stable error code, timing, and safe counts or presence flags. The in-memory parser rejects any non-v2 envelope, unsafe or malformed stable error, aggregate route order other than Direct then WebVPN, route drift, incomplete or extra fields relative to stable DTOs, fractional or out-of-range Rust integer fields, unmasked phone/identity fields, cross-request term mismatches, contradictory status/count/text values, impossible Judge diagnostic counts, forbidden credential/session/raw-response aliases, obvious complete upstream HTML documents or CAS forms, and duplicate Judge keys. It does not classify arbitrary angle-bracket text or fragments as HTML because normalized assignment text may legitimately contain encoded tag examples; exact DTO closure plus deterministic Core parser tests establish that no raw HTML field is exposed. Schedule `dayOfWeek` is null or `1..7`; every grade row repeats the requested wrapper term. `unsupported_portal`, an undergraduate-incompatible account, an upstream interactive verification page, and upstream network/protocol failures are nonzero outcomes and must be recorded in `docs/migration/status.md` with the exact command and rerun condition. A fixture or Mock result cannot be copied into this matrix as live evidence.

SPOC verification uses the hidden diagnostic facade path and requires `globalPageCount` in `1..=u32::MAX`; only then can an empty `result.assignments` be accepted as a real empty authoritative global query. Summary `UNKNOWN` text must contain a nonempty unknown raw value and must not contain any submitted/unsubmitted value recognized by the frozen mapping. Detail may use bare `未知状态`, but a parenthesized value has the same exclusion. A non-empty result triggers one detail read whose `assignmentId` and optional `courseId` must both equal the sampled summary. The hidden command adds no upstream request and returns only the ordinary result plus the safe page count.

Judge verification requires `UBAA_VERIFY_DIGEST_SALT` for both `feature=judge` and `feature=all`. Use the same fresh in-memory salt for routes being compared, then unset it. The hidden diagnostic path returns course, raw-anchor and filtered-unique counts plus ordinary summaries. IDs must remain nonempty digit strings, course `"0"` is invalid, DTO counts stay within nonnegative `i32`, and diagnostic counts stay within JSON's exact-integer ceiling. The verifier also checks that the current list is a subset of `--include-expired`, records the cutoff-skip count, validates one detail's score/problem/status semantics when available, and prints only a short salted digest of sorted identifiers. Full current/include-expired payloads are compared through jq stdin, never command arguments. It never prints or persists those identifiers, titles, bodies, raw HTML, Cookies, tokens, captcha data, or the salt.

For Judge, a non-empty list triggers exactly one detail read. The sample is the first item returned by that same list response. This is deliberate: the list and detail commands run in separate CLI processes, so selecting a later ID can race a changing upstream list and produce a false `not found`; the verifier must not retry with an invented ID or suppress that error. Direct, WebVPN, and `auto` are separate evidence rows. The 2026-08-26 evidence in `docs/migration/readonly-feature-matrix.md` retains transient strict `judge_cutoff` failures and the immediate complete WebVPN reruns that passed; a future failure remains nonzero until its own complete rerun passes.

The historical compatibility form `just verify-live mode=direct|webvpn` remains available for the phase 5 authentication shell contract.
