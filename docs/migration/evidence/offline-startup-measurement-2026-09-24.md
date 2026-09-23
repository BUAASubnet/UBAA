# 离线首页启动与后台成本测量接线证据

日期：2026-09-24。实施区：`codex/offline-home-20260917`。本文件记录测量工具和校验边界，不把工具通过写成设备性能或学校可达性通过。原始启动日志、账号材料和加密快照均保存在仓库外的私有目录，不进入 Git。

## 本批完成

- 独立只读入口继续使用生产 `UbaaAppHost`、`AppController`、Core/Bridge 分段读取和安全材料；启动器拒绝真实 commit，并为每轮建立独立配置目录、材料命名空间和缓存快照。
- 事件分别记录内核进程出生、Dart 入口、首页逻辑帧结束、引擎 raster 首帧、缓存可见、恢复任务开始、首批在线数据和完整首页刷新结束。
- 完整首页范围为五个主要领域（课表、签到、SPOC、评教、希冀）加四个补充来源（已选博雅、研讨室订单、当前周、成绩检查）。成绩检查另记录加密基线检查是否收尾以及是否实际持久化。
- `ReadScheduler` 的可选诊断记录 queued/started/completed/cancelled、排队等待和运行耗时；分段后台操作记录认证、上游、缓存命中、来源和重复操作。
- Python 统计固定计划样本分母，保留未启动和无效样本，P95 使用 nearest-rank；完整首页校验区分主领域 `complete`、补充来源 `finished` 和成绩 `check_complete`。

## RED→GREEN 与门禁

1. 修改分析测试使四个补充来源使用实际输出字段 `finished`，先观察到完整首页样本被错误标记 `incomplete_home_coverage`（RED，日志 `/tmp/ubaa-p5b2-analysis-red.log`）。
2. 按最小范围拆分主领域与补充来源校验，并要求成绩检查收尾信号；7 项 Python 合同测试通过（GREEN，日志 `/tmp/ubaa-p5b2-analysis-green.log`）。
3. Flutter 全量检查在接入调度诊断、成绩收尾回调和独立入口后通过：domain 57、platform 75、app 562、UI 287、bindings 23、host 53、Flutter 应用 55，共 1112 项；7 个包分析器均无问题。日志 SHA-256：`dea8524f9fa80f5c105a36da6f584aba57bbd4585cfe8e3f25b44c750412d9fe`。
4. `just refs`、`just layout-check`、`just check-sensitive`、`just flutter-codegen-check` 已通过；Rust/Bridge 生成目录无漂移。本批没有改变学校协议或 FRB schema。

## 待执行的正式测量

macOS Release、iPhone 17 Pro 模拟器 Debug、iPad Pro 13 M5 模拟器 Debug 各需新建独立私有轮次并完成计划30次。每轮分别报告进程启动、首页首帧、缓存可见、恢复启动、首批数据、完整首页刷新中位数和 P95，并列出认证、上游响应、缓存命中、重复请求和调度等待成本。当前无实体手机/平板、无 Windows/Linux/OHOS 运行环境；模拟器结果不能代替实体设备发布模式证据。Direct/WebVPN 新 App 分段只读验证仍需与旧 CLI 聚合验证分开记录。
