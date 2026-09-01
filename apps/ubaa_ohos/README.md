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

当前机器的 DevEco Studio 与 Command Line Tools 均为 `26.0.0.821`，Hvigor 为
`6.26.4`，ohpm 为 `26.0.0.630`，Node 为 `24.14.1`，OpenHarmony SDK 为 API
26。锁定 fork 的 `ohos/` runner、OHOS Dart app 的 pub get、analyze、widget test、
native 前置和 HAP assemble 前置均已通过。工程使用 API26 要求的
`compatibleSdkVersion`/`targetSdkVersion: "26.0.0"` 与 `modelVersion: "6.0.0"`。

两种安装布局均受门禁支持：DevEco Studio 的 `Contents/tools/...`，以及
Command Line Tools 根目录的 `tool/...`。当前 DevEco 已启用自动签名配置，但没有实体
设备时无法生成 profile。可以用 `UBAA_OHOS_NO_CODESIGN=1` 执行 debug 构建，得到只用于
包内容和 arm64 动态库检查的未签名 HAP；该产物不可安装到实体设备、不可作为发布或 P0
验收证据。不能通过改低 API、伪造清单或删除失败代码规避签名要求。

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

`UBAA_DEVECO_HOME` 也可以指向 Command Line Tools 根目录。脚本会核对固定 Flutter
commit/tag、DevEco/CLI 26、SDK API 26、native SDK、Node、`ohpm`、`hvigor`、`hdc`、JDK 17+ 和 Rust
`aarch64-unknown-linux-ohos` target。任一硬门槛不满足都会非零退出。

## 可复现检查与构建

runner 已由锁定 fork 生成。HAP 构建必须先通过根级预检；正式构建需要签名配置：

```sh
cd /absolute/path/to/UBAA
just ohos-check mode=debug
```

无实体设备时的非发布包内容检查：

```sh
UBAA_OHOS_NO_CODESIGN=1 just ohos-check mode=debug
```

该模式只允许 `debug`，并明确输出 `entry-default-unsigned.hap`；正式
`just ohos-check mode=release` 仍必须使用受控签名。

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
