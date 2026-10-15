# UBAA 2 Agent Guide

## Authority

`goal.md` is the active execution contract. `UBAA2.md` describes the longer migration roadmap. Authentication protocol facts must come from live upstream evidence, then the frozen `examples/ubaa_old/` implementation and tests, then `examples/buaa-api/` at the commits recorded in `docs/migration/references.md`.

## Safety boundaries

- Treat `examples/`, `.env.local`, runtime sessions, captcha images, and live responses as read-only sensitive inputs.
- Never commit credentials, cookies, tokens, raw live bodies, complete personal data, or captcha images.
- UI 运行截图、录屏等验收媒体保存到仓库外的私有目录，不纳入 Git；`docs/design/evidence/` 仅提交原型源文件、文字记录、元数据与摘要。`UBAA_UI_EVIDENCE_DIR` 必须指向仓库外目录；应用图标、静态地图和 golden 测试基准属于工程资源，继续按现有规则管理。归档与旧提交映射见 `docs/design/evidence/README.md`。
- Never disable TLS verification or infer an upstream field or URL without evidence.
- Do not expose `upstream` internals to hosts; hosts use the `facade` API.

## Development loop

首次建立缺失的冻结引用时显式运行 `just refs-bootstrap`；普通开发、验证和发布阶段只运行纯校验的 `just refs`，
不得让验证命令隐式联网或改写冻结目录。

1. Run `git status --short --branch` and `just refs`.
2. Update `docs/migration/status.md` and decision records with current facts.
3. 行为变更或缺陷修复先用有意义的失败反例证明问题；纯文案、样式、文档及可逆机械改动复用已有覆盖，不添加语言自证、固定文案缺席或 Widget 数量断言。整理测试时登记删除项对应的保留覆盖。
4. 实现最小变更，先运行聚焦检查，再用 `just check-plan` / `just check-changed` 按影响范围验证；比较已提交分支时传入 `base=<基线>`。安全、协议、并发、存储和跨语言边界修改保留完整相关门禁。未知影响保守全量。
5. Inspect staged files for sensitive material and keep each phase in a separate commit.

## Project map

- `crates/ubaa-core`: domain, ports, session, connection, authentication, upstream parsing, and facade.
- `crates/ubaa-test-support`: sanitized fixtures and deterministic test transports.
- `apps/ubaa-cli`: human and JSON command-line host.
- `fixtures/auth`: sanitized protocol fixtures only.
- `docs/contracts`: stable public and CLI contracts.
- `docs/migration`: evidence, status, and decision history.
- `scripts`: 按 bootstrap/check/build/live/release/tests 分类的稳定门禁；副作用见 `scripts/README.md`。

## Completion gate

日常阶段按上述改动范围运行检查；修改测试框架、门禁、公共合同或完成跨模块整理时，必须运行 `just refs`、`just layout-check`、`just check-sensitive`、`just check` 及 `just flutter-check`。PR/CI 保留完整确定性检查，不以选择性检查替代最终验收。

认证/读取协议与发布验收另需 CLI 端到端、`just verify-live mode=direct` 和 `just verify-live mode=webvpn`；纯 UI 文案或测试整理不因此触发真实学校请求。Fixture/Mock 成功不代表真实协议成功，CI 永不接收真实凭据。

## Mandatory source-parity gate

Every authentication or read-only feature change must be behaviorally compared against both frozen sources before production code is changed:

- `examples/ubaa_old/` at the commit in `docs/migration/references.md`, including its API interface, DTO, local implementation, and tests;
- `examples/buaa-api/` at the pinned commit, including the nearest equivalent API module, request/redirect code, data model, crypto, cookie/credential store, and error handling.

The comparison must be recorded in `docs/migration/source-parity.md` or a linked decision record. It must cover, separately for each operation: business CAS/bootstrap URL and service parameter, redirect and final-URL rules, Cookie/session scope, HTTP method and exact parameters, headers and body encoding, encryption/signature constants, DTO and parser fields/types, caching/concurrency, and error/exit semantics. “Authentication succeeded” or “the endpoint looks similar” is not evidence for any omitted column.

If one reference does not implement the same upstream protocol, record that fact and do not borrow its URL, fields, encryption, or errors by analogy. If sources conflict, stop the implementation at that boundary, capture the concrete files/commits and live observation in `docs/migration/decision-log.md`, then choose only the behavior supported by live evidence or the applicable frozen local implementation. Never fill an unproven field or parameter from memory.

The required TDD loop for parity gaps is: add a sanitized fixture/Mock request or parser test that fails for the missing behavior, run it and retain the failure evidence, implement the smallest reference-backed change, rerun the focused test, then run `just check-sensitive` and `just check` before the phase commit. Do not stage `examples/`, `.env.local`, raw responses, cookies, tokens, captcha data, or personal data while recording the comparison.
