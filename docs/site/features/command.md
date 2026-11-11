# 桌面命令模式

本页介绍桌面版附带的 `ubaa` 命令：怎样安装，以及常用的查询和修改方式。

`ubaa` 命令可以查询校园信息、操作云盘和管理本机日程。它与图形界面共用账号、登录状态、缓存和日程，适合在终端使用或写脚本调用。

## 安装入口

使用包含命令组件的桌面安装包，保留应用与命令组件的版本一致。

| 平台 | 入口 |
| --- | --- |
| macOS | App 内的 `Contents/MacOS/ubaa_flutter --command`，可用启动脚本包装为 `ubaa` |
| Windows | 应用目录内的 `ubaa.exe`，与同目录的 DLL 和 `data/` 一起保留 |
| Linux | 应用目录内的 `ubaa`，与配套 `lib/` 一起保留 |

Windows 可以将应用目录加入 PATH。Linux 可以将 `ubaa` 链接到 PATH 中的目录，保留实际应用目录和动态库。macOS 可在 PATH 中的目录创建名为 `ubaa` 的脚本，将下面的路径改为实际安装位置：

```sh
#!/bin/sh
exec "/Applications/UBAA.app/Contents/MacOS/ubaa_flutter" --command "$@"
```

为脚本添加执行权限后使用。想自己从源码构建，见[参与开发](/tech/contributing)。

## 常用查询

```bash
ubaa --help
ubaa auth login --username YOUR_USERNAME
ubaa auth status
ubaa schedule terms
ubaa grades list --term 2025-2026-1
ubaa --json agenda unsynced
ubaa agenda list --from 2026-11-01 --to 2026-11-08
ubaa agenda export --from 2026-11-01 --to 2026-11-08 --output ./agenda.ics
```

密码通过不回显输入或标准输入提供，不放在命令参数中。默认的本机日程查询和导出不请求学校服务。命令结束只关闭当前进程，退出账号使用 `ubaa auth logout`。

## 修改与脚本调用

学校写操作需要 `--confirm-write`，本机日程修改需要 `--confirm-local-write`。先用对应子命令的 `--help` 核对输入与目标。操作结果未知时，先查询记录，不自动重复提交。

`--json` 返回结构化结果。脚本应同时检查退出码和返回内容里的业务结果，进程正常退出不等于提交成功。参数、输出与日程字段的完整定义见仓库中的[命令说明](https://github.com/BUAASubnet/UBAA/tree/main/docs/contracts)。

Linux 命令需要当前系统用户可用且已解锁的 Secret Service；SSH 会话没有可用安全存储时，命令会说明原因。
