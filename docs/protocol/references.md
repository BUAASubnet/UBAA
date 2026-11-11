# 冻结参考

| 参考 | 远端 | 固定提交 | 用途 |
|---|---|---|---|
| `examples/ubaa_old/` | `https://github.com/BUAASubnet/UBAA.git` | `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` | Kotlin 本地 Direct/WebVPN 认证、解析器、Cookie、DTO 和测试 |
| `examples/buaa-api/` | `https://github.com/fontlos/buaa-api.git` | `a63712fa2ae0a6c8066197063ddee98e3a6b5b81` | 独立 Rust SSO、用户中心、请求、Cookie、凭据和错误证据 |

两个目录都是本地忽略的嵌套 Git 仓库。必须在固定提交读取；不得修改、暂存、打标签或从中复制凭据。仅在
缺失时显式运行 `just refs-bootstrap`：它在同父目录的临时路径完成 clone/fetch/checkout 和校验，成功后原子
移动到目标，失败不留下半成品。普通验证与 release preflight 只运行纯只读的 `just refs`；缺失、已有路径非
Git 仓库、工作树脏、远端不符或提交不符都会失败并提示下一步，不会联网或改写。本仓库不存在
`ubaa-v1-reference` 标签，也不会自行创建。

来源优先级依次为真实上游证据、冻结 UBAA v1 实现/测试、固定 `buaa-api`，最后是架构文档。发生冲突时，必须在实现前记录到 `decision-log.md`。
