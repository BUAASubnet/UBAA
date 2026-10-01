# 交互验证码整合证据

日期：2026-10-02。起点`4fda272c`，本提交候选。来源见[当前双来源复核](../source-parity-interactive-integration-2026-10-02.md)。原macOS worktree未提交实现保留不动，仅移植适用能力并补齐离线、原位、写保护与固定路线接续。

## 实现与确定性证据

专用Core句柄、受限PNG/JPEG像素帧和120秒单调期限经Bridge v38接入手动登录；自动恢复和CLI保持非交互。取消不等待网络锁，账号、会话、后台、退出及销毁使迟到结果失效。原位登录保留首页导航；成功复用当前凭据与缓存账号收尾。验证码等待期间禁止写准备和后台读取。固定WebVPN已就绪可自动进入，不要求完成另一条路线的挑战。

观察了离线原位/写保护和固定WebVPN接续的行为RED，最小修复后GREEN。Core交互19项、Bridge交互5项、Host交互9项、UI交互1项通过。完整Flutter七包1299项（57/92/625/332/29/89/75）与分析通过。`just check`（含CLI端到端）、Clippy、敏感检查与FRB生成零漂移通过。Rust完整门禁之后仅增加Dart固定路线接续，最后完整Flutter验证涵盖该改动。

## 实时证据与限制

仓库外专用Rust调用器仅从stdin读取凭据，在新的私有配置中调用prepare/submit/continue交互facade，再经WebVPN读取资料。安全结果：`route=webvpn stage=interactive_login status=PASS profile_read=PASS business_writes=0`，退出0。未保存原始响应、挑战图像或资料；配置与会话不纳入Git。本次没有真实验证码，不能证明上游验证码答案提交；这也是Core专项live，不是生产App或Computer Use验收。未执行Direct矩阵。

真实macOS仍锁屏，待用户解锁后重建最新候选并完成按钮验收。门锁显示与当前冻结研究生课表仍待独立批次。

## 日志指纹

日志只保存本地安全摘要或确定性输出，不入Git。

| 日志 | SHA-256 |
|---|---|
| `/tmp/ubaa-interactive-offline-red-20261002.log` | `77e4fa852c3eca6a859f1eb8b3984947bc3f9d84920f8faae6c4f51454b5968b` |
| `/tmp/ubaa-interactive-preferred-route-red-20261002.log` | `a224ab998f10d34b3e9b65a627ac271d2f2f53eeb0f41874b48f11d42e0b1017` |
| `/tmp/ubaa-interactive-offline-green-20261002.log` | `72ee96ca218d18245e462b8f70b778385fe6b202efcc8c26067922662c3577e0` |
| `/tmp/ubaa-interactive-preferred-green-20261002.log` | `48aad7a4aa3a213b18a9d83b5bcd857fffa8b22442c5229e7ca8d749e29d2642` |
| `/tmp/ubaa-interactive-flutter3-20261002.log` | `ed4df695ec913d949071d22be9f8ce0bdc198f4a1f4b1c62b31b109f5c2ff318` |
| `/tmp/ubaa-interactive-check2-20261002.log` | `ba8e883ff33a2eb80a41eb7e492d993c445c24e1b22590e2ea6996409f73387a` |
| `/tmp/ubaa-interactive-codegen-check-20261002.log` | `29063bdcf4962eb7dbf36303bd3c806720ae2c385578437c6f7eec590155f91f` |
| `/tmp/ubaa-interactive-sensitive-20261002.log` | `db4b30fba0ea40ef2a453b0e584d7d066dabb027fd6d10112abf4b2462ffd3a7` |
| `/tmp/ubaa-interactive-core-live-20261002.log` | `421f6c222bd601a434ba053910f0e1aab00362886988965b75d3abd716ede465` |
