# UBAA HarmonyOS 宿主

本目录是 HarmonyOS 的 Flutter OH 薄宿主。页面、主题、状态机、错误文案和
遥测合同来自 `../../packages/`；Rust 业务只能经 FRB binding 调用
`ubaa-core::facade`。宿主不得复制 URL、Cookie、路线选择或协议解析逻辑。

## 固定基线

- 仓库：<https://gitcode.com/CPF-Flutter/flutter_flutter.git>
- tag：`3.41.10-ohos-1.0.1`
- commit：`adaf911c35c9136a7d18fc424d714c9ec7724e60`
- Dart：`3.11.5`
- 目标架构：`ohos-arm64`
- 构建与目标 API：OpenHarmony API 26

不要对 Flutter OH 执行 `flutter upgrade`。它会切回上游 Flutter channel，
破坏 OHOS 适配；版本切换必须使用固定 tag/commit 并重新验证整个矩阵。

## 当前阻塞

当前机器已有 Flutter OH 固定版本、DevEco Studio 6.0.1、OpenHarmony API
21、`ohpm`、`hvigor` 和 `hdc`。该组合不是发布基线：当前 fork 的 API 26
符号不能由 API 21 或公开 API 18 SDK 提供。不能通过改低
`compatibleSdkVersion`、伪造清单或删除失败代码规避。

锁定 fork 已生成 `ohos/` runner，OHOS Dart app 的 pub get、analyze 和 widget test
通过，`ubaa_bindings` 也已接入 arm64 Cargokit HAR。DevEco/Command Line Tools
26.0.0 Beta2、OpenHarmony API 26 和可签名设备就绪前，仍不能生成验收 HAP，
HarmonyOS 状态保持实验支持。

## 共享 package 接入

`pubspec.yaml` 只依赖共享层：

- `ubaa_bindings`：同一 FRB Dart API 与 OHOS arm64 native 构建接线；
- `ubaa_app`：启动、登录、首页 bootstrap 与依赖注入；
- `ubaa_ui`：旧版风格的 Material 3 页面和组件；
- `ubaa_platform`：安全存储、遥测和安全错误投影接口。

`lib/main.dart` 只是 composition root。P0 已执行 `RustLib.init` 与固定 hello；当前
生产入口使用 `createProductionBackend()` 创建 FRB backend，初始化失败时安全显示
`unsupported`，不会回退到 Demo 数据。`DemoBackend` 只允许由 widget 测试显式注入。
HUKS 凭据库与遥测发送器也只在这里组合，不能把平台细节下沉到共享 UI。

本宿主和官方五平台宿主已经依赖同一份生成 Dart API。OHOS 只拥有 runner、
签名、HUKS 适配和必要的平台插件差异。

## 工具链预检

脚本是只读检查，不会下载依赖或生成项目：

```sh
cd apps/ubaa_ohos
UBAA_OHOS_FLUTTER_HOME=/absolute/path/to/flutter-ohos-3.41.10 \
UBAA_DEVECO_HOME=/absolute/path/to/DevEco-Studio.app/Contents \
./scripts/check-toolchain.sh
```

脚本会核对固定 Flutter commit/tag、DevEco 26、SDK API 26、native SDK、
Node、`ohpm`、`hvigor`、`hdc`、JDK 17+ 和 Rust
`aarch64-unknown-linux-ohos` target。任一硬门槛不满足都会非零退出。

## 可复现检查与构建

runner 已由锁定 fork 生成。工具链不匹配时只允许运行 Dart 检查；HAP 构建必须先
通过根级预检：

```sh
cd /absolute/path/to/UBAA
just ohos-check mode=debug
```

`ohos/local.properties` 只保存本机绝对路径，始终忽略且不得提交。设备 FRB smoke 使用
`ohos/ohos_device_smoke_main.dart`，只在 `bridgeHello` 返回固定值后输出
`FRB_OHOS_SMOKE_RESULT=PASS`。

构建产物应位于 `build/ohos/hap/`。正式验收还必须完成：

1. DevEco 自动签名或受控发布签名；
2. `flutter devices` 能发现目标设备；
3. `hdc install` 安装并启动 HAP；
4. FRB Rust 调用、凭据能力、错误提示和只读功能 smoke；
5. 检查 HAP 中包含正确架构的 Rust 动态库；
6. 不产生或提交 `local.properties`、签名材料、密码、session 或遥测队列。
