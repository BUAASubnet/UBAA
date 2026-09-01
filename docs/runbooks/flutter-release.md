# Flutter 六平台发布 Runbook（P6 未完成）

更新：2026-09-01

本 Runbook 只规定可审计的发布顺序，不包含账号、证书、密码、Cookie、token 或签名私钥。
没有项目所有者对具体平台账号和证书的明确授权时，只能执行开发构建与确定性门禁，不能签名、
公证、上传商店或对真实账号执行写操作。

## 1. 发布前硬门禁

在发布分支的干净工作树执行：

```text
just refs
just check-sensitive
just check
just flutter-codegen-check
just flutter-check
just flutter-build platform=linux mode=release
just flutter-build platform=macos mode=release
just flutter-build platform=windows mode=release
just flutter-build platform=android-appbundle mode=release
just flutter-build platform=ios-device mode=release
just ohos-check mode=release
```

每个命令的输出只保留版本、平台、状态、产物路径、大小和校验摘要。禁止把 `.env.local`、
会话目录、构建日志中的凭据或任何原始上游响应加入工件。`ohos-check` 必须先通过锁定的
DevEco/CLI 26.0.0 Beta2 与 OpenHarmony API26 预检；API21 失败不能降级冒充。

## 2. 产物与签名隔离

| 平台 | 未签名验证产物 | 正式签名动作（需单独授权） |
|---|---|---|
| Windows | x64 Release bundle/安装包 | 使用受保护证书生成 MSIX/安装包，验证安装、升级、卸载 |
| macOS | arm64（必要时 x64）App/DMG | Keychain 中的 Developer ID 签名并公证，验证 Gatekeeper |
| Linux | x64 bundle/AppImage/deb | 使用发布密钥签名并生成 SBOM/许可清单 |
| Android | Release APK/AAB | 使用 Keystore 生成 AAB，检查备份策略和签名校验 |
| iOS | device Release Archive/IPA | 使用受保护 Apple 证书签名，验证真机安装与 Keychain |
| HarmonyOS | API26 arm64 HAP | 使用受保护 HarmonyOS 证书签名，验证 HUKS 与实体机 |

签名步骤必须在隔离 runner 执行，私钥不进入仓库、命令参数、普通日志或 artifact。先对未签名
产物做敏感扫描和依赖许可审计，再在受保护环境签名；签名完成后只发布校验摘要与公开版本信息。

## 3. 设备与路线 smoke

每个平台至少保留一份真实 Flutter→FRB→Core→upstream 只读摘要：登录/恢复、用户资料、每个领域
一个代表读取，并分别记录 Direct、WebVPN 的最终状态。Android、iOS、HarmonyOS 还要记录实体机
权限拒绝、前后台恢复和安全存储能力。路线失败必须标记 `BLOCKED`，不能改写为另一条路线成功。

写操作另走逐操作授权清单：目标、账号、操作、路线、时间、预期副作用和清理方式全部明确后，
串行执行 prepare→确认→commit→读取核对；任何 `outcome_unknown` 立即停止，不自动重试。

## 4. 回滚与留档

发布前保存版本号、Git 提交、产物 SHA-256、SBOM、第三方许可、签名/公证回执和设备矩阵。升级
失败时先停止分发，再使用上一份已验证产物回滚；回滚不删除用户 Core Session，除非迁移合同明确
要求清理。发布记录不得包含原始响应、个人资料或凭据。

当前状态：官方 Flutter 五平台 debug 原生 CI 已通过；OHOS API26/DevEco、六平台正式签名、
实体设备、安全存储插件和真实写入矩阵仍未闭合，因此不能执行正式发布步骤。
