# Migration Status

Updated: 2026-08-23

## Conclusion

阶段 7-12 曾被标记完成，但 2026-08-23 的冻结源逐操作复核发现路由、双槽位
CAS、验证码绑定、CLI 合同、Classroom、SPOC、Judge 和 live 断言仍有实质缺口。
当前结论是“修复中，未完成”。下列历史 exit-0 命令只证明当时的请求/解析路径
没有返回错误；在对应请求合同和语义断言修复并重新运行之前，不得把它们当成
当前完成证据。

## Baseline

- Branch: `ubaa2`.
- Frozen `ubaa_old/` HEAD: `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`.
- Frozen `examples/buaa-api/` HEAD: `efb7976bf513f38364b88aeb83d704586cff9b2a`.
- `just refs` on 2026-08-23 verifies both clean reference worktrees and fixed HEADs.
- `.env.local` remains a read-only sensitive input; no value is printed, logged, staged or persisted.
- The previously uncommitted `goal.md` expansion is now part of this remediation contract phase.

## Remediation Status

| Phase | Current status | Required closure |
|---|---|---|
| 0-6 baseline | Preserved | Re-run deterministic and live authentication gates after aggregate-facade changes. |
| 7 route policy | Non-conforming implementation | Replace resolver behavior with `gw.buaa.edu.cn:80` TCP reachability under one 500ms total budget; ordinary failure is OffCampus, internal failure is Unknown; cache 60s in Core facade. |
| 8 dual sessions | Concurrency defect open | Load dual snapshot/revision in one lock epoch; one shared coordinator; aggregate logout uses one CAS and cannot adopt/delete newer slots. |
| 9a schedule/exam/grades | No new defect established by this audit | Preserve existing frozen-source evidence and rerun after facade integration. |
| 9b classroom | Request/state parity gaps open | Restore exact long UA, no-redirect query, strict required `d/list`, and once-per-route synchronized state cleared with session. |
| 9c SPOC | False-empty and detail gaps open | Use global encrypted `queryListByPage` with empty `kcid` even when course metadata is empty; submission is optional; retain summary fallback; remove public raw HTML. |
| 9d Judge | Parser/cache gaps open | Filter internal links, port full problem/score/status parser, move caches to route/client state, clear them with the session. |
| 10 CLI/JSON | Contract gaps open | Aggregate Core facade owns selection; first JSON login works without pre-existing config; all output is schema v2 only; route arrays/order/cardinality are strict. |
| 11 live matrix | Must be rerun | Existing evidence predates the corrected request/parser contracts and cannot close SPOC/Judge semantics. |
| 12 handoff/gates | Not ready | Run focused RED/GREEN evidence, sensitive/full gates and the complete post-fix live matrix before changing this status. |

## Historical Live Authentication

These commands exited 0 on 2026-08-23 and established only that both
authentication routes worked at that time. They do not prove atomic logout,
captcha generation binding, Core-owned selection or any business endpoint.

| Command | Historical result |
|---|---|
| `just verify-live feature=auth route=direct` | Exit 0; `auth_status` parsed a user. |
| `just verify-live feature=auth route=webvpn` | Exit 0; `auth_status` parsed a user. |

## Historical Read-Only Commands And Limitations

| Feature | Direct historical result | WebVPN historical result | Auto historical result | Current interpretation |
|---|---|---|---|---|
| Schedule (terms/weeks/current/today) | Exit 0; all four reads parsed | Exit 0; all four reads parsed | Exit 0; all four reads parsed | Retained as historical evidence; rerun after facade routing changes. |
| Exam arrangement | Exit 0 | Exit 0 | Exit 0 | Retained as historical evidence; rerun with a term returned by schedule. |
| Grades | Exit 0 | Exit 0 | Exit 0 | Retained as historical evidence; rerun with strict old term semantics. |
| Empty classroom | Exit 0; reported 158 for campus 1/date 2026-08-23 | Exit 0; reported 158 | Exit 0; reported 158 | The result predates exact UA/no-redirect/strict-DTO remediation; rerun is required. |
| SPOC assignments/detail | Exit 0; reported empty | Exit 0; reported empty | Exit 0; reported empty | **Unverified until the global empty-`kcid` query is observed.** The current implementation can return a false empty result when course metadata is empty. No live detail ran. |
| Judge list/detail | Exit 0; reported 65 plus one detail | Exit 0; reported 17 plus one detail | Exit 0; reported 65 plus one detail | Counts are historical observations only. Detail score/problem/status semantics are unverified, and the Direct 65/WebVPN 17 difference is unresolved. |

