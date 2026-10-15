# 当前实现与验证状态

2026-10-15 界面精简已完成：覆盖共享 UI、错误与操作表单；七包 1354 项测试、仓库确定性门禁及 macOS 构建通过。清单和验收边界见[本轮记录](ui-copy-cleanup-2026-10-15.md)。

2026-10-14 界面调整：按用户检查反馈移除登录选项下方的密码保存说明，以及连接模式菜单顶部的默认策略说明。仅删减展示文字，验证记录见[决策索引](decision-log.md#2026-10-14登录界面说明精简)。

2026-10-11 工程整改记录（Asia/Shanghai）：F01—F07 工程整改与最终跨平台门禁已完成。源码候选 `0cf097fa6d34994552f842d1a09eadcdd3b0329a`；实现与 RED/GREEN 见[整改记录](quality-repair-2026-10-11.md)，活动合同见 [goal.md](../../goal.md)。

## 当前实现

- CLI JSON schema v11、Flutter bridge contract v41、Session v2、配置 v1、缓存 v6。
- Windows 条件编译修正；Linux 补齐 libsecret 构建依赖与 Secret Service 可用/不可用原生验证。
- 生产初始化通过异步 FRB 打开，Session 两级锁共用 2 秒预算；保留原 CAS 修订和内核排他锁。初始化失败保留白名单分类与诊断编号，可重新打开。
- 写入发送观察独立于收尾。发送后 panic/未分类 Dart 异常保留未知结果，按意图原路线回读，不重放。Dart 投影完成后才确认持久核对提示，材料失败与学校结果分列。
- 会话与缓存生命周期分别由独立所有者管理，跨模块通过命令变更；成绩基线只消费统一 scope，可以独立测试。
- 发布清单覆盖全部 5839 个跟踪输入，使用 UTF-8/LF，关联候选、实际作业和产物相对路径摘要。

## 验证

- 本地严格 Rust/CLI/Shell 门禁、敏感/结构/公开合同、FRB 零漂移通过；七包 Flutter 分析/格式和 1354 项测试通过。
- macOS 默认五个原生入口共 12 项通过，包含真实 FFI 双进程持锁与重试。窗口前置限制仍不构成人工按钮验收证据。
- 最终候选 OHOS 无签名 Debug HAP、arm64 动态库及插件源码合成合同通过。
- 远端 [CI](https://github.com/BUAASubnet/UBAA/actions/runs/38139830762) 全部通过：合同、Flutter、macOS Rust、Windows Rust；Windows 格式、Clippy、测试、构建与文档均实际执行成功。
- 远端[原生矩阵](https://github.com/BUAASubnet/UBAA/actions/runs/38139888742)：Linux、Windows、macOS、iOS simulator、Android APK 全部通过；Linux 安全存储可用/不可用与 macOS 原生回归均实际执行。
- 干净候选 preflight 通过；Windows 已上传材料经下载复核，UTF-8/LF、候选 SHA 与两份清单摘要均吻合。
- 三个实现提交已推送到 `codex/engineering-quality-20261011`；本地另提交收尾验收文档，上述证据绑定源码候选而非文档提交。

## 保留的发布边界

真实账号 Direct/WebVPN、真实学校写入、实体设备、OHOS 实体 HUKS、正式签名/公证/安装升级回退没有由本轮合成验证替代。依赖许可材料仍有 27/848 条缺口，不能凭 SBOM schema 校验通过宣称正式交付批准。

上一轮 I01—I09 与旧真实路线记录仍按其原候选使用，见[2026-10-07 实施记录](engineering-quality-implementation-2026-10-07.md)。三个独立工作树、冻结引用、凭据及原黄金基线保持；本轮没有合并默认分支或发布应用。
