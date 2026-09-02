# Flutter 六平台发布 Runbook（无签名 RC）

更新：2026-09-02

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
just release-preflight /绝对路径/ubaa-release-report
just flutter-build platform=linux mode=debug
just flutter-build platform=macos mode=debug
just flutter-build platform=windows mode=debug
just flutter-build platform=android-apk mode=debug
just flutter-build platform=ios-simulator mode=debug
UBAA_OHOS_NO_CODESIGN=1 just ohos-check mode=debug
# 构建完成后按平台检查 bundle/APK/App 内的入口、资源和 FRB 动态库
just flutter-artifact-check platform=android-apk artifact=/绝对路径/app-debug.apk
```

每个命令的输出只保留版本、平台、状态、产物路径、大小和校验摘要。禁止把 `.env.local`、
会话目录、构建日志中的凭据或任何原始上游响应加入工件。`ohos-check` 必须先通过锁定的
DevEco/CLI 26.0.0 Beta2 与 OpenHarmony API26 预检；API21 失败不能降级冒充。

`release-preflight` 只接受绝对报告目录，并要求工作树干净；它生成 Cargo 依赖元数据、CycloneDX
风格 SBOM、Dart/Flutter 锁文件清单、依赖/许可证审计、源码 SHA-256 和无签名状态摘要，不读取
凭据、不访问真实账号、不签名、不上传。
原生 CI 在上传五平台 Debug 产物前调用 `scripts/verify-flutter-artifact.sh`，逐平台确认宿主入口、
Flutter 资源、App.framework 或 Android 三种 ABI 的 FRB 动态库存在，并输出大小和 SHA-256；缺失
条目会使该平台 job 失败。该检查只验证包结构，不代表签名、安装或设备运行成功。
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

当前状态：提交 `f46c65c` 的本地 `just flutter-check`、`just check`、`just check-sensitive`、`just release-preflight`
和 API26 无签名 OHOS HAP 复核均通过；其合同 CI `33592184452` 与官方 Flutter 五平台 Debug 原生 CI `33592184458`
已终态成功并上传无签名产物。共享确认壳对显式 `outcome_unknown` 及提交异常统一提示先刷新相关状态、禁止重复提交，
不触发自动重试或写后刷新。FRB 零漂移本机复核因 cargo-expand 无输出被安全中断，需恢复工具链后重试，不能记为通过。
提交 `190f318` 的官方 Flutter macOS 宿主集成 4/4 通过，额外覆盖 commit 异常不刷新、不误报成功的安全边界。
该提交的合同 CI `33593160544` 与五平台 Debug CI `33593160580` 均成功，文档提交 `f7d0015` 的合同 CI `33593227275` 亦成功；
产物均为无签名 Debug，不能替代 OHOS 签名、设备安装或真实写后核对。
当前 HEAD 再次尝试 `CARGO_INCREMENTAL=0 CARGO_BUILD_JOBS=1 just flutter-codegen-check` 时，cargo-expand 无输出后被安全中断且无生成漂移；
FRB 本机零漂移仍需工具链恢复后重试，不能记为通过。
最终审计提交 `7e6a4ea` 已复核引用、敏感扫描、无签名 RC 前置报告、差异检查以及 `HEAD == origin/ubaa2`；工作树干净，临时 OHOS
无签名产物已移出仓库。
六平台正式签名、实体设备、安全存储插件和真实写入矩阵仍未闭合，因此只能执行无签名 RC 流程，不能执行正式发布步骤。

最新无签名确定性证据：提交 `949d7eb` 的官方 macOS 宿主集成测试 5/5 通过，覆盖十二个功能的 typed 查询入口；`WriteFlowController`
的十项写操作矩阵验证每项只提交一次并拒绝重复确认。该证据不包含真实写请求、写后上游核对、签名、设备或系统安全存储。

当前无签名平台能力证据：`ubaa_platform` 的 `MethodChannelPermissionGateway`、
`MethodChannelSecureCredentialStore` 和 `MethodChannelPhotoPicker` 已接入官方 Flutter 与 OHOS
宿主默认组合，并以 Mock 覆盖权限状态、凭据探测/读写/清除、无效凭据拒绝和照片字节边界；
`just flutter-check` 通过。未注册原生 handler 时能力保持不可用，不会伪造 Keychain、Keystore、
Secret Service 或 HUKS。原生 handler、实体设备权限/生命周期和硬件安全存储仍为后置 `BLOCKED`。

提交 `30297a5` 后的 OHOS 无签名复核同样通过：`UBAA_OHOS_NO_CODESIGN=1 just ohos-check
mode=debug` 使用 API26 工具链生成并检查 `entry-default-unsigned.hap` 和 arm64 Rust bridge；
产物未签名、未安装、未上传，生成输出已移出工作树。

FRB 零漂移状态已更新：当前 HEAD `1ca6ed8` 执行
`CARGO_INCREMENTAL=0 CARGO_BUILD_JOBS=1 just flutter-codegen-check` 成功并报告“FRB 生成零漂移”。
此前 cargo-expand 无输出并安全中断的记录属于旧次尝试，不应覆盖本次通过证据。

最新 CI 终态：官方 Flutter 原生 run `33599670789`（提交 `1ca6ed8`）的 Windows、Linux、macOS、
iOS simulator、Android APK 五个 job 全部成功；macOS job 同时通过宿主 integration smoke。合同 run
`33600117413`（提交 `993f5a2`）的 `contract-gates`、macOS Rust、Windows Rust 全部成功。产物均为无签名
Debug，结构检查和确定性 smoke 不代表签名、安装、设备或真实账号写入成功。

最新无签名执行终态（2026-09-02）：`81dd9d2` 的官方 macOS 宿主十项写入组合回归在预期失败后通过，
逐操作断言提交后刷新关联只读领域；当前营业窗口内 Direct/WebVPN Core-live 串行复核均 exit code 0。
Flutter 原生 CI `33620644050`（Linux、Windows、macOS、iOS simulator、Android APK）和合同 CI
`33620644066` 均终态成功；十二项详情 golden、状态矩阵、typed 查询、十项写入确认/不确定结果、
API26 无签名 OHOS HAP/arm64、SBOM/依赖审计、敏感扫描、迁移回滚文档与工作树门禁均已复核。因此无签名
执行目标 P3–P6 可交付部分已完成。该终态不包含真实账号写入、写后上游核对、原生安全存储 handler、
实体设备权限/生命周期、签名/公证或商店发布；上述事项继续保持后置 `BLOCKED`。
