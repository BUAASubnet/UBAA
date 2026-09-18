# 更新日志

UBAA 的版本号由 `gradle.properties` 管理，发布资产通过 GitHub Release 工作流生成。客户端版本检查接口为 `GET /api/v1/app/version`。

所有版本的完整发布说明和下载资产请参见 [GitHub Releases](https://github.com/BUAASubnet/UBAA/releases)。

---

## v1.8.1 <Badge type="tip" text="最新" />

**发布日期：** 2026-09-18

- 新增 iHome 功能。

[GitHub Release](https://github.com/BUAASubnet/UBAA/releases/tag/v1.8.1)

## v1.8.0

**发布日期：** 2026-09-14

- 研究生课表：接入 GSMIS“我的课表”，支持整学期导入。
- 在线与离线课表：首页和课表页默认在线加载，无需先导入；点击“课表本地化”才保存整个学期，支持离线查看、学期切换和滑动换周，保存失败保留旧课表。
- Android 桌面组件：新增周课表、今日课程和近日课程，支持缩放及点击进入离线课表。
- 课表展示：显示完整节次与上下课时间，支持研究生晚间第 14 节课程。
- 成绩提醒：新增成绩更新提醒。
- 问题修复：修复 WebVPN 签到失败、桌面端大课表保存失败，以及门户探测异常时研究生中转课表无法加载的问题。
- 课表修复：本科周课表的 `code` 返回学号，不再误判为学期不一致；统一处理带时间的周次日期，修复整学期本地化失败。
- iOS 发布：新增完整 App 签名归档及 App Store Connect 上传流程。
- 启动优化：认证初始化不再等待更新与公告检查完成。
- 重新发布：版本号保持 1.8.0，Android 内部版本代码递增为 31。

首次登录后自动在线加载课表；如需离线使用，请在课表页点击“课表本地化”。使用服务器中转的用户，需要服务端同步升级才能使用研究生课表。

[GitHub Release](https://github.com/BUAASubnet/UBAA/releases/tag/v1.8.0)

## v1.7.2

**发布日期：** 2026-05-09

- 成绩查询：修复加权平均分计算，新增算数平均分
- 座位预约：新增图书馆座位预约功能
- 登录：适配 SSO 密码过期提醒
- 性能优化：优化了部分功能的性能
- 文档：新增[文档](https://www.buaa.team)

[GitHub Release](https://github.com/BUAASubnet/UBAA/releases/tag/v1.7.2)

## v1.7.1

**发布日期：** 2026-05-07

- 修复成绩查询未计算五级制的问题
- 新增公告功能
- 修复已知问题

[GitHub Release](https://github.com/BUAASubnet/UBAA/releases/tag/v1.7.1)

## v1.7.0

**发布日期：** 2026-05-07

- 新增成绩查询功能
- 新增希冀（judge）作业待办功能
- 修复了一些问题
- 现在可以在登录页切换直连模式了
- 校园网环境中强烈建议使用直连模式

[GitHub Release](https://github.com/BUAASubnet/UBAA/releases/tag/v1.7.0)

## v1.6.0

**发布日期：** 2026-04-20

- 支持直连、WebVPN、中转三种连接方式，校园网可直接连接，不在校园网时可自行选择 WebVPN 和中转
- 优化应用性能和表现

[GitHub Release](https://github.com/BUAASubnet/UBAA/releases/tag/v1.6.0)

## v1.5.4

**发布日期：** 2026-04-09

- 优化部分界面
- 服务端现支持分布式部署
- 新增 wiki 文档

[GitHub Release](https://github.com/BUAASubnet/UBAA/releases/tag/v1.5.4)

## v1.5.3

**发布日期：** 2026-04-08

- 优化服务端性能
- 修复已知问题
- 优化部分界面

[GitHub Release](https://github.com/BUAASubnet/UBAA/releases/tag/v1.5.3)

## v1.5.2

**发布日期：** 2026-04-06

- 更新应用图标
- 修复已知问题
- 优化部分界面
- 新增性能监控

[GitHub Release](https://github.com/BUAASubnet/UBAA/releases/tag/v1.5.2)

## v1.5.1

**发布日期：** 2026-04-03

- 建立了 QQ 群便于交流沟通，群号 1097085303
- 优化了 API 请求与响应
- 新增服务端数据监控
- 更改版本更新方式

[GitHub Release](https://github.com/BUAASubnet/UBAA/releases/tag/v1.5.1)

## v1.5.0

**发布日期：** 2026-04-02

- 更新了阳光打卡功能
- 修复了已知问题

[GitHub Release](https://github.com/BUAASubnet/UBAA/releases/tag/v1.5.0)

## v1.4.2

**发布日期：** 2026-03-25

- 修复研究生登录
- 优化待办页刷新速度
- 优化博雅课程相关显示

[GitHub Release](https://github.com/BUAASubnet/UBAA/releases/tag/v1.4.2)

## v1.4.1

**发布日期：** 2026-03-24

- 新增主页待办区
- 进行了很多优化

[GitHub Release](https://github.com/BUAASubnet/UBAA/releases/tag/v1.4.1)

## v1.4.0

**发布日期：** 2026-03-23

- 更新研讨室预约功能
- 优化服务端会话持续时间

[GitHub Release](https://github.com/BUAASubnet/UBAA/releases/tag/v1.4.0)

## v1.3.0

**发布日期：** 2026-03-17

- 更新了 SPOC 作业查询功能，可一键查看所有 SPOC 作业
- 优化了空教室查询界面的教学楼选择逻辑
- 修复了服务端性能问题

[GitHub Release](https://github.com/BUAASubnet/UBAA/releases/tag/v1.3.0)

## v1.2.0

**发布日期：** 2026-01-08

- 新增一键自动评教功能
- 优化界面

[GitHub Release](https://github.com/BUAASubnet/UBAA/releases/tag/v1.2.0)

## v1.1.0

**发布日期：** 2025-12-24

- 修复启动页 bug
- 暂时停更

[GitHub Release](https://github.com/BUAASubnet/UBAA/releases/tag/v1.1.0)

## v1.0.3

**发布日期：** 2025-12-24

[GitHub Release](https://github.com/BUAASubnet/UBAA/releases/tag/v1.0.3)

## v1.0.2

**发布日期：** 2025-12-24

[GitHub Release](https://github.com/BUAASubnet/UBAA/releases/tag/v1.0.2)

## v1.0.1

**发布日期：** 2025-12-24

[GitHub Release](https://github.com/BUAASubnet/UBAA/releases/tag/v1.0.1)
