# 测试与质量

工程使用脱敏 Fixture、Mock、Rust 测试、Dart 测试与界面回归检查。修改协议需要先比较冻结参考并建立失败反例，再实现修复。

日常改动用 `just check-plan` 规划范围，再运行对应检查。维护门禁、公共合同或跨模块整理还需完整的 Rust/Shell 与 Flutter 检查。

```bash
just refs
just layout-check
just check-sensitive
just check
just flutter-check
```

真实学校只读验证、实体设备、安装升级、签名与发布分别验收。模拟数据通过不能证明真实预约或提交已经成功。CI 不接收真实学校凭据。

网站使用 `npm ci` 安装锁定依赖，运行 `npm run docs:build` 检查 Markdown 与站内链接，再用 `npm run docs:preview` 核对页面。
