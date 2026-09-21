# 离线首页与后台恢复执行记录

## 基线核对

2026-09-17：源工作区 `ubaa2 @ d7c37f73` 干净。`git merge-base --is-ancestor` 确认 `7273283a` 与 `db4e198d` 均已包含。既有引用管理、UI、图标和查询更改已分别提交于 `f63e6d06`、`8f66ce7e`、`d7c37f73`，实施分支完整继承，不冒充新成果。源目录保留原样。

隔离区 `.worktrees/offline-home-20260917`、分支 `codex/offline-home-20260917`，只读复用源目录冻结引用。源和实施区 `just refs` 均退出 0，SHA 与 references.md 一致。无凭据复制、无运行会话修改、无真实学校写入。

## 当前证据

| 类别 | 当前结论 |
|---|---|
| 合同 | 已归档旧暂停合同，建立新 P0–P5 合同 |
| 实现/确定性 | 已有 Core 加密仓库、安全材料/索引和 P1-A 首页恢复；业务缓存接线仍未完成 |
| 原生/性能 | macOS 合成安全材料原生通过、OHOS 无签名构建通过；缓存首屏指标未测 |
| Core-live / 真实 App | 尚未运行 |
| 发布 | 不在本轮授权范围，无发布证明 |

## 当前步骤

P0：核对逐操作来源、加密存储及平台密钥能力、独立本地读取与分段认证/读取边界。已发现当前启动等待 authStatus/userInfo，前台恢复固定 rebuildBackend，安全平台通道目前仅提供凭据结构，均需明确改造而非仅隐藏加载动画。

## P0-A：所需路线恢复与存储可行性

新增 `UbaaClient::recover_required_session(feature)`，仅调用 Core 既有路由矩阵解析出的路线。RED：新 facade 入口缺失，E0599、退出 101；GREEN：4 项新增恢复测试通过，整个 facade 24 项通过。双路线均有保存槽位时，未选中路线 transport 一旦调用即失败，以验证只访问目标路线；另外验证缺材料零请求、503 保留会话/401 只清目标路线，以及 Auto 不越过功能矩阵切换到已有 Direct。

`just check` 退出 0，包含 Rust fmt/clippy、Core feature-on/off、CLI 二进制端到端 16 项、Bridge 110 项通过/2 项既有忽略、Shell 合同、文档编译等。此阶段未改 Bridge/Dart，尚未实现 App 路线恢复接线，不宣称登录性能改善。首次新增 Auto 测试曾错误预期签到支持就绪路线回退；现有功能矩阵禁止该回退，已修正测试以保持原合同，生产路由规则未改动。

存储可行性原型使用 rusqlite 0.38.0（bundled SQLite）与 aes-gcm 0.10.3，在仓库外 `/tmp/ubaa-offline-storage-probe` 运行合成数据插入、密文读取和 AAD 不匹配拒绝。macOS 运行退出 0；`aarch64-unknown-linux-ohos`、`aarch64-apple-ios-sim`、`aarch64-linux-android` 均编译退出 0。OHOS 使用当前 DevEco native clang，Android 使用 NDK 28.2 的 API23 clang。这些是原型可编译/本机运行证据，不是宿主绑定、原生数据库运行或六端完成证明；Windows/Linux 原生运行未验证。

macOS 仓库外 Swift Keychain 原型采用随机独立 service 和合成 32 字节测试值，SecItemAdd/CopyMatching/Delete 均返回 0，内容匹配；没有读取或改动既有账号/凭据。iOS/Android/OHOS 安全存储运行尚未验证，Windows/Linux 也待验证。原生 handler 仍需实现。

