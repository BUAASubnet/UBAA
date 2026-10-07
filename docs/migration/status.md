# 当前实现与验证状态

更新日期：2026-10-07（Asia/Shanghai）。当前任务为[可持续开发性整理与修复](../../goal.md)，实施分支 `ubaa2`，本地阶段提交、不推送发布。历史流水已移至[整理前快照](history/status-before-maintainability-2026-10-07.md)。

## 当前事实

- 公开合同保持 CLI JSON schema v11、Flutter bridge contract v40；Session v2、配置 v1、缓存 schema v6 独立管理。
- 冻结来源保持 ubaa_old `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`、buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`；普通校验不改写引用。
- UI、Bridge、Controller 已拆为显式独立 library，保留原公开组件、客户端、单一通知链、账号代次及 WriteCoordinator；当前组织见[架构规范](../architecture/code-organization.md)。
- 测试按领域与横切职责独立注册，夹具进入 support；移除筛选 State 旁路、手写名字计数和迁移文件路径锁定，保留独有行为保护。
- 原生目录按 synthetic/platform/live/manual 分类，登记 73 个入口；16 个常驻巡检模式已拆出 driver，并补录照片巡检与真实启动测量。
- library、part、依赖环、入口清单和 Python/CJS 规模进入门禁；历史 UI 元数据只增加批次索引和默认检索隔离，原内容与归档均保留。

## 本轮验证

生产模块拆分后，Rust/CLI/Shell 与官方七包 Flutter 门禁已逐阶段通过。测试拆分后的全量 Flutter 通过，golden 字节未改动；独立运行发现的博雅分页屏外点击已通过真实滚动/命中操作修复。最终严格门禁、原生及可用平台复验正在收尾，具体日志与结果见[实施记录](maintainability-implementation-2026-10-07.md)。

## 继续保留的产品验收边界

此前合同中的 B2/C2/C3/D，涉及真实上游数据、完整 macOS 逐按钮复验及设备/发布条件，仍按[原合同](history/goal-2026-10-07-before-maintainability.md)和[按钮记录](../design/macos-ui-button-results.md)跟踪，不由结构治理自动关闭。

本轮校外仅 WebVPN 只读；Direct、真实学校写入、实体设备和签名发布不混入确定性结果。Windows/Linux 运行、OHOS 实体 HUKS及正式分发仍需对应环境证据。
