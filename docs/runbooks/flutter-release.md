# Flutter 六平台交付与发布流程

更新：2026-10-07。本文规定当前可执行流程，历史候选与旧测试数量见[归档](../migration/history/flutter-release-before-engineering-2026-10-07.md)。实际授权、路线及设备范围以 [goal.md](../../goal.md) 为准；当前工程整改不执行真实账号验证、签名或发布。

## 候选与证据

为每轮记录源码候选 SHA、工作树状态、工具链、命令、平台/设备、路线、退出码、产物摘要和未执行原因。确定性、原生合成、真实插件通道、设备、Core-live、真实 App、签名/发布独立记账。

先完成并提交源码候选，再在同一候选验证。后续新增纯证据文档必须分别记录文档提交与被验证源码 SHA，不得将旧日志改称新 HEAD 全部通过；任何源码、测试、生成、锁文件或构建配置变化都使对应门禁失效。远端 workflow 以实际 head_sha、job 终态核对，不能以本地 ahead 或历史 run 推断当前 CI。

## 环境准备

首次缺少冻结引用时显式执行 `just refs-bootstrap`；已有引用只运行 `just refs`。质量工具依赖由显式 `just quality-tools-bootstrap` 建立；首次用 `cargo fetch --locked` 预取所有目标、`just flutter-dependencies` 准备七包锁定源码。preflight 不隐式联网安装。官方 Flutter/OHOS、Rust、FRB 固定版本及路径见[平台矩阵](../architecture/flutter-platforms.md)。

## 完整确定性门禁

```bash
just refs
just layout-check
just check-sensitive
just check-strict
just flutter-check
CARGO_INCREMENTAL=0 CARGO_BUILD_JOBS=1 just flutter-codegen-check
just integration-test
git diff --check
```

`check-strict` 强制固定 ShellCheck 并包含 Rust/CLI、Shell/Python、布局、依赖闭包、集成清单及合同检查；不能以明确跳过 ShellCheck 的宽松入口替代最终维护验收。Flutter/codegen/原生测试不是 Rust 门禁的隐含部分。

默认 macOS 集成包含应用流程、合成 FFI 缓存、本地恢复和真实插件通道。网络插件读取/订阅只证明 handler 正常，不证明校园可达；普通偏好使用独立合成 scope 并清理。其余平台及设备按清单单独执行，不对整个 integration_test 通配运行。

## 无签名构建与交付材料

在对应 runner 上执行实际目标，不在缺工具平台声称完成：

```bash
just flutter-build platform=macos mode=debug
just flutter-build platform=linux mode=debug
just flutter-build platform=windows mode=debug
just flutter-build platform=android-apk mode=debug
just flutter-build platform=ios-simulator mode=debug
UBAA_OHOS_NO_CODESIGN=1 just ohos-check mode=debug
just flutter-artifact-check platform=android-apk artifact=/绝对路径/app-debug.apk
just release-preflight /仓库外绝对路径/ubaa-release-report
```

`release-preflight` 要求工作树干净、报告目录为空，只运行纯 refs/敏感检查并生成依赖与源码清单；原始 Cargo metadata 仅为自动清理的临时输入，不进入报告。SBOM 必须通过其声明版本的固定 schema 校验；Cargo 元数据是解析依赖图，不自动等于每个平台实际打包集合。Dart/OHOS 许可材料应列出锁定来源、许可证证据及缺失项；包名/版本清单不称作许可批准。未解决的材料缺口进入发布阻塞清单。

产物结构检查覆盖宿主入口、Flutter资源和Rust动态库；macOS还核验实际签名权限。无签名Debug包和HAP不能证明商店签名、安装升级、设备HUKS或正式发布。普通日志、报告和工件不能包含凭据、Cookie、token、原始响应、完整个人资料或本机敏感路径；UI媒体在仓库外私有目录。

## 设备、真实路线与签名

Android/iOS/OHOS实体机权限、前后台、网络订阅及安全材料写读删需要独立设备证据。Core-live/真实App只在当前合同明确允许的路线和只读范围内执行，空结果、静态回退与Mock不能当作真实按钮验收。真实写入必须有具体操作、目标、路线及时间授权；unknown立即停止，不重试。

正式签名、公证和上传只能在相应授权和环境满足后进行。签名材料由平台安全存储和隔离runner管理，不进入源码、argv、普通日志或artifact；发布前核对候选SHA、校验摘要、许可材料、安装/升级/卸载和平台权限。

## 回退

保存上一份已验证产物、源码/生成/锁文件版本、独立磁盘Session/config/cache schema及兼容说明。失败时停止分发，先判定旧版本能否读取新格式，再回退产物；不能删除用户Session或密钥来掩盖不兼容。数据不可逆或旧版不支持的情形必须标明不能安全自动回退。回退后重新验证原平台启动、离线内容、安全材料和只读恢复，不重放写入。
