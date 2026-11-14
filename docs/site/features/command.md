---
description: 在终端使用 UBAA 桌面版附带的 ubaa-cli 命令查询校园信息、操作云盘和管理本机日程。
---

# 桌面命令模式

本页帮你在终端里使用 UBAA：找到 `ubaa-cli` 命令、完成常用查询，以及在脚本中安全地调用。

`ubaa-cli` 可以查询校园信息、操作云盘和管理本机日程。它与图形界面共用账号、登录状态、缓存和日程，适合在终端使用或写脚本调用。

## 找到命令

Windows、macOS 和 Linux 的官方安装包都附带 `ubaa-cli`，不需要另外下载，见[下载 UBAA](/download)。命令与图形应用来自同一个安装包，版本始终一致。

| 平台 | 命令位置 | 加入 PATH 的方式 |
| --- | --- | --- |
| Windows | 安装目录中的 `ubaa-cli.exe`，默认在 `%LOCALAPPDATA%\Programs\UBAA` | 把安装目录加入 PATH，或直接运行完整路径 |
| macOS | `UBAA.app/Contents/MacOS/UBAA --command` | 按下文创建名为 `ubaa-cli` 的脚本 |
| Linux | 解压目录 `bundle/` 中的 `ubaa-cli` | 把它链接到 PATH 中的目录，保留原目录和其中的 `lib/` |

Windows 的 `ubaa-cli.exe` 需要与同目录的 DLL 和 `data/` 一起使用，不要单独复制。

macOS 可以在 PATH 中的目录创建名为 `ubaa-cli` 的脚本，路径改为实际安装位置，再添加执行权限：

```sh
#!/bin/sh
exec "/Applications/UBAA.app/Contents/MacOS/UBAA" --command "$@"
```

## 常用查询

```bash
ubaa-cli --help
ubaa-cli auth login --username YOUR_USERNAME
ubaa-cli auth status
ubaa-cli schedule terms
ubaa-cli grades list --term 2025-2026-1
ubaa-cli agenda list --from 2026-11-01 --to 2026-11-08
ubaa-cli agenda export --from 2026-11-01 --to 2026-11-08 --output ./agenda.ics
```

- 密码通过不回显输入或标准输入提供，不放在命令参数中。
- 本机日程的查询和导出不请求学校服务。
- 命令结束只关闭当前进程，退出账号使用 `ubaa-cli auth logout`。

## 修改与脚本调用

- 学校写操作需要加 `--confirm-write`，本机日程修改需要加 `--confirm-local-write`。先用对应子命令的 `--help` 核对输入与目标。
- 操作结果未知时，先查询记录，不要自动重复提交。
- `--json` 返回结构化结果，例如 `ubaa-cli --json agenda unsynced`。脚本应同时检查退出码和返回内容里的业务结果，进程正常退出不等于提交成功。

JSON 输出的完整格式见开发者文档中的 [命令 JSON 格式](https://github.com/BUAASubnet/UBAA/blob/main/docs/contracts/cli-json.schema.json)。

## 资料目录

命令默认与图形界面使用同一个资料目录，也可以用 `--config-dir` 指定另一个目录。系统安全存储里的账号材料仍属于当前系统用户，单独换目录不等于隔离全部账号材料。

## 平台说明

Linux 命令需要当前系统用户可用且已解锁的 Secret Service（如 GNOME 钥匙环）。通过 SSH 登录、没有可用安全存储时，命令会说明原因。

想自己从源码构建，见[参与开发](/tech/contributing)。
