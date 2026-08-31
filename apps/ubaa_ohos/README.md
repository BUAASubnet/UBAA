# UBAA HarmonyOS 宿主

本目录是 HarmonyOS 的 Flutter OH 薄宿主。页面、主题、状态机、错误文案和
遥测合同来自 `../../packages/`；Rust 业务只能经后续的 FRB binding 调用
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

在 DevEco/Command Line Tools 26.0.0 Beta2、OpenHarmony API 26 和可签名
设备就绪前，本目录只代表可审查宿主骨架，HarmonyOS 状态仍为实验支持。

## 共享 package 接入

`pubspec.yaml` 只依赖共享层：

- `ubaa_app`：启动、登录、首页 bootstrap 与依赖注入；
- `ubaa_ui`：旧版风格的 Material 3 页面和组件；
- `ubaa_platform`：安全存储、遥测和安全错误投影接口。

`lib/main.dart` 只是 composition root。当前默认注入 `DemoBackend`、会话内
凭据库和关闭的遥测，便于无账号预览；FRB、HUKS 凭据库与遥测发送器完成
后在这里注入平台实现，不能把平台细节下沉到共享 UI。

后续 `packages/ubaa_bindings` 就绪后，本宿主和官方五平台宿主应依赖同一份
生成 Dart API。OHOS 只拥有 runner、签名、HUKS 适配和必要的平台插件差异。

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

## 生成 runner

只有预检全部通过后才能生成 `ohos/`：

```sh
cd apps/ubaa_ohos
export UBAA_OHOS_FLUTTER_HOME=/absolute/path/to/flutter-ohos-3.41.10
export UBAA_DEVECO_HOME=/absolute/path/to/DevEco-Studio.app/Contents
export HOS_SDK_HOME="$UBAA_DEVECO_HOME/sdk"
export OHOS_SDK_HOME="$HOS_SDK_HOME/default/openharmony/native"
export NODE_HOME="$UBAA_DEVECO_HOME/tools/node"
export PATH="$UBAA_OHOS_FLUTTER_HOME/bin:$UBAA_DEVECO_HOME/tools/ohpm/bin:$UBAA_DEVECO_HOME/tools/hvigor/bin:$NODE_HOME/bin:$PATH"

flutter create --platforms ohos --org cn.edu.ubaa .
cp local.properties.example ohos/local.properties
# 修改 ohos/local.properties 中全部占位路径，再审查 flutter create 的 diff。
flutter pub get
flutter build hap --debug --target-platform ohos-arm64
```

构建产物应位于 `build/ohos/hap/`。正式验收还必须完成：

1. DevEco 自动签名或受控发布签名；
2. `flutter devices` 能发现目标设备；
3. `hdc install` 安装并启动 HAP；
4. FRB Rust 调用、凭据能力、错误提示和只读功能 smoke；
5. 检查 HAP 中包含正确架构的 Rust 动态库；
6. 不产生或提交 `local.properties`、签名材料、密码、session 或遥测队列。
