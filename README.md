# UBAA

**UBAA（智慧北航 Remake）** 是面向北京航空航天大学学生的跨平台校园服务客户端。课表、作业、成绩、选课和预约集中在一个应用中，也可以管理自己的日程与北航云盘文件。

UBAA v2.0 使用 Flutter 和 Rust 重新构建，面向 Android、iOS、Windows、macOS、Linux 和 HarmonyOS，提供适合手机、平板与桌面的界面。

## 入口

- 下载与发布说明：[GitHub Releases](https://github.com/BUAASubnet/UBAA/releases)
- 使用指南：[安装与首次登录](docs/site/guide/start.md)
- 新版介绍：[UBAA v2.0 相比旧版升级了什么](docs/site/guide/ubaa2.md)
- 功能说明：[功能总览](docs/site/features/index.md)
- 问题反馈：[GitHub Issues](https://github.com/BUAASubnet/UBAA/issues)

UBAA v2.0.0 正在准备发布。下载时请确认发布说明明确标注 UBAA v2.0，并选择对应平台的安装包；旧版 v1.x 仍可在 Releases 中找到。各平台的实际分发情况以发布说明为准。

## 主要功能

- **学习安排**：查看课表、考试、成绩、空教室、SPOC 与希冀作业，使用博雅课程、课堂签到和教学评教。
- **校园服务**：查询和管理图书馆座位、研讨室预约、阳光打卡、iHome 诉求与财务收入记录。
- **日程与待办**：把学校安排与自建事项放在一起，支持重复日程、教学周、完成标记和日历导出，也可按需开启北航云盘同步。
- **北航云盘**：浏览和管理文件，上传、下载、分享，以及查看回收站。
- **自动连接与离线查看**：根据网络使用直连或学校 WebVPN，已有缓存可在离线时阅读。
- **桌面命令模式**：在终端查询校园信息和管理日程，与应用共用账号及本机数据。

各功能的使用方法与适用范围见[使用文档](docs/site/index.md)。从旧版升级前，建议阅读[新版变化与升级说明](docs/site/guide/ubaa2.md)。

## 文档

- [安装与首次登录](docs/site/guide/start.md) · [连接方式](docs/site/features/auth-and-connection.md) · [常见问题](docs/site/tech/troubleshooting.md)
- [日程与待办](docs/site/features/agenda.md) · [北航云盘](docs/site/features/bhpan.md) · [桌面命令模式](docs/site/features/command.md)
- [隐私政策](docs/site/tech/privacy-policy.md) · [免责声明](docs/site/tech/disclaimer.md) · [更新日志](docs/site/changelog/index.md)
- [开发文档](docs/index.md) · [贡献指南](CONTRIBUTING.md) · [发布流程](docs/runbooks/flutter-release.md)

## 参与开发

`main` 保存发布主线，`dev` 用于日常开发，旧版代码保存在 [`ubaa1`](https://github.com/BUAASubnet/UBAA/tree/ubaa1) 分支。欢迎提交问题反馈和改进建议，代码贡献请先阅读[贡献指南](CONTRIBUTING.md)。

项目使用 Rust 处理校园服务，Flutter 提供跨平台界面。环境搭建见[开发环境](docs/development/setup.md)，目录与模块说明见[工程文档索引](docs/index.md)。

## 说明与许可

UBAA 由学生开发者制作和维护，是第三方工具，与北京航空航天大学官方无任何利益关系。课程、成绩和预约结果以学校系统为准。

项目采用 [MIT 许可证](LICENSE)，第三方代码与协议参考见[第三方声明](THIRD_PARTY_NOTICES.md)。
