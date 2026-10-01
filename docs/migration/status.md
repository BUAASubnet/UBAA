# 当前迁移与交付状态

更新日期：2026-10-01（Asia/Shanghai）。用户已明确恢复整体项目开发与 macOS 真实审查。活动合同见 [goal.md](../../goal.md)。实施分支为 `codex/project-completion-20261001`。

## 已核实的当前事实

- 主目录起点 `d7c37f73`，工作树干净，比 `origin/ubaa2` 多7个本地提交。
- 离线首页分支已提交77项，顶端 `e1af4360`，是主目录的后继；已快进纳入整合分支。原 worktree 的4个未提交文档保持原样。
- macOS 按钮分支有11个独立提交和未完成的交互验证码工作；待审查整合，不把旧测试计数视为当前通过。
- 另一 `ui-button-parity` worktree 只有计划/状态改动，保持原样。
- 两冻结来源校验通过：ubaa_old `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`；buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。
- 公开合同当前为 CLI JSON schema v10、Flutter bridge contract v36、Session v2、配置 v1、业务缓存 schema v6；后续整合变更须同步检查。

## 当前实现与验证边界

离线首页、首帧恢复、分批查询、十二领域缓存、成绩基线加密、关联失效与重启核对线索已有实现。旧版按钮分支已实现博雅三维筛选/跨启动偏好、完整详情、图书馆逐日时段及登录/Keychain/语义按钮修复，但尚未并入当前代码。

本轮完整门禁、WebVPN Core-live、当前 macOS 真实 App 与按钮验收均待执行；当前不宣称完成。Direct 按用户网络条件本轮不运行。历史性能与三端测试保留在[接续前状态](history/status-2026-10-01-before-consolidation.md)，不能代替本轮证据。

后续次序：项目整理 → 分支整合 → 剩余行为修复 → 当前门禁与多端适配 → WebVPN 真实读取 → macOS Computer Use 全流程 → 修复复验与交付。
