# 测试策略

测试按证据等级明确分层：

| 层级 | 位置 | 证明内容 |
|---|---|---|
| 单元/合同 | `crates/ubaa-core/tests/` | DTO、错误、URL 转换、Cookie、no-follow/revision 持久化和稳定 JSON 结构 |
| 脱敏 Fixture | `fixtures/`、`crates/ubaa-test-support/` | 仅使用合成值的解析器行为和请求脚本 |
| Mock 集成 | `crates/ubaa-test-support/tests/auth.rs`、`readonly.rs` | 无网络时的认证顺序，以及精确只读 URL、表单、Header、分页和 Direct/WebVPN 路线锁定 |
| CLI 合同 | `apps/ubaa-cli/tests/cli_contract.rs` | 人工/JSON 渲染、脱敏、不支持交互步骤处理、序列化 envelope Schema 校验和稳定退出码 |
| CLI 二进制 | `apps/ubaa-cli/tests/binary_e2e.rs` | 帮助/JSON 参数面、facade-only 宿主访问、锁定 Cargo 门禁、缺少会话和真实宿主注销已保存会话 |
| Shell contract | `scripts/test-verify-live.sh` | 验证凭据只经 stdin、不会进入参数或 xtrace，拒绝 `auto`/未知功能，并确保 verify-live 只调用一次 Core-live |
| Core-live 入口 | `apps/ubaa-cli/src/bin/core-live.rs` | 单个固定路线客户端的一次登录、逐操作只读调用、依赖状态和安全摘要；源码不包含任何写操作调用 |
| Real integration | `scripts/verify-live.sh` + `scripts/core-live.sh` | Direct/WebVPN 各自一次 Core-live 批次；每项输出 `PASS/FAIL/BLOCKED/NOT_APPLICABLE`，不在 Shell 重复网络或 DTO 解析 |

运行确定性测试使用 `cargo test --locked --workspace --all-targets` 或 `just check`。`just check` 先用无依赖元数据校验 `Cargo.lock`，所有依赖解析命令都带 `--locked`。CI 不执行真实认证；仅在安全凭据存在时，人工分别运行 Direct 与 WebVPN 的 `feature=all`，并把逐操作结果写入 `docs/migration/status.md`。`auto` 只有 Mock/确定性路由证据，Fixture 或 Mock 通过不能建立真实协议成功。

每个新行为都从失败的 focused 测试开始。Fixture 必须使用合成值，断言敏感值不在输出中，
上游事实变化时增加迁移或合同记录。
