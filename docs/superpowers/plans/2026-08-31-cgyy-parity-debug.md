# Cgyy 路由与真实只读入口执行记录

本记录对应 `goal.md` 本周期合同，协议事实来自冻结 `ubaa_old`、固定版本
`examples/buaa-api`（Cgyy 无等价实现）和脱敏 Mock。所有修复均先有失败测试，
再做最小实现；真实写操作不在本记录范围内。

## 已完成

- [x] 记录基线：`just refs`、`just check-sensitive` 通过；Clippy 的可复制路线参数失败已记录并修复。
- [x] 用 WebVPN-only 会话复现 Cgyy 误走 Direct，保留失败输出，再修复 facade 路线选择。
- [x] 为站点、用途、日期、订单、详情、锁码统一使用当前路线 runtime；业务认证失效最多清理、重登和重放一次。
- [x] 为锁码公共序列化添加失败测试并收敛为 `{available: boolean}`，不把原始 data 放入 facade、CLI、Session 或日志。
- [x] 新增单批次 `core-live`：固定路线 `RouteClient` 登录一次，逐操作串行读取并输出安全状态行；写方法不在白名单。
- [x] 将 `verify-live` 收敛为参数校验、`.env.local` 安全读取、一次 stdin 转发；`auto` 真实入口拒绝。
- [x] 重写 Shell 合同测试和二进制静态合同，覆盖单次调用、stdin 凭据、xtrace/参数脱敏、未知功能和 auto 拒绝。
- [x] 更新路线、锁码、Core-live 和失败记录文档；中文说明与 source-parity 冲突边界同步。

## 待本周期最终验收

- [ ] 运行并记录 Direct Core-live 完整只读矩阵。
- [ ] 运行并记录 WebVPN Core-live 完整只读矩阵。
- [ ] 运行 `just refs`、`just check-sensitive`、`just check`、CLI 全量 E2E 和 Shell 合同测试。

如果真实上游逐项失败、阻塞或不适用，必须记录对应 `route/feature/operation/status/error`
和重跑条件；不能用聚合成功、Mock 或历史脚本结果代替。
