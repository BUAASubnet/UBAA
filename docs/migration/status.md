# Migration Status

Updated: 2026-08-27

## Conclusion

阶段 7-12 曾被标记完成，但 2026-08-23 的冻结源逐操作复核发现路由、双槽位、
SPOC/Judge 语义和 live verifier 仍有实质缺口。本轮已补齐确定性实现、回归测试、
source-parity 记录和二次审查；截至 2026-08-26，认证、六类只读功能的 Direct/WebVPN
显式矩阵、`all/auto`、`all/direct` 和最新 `all/webvpn` 均通过。一次较早的
`all/webvpn` 运行因 Judge 两次上游列表快照漂移触发严格 `judge_cutoff`，即时重跑后
通过；这些失败和成功均保留在下方，不放宽验证器。因此当前代码门禁结论为“已修复、
最新完整矩阵通过”，但上游快照波动仍是运行时重试条件。

## Baseline

- Branch: `ubaa2`.
- Frozen `ubaa_old/` HEAD: `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`.
- Frozen `examples/buaa-api/` HEAD: `efb7976bf513f38364b88aeb83d704586cff9b2a`.
- `just refs` on 2026-08-23 verifies both clean reference worktrees and fixed HEADs.
- `.env.local` remains a read-only sensitive input; no value is printed, logged, staged or persisted.
- The previously uncommitted `goal.md` expansion is now part of this remediation contract phase.

## Remediation Status

### 2026-08-28 Cgyy/Bykc/扩展只读 CLI

Cgyy 场馆预约五项只读查询已完成 DTO、解析器、路线隔离业务会话、Core Facade、CLI 双执行路径和 JSON Schema；Bykc 五项只读查询同样已完成。当前 CLI 已覆盖合同六类业务以及 Signin、Ygdk、LibBook、Bykc、Cgyy 的全部只读入口。所有真实上游验证仍需按路线矩阵单独执行，不能由 Mock 或编译通过替代。

### 2026-08-27 Ygdk

Ygdk 阳光打卡已完成只读概览与记录的 Core 解析、独立 OAuth/业务令牌请求、路线 facade、CLI `ygdk overview`/`ygdk records` 及 JSON Schema 接线。提交打卡和照片上传仍明确排除；Direct/WebVPN 真实上游验证尚未完成。

| Phase | Current status | Required closure |
|---|---|---|
| 0-6 baseline | Preserved; final deterministic gates passed | Frozen references, sensitive-data scan, format, Clippy, workspace tests, build, docs and diff checks pass on the current tree. |
| 7 route policy | Deterministic remediation complete; live Direct/auto/WebVPN resolution accepted | TCP target/total budget/failure classes, explicit-policy probe bypass, 60-second single-flight cache and Core-owned operation resolution are covered; future WebVPN retries may encounter transient upstream Judge snapshot drift. |
| 8 dual sessions | Deterministic remediation complete; aggregate login live-checked | Atomic load, shared coordinator, route-logical CAS, uncertain-write termination, unconditional remote attempts, one-CAS aggregate logout, terminal conflict fail-fast and whole-facade invalidation are covered; aggregate Direct/WebVPN login succeeded in the accepted `all` runs. |
| 8a authentication verification boundary | Deterministic remediation complete | The old challenge registry, image fetch, answer binding and captcha exit contract are removed. A `config.captcha` or other interactive verification marker returns `upstream_changed` before image fetch or credential POST; the sanitized regression proves the one-GET/no-POST boundary. |
| 9a schedule/exam/grades | Corrected live Direct/auto aggregate and WebVPN explicit runs passed | Schedule display `code` is validated as a non-empty string independent of the requested term, matching the frozen parser and live shape; preserve the source-parity record. |
| 9b classroom | Corrected live Direct/auto aggregate and WebVPN explicit runs passed | Exact long UA, one no-follow query, strict required `e/m/d/list` and room strings, best-effort once-per-route synchronization, route isolation, and session lifecycle clearing are covered and live-checked. |
| 9c SPOC | Corrected live Direct/auto aggregate and WebVPN explicit runs passed | The hidden diagnostic observed one authoritative global page on each accepted run; the empty result is therefore evidence-backed. Non-empty detail remains conditional on upstream data. |
| 9d Judge | Direct/auto/WebVPN aggregate accepted on the latest complete matrix | Frozen DOM/problem/score/status parsing, link filtering, grouped four-worker batch reads, clamped cutoff, bounded route/client caches, lifecycle invalidation, safe diagnostics, and terminal UC arbitration are covered. Judge list snapshots can drift between the two required reads; the verifier remains strict and a transient `judge_cutoff` failure is recorded rather than normalized. |
| 9e 签到查询 | Core 解析、独立 iClass 会话、facade 与 CLI 已接入；真实路线待验证 | `signin today` 使用路线隔离的 iClass 业务会话，按旧版固定跳转、登录参数和今日查询参数实现；脱敏解析与确定性接线已覆盖。必须补充 Direct/WebVPN live 验证后才能标记为完整迁移。签到提交仍不在范围内。 |
| 9f 扩展只读查询 | Signin、Ygdk、LibBook、Bykc、Cgyy 的只读 Core/CLI 已接入；真实路线待验证 | 各功能的业务令牌、签名、分页和解析均按冻结来源实现；写操作、验证码和锁码仍未迁移。需为扩展功能补充真实验收命令或明确记录未验证状态。 |
| 10 CLI/JSON | Deterministic remediation complete; final CLI E2E passed | Ordinary commands use the aggregate Core facade; every renderer, startup/argument failure and hidden diagnostic emits schema v2; aggregate auth/logout metadata and route data are fixed Direct then WebVPN; unsafe config targets and concurrent atomic writes are covered. |
| 10a live verifier | Deterministic remediation complete | The harness rejects unsafe errors, non-v2/wrong aggregate order, invalid integer bounds, cross-request term/SPOC identity drift, missing SPOC query proof, incomplete Judge semantics, route contradictions, sensitive/raw output and Judge JSON in argv; it proves xtrace suppression and username/password stdin routing. Production verification is non-interactive and records an upstream interactive verification page as `upstream_changed`. |
| 11 live matrix | Latest complete matrix passed; transient WebVPN Judge snapshot failures retained | Keep the strict `judge_cutoff` subset check and rerun the complete aggregate when upstream list volatility causes a nonzero result. |
| 12 handoff/gates | Ready for continued development; worktree remains intentionally uncommitted | `just refs`, `just check-sensitive`, `just check`, CLI E2E, auth Direct/WebVPN, all six explicit routes, `all/auto`, `all/direct`, and the latest `all/webvpn` passed. Commit separation and future live reruns remain release-process work. |