选型依据：[rusqlite 官方仓库](https://github.com/rusqlite/rusqlite) 的 bundled 构建和 [RustCrypto AES-GCM](https://docs.rs/aes-gcm/0.10.3/aes_gcm/) 的认证载荷接口；Apple 密钥保护使用 [设备本机的首次解锁后可访问策略](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly)。当前只锁定可行性方向，后续业务缓存仍须 RED/GREEN、精确键/事务/代次/容量/故障注入验证。

下一步：实现 Core 独立本地加密仓库及平台安全密钥合同，再连接本地首页与首帧恢复。P0 全阶段未完成，P1–P5 未完成。

## P0-B：Core 加密缓存基础

新增独立 OfflineRepository，使用 bundled SQLite 短事务、AES-256-GCM 随机 nonce、HMAC 查询索引和 Zeroizing 密钥；账号采用随机内部别名，各库独立，查询依据和载荷都加密。只允许白名单课表/希冀索引与展示 DTO，不能保存任意 JSON、Cookie、写资格或 opaque handle。业务读取尚未接线，新增库不会自动访问学校网络或启用离线首页。

请求 ticket 由持久修订和账号代次保护；新请求使旧响应失效，退出/清理使所有旧句柄回写失效；成功完整空集合可替换，部分/失败保留旧内容和 fetchedAt。单条损坏只隔离该范围；未知版本/错误密钥不重建成明文；软容量优先淘汰旧详情，硬容量和 SQLite 页数失败保留上个事务。随机内部别名不是用户名。

RED：缓存类型/仓库缺失，聚焦命令退出 101。实现中路径测试暴露 macOS /var 系统祖先链接与 SQLITE_OPEN_NOFOLLOW 的冲突，已在校验调用方目录后固定 canonical 父目录；数据库与 journal/wal/shm 自身链接仍拒绝。同秒失败新鲜度断言实际失败，增加独立成功标记后 GREEN。最终新增 13 项仓库行为测试全部通过（命令过滤同时运行 2 项既有内存 cache 测试，共 15 项）；覆盖加密重开、日期/路线/账号隔离、AAD 交换拒绝、失败/部分/完整空集合、旧修订/重复/跨账号 ticket、跨句柄退出清理、容量淘汰、真正 SQLITE_FULL 回滚、损坏隔离、未知版本和符号链接。

`cargo clippy --locked -p ubaa-core --all-targets --all-features -- -D warnings` 和本阶段 `just check` 均退出 0；依赖及编译合同的两个 Cargo.lock 已同步，旧 CLI/Bridge 合同版本不变。这里证明 Core 仓库基础，不证明平台安全材料接线、业务接入、多端缓存首屏或真实性能。下一步继续安全存储适配与本地账号索引。

## P0-C：安全材料和本机账号索引

增加安全材料适配、本机账号索引和独立随机缓存密钥。索引/密码/缓存密钥分开保存，退出持久关闭恢复并递增代次；换账号不共享密钥，旧密钥缺失明确失败而不悄悄生成替代。旧 autoLogin=false 保持 false；存在原生旧凭据通道时优先保留其路径。新代码尚未接入 AppController 启动，不能把本阶段当成本地首页完成。

RED：安全材料和账号索引接口缺失，Flutter 新增测试失败；实现后 GREEN。共享 Flutter 全部 7 个 package/宿主检查通过：domain 54、platform 65、app 273、UI 249、bindings 15、host 30、官方宿主 54，共 740 项。随后针对 macOS 插件真实参数差异增加回归测试，platform 完整复验为 66 项。`flutter analyze`、格式化与本阶段 `just check`、refs/sensitive 均通过。新增原生测试归入 integration_test/offline，保持每层目录结构门禁，不扩大 baseline。

macOS 真实合成探测：`integration_test/offline/secure_material_test.dart -d macos` 的同一测试内容执行 1 项通过，验证实际系统安全存储写入、重新建立适配器读取、删除及确认空值。整个探测仅用随机独立测试键和合成文本，finally 清理。初次添加 Keychain Sharing 使本地无开发签名构建失败；改用登录钥匙串后又由允许字段诊断定位原生 -34018，最终按固定 darwin 0.2.0 的真实参数键修复并通过。保持沙箱；没有读取用户现有凭据、没有签名发布。工具报告无法将窗口置前，但原生测试进程执行成功；不据此声称视觉验收通过。

OHOS：新增独立 HUKS 通道，按本机 API26 和官方 AES-GCM 合同编译；`UBAA_OHOS_NO_CODESIGN=1 just ohos-check mode=debug` 退出 0，HAP 和 arm64 动态库门禁通过。只有无签名构建证据，未在设备运行 HUKS。构建生成的 SDK 相对锁路径和 buildinfo 已恢复为原基线，生成 rawfile/动态库/BuildProfile 明确忽略，不把临时工程资源提交。

iOS/Android 安全材料运行及 Windows/Linux 原生运行仍未验证；这些平台有插件接线，不以接线替代运行。下一步 P1 首帧本地首页与立即恢复；P0 的 Judge 分段及全操作合同仍需继续补齐。

## P1-A：首页首帧恢复与原位登录（2026-09-21 续跑核验）

续跑核对：源工作区仍为干净的 `ubaa2 @ d7c37f73`，隔离分支 `c516bb0a` 上保留上轮未提交 P1 代码；无仍运行的构建，冻结引用再次通过。上轮为有实际提交/代码/测试证据的进展，非等待或无进展。

生产宿主注入安全账号索引；有可恢复账号时先进入首页，首帧回调自动创建/合并恢复；缺材料、网络失败不将当前页换回全屏启动。旧 autoLogin=false 仍检查会话但不自动提交密码，明确失效且获准凭据存在才登录。用户可在原页面打开登录面板，成功后保留所选入口；登录选项合并为“在此设备保留登录”，用户操作同时明确授权保留和自动使用材料。安全材料不可用保留非敏感外壳，避免 user=null 崩溃。

恢复认证和学校写资格分离，唯一 WriteCoordinator 在未恢复状态拒绝 prepare，恢复完成不自动重放；退出前持久关闭账号恢复，晚到认证/手动登录不重开账号。原位登录失败保留页面生命期并清空临时密码；返回其他账号身份时清除个人投影、关闭旧索引并停止读取。Bridge 聚合 none_ready 只有在两路线均明确 authentication_required 时才投影 signedOut，网络/解析/上游错误保留原类别，不误触发保存密码的提交。

RED→GREEN：新增缺失接口失败；原位登录参数缺失失败；真实 Bridge DTO 网络错误原先错误返回 signedOut 的断言失败；手动登录返回其他账号原先错误 ready 的断言失败；分别最小修正后通过。当前 App 完整 285 项通过（含新增 10 项启动/操作/身份测试和 2 项 Bridge 认证分类测试），Host 新增 2 项 widget 测试通过，验证无需点击开始恢复、挂起时切三入口、原位登录后仍在普通功能页、密钥不可用空壳不崩溃。

共享 `just flutter-check` 全套通过时计数 754 项，随后新增手动身份保护的 App 完整复验为 285 项，组合覆盖为 755 项；UI 249 项中没有更新任何 golden。`just check`、layout、refs 和 sensitive 通过；实现期间修复了给旧宿主读取无条件新增 await 导致的未订阅迟到异常，以及安全存储不可用时重复显示保存承诺的问题。上述证据是确定性和宿主 widget，不是缓存已展示或真实 App 性能证明。

本阶段仍使用设计允许的聚合恢复；所需路线 facade 尚未接入 Bridge，短暂后台仍待 P2 改为合并恢复。Core 缓存尚未自动保存在线业务结果/恢复首页；下一步 P1-B 连接 Core→Bridge→App 的精确缓存结果，P1 不勾选完成。
