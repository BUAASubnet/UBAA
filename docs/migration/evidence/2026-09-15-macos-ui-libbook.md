# 图书馆逐日日程与座位查询修复证据

日期：2026-09-15。实现提交：`d6e53a97d0320550ee14e8325f615b84832784fb`。本记录关闭图书馆这一批的实现、确定性验证和独立审查；实际 macOS 逐按钮验收及最终候选实时读取仍待完成。

## 修改与来源

冻结旧版为 `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`，示例为 `efb7976bf513f38364b88aeb83d704586cff9b2a`，均经 `just refs` 校验。逐操作来源及兼容决定见[图书馆日期对照](../source-parity-ui-libbook-dates.md)。示例没有同协议实现，不从其他预约功能借用字段或请求。

新增独立分区日程 API，贯穿 Core facade、Bridge、App 和共享 UI，保留每一天自己的原始时段。正常查询现在能够从楼馆、楼层、分区选择日期和时段，再明确查询座位。关闭面板保留有效草稿；切换父项或日期立即清除旧座位和动作。旧手输入口继续保留。

请求仍为原 `Space/map` 和仅含分区 `id` 的正文。旧分区详情和 CLI JSON schema v10 不加字段；Session v2、配置 v1、预约资格及最终写入权威不变。本专项未发布候选采用 Flutter bridge contract v10，Rust 与 Dart 绑定共同更新。

## 独立审查与修复

首轮独立审查复现一项 P2：已加载 A 分区日程，手动应用 B 分区座位查询，首次网络失败后点击正文重试；相同参数成功返回，座位却被旧 A 日程隐藏。原因是重试无条件清除了高级查询的显示上下文。

修复只在完整查询参数变化时清除该上下文。新增正式回归先观察到座位卡缺失的断言失败，再验证重试成功可见、只增加一次读取、准备目标仍属于 B 分区；取消后重新选择自然日期仍清除旧座位与动作。原外部探针保持原样并通过。限定复审结论为原 P2 已关闭，规范与质量通过，未发现修复差异新增破坏。

首轮审查覆盖51个候选文件，修复轮相对已审候选仅两文件变化。修复包 SHA-256 为 `d57e955b825b2561c914ef1216a09c0e76b4ed09e5b0ee97c387233b76b78c4f`；提交前再次核对全部文件哈希与审查清单一致，暂存区只包含该范围。

## 验证

日志位于仓库外私有目录 `macos-ui-20260915/libbook-dates/`。Flutter 固定使用3.41.9；Core/Bridge/仓库命令在专项工作区根运行，组件测试在 `apps/ubaa_flutter` 运行。

| 阶段 | 命令或覆盖 | 结果 |
|---|---|---|
| 新能力 RED | Core逐日关联、空首日期、重复日期；App嵌套投影；UI日期控件 | 均为成功编译后的行为断言失败 |
| 修复前完整候选 | `just flutter-check` | 退出0，816项；不冒充修复后重跑 |
| 领域及合同 | Core图书馆26项、Bridge112项、相关App180项 | 通过；Bridge两个既有子进程入口独立标记ignored |
| P2正式 RED | `flutter test test/libbook_dates_test.dart --no-pub --plain-name '高级跨分区查询失败后正文重试显示原参数座位' --reporter expanded` | 退出1，座位可见性断言失败 |
| P2修复聚焦 | `flutter test test/libbook_dates_test.dart test/libbook_navigation_test.dart --no-pub --reporter expanded` | 退出0，28项通过 |
| 原外部探针 | `manual_retry_probe_test.dart`，直接成功及失败后重试两个对照 | 退出0，2项通过；探针未改 |
| 修复文件静态检查 | 对修改的生产文件和正式测试分别运行 `flutter analyze --no-pub` | 均退出0 |
| 修复后仓库门禁 | `just check-sensitive`、`just check` | 均退出0；包含CLI端到端16项及CLI合同94项 |
| 提交后生成门禁 | `just flutter-codegen-check`，源码为上方实现提交 | 退出0，正式FRB生成零漂移 |

首次正式生成检查在新绑定尚未提交时退出1，曾另存8个文件生成前后哈希一致的证据。这只能证明候选可重现。提交后的 `codegen-postcommit.log` 已独立记录正式检查退出0，才关闭生成门禁。

本批没有新增真实预约或取消。专用图书馆 live 驱动只迁移了代码，尚未执行。当前运行 App 仍是早期产物，不能据上述测试将新日期、时段、查询、返回等按钮记为真实 App 通过。
