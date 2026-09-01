# Flutter 六平台发布 Runbook（无签名 RC）

更新：2026-09-01

本 Runbook 规定无签名 RC 的可审计顺序，并把正式签名发布列为后置流程；不包含账号、证书、密码、
Cookie、token 或签名私钥。没有项目所有者对具体平台账号和证书的明确授权时，仍不能签名、公证、
上传商店或对真实账号执行写操作。

## 1. 发布前硬门禁

在发布分支的干净工作树执行无签名 RC 门禁：

```text
just refs
just check-sensitive
just check
just flutter-codegen-check
just flutter-check
just release-preflight report_dir=/绝对路径/ubaa-release-report
just flutter-build platform=linux mode=debug
just flutter-build platform=macos mode=debug
just flutter-build platform=windows mode=debug
just flutter-build platform=android-apk mode=debug
just flutter-build platform=ios-simulator mode=debug
UBAA_OHOS_NO_CODESIGN=1 just ohos-check mode=debug
```

每个命令的输出只保留版本、平台、状态、产物路径、大小和校验摘要。禁止把 `.env.local`、
会话目录、构建日志中的凭据或任何原始上游响应加入工件。`ohos-check` 必须先通过锁定的
DevEco/CLI 26.0.0 Beta2 与 OpenHarmony API26 预检；API21 失败不能降级冒充。

`release-preflight` 只接受绝对报告目录，并要求工作树干净；它生成 Cargo 依赖元数据、CycloneDX
风格 SBOM、Dart/Flutter 锁文件清单、依赖/许可证审计、源码 SHA-256 和无签名状态摘要，不读取
凭据、不访问真实账号、不签名、不上传。
报告目录应放在仓库外或 CI 临时目录，完成审计后按项目保留策略归档。

## 2. 产物与签名隔离

| 平台 | 本轮无签名验证产物 | 后置正式签名动作（需单独授权） |
|---|---|---|
| Windows | x64 Debug bundle/安装包结构 | 使用受保护证书生成 MSIX/安装包，验证安装、升级、卸载 |
| macOS | arm64 Debug App | Keychain 中的 Developer ID 签名并公证，验证 Gatekeeper |
| Linux | x64 Debug bundle；Release 结构若工具链允许 | 使用发布密钥签名并生成 SBOM/许可清单 |
| Android | Debug APK 与 ABI/产物结构 | 使用 Keystore 生成 AAB，检查备份策略和签名校验 |
| iOS | simulator Debug App | 使用受保护 Apple 证书签名，验证真机安装与 Keychain |
| HarmonyOS | API26 arm64 无签名 HAP | 使用受保护 HarmonyOS 证书签名，验证 HUKS 与实体机 |

签名步骤必须在隔离 runner 执行，私钥不进入仓库、命令参数、普通日志或 artifact。先对未签名
产物做敏感扫描和依赖许可审计，再在受保护环境签名；签名完成后只发布校验摘要与公开版本信息。

## 3. 设备与路线 smoke

无签名 RC 至少保留一份可复现 Flutter→FRB→Core 确定性摘要：登录/恢复、用户资料、每个领域
一个代表读取，并分别记录 Direct、WebVPN 的 Core-live 状态。Android、iOS、HarmonyOS 的实体机
权限拒绝、前后台恢复和安全存储能力在没有设备时标记 `BLOCKED`；路线失败必须标记 `BLOCKED`，
不能改写为另一条路线成功。

写操作另走逐操作授权清单：目标、账号、操作、路线、时间、预期副作用和清理方式全部明确后，
串行执行 prepare→确认→commit→读取核对；任何 `outcome_unknown` 立即停止，不自动重试。

## 4. 回滚与留档

无签名 RC 前保存版本号、Git 提交、产物 SHA-256、SBOM、第三方许可、设备/签名阻塞清单和回滚
记录。升级失败时先停止分发，再使用上一份已验证产物回滚；回滚不删除用户 Core Session，除非
迁移合同明确要求清理。发布记录不得包含原始响应、个人资料或凭据。

当前状态：官方 Flutter 五平台 Debug 原生 CI 与 OHOS API26 无签名 Debug HAP 已通过；六平台
正式签名、实体设备、安全存储插件和真实写入矩阵仍未闭合，因此只能执行无签名 RC 流程，不能
执行正式发布步骤。
