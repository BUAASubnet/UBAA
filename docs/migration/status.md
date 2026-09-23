# 当前迁移与交付状态

更新日期：2026-09-23，Asia/Shanghai。活动合同为[离线首页与后台恢复](../../goal.md)，P0–P5仍执行中。实施区`.worktrees/offline-home-20260917`、分支`codex/offline-home-20260917`；主工作区保持原样，不推送、不发布。旧UI/UX状态已归档到[接续前状态](history/status-2026-09-23-before-offline-resume.md)。

接续起点`c7e55171`的29项未提交工作已保留并完成。现有独立提交P2-P `e09e63f4`、P2-Q `a80bbf33`、P3-B `c729e6b9`、P2-R `950c8192`、iPhone原生证据`55fe5dad`、P4-AG `3ca371fc`、P5-B1 `1a8f7ded`、P2-S `94ff3a5c`。Bridge当前为 **Flutter bridge contract v36**，业务缓存schema v6、CLI JSON schema v10、Session v2、配置v1；FRB零漂移通过。

已实现缓存首页与首帧恢复、所需路线认证、独立学校/缓存错误、希冀持久索引与逐批在线退路/完整详情、明确失效句柄原位重建、十二领域精确范围缓存、完整学期导入、关联写后失效和加密最小未知结果核对提示。写资格仍只来自实时验证，恢复不自动提交。

P5-B1修复真实iOS空环境无法找到私有目录，新增3项行为RED→GREEN，iPhone原生目录与系统材料2项通过，见[证据](evidence/offline-ios-private-directory-2026-09-23.md)。P2-S去除希冀每批重复激活，完整数据/每批选课保持，Core分段29项与Bridge4项聚焦通过，完整just check通过（含CLI16与Bridge139），见[证据](evidence/offline-judge-activation-2026-09-23.md)。

原生合成异常/交互矩阵在macOS、iPhone/iPad模拟器各80项通过，固定日期测试经显式Clock装配保留原断言，修改后完整Flutter1069项/7包分析通过，见[矩阵](evidence/offline-native-matrix-2026-09-23.md)。这些是已执行阶段证据，不能替代后续P2-T当前候选的门禁。

P5-B第一轮macOS进程基线启动21次，19次完整刷新、1次600秒超时、1次停滞后中断，原始失败及诊断干预保留，30次未完成。已有20份完整启动记录缓存可见中位数394.063ms、P95 453.238ms，仅表示这个未完成轮次的观测；成功子集全部刷新P95不能代表全轮次，见[启动记录](evidence/offline-startup-2026-09-23.md)。旧0.6秒/85–96秒为历史单次debug宿主装配，不能作为当前进程验收。

随后Debug新App复现hidden→inactive可见窗口仍被当作后台：控制器前台标记false，调度器空闲且4项读取等待。P2-T已经过双来源/锁定Flutter SDK状态核对及3项行为RED→GREEN，最小修复按可见性恢复，不因普通焦点变化重复认证。其完整just check、Flutter1072项/7包分析、三端各83项原生合成矩阵及WebVPN真实App可见恢复回归已通过，见[本轮证据](evidence/offline-visible-resume-2026-09-23.md)；不能据此宣布所有旧超时均已解决。

剩余必需工作：当前候选新App Direct/WebVPN只读、刷新停滞回归、认证/上游/缓存命中/重复请求/调度等待成本分解和继续优化、手机/平板/macOS各30次进程缓存启动及设计15类场景最终核对。P5-A有历史双路线功能证据；最近聚合WebVPN成功，Direct因SPOC network_error退出5；评教新分段Direct激活networkError尚未通过，禁止借旧CLI空集合容错替代新链路。

设备边界：macOS与iOS模拟器可用，无连接实体手机/平板。Android SDK和emulator存在，但本机无系统镜像、AVD及sdkmanager；Windows/Linux/OHOS当前原生运行证据仍不足。不得以构建或模拟器冒充实体/发布证据。安全输入和媒体留仓库外私有目录，真实学校业务写入禁止；继续所有不受外部条件阻挡的实现和验证。最终索引见[验收表](evidence/offline-home-acceptance-2026-09-23.md)。

P2-T已独立提交`7afd433d`。P2-U已补齐首页自动成绩检查的后台优先级和主动同学期查询合并，5项RED、9项专项GREEN、完整Flutter1081项/7包分析、just check及三端各92项原生矩阵通过，见[证据](evidence/offline-grade-priority-2026-09-23.md)。该阶段发现的旧成绩提醒JSON明文问题已由下述P4-AH接入Core仓库；正式性能等待最终候选。

P4-AH已实现成绩变化基线统一加密及安全迁移，生产不再新增明文成绩；清理后提醒随业务缓存代次撤销，缓存失败与在线结果分列。3项行为RED、完整Flutter1099项/7包分析、just check（CLI16、Bridge140）、FRB零漂移和敏感扫描通过；macOS/iPhone/iPad各100项原生矩阵，macOS成绩旧交互12项通过，详见[证据](evidence/offline-grade-baseline-2026-09-23.md)。下一项审查缺口为“退出并清除”遗漏提醒偏好清理；完整性能成本和最终真实双路线仍待。
