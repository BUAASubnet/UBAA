# 离线首页与后台恢复执行记录

## 基线核对

2026-09-17：源工作区 `ubaa2 @ d7c37f73` 干净。`git merge-base --is-ancestor` 确认 `7273283a` 与 `db4e198d` 均已包含。既有引用管理、UI、图标和查询更改已分别提交于 `f63e6d06`、`8f66ce7e`、`d7c37f73`，实施分支完整继承，不冒充新成果。源目录保留原样。

隔离区 `.worktrees/offline-home-20260917`、分支 `codex/offline-home-20260917`，只读复用源目录冻结引用。源和实施区 `just refs` 均退出 0，SHA 与 references.md 一致。无凭据复制、无运行会话修改、无真实学校写入。

## 当前证据

| 类别 | 当前结论 |
|---|---|
| 合同 | 已归档旧暂停合同，建立新 P0–P5 合同 |
| 实现/确定性 | 尚未开始，不宣称缓存或恢复已可用 |
| 原生/性能 | 尚未测量 |
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
