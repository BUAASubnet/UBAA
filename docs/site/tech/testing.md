# 测试与质量

工程使用脱敏 Fixture、Mock、Rust、Dart 和界面回归检查。长期安全边界与来源对照要求见 [AGENTS](https://github.com/BUAASubnet/UBAA/blob/ubaa2/AGENTS.md)，当前阶段目标和已执行结果分别记录。

本地门禁清单、check 与 check-strict 的区别、原生专项及 CI 实际范围统一在仓库的[开发命令](https://github.com/BUAASubnet/UBAA/blob/ubaa2/docs/development/commands.md)维护。测试设计、golden 和预览入口见[测试策略](https://github.com/BUAASubnet/UBAA/blob/ubaa2/docs/development/testing.md)，网站安装与构建命令也在同一命令清单中说明。

真实学校读取、设备、安装升级、签名与发布分别验收。模拟数据通过不能证明真实预约或提交成功；学校请求按当前会话用户授权执行，CI 不接收真实凭据。