## 2026-08-26 Corrected Live Matrix

Only safe counts, route metadata and stable outcomes are recorded here. No
assignment IDs, titles, response bodies, cookies, tokens or digest salt are
stored.

## 2026-08-28 扩展只读实时结果

使用临时进程内摘要盐运行 `feature=all route=auto`，未保存盐值或任何敏感
响应。课表、考试、成绩、空闲教室、SPOC、Judge、图书馆和场馆预约均成功；
Signin 与 Ygdk 在业务登录页返回 `upstream_changed`；Bykc 在 CLI 聚合路由修复
后仍返回 `authentication_required`，表示业务 CAS 会话未建立。随后单独运行
`feature=auth route=direct` 成功，但 `feature=bykc route=auto` 仍未通过语义门禁。
这些结果只证明本次真实运行的具体功能状态，不把认证成功推导为业务成功。
同日 `feature=auth route=webvpn` 认证成功，但 `feature=cgyy route=webvpn`
返回 `authentication_required`，因此场馆 WebVPN 业务路线仍未验证通过。
Bykc 首次结果的 `invalid_semantics` 后经审计确认为验证器误将合法分页字段
`data.content` 判为敏感键；修复提交 `adc3d4f` 后，`feature=bykc route=direct`
成功并解析到 1 条课程。该结果不替代 WebVPN 路线验证。

| Run | Result |
|---|---|
| `feature=all route=auto` | Exit 0; resolved Direct; all six features passed. Classroom count 158; SPOC global page count 1 with empty assignments; Judge counts course/raw/filtered/current/cutoff `5/88/83/65/18`, detail present. |
| `feature=all route=direct` | Exit 0; all six features passed. Judge counts `5/88/83/65/18`, detail present. |
| `feature=schedule`, `exam`, `grades`, `classroom`, `spoc`, `judge` on Direct | Exit 0 for each; Judge counts `5/88/83/65/18`, detail present; SPOC global page count 1 with empty assignments. |
| `feature=schedule`, `exam`, `grades`, `classroom`, `spoc`, `judge` on WebVPN | Exit 0 for each; Judge standalone counts `5/49/49/17/32`, detail present; SPOC global page count 1 with empty assignments. |
| `feature=all route=webvpn` first attempt | Exit 1 at strict `judge_cutoff`; schedule/exam/grades/classroom/SPOC passed. The failure is retained as upstream snapshot volatility evidence. |
| `feature=all route=webvpn` immediate rerun | Exit 0; all six features passed. Judge counts `5/77/57/17/40`, detail present. |
| final `feature=all route=webvpn` verification attempt | Exit 1 at strict `judge_cutoff`; schedule/exam/grades/classroom/SPOC passed. The failure is retained as upstream snapshot volatility evidence. |
| final immediate `feature=all route=webvpn` rerun | Exit 0; all six features passed. Judge counts `5/77/57/17/40`, detail present. |

## 2026-08-26 Deterministic Gates

- `just refs`: passed for both frozen commits listed above.
- `just check-sensitive`: passed; no credentials, cookies, tokens, captcha data or raw live material entered the checked tree.
- `just check`: passed, including format, Clippy with `-D warnings`, all workspace tests, shell verifier regression, build, docs and diff checks.
- `cargo test --locked -p ubaa-cli --test binary_e2e`: 11 passed.
- `bash ./scripts/test-verify-live.sh`: passed.

