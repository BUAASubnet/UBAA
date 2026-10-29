# 门锁专用显示阶段证据

日期：2026-10-02。起点`2848434c`，本提交候选。当前来源详见[逐操作九列与复核](../source-parity-ui-sensitive-displays.md)。Core与Bridge的sensitive模块承载页面句柄、固定路线fresh读取与可同步取消；普通只读API和CLI形状保持。

## RED与当前GREEN

本轮先为缺失的专用字段契约建立未实现占位，运行2项解析行为用例，观察前导零返回None、未知形状未拒绝的RED；日志捕获真实复现原门锁响应含body_sha1；UI占位运行3项测试，实际请求次数0而期望1。实现后对应解析、日志及生命周期测试通过。中断前RED原日志位于/tmp，接续时已被系统清理，本条保留会话中观察的结果，不声称原文件仍可读取。

接续后重新运行当前候选：just refs、完整just check（包含结构、Clippy、Rust/CLI端到端及文档）、敏感扫描、FRB生成零漂移通过。七包Flutter分析与1307项测试通过（57/92/627/335/30/91/75）。Core Mock证明WebVPN固定路线、精确GET参数、取消/切路线/异实例/迟到拒绝；App证明材料不入快照与后台/退出清理；UI证明30秒边界、定时手动单飞、失败清旧码；Host在390×844及1024×900验证真实控件入口、刷新和返回。

## 实时结果

仓库外私有调用器，在新独立配置中从stdin接收账号材料，经新交互facade登录并WebVPN读取资料，再打开门锁专用页面读取一次。输出：`interactive_login=PASS profile_read=PASS lock_display=PASS password_present=false reservation_present=false business_writes=0`，退出0。没有取得真实密码或有效预约；不能用空结果、合成材料或Core测试代替真实有码App验收。未运行Direct矩阵。

旧私有会话重开测试此前返回upstream_changed，按正常authStatus恢复后返回authentication_required；没有修改协议规避，使用新隔离会话重新登录完成本次专项。该历史过程不记作成功。原默认会话、.env.local和冻结来源没有修改。

## 日志与边界

当前日志保存在仓库外私有目录，内容仅确定性输出或安全live摘要。验收截图不入Git；门锁菜单golden是合成工程资源，仅核准“查看密码”文案。生产macOS最新构建与Computer Use仍未完成；上一阶段实际调用被锁屏阻断。

| 日志 | SHA-256 |
|---|---|
| `lock-check.log` | `ba4803437e6aed39e04bcb73cc11903e70630fcc2400781e4c7e4566d928ed0d` |
| `lock-flutter.log` | `ec887352273b21b45c973c6569b612df497f48bcd5de30e69df81b2c63f0bae9` |
| `lock-codegen.log` | `29063bdcf4962eb7dbf36303bd3c806720ae2c385578437c6f7eec590155f91f` |
| `lock-sensitive.log` | `b950391523c26e866b9063b2772ab06e95f152baf97a49aaf37bc5b364f9b03a` |
| `lock-live.log` | `9664b07ed5dd969ceaca1b1a5593cb1648d7fcb9022faf4d439c30e69c92599a` |

私有日志根：`<private-evidence>/project-review-20261002-resume`。