The following individual command summaries are retained as historical command
evidence, not current acceptance:

```text
feature=schedule route=auto: exit 0; terms/weeks/current/today parsed
feature=exam route=auto: exit 0; term selected and response parsed
feature=grades route=auto: exit 0; term selected and response parsed
feature=classroom route=auto: exit 0; result_count=158 date=2026-08-23
feature=spoc route=auto: exit 0; reported result_count=0; INVALID AS EMPTY-SEMANTICS PROOF
feature=judge route=auto: exit 0; reported result_count=65 plus one detail; DETAIL SEMANTICS UNVERIFIED
```

Additional explicit-route commands historically exited 0:

```text
schedule direct/webvpn: terms/weeks/current/today parsed on both
exam direct/webvpn: parsed on both
grades direct/webvpn: parsed on both
classroom direct/webvpn: reported result_count=158 on both
spoc direct/webvpn: reported result_count=0 on both; global empty-kcid request not established
judge direct: reported result_count=65 plus one detail
judge webvpn: reported result_count=17 plus one detail
```

The historical aggregate
`just verify-live feature=all route=auto` also exited 0 after reporting each
feature successful. It is not a current hard-gate pass because SPOC could have
short-circuited before the authoritative global query, Judge detail assertions
did not cover the old parser semantics, and automatic selection used the
superseded resolver/CLI-owned implementation.

Historical failed Judge attempts remain relevant: explicit Direct previously
returned `upstream_unavailable`; later WebVPN/auto attempts returned `timeout`
or `upstream_changed`; stale sampled IDs returned not found. These observations
show upstream volatility but select neither a permanent route nor a parser
contract. The 65/17 count divergence must be investigated using safe in-memory
IDs/counts after the parser/cache fixes; it must not be normalized or hidden.

## Historical Deterministic Gates

Before this audit, the following passed:

- `cargo test --locked --workspace`.
- `cargo clippy --locked --workspace --all-targets -- -D warnings`.
- `cargo test --locked -p ubaa-cli --test binary_e2e` (10 passed).
- `cargo test --locked -p ubaa-test-support --test readonly` (19 passed).
- `cargo test --locked -p ubaa-test-support --test support` (8 passed).
- `./scripts/test-verify-live.sh`.
- `just refs`, `just check-sensitive`, and `just check`.

Those passes describe the pre-remediation implementation. They do not validate
the newly corrected contract and must be rerun after every production phase.
CI remains deterministic-only and never reads `.env.local`.

## Open Defects And Evidence Gaps

- Production automatic selection still needs the accepted TCP reachability implementation and Core-facade ownership.
- Dual logout/session mutation still needs one shared snapshot/revision coordinator and stale-writer tests.
- Route/generation-bound captcha IDs and zero-request user preflight remain required.
- Config writes must match the documented symlink, regular-file and unique-temp safety behavior.
- Classroom must be compared against the exact frozen UA/redirect/DTO/state contract.
- SPOC empty-list evidence is invalid until the encrypted global request has `kcid=""`; a non-empty account is still needed to live-check optional submission/detail fallback.
- Judge detail semantics and cache lifecycle are unverified; the 65/17 route difference is unresolved.
- All CLI envelope branches, including argument errors and hidden diagnostics, must become schema v2 only.
- No write operation is migrated: submission/upload, answers, reservations, attendance, grading changes and other side effects remain out of scope.
- Windows owner-only directory ACL enforcement remains a release-audit item from the baseline.

## Rerun Handoff

1. Complete each focused RED/GREEN remediation phase and run `just check-sensitive` plus `just check` before its commit.
2. Run `just refs`, `just check-sensitive`, `just check`, CLI binary E2E and verifier regression from the final clean tree.
3. Run authentication on Direct/WebVPN, then all six explicit routes and each `auto` feature with the facade-owned TCP probe.
4. For SPOC, assert the live list actually reached the global empty-`kcid` operation; if non-empty, read one detail and treat submission failure as optional.
5. For Judge, assert safe parser semantics (problem/status/score presence rules), compare route counts without persisting IDs/titles, and record the unresolved cause if 65/17 or another difference remains.
6. Only after the corrected aggregate `all/auto` and every required gate pass may this document return to “complete”.
