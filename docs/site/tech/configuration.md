# 配置说明

## 应用设置

应用设置提供连接方式、主题、缓存与诊断入口。外观主题可选跟随系统、浅色或深色，作为设备偏好保存，重启后恢复上次选择，不随退出或清除账号删除。首次使用、读取失败或保存值无效时跟随系统。保存失败时，本次界面的主题选择仍然生效，下次启动可能无法恢复。

保存账号与密码使用设备安全存储，能力不可用时会给出提示。外观偏好与账号凭据分别保存。

## CLI

桌面 `ubaa` 命令与应用共用账号及本机数据，也可通过 `--config-dir` 指定业务资料目录。系统安全材料仍属于当前系统用户，单独修改目录不等于隔离全部账号材料。

```bash
ubaa --help
ubaa auth login --username YOUR_USERNAME
ubaa auth status
```

密码使用不回显输入或标准输入，不放在命令行参数中。

安装入口与脚本调用见[桌面命令模式](/features/command)。

## 开发环境

工具链版本、冻结参考与构建命令见仓库[开发环境](https://github.com/BUAASubnet/UBAA/blob/main/docs/development/setup.md)。网站本身使用 Node.js 与 VitePress，不需要部署校园业务服务端。
