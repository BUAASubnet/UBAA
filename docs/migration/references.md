# 冻结参考

| 参考 | 远端 | 固定提交 | 用途 |
|---|---|---|---|
| `ubaa_old/` | `https://github.com/BUAASubnet/UBAA.git` | `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e` | Kotlin 本地 Direct/WebVPN 认证、解析器、Cookie、DTO 和测试 |
| `examples/buaa-api/` | `https://github.com/fontlos/buaa-api.git` | `efb7976bf513f38364b88aeb83d704586cff9b2a` | 独立 Rust SSO、用户中心、请求、Cookie、凭据和错误证据 |

两个目录都是本地忽略的嵌套 Git 仓库。必须在固定提交读取；不得修改、暂存、打标签或从中复制凭据。运行 `just refs` 可在目录缺失时获取参考，若已有参考目录脏、远端不符或提交不符则直接失败。本仓库不存在 `ubaa-v1-reference` 标签，也不会自行创建。

来源优先级依次为真实上游证据、冻结 UBAA v1 实现/测试、固定 `buaa-api`，最后是架构文档。发生冲突时，必须在实现前记录到 `decision-log.md`。
