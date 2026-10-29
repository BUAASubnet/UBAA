# 配置说明

## 应用设置

应用设置提供连接方式、主题、缓存与诊断入口。外观主题的当前设置仅本次运行生效，重启后跟随系统。保存账号与密码使用设备安全存储，能力不可用时会给出提示。

## CLI

CLI 使用平台用户配置目录，也可通过 `--config-dir` 指定独立目录。其中的配置与会话包含运行状态，不应提交到 Git 或随问题反馈上传。

```bash
cargo run --locked -p ubaa-cli -- --help
cargo run --locked -p ubaa-cli -- auth login --username YOUR_USERNAME
cargo run --locked -p ubaa-cli -- auth status
```

密码使用不回显输入或标准输入，不放在命令行参数中。

## 开发环境

工具链版本、冻结参考与构建命令见仓库[开发环境](https://github.com/BUAASubnet/UBAA/blob/ubaa2/docs/development/setup.md)。网站本身使用 Node.js 与 VitePress，不需要部署校园业务服务端。
