# Flutter 六平台交付与发布流程

更新：2026-10-07。本文规定当前可执行流程，历史候选与旧测试数量见[归档](../migration/history/flutter-release-before-engineering-2026-10-07.md)。当前阶段目标见 [goal.md](../../goal.md)，授权与安全规则见 [AGENTS](../../AGENTS.md#真实账号与验收范围)；历史任务不能授权新的账号请求、签名或发布。

## 候选与证据

为每轮记录源码候选 SHA、工作树状态、工具链、命令、平台/设备、路线、退出码、产物摘要和未执行原因。确定性、原生合成、真实插件通道、设备、Core-live、真实 App、签名/发布独立记账。

先完成并提交源码候选，再在同一候选验证。后续新增纯证据文档必须分别记录文档提交与被验证源码 SHA，不得将旧日志改称新 HEAD 全部通过；任何源码、测试、生成、锁文件或构建配置变化都使对应门禁失效。远端 workflow 以实际 head_sha、job 终态核对，不能以本地 ahead 或历史 run 推断当前 CI。

## 环境准备

首次缺少冻结引用时显式执行 `just refs-bootstrap`；已有引用只运行 `just refs`。质量工具依赖由显式 `just quality-tools-bootstrap` 建立；首次用 `cargo fetch --locked` 预取所有目标、`just flutter-dependencies` 准备七包锁定源码。preflight 不隐式联网安装。官方 Flutter/OHOS、Rust、FRB 固定版本及路径见[平台矩阵](../architecture/flutter-platforms.md)。

## 验收入口

完整确定性清单、原生/发布候选的默认集成集合及平台专项只在[开发命令](../development/commands.md#检查选择与完成条件)维护。按该清单运行并保留实际结果；普通 Flutter、FRB 和原生测试分别记账。原生集合中的插件网络读取/订阅只证明 handler 行为，不证明校园可达。

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

`release-preflight` 要求工作树干净、报告目录为空，只运行纯 refs/敏感检查并生成 Dart/OHOS 许可证材料。Rust 依赖的许可与安全公告由 `just dependency-audit`（cargo-deny）检查，发布前单独运行。源码以提交 SHA 标识，不再另生成逐文件源码清单或 SBOM。Dart/OHOS 许可材料应列出锁定来源、许可证证据及缺失项；包名/版本清单不称作许可批准。默认严格模式遇到材料缺口会保留报告并以状态 3 阻断发布。仅报告模式仍列出缺口，但不能用于判定发布通过，日常 CI 不运行本入口；参数与实际边界见[开发命令](../development/commands.md#构建与发布命令)。

产物结构检查覆盖宿主入口、Flutter资源和Rust动态库；macOS还核验实际签名权限。无签名Debug包和HAP不能证明商店签名、安装升级、设备HUKS或正式发布。共享日志、报告和工件不能包含凭据、Cookie、token、原始响应、完整个人资料或本机敏感路径；本地原始调试材料与 UI 媒体统一保存在被忽略的 `.ubaa_local/` 任务子目录。

## 设备、真实路线与签名

各平台材料、旧版升级身份、本机配置与 CI secret 映射统一见[应用签名配置](app-signing.md)。

Android/iOS/OHOS实体机权限、前后台、网络订阅及安全材料写读删需要独立设备证据。Core-live/真实App只在当前会话用户已授权的路线和只读范围内执行，空结果、静态回退与Mock不能当作真实按钮验收。真实写入必须有具体操作、目标、路线及时间授权；unknown立即停止，不重试。

正式签名、公证和上传只能在相应授权和环境满足后进行。签名材料由平台安全存储和隔离runner管理，不进入源码、argv、普通日志或artifact；发布前核对候选SHA、校验摘要、许可材料、安装/升级/卸载和平台权限。

## 回退

保存上一份已验证产物、源码/生成/锁文件版本、独立磁盘Session/config/cache schema及兼容说明。失败时停止分发，先判定旧版本能否读取新格式，再回退产物；不能删除用户Session或密钥来掩盖不兼容。数据不可逆或旧版不支持的情形必须标明不能安全自动回退。回退后重新验证原平台启动、离线内容、安全材料和只读恢复，不重放写入。


### 候选输入与产物关联

原生工作流的 build-record.json 将候选 SHA、工作树是否干净和 GitHub 作业关联，源码内容由提交 SHA 唯一确定；原生工作流同时生成 artifact-files.json，使用相对路径及逐文件摘要，避免同一产物因本机绝对目录不同而得到不同内容摘要。外部 SDK、系统库、下载依赖和签名环境仍需按平台登记，这不是可复现构建证明。

## OHOS 原生依赖材料

OHPM 的本地依赖分两类处理。受 Git 跟踪、位于本仓库内的纯 `.d.ts` 包记录版本与文件摘要，并沿用项目许可证；这类记录不包含实际动态库。三个 OHOS 插件依赖的 `@ohos/flutter_ohos`（Flutter embedding HAR）来自锁定的 OHOS Flutter SDK：报告器读取 `.env.toolchain` 中的 `UBAA_OHOS_FLUTTER_HOME`，确认其提交等于 `versions.env` 的 `OHOS_FLUTTER_COMMIT` 后，收集 SDK 根目录与 `bin/cache/artifacts/engine/ohos-arm64/` 中的许可证正文，并记录 `OHOS_FLUTTER_REMOTE`、提交和版本。不需要手写材料清单。

SDK 未配置或提交不符时，该依赖保留为缺口，严格模式以状态 3 阻止发布。来源字段来自锁定 SDK，不能独立证明二进制由该源码构建；实际 HAP、动态库架构、签名和构建关联仍按本手册的产物验收执行。
