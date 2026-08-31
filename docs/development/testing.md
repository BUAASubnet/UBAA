# 测试策略

测试按证据等级明确分层：

| 层级 | 位置 | 证明内容 |
|---|---|---|
| 单元/合同 | `crates/ubaa-core/tests/` | DTO、错误、URL 转换、Cookie、no-follow/revision 持久化和稳定 JSON 结构 |
| 脱敏 Fixture | `fixtures/`、`crates/ubaa-test-support/` | 仅使用合成值的解析器行为和请求脚本 |
| Mock 集成 | `crates/ubaa-test-support/tests/auth.rs`、`readonly.rs` | 无网络时的认证顺序，以及精确只读 URL、表单、Header、分页和 Direct/WebVPN 路线锁定 |
| CLI 合同 | `apps/ubaa-cli/tests/cli_contract.rs` | 人工/JSON 渲染、脱敏、不支持交互步骤处理、序列化 envelope Schema 校验和稳定退出码 |
| CLI 二进制 | `apps/ubaa-cli/tests/binary_e2e.rs` | 帮助/JSON 参数面、facade-only 宿主访问、锁定 Cargo 门禁、缺少会话和真实宿主注销已保存会话 |
| Shell 合同与运行时 | `scripts/test-verify-live.sh` | verify-live 凭据只经 stdin、不会进入参数或 xtrace；core-live 启动器成功、失败、构建失败、信号清理、显式目录保留和参数转发；拒绝 `auto`/未知功能 |
| Core-live 入口 | `apps/ubaa-cli/src/bin/core-live.rs`、`apps/ubaa-cli/tests/core_live_runtime.rs`、`scripts/test-verify-live.sh` | 单个固定路线客户端的一次准备/登录、逐操作只读调用、依赖状态、SPOC/Judge 诊断复用行和安全摘要；周次无有效 ID 时输出 `NOT_APPLICABLE`，不猜测默认周次。二进制运行时测试覆盖 auto/凭据失败、敏感输入和会话材料清理，启动器合同覆盖成功、认证/网络非零退出、依赖参数转发、自动与显式目录、信号和构建失败；其它认证失败、网络失败、依赖阻断、无 ID、单客户端 Cgyy 业务令牌复用及写操作阻止由 `crates/ubaa-test-support/tests/auth.rs`、`readonly.rs`、`crates/ubaa-core/tests/facade.rs` 和 CLI 合同测试提供等价 Mock/Fixture 证据，源码不包含任何写操作调用 |
| 真实集成 | `scripts/verify-live.sh` + `scripts/core-live.sh` | Direct/WebVPN 各自一次 Core-live 批次；每项输出 `PASS/FAIL/BLOCKED/NOT_APPLICABLE`，不在 Shell 重复网络或 DTO 解析 |

运行确定性测试使用 `cargo test --locked --workspace --all-targets` 或 `just check`。`just check` 先用无依赖元数据校验 `Cargo.lock`，所有依赖解析命令都带 `--locked`。CI 不执行真实认证；仅在安全凭据存在时，人工分别运行 Direct 与 WebVPN 的 `feature=all`，并把逐操作结果写入 `docs/migration/status.md`。`auto` 只有 Mock/确定性路由证据，Fixture 或 Mock 通过不能建立真实协议成功。

每个新行为都从失败的 focused 测试开始。Fixture 必须使用合成值，断言敏感值不在输出中，
上游事实变化时增加迁移或合同记录。

认证失败、网络/协议失败、依赖阻断、无 ID、单客户端业务登录复用和真实写操作默认拒绝
由 `ubaa-core` Mock/Fixture 集成测试与 CLI 合同测试覆盖；Core-live 本身只接受真实只读
路线，不能用测试运行替代实时证据。
