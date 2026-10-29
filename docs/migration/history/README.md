# 历史记录

本目录保存已被取代的目标、状态、设计、审计和决策快照。文件中的“当前”“待完成”、测试计数、旧源码路径及任务授权均属于记录时点。当前实现见[状态页](../status.md)，长期规则见 [AGENTS](../../../AGENTS.md)，现行界面见[UI 规格](../../design/flutter-ui-spec.md)，决策见[当前入口](../decision-log.md)与[完整旧索引](2026-10-30-decision-index.md)。

## 链接与追溯

沿用阶段 3 已登记的归档约定：本目录内部链接按历史位置和内容保留，不属于现行断链门禁范围；现行文档指向本目录的文件和锚点仍检查。原链接若已失效，应结合原提交的目录结构查阅，不能把旧源码或旧命令当当前入口。完整决策文件保持原文，避免修改协议裁决或历史证据。

阶段 4 的移动均使用 git mv，机械提交 `308fa383` 未改写正文。可用 `git log --follow -- <归档文件>` 查看原位置；需要重建当时的上下文时，使用对应历史提交的文件树。主题仅本次生效、旧四导航及旧原生全流程等描述已被现行规格和原生范围决定取代。

## 阶段 4 归档位置

| 原位置 | 当前归档 |
|---|---|
| migration/status.md | [2026-10-30 状态快照](2026-10-30-status-before-quality-phase4.md) |
| migration/decision-log.md | [截至阶段 3 的完整决策](2026-10-30-decisions-through-quality-phase3.md) |
| superpowers/plans 与 specs | [场馆排查](2026-08-31-cgyy-parity-debug.md)、[代码组织](2026-09-03-code-organization.md)、[写协调器](2026-09-05-write-coordinator.md)、[维护计划](2026-09-07-maintainability.md)、[维护设计](2026-09-07-maintainability-design.md) |
| design/ui-ux-* | [审查](2026-09-08-ui-ux-audit.md)、[实施](2026-09-08-ui-ux-implementation.md)、[功能清单](2026-09-08-ui-ux-inventory.md)、[旧版基准](2026-09-08-ui-ux-old-baseline.md)、[来源审查](2026-09-08-ui-ux-parity-review.md)、[首版方案](2026-09-08-ui-ux-redesign.md) |
| design/macos-ui-* | [逐按钮计划](2026-09-15-macos-ui-button-plan.md)、[逐按钮结果](2026-09-15-macos-ui-button-results.md)、[源码审查](2026-09-15-macos-ui-source-audit.md)、[检查点](2026-10-03-macos-ui-button-checklist.md)、[桌面记录](2026-10-03-macos-ui-desktop-review.md) |
| design/offline-home-and-background-sync.md | [2026-09-17 离线设计](2026-09-17-offline-home-and-background-sync.md)，现行规则见[离线合同](../../contracts/offline-cache-and-recovery.md) |

配色与首页规格改为不带日期的[配色](../../design/color-system.md)与[首页](../../design/home-layout.md)入口。旧命名保存在 Git 历史中，运行结果仍标明原验收日期。