These repository gates are deterministic and were rerun after the production fixes. The live
matrix above is separate evidence; it is not replaced by fixture or Mock success.

## Historical Live Authentication

These commands exited 0 on 2026-08-23 and established only that both
authentication routes worked at that time. They do not prove atomic logout,
the intentionally unsupported interactive-verification boundary, Core-owned selection or any business endpoint.

| Command | Historical result |
|---|---|
| `just verify-live feature=auth route=direct` | Exit 0; `auth_status` parsed a user. |
| `just verify-live feature=auth route=webvpn` | Exit 0; `auth_status` parsed a user. |

## Historical Read-Only Commands And Limitations

| Feature | Direct historical result | WebVPN historical result | Auto historical result | Current interpretation |
|---|---|---|---|---|
| Schedule (terms/weeks/current/today) | Exit 0; all four reads parsed | Exit 0; all four reads parsed | Exit 0; all four reads parsed | Pre-fix historical evidence only; current Direct/WebVPN/auto cells remain pending. |
| Exam arrangement | Exit 0 | Exit 0 | Exit 0 | Pre-fix historical evidence only; rerun with a term returned by schedule. |
| Grades | Exit 0 | Exit 0 | Exit 0 | Pre-fix historical evidence only; rerun with strict old term semantics. |
| Empty classroom | Exit 0; reported 158 for campus 1/date 2026-08-23 | Exit 0; reported 158 | Exit 0; reported 158 | The result predates exact UA/no-redirect/strict-DTO remediation; rerun is required. |
| SPOC assignments/detail | Exit 0; reported empty | Exit 0; reported empty | Exit 0; reported empty | **Unverified until the global empty-`kcid` query is observed.** The pre-remediation implementation could return a false empty result when course metadata was empty. No live detail ran. |
| Judge list/detail | Exit 0; reported 65 plus one detail | Exit 0; reported 17 plus one detail | Exit 0; reported 65 plus one detail | Counts are historical observations only. That sampled detail did not prove score/problem/status semantics, and the Direct 65/WebVPN 17 difference is unresolved. |

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
superseded host-owned resolver implementation.

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

- Production automatic selection now uses the accepted TCP reachability implementation and Core-facade ownership; corrected Direct/auto and latest WebVPN aggregate evidence is accepted. A transient WebVPN Judge snapshot failure remains recorded and must be retried strictly if it recurs.
- Interactive verification is intentionally unsupported: the Core regression proves that `config.captcha` causes `upstream_changed` after the login-page GET with no image request or credential POST. A live occurrence is a hard-gate upstream-change result, not a reason to add a prompt or bypass.
- Config persistence now has deterministic symlink, regular-file, unique-temp, permission and concurrent-write coverage; real routing configuration behavior remains part of the later live matrix.
- Classroom now matches the frozen UA/redirect/DTO/state contract in deterministic tests and passed the corrected Direct/auto aggregate plus WebVPN explicit runs.
- SPOC transport tests now capture and decrypt both actual global page requests, including `kcid=""`; corrected live diagnostics observed one authoritative global page on Direct, WebVPN and auto. Non-empty detail/submission semantics remain conditional on upstream data.
- Judge parser, detail, cutoff, grouped batch and cache lifecycle are deterministically covered. Direct/auto and the latest WebVPN aggregate passed safe semantic checks; multiple WebVPN aggregate attempts failed `judge_cutoff` because upstream list snapshots drifted, and each immediate rerun passed, so the strict check remains unchanged. Route-local count differences remain observations, not normalization rules.
- Judge terminal business-authentication failures now have a source-backed UC arbitration path under test and live-ready behavior: only explicit UC Invalid clears the selected route; valid or unavailable UC results preserve the primary session and return retryable `upstream_unavailable`.
- CLI schema v2 and the live verifier's semantic rejection cases are deterministically covered for routed, unresolved, aggregate, SPOC query/detail identity, and Judge list/detail output. Judge cross-request comparison uses stdin rather than argv. Interactive verification fields and error codes are absent from the schema. This establishes verifier behavior only, not a real route result.
- No write operation is migrated: submission/upload, answers, reservations, attendance, grading changes and other side effects remain out of scope.
- Windows owner-only directory ACL enforcement remains a release-audit item from the baseline.

## Rerun Handoff

1. On future upstream changes, rerun `just refs`, `just check-sensitive`, `just check`, CLI binary E2E and verifier regression from the integrated tree.
2. Generate one ephemeral `UBAA_VERIFY_DIGEST_SALT`, keep it only in the current shell for comparable Judge digests, and never record its value.
3. Rerun `feature=auth` on Direct and WebVPN, `feature=all route=auto`, every feature on both explicit routes, and both complete explicit aggregates. Every multi-request feature must retain one resolved route.
4. For SPOC, require `global_page_count >= 1`; if non-empty, require one detail. For Judge, require course/raw-anchor/filtered/current/cutoff counts and one semantic detail when available.
5. Record only safe route, timing, count, presence, stable error and salted-digest summaries. If list snapshots drift, retain the strict failure and rerun; never normalize route differences or weaken subset checks.
