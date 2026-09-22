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

## P1-B：今日课表持久接线与独立本地读取

Core 新增 `OfflineCache` 与 `refresh_cached_today`，前者不包含网络客户端，后者沿原 UC/课表协议核实身份并保存同一上海日期的 typed 内容。只有确认身份后才读取教务数据；完整成功保存与保存失败分别返回，不改变 CLI 读取出口。Bridge 升为 v10，缓存 SQLite 操作放入阻塞任务池，本地读取与停用不等待共享网络客户端锁；在线读取仍由原客户端拥有会话，已有学校写意图时拒绝隐式认证。

生产 BridgeBackend 和 App 接入本地账号密钥、独立缓存句柄与首页只读投影。认证和本地读取同时开始；磁盘迟到不能覆盖成功在线结果、当前显式查询或退出后的新生命周期。缓存投影移除写动作。失败保留原取得时间，包括磁盘结果在请求中途才返回的情况；原来的“失败后更新时间变成刚刚”已修复。空课表显示“上次保存时没有课程安排”，跨校园午夜不显示昨日条目为今日内容。主动退出立即隐藏个人数据，再关闭持久索引/缓存，最后等待学校注销；存储关闭失败会记录，不伪装清理成功。

RED→GREEN：Core 缺少在线缓存出口时编译失败，身份不符与精确日期用例随后 2 项通过；Domain 缺少不可写投影时编译失败，写动作剥离与时间依据 1 项通过；App 缺少本地接口时失败，随后新增迟到缓存遇鉴权错误出现空集合的断言失败、注销挂起仍显示首页的断言失败，分别修复后通过。UI 空缓存和跨午夜两项断言先失败后通过。没有修改既有 golden。

本阶段 App 完整复验 295 项通过，包含新增缓存/迟到/退出/账号切换 8 项及 Bridge 缓存适配 2 项；Bridge 错误闭包增加身份不符分类且保留严格枚举覆盖。共享 Flutter 全套首次通过时为 domain 55、platform 66、app 293、UI 251、bindings 15、host 32、官方宿主 54；随后新增注销立即隐藏测试并修正旧注销时序断言，再补充原位账号切换的旧内容泄露和注销期间新登录竞态断言，App 完整复验 295 项，组合 768 项。类型检查与格式检查通过；最终 Rust/CLI/生成门禁及原生复验结果续记于下。

macOS 原生合成测试使用随机临时目录、固定合成身份和测试密钥，验证 Bridge v10 打开、重开、跨句柄退出栅栏、重新启用与清理。测试进程 1 项通过；工具仍报告窗口置前失败，不因此宣称视觉验收。该测试没有学校网络/真实账号，也不替代有真实缓存内容的 App 启动性能测量。

范围限制：目前自动持久读写只接今日课表，待办尚未接入；当前需要 UC 前置校验，未验证性能收益。所需路线优先恢复、调度/分段、Judge 选择性和十二领域仍待后续阶段，P1 不标完整完成。Core-live、真实 App 业务只读与多端 30 次指标均未在本阶段获得通过证据。

最终 Rust 门禁：`just check` 退出 0，包含 Core 全/无默认 feature、CLI 二进制 16 项、Bridge 111 项通过/2 项既有忽略、fmt/clippy、构建及文档门禁。`flutter-codegen-check` 重生成后零漂移，CLI/Bridge 当前版本校验均为 v10。SQLite 阻塞池调整后 macOS 原生缓存探测再次 1 项通过；仍仅为合成存储/绑定运行证据。

## P1-C：希冀最小待办缓存接线

逐操作核对当前两份冻结引用后，新增 Core 希冀摘要缓存出口，保持原聚合协议及错误收尾；包含过期项和默认筛选使用不同的持久范围。Bridge 升为 v11，宿主及生成绑定同步；缓存只包含原 typed 摘要，首页保留原时间、实际路线及详情只读导航。未改变学校写流程。

新增 `OfflineHomeRead` 显式表达可用投影与局部缓存错误，逐范围继续读取；今日课表的一条记录损坏时，希冀缓存仍可展示，错误单独保留。界面将已保存待办标为“上次保存…待核实更新”，不会将单纯离线恢复误称刚发生读取失败。

RED→GREEN：Core 出口缺失时失败，完成后验证摘要重开及 includeExpired 范围隔离；Bridge read_judge 缺失时失败，完成后验证字段投影和精确范围；App 原仅恢复课表时找不到希冀投影，接入后通过；缺少局部结果错误合同先失败，完成后验证损坏隔离；UI 原文案断言先失败，改为保存依据后通过。合成网络严格模拟原 SSO→Judge 跳转，没有放宽认证判别。

当前新增 Core 测试 1 项、Bridge 测试 1 项、App 故障隔离测试 1 项、UI 保存提示测试 1 项；原有缓存适配测试扩展检查希冀。macOS Bridge v11 合成原生探测 1 项通过，覆盖新增缓存出口的绑定调用；没有学校 HTTP 请求，不视为真实 App 业务或性能验收。

范围限制保持明确：自动持久读取现在为今日课表与希冀摘要；SPOC、签到、博雅等来源未接完。希冀当前仍复用旧聚合和六个月行为，没有完成选择性详情、历史复查或锁让位。P1/P2/P3/P4/P5 仍未全量完成。

P1-C 最终门禁：`just check` 退出 0，Bridge 112 项通过/2 项既有忽略，CLI 二进制端到端及其余 Rust/Shell/文档门禁通过；`just flutter-check` 七个包/宿主共 770 项通过（55/66/296/252/15/32/54），格式/静态分析通过。`flutter-codegen-check` 重生成零漂移；refs/layout/sensitive 通过。确定性和原生合成存储证据与仍未执行的 Core-live、真实 App、性能和发布证据分开记录。

## P2-A：前后台合并恢复与写活动收尾（2026-09-22）

当前轮从干净的 `34a1eb2c` 继续，冻结引用再次校验通过。返回前台不再固定重建，保留当前页面与 backend；多个进行中的恢复合并。初始化/登录期间的恢复触发等待就绪；后台未发送的认证等待前台，后台结束认证不新发首页同步。

新增可观察的写活动收尾边界：除 WritePhase 外还检查真实活动及待确认意图，避免 idle 通知早于 finally 完成。取消/提交回读完全结束后才唤醒一次恢复；主动退出和销毁取消等待。重建在准备、确认、提交、既定回读及认证未完成期间拒绝执行。旧测试中“后台总重建”“在途提交期间可重建”的预期与已接受设计冲突，已改为保护原流程直到安全终态，仍检查旧协调器不可复用、单次释放及不向新 backend 重发。

RED→GREEN：原恢复忙时返回两个独立空 Future 的断言失败；宿主多次恢复/初始化/登录期间保持实例的断言失败；前台唤醒与显式恢复同时发生造成三次认证而非两次的断言失败；待确认意图仍能重建的断言失败；旧宿主错误自动提交另一账号密码的断言失败。逐项修复，保留对应日志及确定性用例。宿主测试同时修正为手机断点和 Flutter 合法生命周期事件顺序，不把测试设置错误作为实现失败或通过依据。

新增 App 恢复测试 7 项，宿主 6 项生命周期合同覆盖 paused/hidden/detached、页面入口保留、进行中合并、初始化/登录忙时恢复。全部使用合成 backend，不进行真实学校写入。优先队列、退避、真实 handle 失效判别、路线优先、长批次让位和性能测量仍未完成；本阶段不标 P2 完成。

P2-A 最终门禁：`just check` 退出 0；Flutter 七包/宿主全套 775 项通过，随后补充成功/未知结果等待恢复的两项测试，App 完整复验 303 项通过，组合覆盖 777 项。静态分析、格式、refs/layout/sensitive 通过。未知结果用例保留既有 typed `outcomeUnknown=true/success=false` 语义，不把它改写成成功或触发第二次 commit。此阶段没有新增原生、多端或真实网络证据。

## P2-B：所需路线恢复合同与 App 接线（2026-09-22）

当前从干净 `8d6e180e` 继续，冻结引用再次通过。新增 Core `login_required_route`，与已有 `recover_required_session(feature)` 配对；保留旧双路线接口。源对照明确旧 WebVPN 附带 Direct 登录与新分阶段调度的差异，不复制 Cookie 或创建第二持久会话客户端。Bridge 升为 v12，目标功能、已核实身份、目标路线和原错误分类穿过 typed 合同；待确认写意图存在时拒绝恢复/登录，不清除意图。

生产 App 首次首页恢复使用课表所需路线，复用返回的已验证身份；显式查询先恢复该任务的路线。不同目标排队，同目标合并，用户目标可提升已排队项。首页默认刷新不会使当前显式查询修订失效；修复了恢复完成后默认刷新覆盖用户查询的竞态。恢复错误按目标保留 code/kind/retryable/route，不能将 timeout 压缩为 network_error。

RED→GREEN：缺少单路线登录 facade、Bridge 恢复出口和 App 所需路线接口时分别失败；现有查询被默认刷新覆盖时断言失败；具体超时错误丢失断言失败；提升后台已有任务仍按旧顺序运行的断言失败；未支持交互后另一目标重复提交密码及手动材料保存失败仍解除限制的断言均失败。逐项实现后定向和 App 完整复验通过。

Core 新增两项验证：失败的指定路线不触及兄弟路线；有效 SSO 走 GET/UC 验证复用，不 POST 密码且返回明确 pinned 身份。Bridge 新增两项验证：待确认意图不被恢复清除、已销毁错误保持；一次目标 UC 请求直接返回身份，不调用另一条路线。App 增加目标恢复、队列提升、查询保护、错误/凭据边界测试，并验证 Bridge→App 的目标与身份投影。

macOS Bridge v12 合成原生探测 1 项通过，新增无本地会话时的所需路线入口调用与错误路线校验；仍使用临时目录和合成材料，不访问学校，不作为真实 App 业务或性能证据。原生工具仍报告不能将窗口置前，不据此声称视觉验收。

范围仍有限：这是认证范围和安全边界的接线；所有业务读取的优先队列、跨重启失败策略/退避、真实 handle 失效自动重建、Judge 分段让位与选择性历史复查尚未完成。个人完整资料按需补读仍待 P4 接入；UC 返回身份不等价于完整资料刷新。P2 不标全阶段完成。

P2-B 补充审查：当用户目标已等待时，首页整批预载延迟到目标认证之后，避免预载抢先进入共享锁；这是发送顺序证据，不是长请求可抢占证据。状态响应仅含真实 schoolId 时沿冻结旧身份优先级建立最小身份投影，不以缓存或姓名填造；旧完整 userInfo 投影合同不变。对应新断言先失败后通过。

P2-B 最终门禁：`just check` 退出 0，含 Bridge 114 项通过/2 项既有忽略及 CLI 端到端；FRB 重生成零漂移。Flutter 七包/宿主全套 785 项通过后，补充材料保存、请求顺序与最小身份断言，App 完整复验 315 项、Host 32 项和官方宿主 54 项通过，组合覆盖 789 项。格式与静态分析、refs/layout/sensitive 通过；没有将这批确定性/合成绑定证据计为 Core-live、真实 App 全业务或性能验收。


## P2-C：Core/Bridge 希冀分段边界（2026-09-22）

从 `f1e986fd` 继续，逐操作冻结来源对照先于实现，refs 通过。新增扫描在主运行时完整执行选课与一次索引/详情，收尾后返回；不增加 worker、不复制 Cookie、不并发改写持久会话。原四 worker 聚合和 CLI 保持原义，旧六个月逻辑不是本阶段新增成果。新原始扫描逐项读取全部课程/作业，不继承历史课程永久排除或未证实排序的早停。

RED：facade 集成测试因缺少 `JudgeScanKind`、begin/next 扫描接口编译失败；缓存票据校验测试因缺少 validate_read 失败。实现后，课程索引→课表插入→另一扫描改选课程→原扫描详情重新选课通过。新增主认证失效用例先失败，暴露认证清理递增代次后原错误被 Superseded 覆盖；修正为优先保留认证/内部收尾错误后通过。Dart schema 测试先因缺 beginJudgeScan 失败，再生成 v13 绑定。

当前确定性覆盖：Core 扫描 8 项（7 项 facade 集成和 1 项路线来回切换代次）、缓存票据 1 项、Bridge 1 项。覆盖分批返回、主 Cookie 选课上下文、请求前取消/在途取消后丢弃、另一客户端拒绝、同范围新请求、账号关闭、单课程失败继续、主 UC 有效/失效仲裁、路线 A→B→A 拒绝。Bridge 以真实共享锁与合成传输证明扫描未完成时其他恢复调用可完成，并验证写意图冲突与 dispose 错误；没有学校写入。

仍未完成：App 按任务消费批次、持久索引/详情、选择性新鲜度、长扫描票据续租、缓存不可用时扫描降级、历史复查、十二领域、多端和性能验收。此阶段不把返回原内存 TTL 内容称为刚刚完成网络更新，也不把 Core/Bridge 可让位称为 App 已具备完整抢占。未执行本任务真实双路线只读或真实性能测量。


审查补充：扫描归属使用弱引用，不因扫描句柄延长已释放客户端私有状态的生命周期；路线代次测试同时验证释放。取消标记不获取任何异步锁，next 固定先计划锁再客户端锁，避免同计划排队占用客户端锁；未引入与 begin/dispose 的反向锁序。


P2-C 最终门禁：`just check` 退出 0（弱引用审查修改后完整复验），含 Core feature 开/关、Bridge 115 项通过/2 项既有忽略、CLI 二进制端到端 16 项、fmt/clippy/build/doc/Shell；refs、layout（零 baseline 违例）、sensitive（5205 个文件）通过。Flutter 全套 789 项通过（55/66/315/252/15/32/54），FRB 重生成零漂移。首次门禁发现四处当前合同文档和一个测试构造仍为 v12，修正为 v13 后通过，不掩盖该失败。

macOS 原生 v13 合成缓存探测 1 项通过，窗口置前失败但测试进程退出 0；仅证明生成绑定/私有临时缓存运行，不是视觉或学校业务验收。随后仅收紧 Core 计划弱引用并经上述 Rust 全量复验，未以此声明六端原生验证。源工作区仍干净且未改动；所有新增证据均无真实学校写入、凭据和原始响应正文。

## P3-A：Core 希冀持久选择性刷新（2026-09-22）

从干净 `71470139` 继续，refs 再次通过，生产修改前补充冻结来源/缓存语义差异。新刷新复用 P2-C 短批次，保留旧聚合和 CLI；学校 URL/参数/头/重定向未改变。新鲜请求显式绕过内存 TTL，持久复用保留原时间；当前详情、新增或索引变化优先，活跃项其次，稳定历史项最后。历史判定要求严格日期与明确提交完成，长期未截止、未知/未完成和无效日期不隐去；不依赖页面时间顺序。

RED→GREEN：长扫描续租/父子联合发布测试先因缺少出口失败；持久刷新重启复用/完整刷新先因缺少 facade 失败；历史复查测试先因缺少元数据合同失败。当前详情优先用例观测到错误返回 101 而非 102，修正批次排序后通过。认证失败尝试状态用例观测到仍标成功，修正仅推进失败尝试且保留原内容后通过。

确定性场景覆盖：客户端重建后复用三项详情且详情 HTTP 数保持 3，完整刷新后增加到 6；这些只是合成请求计数，不是真实性能指标。历史课程一天内复用索引，到期重查后发现旧项目后的新 ID；历史详情过七天即使索引复用也重新读取；同 ID 标题变化触发更新；部分课程失败保留原完整摘要；认证失效保留原错误与旧内容并记录失败尝试。长扫描跨越 4100 个子条目仍可续租，但较新同范围请求出现后不能抢回；子条目和父资格在单个事务验证。另有原时间/尝试时间分离及严格历史判定单元覆盖。

本阶段只增加 Core 合同和仓库能力，Bridge v13/Dart 生成 API 未改变。Bridge/App 新刷新接线、业务任务队列、缓存不可用降级、十二领域及多端/真实只读/性能验收仍未完成；不标 P2/P3 整体完成。


审查补充：排序最初逐条读取详情，会在大课程下产生多次同步磁盘事务；已改为一次读取紧凑课程摘要，排序阶段不再访问完整详情。每项实际新鲜度仍在自己的批次判定。父扫描和长课程复查票据都续租，避免单个长课程超过请求回收阈值；续租测试同时覆盖两种长期票据。此项没有真实耗时测量，不宣称达到性能阈值。


P3-A 最终门禁：审查调整后 `just check` 退出 0；Core 单元 240 项分别在默认/测试注入配置通过，新增 6 项刷新集成与原 7 项扫描集成共 13 项通过；Bridge 115 项通过/2 项既有忽略，CLI 二进制端到端 16 项通过；编译开/关、fmt/clippy/build/doc/Shell 通过。refs、layout（零 baseline 违例）、sensitive（5210 个文件）及 diff 检查通过。Dart/FRB API 和宿主未改变，本阶段没有重跑 Flutter/原生或真实双路线，不沿用旧原生/性能结果作为新刷新接线验收。源工作区保持干净。

## P2-D / P3-B：Bridge/App 渐进读取与调度（2026-09-22）

从干净 `e53d89b3` 继续，refs 通过，新增接线前已记录来源边界。Core 为混合摘要逐项保留来源时间和缓存标记，避免最后一批时间覆盖仍未更新项目；Bridge 升 v14，begin/next/cancel 明确逐批返回。App 生产摘要/单详情接线、部分结果、混合来源和完整刷新入口已实现，三入口与顶栏布局未改变。

RED→GREEN 包括：Core 汇总时间缺少合同；Bridge 缺少持久渐进出口；控制器仍走旧整批时观察不到逐批调用；重复首页在途请求实际 begin 两次而非一次。实现后首批通知可立即呈现，监听通知中进入签到时其读取先于后台下一批；相同请求合并；写意图期间既定回读完成且认证调用数不增加；后台暂停后续批次、退出取消句柄；部分失败保留合法新旧内容；进行中的混合来源不被迟到磁盘覆盖。全部使用脱敏 backend，不执行真实学校写入。

兼容检查发现未初始化控制器的显式读取会被首页阶段条件阻塞，修正为保留该既有显式调用合同，并继续由 Core 返回真实错误。逐批调度仅针对具有该能力的生产 backend；旧无此能力的测试/离线占位 backend 不伪装可抢占。无缓存、显式批量详情等剩余边界见当前合同，P2–P5 保持未完成。


界面审查补充：旧详情页即使已有逐批数据，loading 仍隐藏列表并禁止导航。新增组件用例先观察到首批不可见，随后开放希冀只读批次显示/导航，并在返回未完成父列表时恢复原查询；其他写领域的 loading 资格行为保持原合同。另补“所有课程失败且无缓存”用例，先发现结果仍携带有效部分内容依据，修正为明确失败而非空结果/部分成功。

P2-D/P3-B 最终门禁：`just check` 退出 0，含 Core 开/关配置、Bridge 116 项通过/2 项既有忽略、CLI 二进制端到端 16 项、fmt/clippy/build/doc/Shell；refs/layout/sensitive 通过（5220 个文件，结构零 baseline 违例），FRB 重生成零漂移。界面修正后 Flutter 七包/宿主全套 801 项通过（55/66/326/253/15/32/54）；最后补全失败结果用例后 App 完整复验 327 项及静态分析通过，组合覆盖 802 项，不将重复执行计入数量。

macOS v14 合成绑定探测 1 项通过，覆盖新 beginJudgeRefresh 的 typed 参数与固定路线认证错误、缓存跨句柄退出；未发学校 HTTP，也没有真实账号操作。窗口置前失败但测试进程退出 0，所以仅记原生绑定运行证据，不记视觉/实景业务或性能验收。源工作区保持干净，媒体/凭据/原始学校响应未进入提交。


## P2-E：逐目标认证与失效计划重建（2026-09-22）

从 `c23d4d05` 继续，源工作区未修改；生产改动前补充冻结来源对照。本阶段只调整 App 已有明确 facade/Bridge 合同的调用时机，不改变上游 URL/参数、Bridge v14、CLI 或缓存 schema。

RED：新增目标认证用例观察到其他首页领域直接读取、未调用自己的恢复，也未向 Core 指定路线登录；首次修复又暴露课表读取排在其他首页认证之后。将认证与读取安排在同一业务队列、合并无分段能力的开始/读取步骤，并赋予认证后同级继续优先后 GREEN。真正紧急任务仍优先，未把 Dart 排序当作在途 HTTP 抢占。

新增覆盖：首页课表先读、逐领域恢复、缺材料不阻止另一就绪领域、仅向 Core 指定路线提交已授权材料、认证失效只重建一次、持续失效原位错误、另一领域登录只取消同路线计划、保留已显示内容、预约辅助读取不被自己的恢复误取消、恢复后继续仍让位紧急任务。均为脱敏 backend/队列证据；未执行学校写入。

首次完整 App 330 项通过，随后补充重建/路线隔离和辅助读取用例均通过。没有真实双路线、真实 App 或性能测量，也没有把当前全局写入口的保守限制宣称为最终认证/写资格隔离完成。


P2-E 最终门禁：`just check` 退出 0，含 Core 开/关配置、Bridge 116 项通过/2 项既有忽略、CLI 二进制端到端 16 项以及 fmt/clippy/build/doc/Shell；Flutter 七包/宿主全套 811 项通过（55/66/336/253/15/32/54）且全部静态分析通过。refs/layout/sensitive 与 diff 检查通过（5222 个文件，结构零 baseline 违例）。本阶段没有修改 Core/FRB/原生 ABI，未重复生成绑定或把旧原生结果记作本轮运行。源工作区 `ubaa2` 仍干净。


## P4-A：精确查询与希冀详情离线恢复（2026-09-22）

从干净 `96ce29bb` 继续，refs 通过；实现前补充来源边界。Core 增加已有 typed 详情的精确本地读取，Bridge v15 新增只读出口；不新增上游协议、学校请求或缓存 schema。App 接入精确查询缓存，先覆盖已有持久内容的今日课表、希冀摘要/详情，同时建立后续领域复用的账号/查询/生命周期归属边界。

RED→GREEN：Bridge 测试先因缺少 read_judge_detail 失败；App 查询测试先因缺少本地查询合同/上下文失败；审查新增“首页通知中立即进详情”测试确实无法显示缓存，发现本地打开任务登记晚于状态通知，调整为先登记、不等待磁盘后通过。初次 Flutter 门禁发现测试误用不存在的枚举 none，改用 typed unsubmitted 后重跑，不计失败为通过。

新增确定性覆盖：缓存详情的路线/课程/作业精确隔离、持有网络锁期间本地读取及时完成、退出栅栏；App 认证前直接展示、失败保留原时间、晚磁盘不覆盖在线、新旧查询隔离、错账号/错查询拒绝；Auto 保留真实来源且选最新、单路线损坏仍返回其他有效记录、固定路线不串用、周课表不被今日替代、include_expired 精确传递。合成测试没有学校写入。

macOS v15 合成绑定运行 1 项通过，新增实际生成 readJudgeDetail 空记录调用；使用临时账号和目录，未访问学校。窗口置前失败，故只记原生绑定运行，不记视觉、真实 App 业务或性能验收。十二领域其他持久范围与最终验收继续。


P4-A 最终门禁：`just check` 退出 0（Core feature 开/关、Bridge 117 项通过/2 项既有忽略、CLI 二进制端到端 16 项、fmt/clippy/build/doc/Shell）；refs/layout/sensitive 通过（5225 个文件，结构零 baseline 违例），FRB 重生成零漂移。Flutter 全套 819 项通过（55/66/344/253/15/32/54），启动竞态修正后 App 完整复验 345 项和静态分析通过，组合覆盖 820 项。源工作区未改动；没有真实学校写入、Core-live 或真实性能指标。


## P4-B：Core 学业和空教室持久化（2026-09-22）

从干净 `329b4c70` 继续，refs 通过。新增逐操作九列来源对照后，覆盖学期、周次、周课表、考试、成绩与空教室六个 typed 范围；既有 HTTP 实现、CLI、Bridge v15 和学校写权限未改变。保存操作有账号身份检查，按实际路线和原请求参数隔离。

RED→GREEN：新的跨重开集成测试先因缺少 AcademicQuery/refresh_cached_academic 失败；实现后六类结果可保存，重开读取没有新增 HTTP。另覆盖原周课表表单三字段、成绩 xq/year、空教室 xqid/floorid/date，非法范围认证前拒绝、错账号不访问业务、失败保留原内容与时间、完整空周替换、容量不足返回在线内容且带保存错误、退出后的迟到响应失败。测试一次因尚未创建合成临时目录而失败，修正测试初始化后通过。

审查发现共用发布先检查载荷会掩盖退出错误，新增测试实际得到 InvalidInput 而非 Inactive；现已在同一 SQLite 事务先检查票据再校验载荷，缓存聚焦 20 项通过。成绩/学期/周次/日期/校区隔离及非有限 credit 拒绝保存另有持久仓库断言。完整门禁第一轮与追加 RED 测试并行，命中其尚未格式化版本；格式化后按最终代码重跑，不沿用该失败轮为通过证据。

本阶段没有完成 Bridge/App 新学业范围接线，既有今日和希冀产品缓存保持之前范围；无实时学校请求、原生新场景或性能测量。其余十二领域与最终验收继续。


补充审查：旧空教室 ViewModel 直接展示解析成功的响应，没有新增非零 e 的学校错误分类。本轮仅限制这类未证明完整可用的载荷不进入完整缓存，保留原在线合同，后续 Bridge/App 必须分开呈现内容与保存/完整度；不从惯例推导新的上游错误语义。clippy 指出新增测试过长及默认构造表达不明确，已拆分独立断言/辅助函数并使用显式类型，未增加 lint 豁免。


P4-B 最终门禁：最终 `just check` 退出 0，Core 单元 243 项分别在默认/测试注入配置通过，新增四项学业 facade 集成通过；Bridge 117 项通过/2 项既有忽略，CLI 二进制端到端 16 项、fmt/clippy/build/doc/Shell 通过。refs/layout/sensitive 与 diff 检查通过（5226 个文件、结构零 baseline 违例）。本阶段未改 Dart/FRB API，没有重复 Flutter/原生运行，不把历史产品端或实景结果作为新缓存接线证据。源工作区保持干净。


## P4-C：Bridge/App 学业与空教室缓存接线（2026-09-22）

从干净 `ce7d816f` 继续，refs 通过。新增 typed Bridge v16 出口，在线与本地共用学业展示映射，App 接入六类范围及公开学期/教学周选项；阶段实现不改变学校 URL/参数、CLI 或缓存 schema。读取记录与学校写资格分离，待确认写意图阻止新缓存刷新中的认证。

RED→GREEN：Bridge 缺少本地成绩出口；App 离线成绩无投影、在线仍调用旧 grades；选项入口认证前无法完成；磁盘成绩被写入出分基线；loading 的考试缓存页面只转圈。每个问题均由失败测试观察后修复。覆盖同路线唯一当前学期、周次/周课表原字段、考试子集、教室校区/日期与3/13节次精确过滤、保存失败不冒充在线失败、完整成绩概览不因筛选丢项、原时间、无写动作，以及本地读取不等待网络锁和退出栅栏。

完整回归发现测试 fake 未实现新增周课表读取（应返回缺记录）、旧 stale 重试按钮被条件误隐藏，修正后相应用例通过；clippy 的 wildcard import/相似命名已修正，未增加豁免。

macOS v16 原生合成绑定 1 项通过，新增六个本地读取和一个缺会话在线入口的真实生成绑定调用；临时账号/目录，无学校 HTTP、无学校写入。窗口置前失败，不能计作视觉或真实 App 学业验收。当前未执行本任务真实双路线或性能测量；跨学期离线统计与其余领域/最终验收继续。


最终完整度审查新增“不完整但为空”用例，实际发现旧“暂无数据”文案错误；修正为明确不完整提示，并为非空部分内容保留不完整说明。P4-C 最终 `just check` 退出 0：Core 默认/测试注入配置各 243 项、Bridge 118 项通过/2 项既有忽略、CLI 二进制端到端 16 项，fmt/clippy/build/doc/Shell 通过。Flutter 全套 828 项通过（55/66/351/255/15/32/54），最后补完整度提示后 UI 完整复验 256 项、静态分析通过，组合覆盖 829 项；显示非空部分说明后再跑相关学业布局聚焦用例。refs/layout/sensitive（5232 个文件，结构零 baseline 违例）和 FRB 零漂移通过。源工作区保持干净；所有事实均未扩大为双路线实景或性能通过。


## P4-D：Core 首页待办缓存与部分保护（2026-09-22）

从干净 `7f7c0517` 继续，refs 通过，核对当前两个固定引用；签到依据更新后的 2026-09-17 旧版修正，未恢复主矩阵中已废弃的登录入口。实现前记录逐操作来源边界。新增签到、SPOC 列表/详情和阳光概览持久范围，在线结果与不可写持久 DTO 分开，Bridge v16/Dart 尚未接线。

RED→GREEN：持久投影测试先因缺少专用只读类型失败；facade 测试先因缺少 HomeQuery/刷新合同失败；阳光成功信封但无计数字段、SPOC 空页仍声明下一页各自实际错误标为完整，新增断言失败后修正。原公开 CLI/只读 DTO 仍维持可选容错和停止行为，新标记仅约束缓存完整性。

当前确定性证据覆盖：签到实际请求日期等于缓存键且在线目标仍存在、持久序列化无 signin/submit 资格和写目标；课程补充、提交补充、统计、学期及分页未覆盖时旧完整内容/原时间保持；首次部分结果标 Partial；Stored 与 Preserved 区分；另一条路线不能读到该记录；必需全局页失败明确返回错误。全部使用脱敏 backend，无真实签到、打卡或照片上传。

剩余范围包括这批 Core 的 Bridge/App 首页接线、阳光记录分页、其余领域、SPOC 等长聚合的必要安全边界及最终 15 场景/多端/真实只读/性能验收；不将本阶段标为 P4 或完整 Goal 已完成。


P4-D 最终门禁：`just check` 退出 0，Core 默认/测试注入配置各 244 项通过，新首页 facade 两项场景组覆盖上述完整/部分/必需失败边界；Bridge 118 项通过/2 项既有忽略、CLI 二进制端到端 16 项、fmt/clippy/build/doc/Shell 通过。refs/layout/sensitive（5235 个文件，结构零 baseline 违例）与 diff 检查通过。Dart/FRB API 未改变，本阶段不重复原生/Flutter，也不继承旧验收为新首页接线证明。源工作区保持干净。


## P4-E：首页待办 Bridge/App 接线（2026-09-22）

实施基线为 `6351f9e7`，仅在 `codex/offline-home-20260917` 隔离区修改；源工作区仍为 `ubaa2@d7c37f73`，干净、ahead 7。沿 P4-D 已核对的四个 Core 操作，新增 Bridge v17 typed 本地与在线入口，SPOC、签到、阳光恢复到本地首页；SPOC 单详情进入精确查询缓存。签到缓存没有资格或 target，跨日不生成当天待办，同日只读导航。在线部分结果与旧完整内容分别管理，阳光本次记录页不会被旧统计覆盖。

RED：`/tmp/ubaa-p4e-bridge-red.log` 记录尚无本地首页 Bridge 入口；`/tmp/ubaa-p4e-app-red.log` 记录缺少明确签到既定回读能力；`/tmp/ubaa-p4e-domain-red.log` 中跨日签到仍生成待办及部分统计仍生成未达标提醒两项失败；`/tmp/ubaa-p4e-state-red.log` 中 complete=false/error=null 被标为 success；`/tmp/ubaa-p4e-ui-red.log` 中未出现“统计尚未确认”。编译过程中两次工作目录错误、一次诊断布尔表达式编辑错误已修正，不作为行为 RED。

GREEN：Bridge 本地读不等待网络锁、路线隔离、退出屏障及 pending 写意图拒绝；App 首页三来源、无缓存写动作、签到既定回读独立派发、部分 SPOC 保留旧集合、阳光旧完整统计/旧 Partial 区分、本次记录页保留；Domain 跨日/只读导航/未知统计；UI 部分统计与真实记录错误区分，全部通过。首轮完整 Flutter 的宿主导航测试点击落在 800×600 屏幕外，修正测试为先居中并断言 hitTestable；保留首轮失败日志，不削弱业务断言。

最终确定性门禁：`just check` 退出 0，Core 两配置各 244 项，Bridge 119 项通过/2 项既有忽略，CLI 二进制端到端 16 项，fmt/clippy/build/doc/Shell 均通过。完整 `just flutter-check` 退出 0，各套件 57/66/357/257/15/32/54，共 838 项通过，format/analyze 无问题；FRB v17 `just flutter-codegen-check` 零漂移。refs 校验两个原固定 SHA；layout 零 baseline 违例；sensitive 扫描 5240 文件通过。日志为 `/tmp/ubaa-p4e-check.log`、`/tmp/ubaa-p4e-flutter-final.log`、`/tmp/ubaa-p4e-codegen-check.log`、`/tmp/ubaa-p4e-sensitive.log`，仅脱敏测试内容。

原生合成证据：macOS `integration_test/offline/cache_bridge_test.dart` 1 项通过，v17 四个本地入口空库返回、缺会话在线入口、句柄重开/退出跨句柄栅栏均经真实 FRB 运行。启动器 `Failed to foreground app; open returned 1`，所以不记为独立实窗视觉验收；未生成验收媒体、未使用真实会话。日志 `/tmp/ubaa-p4e-native.log`。真实学校写入为零；本阶段没有 Direct/WebVPN Core-live 或真实 App 新验收，未测真实性能，不据此声称缓存首屏或全部更新达到目标。

余项仍包括十二领域其他持久范围、阳光记录分页、SPOC/无缓存希冀等大读取安全分段、剩余生命周期/异常场景及多端和双路线真实只读/性能测量。P0–P5 整体不勾选完成；活动合同继续。

P4-E 收尾审查：首页来源说明对无错误码部分结果曾误称“刷新失败”，新增 `/tmp/ubaa-p4e-home-caption-red.log` 后修复；UI 全套追加验证 258 项通过、analyze 无问题。阳光同分类但已观察学期改变曾拼入旧统计，`/tmp/ubaa-p4e-term-red.log` 复现后按 termId 共同约束，App 全套追加验证 358 项通过、analyze 无问题。收尾日志为 `/tmp/ubaa-p4e-ui-final-{analyze,test}.log` 与 `/tmp/ubaa-p4e-app-final-{analyze,test}.log`；与其余未变套件合计 840 项，之前单次完整门禁为 838 项，二者不混记。最终 layout/sensitive 再验通过，仍为 5240 文件；源码差异和暂存内容复核未含凭据、会话、冻结材料或验收媒体。


## P4-F：博雅 Core 五项只读持久化（2026-09-22）

实施基线 `ee40fc63`，冻结引用纯校验通过，原工作区未修改。先核对两个冻结来源的五个只读操作、CAS/业务令牌、加密和错误处理，记录于来源对照 P4-F。新增 `cache/bykc.rs` 的不可写课程/已选投影及 facade `BykcCacheQuery/BykcReadData/refresh_cached_bykc/read_bykc`。原在线 DTO 不丢字段，持久投影排除 eligibility、signInfo 位置结果、签到点坐标和附件路径。已选快照记录原 getAllConfig 真正选择的起止日期；分页只保存该请求页，不称作全课程覆盖。

RED：`/tmp/ubaa-p4f-red.log` 为新持久类型/分页键不存在；`/tmp/ubaa-p4f-facade-red.log` 为新 facade/本地读取入口不存在。GREEN：`/tmp/ubaa-p4f-cache-green.log`、`/tmp/ubaa-p4f-facade-{green,final}.log`，覆盖 page/size/all/路线隔离、非法参数不发请求、在线与不可写持久投影分离、五项业务失败保留旧值、实际学期范围、空成功替换、详情 ID 不符只影响保存及退出后拒绝读取。测试 transport 只允许五个原只读端点和 getAllConfig，不解密/记录随机加密正文，不调用真实学校写入。

首轮 `just check` 因重复 match 分支与超长测试函数失败；按职责合并分支、拆出测试准备/替换断言和独立位置剥离测试，未降低 lint 标准。最终 `just check` 退出 0：Core 默认与 test-contract 各 246 项、facade 50 项、Bridge 119 项通过/2 项既有忽略、CLI 二进制端到端 16 项，fmt/clippy/Shell/build/doc 通过。refs 两个固定 SHA、layout 零 baseline 违例、sensitive 5243 文件和 diff 检查通过。收尾日志为 `/tmp/ubaa-p4f-check-final.log`、`/tmp/ubaa-p4f-layout.log`、`/tmp/ubaa-p4f-sensitive-final.log`。本阶段不改 Bridge/Dart 合同，未运行 App、原生或真实双路线验收，也未测性能，不能把 Core 缓存完成当作博雅离线首页已接线。


## P4-G：博雅 Bridge/App 五查询与首页已选接线（2026-09-22）

实施基线 `79c4c49b`。Bridge v18 新增五项 typed 本地读取及在线缓存入口，不把资格、坐标或任意正文放入缓存 DTO。App 共用原展示映射，恢复课程页 pagination 与已选学期范围；首页已选按补充查询身份恢复，不能覆盖普通博雅列表。BykcReadbackBackend 将既定回读送往原在线方法，待确认写意图时不进入缓存认证。

RED：`/tmp/ubaa-p4g-bridge-red.log` 为缺少本地博雅入口；`/tmp/ubaa-p4g-app-red.log` 为缺少明确既定回读能力；`/tmp/ubaa-p4g-home-red.log` 为首页排除了博雅补充缓存。UI 测试最初在新概要类型未穷尽匹配时编译失败（`/tmp/ubaa-p4g-ui-red.log`），该记录仅为编译 RED；修复后首页保留缓存/来源说明及失败保护有组件断言。另修正测试目录误用、合成缓存临时目录未建立、重复导入、测试错误映射器不可见、版本文档同步、wildcard import 与测试长度问题，没有放宽门禁。

GREEN：Bridge 本地读取在 Core 网络锁被持有时仍可返回；页/路线隔离、pending 写意图保护、退出屏障通过。App 五类缓存均只读，课程分页/详情导航和已选真实范围保留；待确认写意图下控制器只派发专用博雅回读、不增加恢复调用。首页本地已选不会污染普通列表，补充来源失败仍可显示缓存；补充结果携带原 evidence，不把旧数据称为新成功。

最终确定性证据：`just check` 退出 0，Core 两配置各 246 项、facade 50 项、Bridge 120 项通过/2 项既有忽略、CLI 二进制端到端 16 项，fmt/clippy/Shell/build/doc 通过。`just flutter-check` 单次全套 57/66/359/259/15/32/54，共 842 项通过；收尾追加回读与失败测试后 App 全套 361 项、UI 全套 260 项及各自 analyze 通过，与其余未变套件合计 845 项。FRB v18 零漂移，refs 原固定 SHA、layout 零 baseline 违例、sensitive 5248 文件、diff 检查通过。

日志：`/tmp/ubaa-p4g-check-final.log`、`/tmp/ubaa-p4g-flutter-final.log`、`/tmp/ubaa-p4g-app-{analyze,final}.log`、`/tmp/ubaa-p4g-ui-{analyze,final}.log`、`/tmp/ubaa-p4g-focused.log`、`/tmp/ubaa-p4g-codegen-check.log`、`/tmp/ubaa-p4g-layout.log`、`/tmp/ubaa-p4g-sensitive-final.log`，仅脱敏内容。

macOS 原生合成：v18 缓存集成 1 项通过，新增五个博雅空库读取及缺会话在线入口经真实 FRB；仍有 `Failed to foreground app; open returned 1`，不算独立实窗验收。日志 `/tmp/ubaa-p4g-native.log`；未生成媒体、未使用真实会话、真实学校写入为零。没有本阶段双路线 Core-live、真实 App 或性能测量。研讨室/图书馆/评教等剩余缓存、阳光分页、写后跨范围失效、大读取余项、生命周期全矩阵及多端/真实性能继续，P0–P5 不整体勾选完成。


## P4-G 审查修正：缓存 Bridge 字段白名单（2026-09-22）

基线 `cdfa41bd`。研讨室接入前核对既有来源与公开字段边界，发现新的 BridgeCachedBykcChosenCourse 误带出作业正文/附件名称，虽然页面不消费，仍违反 2026-09-02 明确禁曝决定。新增 schema_snapshot_test 对缓存 DTO 的断言，`/tmp/ubaa-p4g-boundary-red.log` 确认 homework 出现在生成类型；随后删除两个 Rust 字段及映射，重生 FRB 并将 Rust/Dart 合同同时提升至 v19。原 Core 加密存储、学校协议、页面功能和写路径不变。

完整 Flutter `just flutter-check` 退出 0，57/66/361/260/16/32/54，共 846 项通过，format/analyze 无问题。FRB v19 零漂移，refs 固定 SHA、layout 零 baseline 违例、sensitive 5248 文件通过。macOS 原生合成缓存测试 1 项通过，版本19与全部本地入口/缺会话入口/句柄栅栏经真实绑定运行；依然无法置前（open returned 1），不算独立实窗验收。没有本轮真实学校调用、验收媒体或性能数据。

日志为 `/tmp/ubaa-p4g-boundary-{red,codegen,drift,flutter,native,layout,sensitive}.log`。`/tmp/ubaa-p4g-boundary-check.log` 中 `just check` 退出 0：Core 两配置各 246 项、facade 50 项、Bridge 120 项通过/2 项既有忽略、CLI 二进制端到端 16 项，fmt/clippy/Shell/build/doc 通过。源工作区仍干净，阶段暂存内容复核未含凭据、会话、冻结材料或验收媒体。此次修正独立提交；研讨室已开始源码核对，但尚无该领域新增缓存实现，不将此修正冒充研讨室交付。完整 Goal 继续活动。


## P4-H：研讨室 Core 五范围缓存与兼容回退保护（2026-09-22）

基线 `e9ea9db6`。先核对旧版 Cgyy API/本地实现/DTO/签名/测试；另一冻结源 Srs 为 byxk/xsxk 选课，不借用。新增 cache/cgyy.rs 明确只读字段、CgyyCacheQuery/CgyyReadData/CgyyRefresh 及 refresh_cached_cgyy/read_cgyy。范围为站点、用途、站点/日期空间、零基订单页、订单详情；门锁继续按需在线，不落盘。原学校 feature、签名、会话和写路径未修改。

RED：`/tmp/ubaa-p4h-cache-red.log` 为持久范围/不可写 DTO 尚不存在；`/tmp/ubaa-p4h-facade-red.log` 为新 facade 缺失；`/tmp/ubaa-p4h-scope-red.log` 证明日期响应回退到其它日期时仍被标为 complete。GREEN：`/tmp/ubaa-p4h-cache-green.log`、`/tmp/ubaa-p4h-facade-final.log`，覆盖写资格与内部材料剥离、日期严格校验、跨日/路线/分页隔离、失败保留、合法空订单页替换、默认空详情不得覆盖、错日期不归档且未完成、动态用途失败保护旧值、首次 StaticFallback 保存为 Partial。

期间修正合成用途名称未包含旧 parser 要求的“类”、模块注释放置、枚举大小和函数长度；没有修改上游解析规则或降低 lint。CgyyDay/Detail 响应必须对应请求才可标完成，静态用途回退不等于成功动态更新。最终 `just check` 退出 0：Core 两配置各 249 项、facade 52 项、Bridge 120 项通过/2 项既有忽略、CLI 二进制端到端 16 项，fmt/clippy/Shell/build/doc 通过。refs 两个原固定 SHA、layout 零 baseline 违例、sensitive 5252 文件和暂存 diff 检查通过；日志为 `/tmp/ubaa-p4h-check.log`、`/tmp/ubaa-p4h-layout.log`、`/tmp/ubaa-p4h-sensitive-final.log`。

本阶段仅 Core，Bridge/Dart 合同仍为 v19，未把旧 Flutter/原生结果当作新的研讨室接线证明。未访问真实学校服务、未执行真实写入、未生成媒体或测量性能。Bridge/App、其他领域/阳光分页/跨范围失效/剩余长读取与完整生命周期、多端真实只读和性能验收继续。原工作区保持干净。


## P4-I：研讨室 Bridge/App 五范围、用途与首页订单（2026-09-22）

基线 `89d71d60`。Bridge v20 增加 sites/purposes/day/orders/detail 五项本地与在线缓存入口，缓存 DTO 只含既有公开字段且无学校操作资格。App 共用原投影，保持明确日期和订单零基请求/一基显示；首页缓存以 cgyyOrders 补充身份恢复，不污染普通站点列表。用途辅助读取复用本地优先机制并保留 evidence，预约后的明确 readback 能力绕过新增认证，取消原固定路线双回读未修改。

RED：`/tmp/ubaa-p4i-bridge-red.log` 为本地订单入口不存在；`/tmp/ubaa-p4i-app-red.log` 为预约既定回读能力不存在；`/tmp/ubaa-p4i-home-red.log` 为用途等待认证和首页拒绝研讨室缓存；`/tmp/ubaa-p4i-ui-red.log` 复现无 error 的 stale 缓存触发空值断言；`/tmp/ubaa-p4i-first-partial-red.log` 复现首次 Stored Partial 被误标为旧内容；`/tmp/ubaa-p4i-purpose-retry-red.log` 在正确进入用途选择弹窗后复现失败清空已选选项。代码生成过程重复 visibility、mapper 命名、临时格式化差异，以及测试 import、fixture 必填字段和导航准备错误均已修正，不计作业务 RED。

GREEN：本地读取不等待网络锁、路线/分页隔离、pending 写意图和退出屏障；五类缓存公开字段禁曝；原页信息、站点导航日期、只读详情与首页订单；部分用途/错日期保留同范围旧内容，首次 Partial 来源不失真；无缓存写动作；预约回读不增加恢复调用，取消原两读保持；首帧前用途可本地返回；时段 stale/error/loading 分开处理；用途保存提示、完整度及失败后的选项/草稿保留均通过。

确定性门禁：`just check` 退出 0，Core 两配置各 249 项、facade 52 项、Bridge 121 项通过/2 项既有忽略、CLI 二进制端到端 16 项，fmt/clippy/Shell/build/doc 通过。单次 `just flutter-check` 57/66/364/261/17/32/54，共 851 项通过；收尾新增测试及修复后 App 全套 367 项、UI 全套 263 项及各自 analyze 通过，与其余未变套件合计 856 项。FRB v20 最终零漂移，第一次漂移仅为 private mapper 改名的生成注释，已重新生成并核对；等待生成完成后 diff 检查通过，未把生成过程的临时空白当作稳定结果。最终 refs 校验两个固定 SHA，layout 零 baseline 违例，sensitive 检查暂存后的 5258 文件通过（选项 helper 重命名已归并），暂存 diff 无空白错误或敏感材料。

日志为 `/tmp/ubaa-p4i-check-final.log`、`/tmp/ubaa-p4i-flutter-final.log`、`/tmp/ubaa-p4i-app-{analyze,final}.log`、`/tmp/ubaa-p4i-ui-{analyze,final}.log`、`/tmp/ubaa-p4i-codegen-final.log`、`/tmp/ubaa-p4i-layout.log`、`/tmp/ubaa-p4i-sensitive-final.log`。macOS v20 原生合成缓存集成 1 项通过（`/tmp/ubaa-p4i-native.log`），五个新增本地入口及缺会话在线入口经真实 FRB；仍无法置前（open returned 1），不算独立实窗验收。未访问真实学校服务、未做真实写入、未生成验收媒体或性能数据。

其余图书馆/评教/资料与阳光分页、跨范围失效、长读取余项、完整生命周期/多端/双路线真实只读与性能仍需继续；不关闭整个 P4/P5。源工作区保持干净。


## P4-J 图书馆 Core 五范围（2026-09-22）

基线 e40cbfd5。逐操作对照冻结 old LibBook 接口/本地请求/DTO/BackendTest，以及 buaa-api 无对应协议事实后，新增五范围持久化和独立只读类型。原学校请求参数/登录/单次恢复、CLI 和写链保持，无真实学校请求或写入。

RED：/tmp/ubaa-p4j-red.log 为缺少持久类型和查询；/tmp/ubaa-p4j-facade-red.log 为缺少 facade；/tmp/ubaa-p4j-partial-red.log 复现缺集合仍被标完整；/tmp/ubaa-p4j-observed-red.log 复现日期观察与 parser 别名优先级不一致。GREEN：只读资格剥离、精确键、五请求参数、路线隔离、失败和部分保护、错页拒绝、合法空页替换、认证前参数拒绝、原解析/加密 golden 保持。日志 /tmp/ubaa-p4j-green.log、facade-green.log、partial-green.log、observed-green.log（均同前缀）。类型解构编译修正不计业务 RED。

初次 just check 在审查追加测试后遭遇格式化检查失败，未记通过；随后 clippy 指出同返回值分支和过长测试，已合并分支/拆出 helper 并修正多余借用，重新运行完整门禁。Core-only 阶段，Bridge 仍 v20，尚未接 App；无新增原生渲染、Core-live、真实 App 或性能证据。

最终确定性门禁：just check 退出0（/tmp/ubaa-p4j-check-final.log），Core 两配置各253、facade53、Bridge121通过/2既有忽略、CLI二进制端到端16，fmt/clippy/Shell/build/doc 通过。refs固定引用校验、layout零baseline违例、暂存后 sensitive5263文件通过，diff无空白错误。本阶段无 Dart/Bridge 合同修改，未重复 Flutter 或原生渲染。原始源工作区保持干净；全部 P0–P5仍未完成，下一阶段为图书馆 Bridge/App 接线。


## P4-K 图书馆 Bridge/App 五查询（2026-09-22）

基线 b138b3ee。Bridge v21 本地/刷新五入口、只读 DTO、App 共用投影与分页/日期恢复已接通；LibbookReadbackBackend 保持原预约/取消既定读取，不走新增恢复。UI 保留缓存 loading 网格，显示保存时间与未完整提示，不生成预约操作。

RED：/tmp/ubaa-p4k-bridge-red.log（本地/刷新入口缺失）；schema-red.log（生成缓存类型缺失）；app-red.log（明确回读能力缺失）；ui-red.log（loading 后座位消失）；input-red.log（缺segment却调用一次网络）；scope-red.log（无旧记录时错误页仍有分页投影）。前缀均 /tmp/ubaa-p4k-。测试准备中的错误路径、缺activate、readContext误用参数和假查询回调未发布结果所致timeout已修正，不计行为RED。Bridge mapper可见性修正后完成生成；初轮整体验证发现五处版本文档及一个合同测试仍v20，修正为v21后重跑。

GREEN：本地读取独立网络锁、页/路线/退出隔离及pending写阻止恢复；公开DTO禁曝；五种精确范围恢复、原分页和保存时间、部分失败旧记录保护；离线无动作、预约/取消回读不增加缓存恢复；缺时段网络前拒绝、错页无旧记录不显示异范围；loading网格及静态地图原回归通过。

确定性门禁：最终 just check 退出0，Core两配置各253、facade53、Bridge122通过/2既有忽略、CLI二进制端到端16，fmt/clippy/Shell/build/doc通过（/tmp/ubaa-p4k-check-final.log）。单次完整Flutter 57/66/372/264/18/32/54，共863项；错页收尾后App全套373和analyze通过，其余未变套件合计864项，不称为单次864。日志 /tmp/ubaa-p4k-flutter-final.log、app-final.log、app-final-analyze.log。FRB v21最终零漂移（codegen-final.log），敏感扫描暂存5270文件通过；原始源工作区无改动。

macOS合成集成1项通过：五新增本地读取、缺会话在线缓存入口经真实FRB调用，断言合同v21。应用仍报 Failed to foreground app; open returned 1，只记绑定执行，不作为独立实窗/真实业务证据。没有新增真实学校请求、真实写入、验收媒体或性能测量。资料/评教和阳光分页、跨范围失效、剩余长读/生命周期/多端及双路线真实只读仍待后续；还需统一审查其他领域的“错范围且无旧缓存”投影边界，不能仅凭保存拒绝推定页面安全。

最终refs固定SHA校验与layout零baseline违例通过，暂存敏感扫描5270文件通过。macOS最后复验日志 /tmp/ubaa-p4k-native-final.log 同样1项通过/仍无法置前；非视觉验收。最终暂存diff无空白错误。


## P4-L 跨范围响应防护审查（2026-09-22）

基线e70b56e9。重新查阅冻结LocalCgyyApi.getMyOrders和LocalBykcApi.getCourses及另一源boya/opt：研讨室分页缺省沿请求；博雅公共currentPage/pageSize取请求，另一源只返回课程集合，不能借用页号换算。App对错日期/详情/页码增加展示保护，博雅缓存详情无法取得同范围旧值时拒绝。学校请求、签名/会话、CLI和原写回读不改。

RED：/tmp/ubaa-p4l-core-red.log 复现明确错页仍完整；app-red.log 复现博雅错详情仍展示另一课程；cgyy-red.log 复现无旧缓存时显示别日；page-red.log 复现请求第2页却显示响应number=1。Cgyy测试初次漏填cancelEligibility导致编译失败，仅算准备错误，补全后才记录行为RED。GREEN：Core研讨室缓存3项、App两领域及原展示/写合同回归54项通过。缺集合保旧、data=null非首页及非默认大小按请求归档；错范围不产生新页面动作；本地缓存查询/退出屏障保留。

本阶段Bridge合同仍v21且没有生成结构变化；不新增原生渲染、Core-live、真实App或性能证据。其余资料/评教/阳光分页、跨范围写后失效、长读取与最终15场景/多端/双路线只读验收保持待办。

最终just check退出0：Core两配置各253、facade54、Bridge122通过/2既有忽略、CLI二进制端到端16，fmt/clippy/Shell/build/doc与layout零baseline违例通过（/tmp/ubaa-p4l-check.log）。完整Flutter 57/66/375/264/18/32/54，共866项通过（flutter.log）；博雅页码收尾后App全套375及analyze再次通过（app-final.log、app-analyze.log），针对两个领域/既有展示合同54项通过（page-green.log）。refs固定SHA、敏感扫描5270文件通过，暂存diff无空白错误；源工作区仍干净。日志上述短名均位于/tmp/ubaa-p4l-前缀。整个P0–P5未关闭，下一项继续评教与资料/阳光分页接入。


## P4-M 评教 Core 当前任务范围（2026-09-22）

基线04f6268c。按两冻结实现核对评教激活/任务/问卷/课程链、查询参数、DTO和错误边界后，新增只读持久类型与当前任务范围facade。现有Bridge公开四展示字段作为上限，进度与完整性分别携带，不持久化提交资格和目标。任务固定1/10且达到页上限时不宣称全覆盖。

RED：/tmp/ubaa-p4m-red.log为新facade缺失；partial-red.log在接入旧读取后复现课程请求失败被标完整（模式1）。GREEN：green-final.log验证合成正常保存/路线隔离/字段禁曝，课程503、任务身份缺失、10项任务、激活503、ypjcs缺失、两问卷部分成功全部保留旧完整载荷；合法空任务替换，认证401不降级，退出本地读取拒绝。clippy-final.log通过。中途match缺逗号的编译错误修正不计行为RED。以上短名均为/tmp/ubaa-p4m-前缀。

此阶段不访问真实学校服务、没有真实写入或媒体，没有Flutter/原生/真实性能新增证据。Bridge/App评教接线、长聚合分段、剩余领域/生命周期及双路线真实只读验收继续待办。

最终just check退出0（/tmp/ubaa-p4m-check.log）：Core两配置各253、facade55、Bridge122通过/2既有忽略、CLI二进制端到端16；fmt/clippy/Shell/build/doc和layout零baseline违例通过。refs固定SHA校验、暂存敏感扫描5273文件通过，diff无空白错误。Core-only无Dart/Bridge结构变化，本阶段未重复Flutter或原生测试，不能继承旧原生证据为本轮通过。原始源工作区干净；隔离阶段继续下一项评教Bridge/App。


## P4-N 评教 Bridge/App 只读恢复（2026-09-22）

基线45068685。Bridge v22增加本地与缓存刷新入口，缓存白名单课程/进度不带提交材料；App恢复摘要和待评视图、原进度与取得时间，部分失败旧数据保留，完整在线资格维持原映射。EvaluationSubmissionReadbackBackend原固定路线回读未改。

RED：/tmp/ubaa-p4n-bridge-red.log（本地方法不存在）；schema-red.log（只读类型文件尚未生成）；app-red.log（查询不恢复缓存且未调用新刷新入口）；ui-red.log（Partial仍显示待评0）。GREEN：本地读取独立网络锁、路线/退出隔离、pending写保护；schema禁曝；缓存筛选/进度/动作剥离、部分旧时间保留、首次Partial来源、完整在线资格和固定路线回读；Partial进度和loading可读、原课程内容回归12项通过。日志短名均使用/tmp/ubaa-p4n-前缀。

当前不宣称真实学校协议、真实App业务或性能通过；原生合成与确定性门禁单独记录。整个P0–P5仍未完成。

最终门禁：just check退出0（/tmp/ubaa-p4n-check.log），Core两配置各253、facade55、Bridge123通过/2既有忽略、CLI二进制端到端16，fmt/clippy/Shell/build/doc与layout零baseline违例通过。完整Flutter 57/66/378/265/19/32/54，共871项及静态分析通过（flutter.log）；FRB v22零漂移（codegen-final.log）；refs固定SHA校验、暂存敏感扫描5278文件通过，diff无空白错误。上述短日志名均/tmp/ubaa-p4n-前缀。

macOS合成集成1项通过（native.log），实际v22绑定执行了新增评教空本地读取与缺会话缓存刷新错误路径，以及原多句柄退出屏障。仍有Failed to foreground app; open returned 1，不能记作实窗、真实业务或非空评教DTO原生展示。未做真实学校写入、未生成验收媒体或性能数据。源工作区干净，整个目标继续，下一项为阳光记录分页和资料/缓存管理等余项。


## P4-O 阳光记录 Core 分类分页（2026-09-22）

基线136e0c2a。按冻结Ygdk接口/本地实现/DTO/第2页5条测试，以及另一源无此协议事实核对后，增加按分类/页/大小的持久键、只读分类索引和facade。记录只保留公开字段与图片数量，账号、实际路线与本地修订分开管理。

RED：/tmp/ubaa-p4o-red.log为新facade不存在；partial-red.log复现缺集合被标完整并清空旧页；parent-red.log复现索引被新任务替代后旧请求仍先写数据页（revision4而非2）；failure-fence-red.log复现迟到失败仍把旧页成功标记改false。GREEN：green-final.log两项合成集成覆盖分类切换、页/路线隔离、query/form双写、图片地址不落盘、失败/部分保旧、合法空页替换、非法分页网络前拒绝、父票据替代同时阻止数据与失败元数据修改。结构检查指出主方法过长，抽取范围构造和发布辅助函数后clippy-final.log通过。

日志短名均/tmp/ubaa-p4o-前缀。本阶段无真实学校请求/写入，没有Flutter/原生/真实性能新增证据，Bridge/App与余项继续待办。

最终just check退出0（/tmp/ubaa-p4o-check.log）：Core两配置各253、facade57、Bridge123通过/2既有忽略、CLI二进制端到端16；fmt/clippy/Shell/build/doc与layout零baseline违例通过。refs固定SHA校验、暂存敏感扫描5281文件通过，diff无空白错误。Core-only未改Dart/Bridge结构，本阶段没有重复Flutter或原生测试，旧证据不充当当前通过。原始源工作区干净，下一阶段继续阳光记录Bridge/App接线及既定固定路线回读保护。


## P4-P 阳光记录 Bridge/App 接线（2026-09-22）

基线 a0aff147。实施前补来源对照，Bridge v23 复用只含图片数量的既有记录白名单；增加普通缓存读取与概览路线/分类匹配合同。原学校参数与固定路线写后双回读保持。

RED：/tmp/ubaa-p4p-route-red.log 为 Core 匹配方法缺失；bridge-red.log 为本地方法缺失；schema-red.log 为新增只读类型尚未生成；app-red.log 为本地查询空投影及普通刷新仍调用旧接口；home-behavior-red.log 为首页未按概览分类读页且未调用匹配合同；ui-red.log 三项失败分别证明部分空页误报无记录、分类变化留下旧记录、首次失败未展示持久内容。初次测试夹具缺 message 和误用 const 已修正，不作为行为 RED。

GREEN：Core 阳光缓存三项、Bridge 独立锁/范围/退出/pending 写保护一项；App 六项覆盖精确页、时间、部分回退、首次 Partial、概览匹配、局部失败保旧、缓存损坏保概览与固定回读分流；UI 八项包含三项新增及原内容/详情回归。短日志名均使用 /tmp/ubaa-p4p- 前缀。完整门禁及原生合成结果待本阶段收尾填写，不声称真实业务或性能通过。

审查追加 local-failure-red.log：记录缓存错误原使整个概览投影为null，改为记录独立错误并保留合法统计；app-final.log六项通过。初轮完整check被Bridge测试函数139行结构限制拒绝，抽取合成播种辅助函数后clippy通过；Flutter初轮在原生测试夹具的可空client闭包静态检查失败，修正后完整复跑通过881项（57/66/384/268/20/32/54）及静态分析。FRB v23重生成零漂移（codegen-final.log）。

最终 just check 退出0（check-final.log）：Core两配置各253、facade58、Bridge124通过/2既有忽略、CLI端到端16；fmt/clippy/Shell/build/doc和结构门禁通过。refs固定SHA通过，暂存敏感检查5286文件，源工作区ubaa2仍干净。macOS合成集成1项通过（native.log），实际v23绑定调用了阳光空索引/空页和两个缺会话入口；仍出现Failed to foreground app; open returned 1，不计可视实窗、非空记录渲染或真实App业务。

当前候选 Core-live：用原工作区只读凭据经stdin注入独立临时会话，学校业务写入0。Direct全量24.389秒：35 PASS、2 FAIL、3 BLOCKED，失败为同一次Judge include_expired及其复用diagnostics的upstream_unavailable，current/detail/details_batch因此BLOCKED；WebVPN全量24.514秒40 PASS。有限Direct Judge复核7.079秒再次失败，安全传输元数据证明一个GET在约5.007秒返回HTTP 502、body_bytes=0（live-direct-judge.log），不推断具体学校故障位置，不改冻结URL、TLS或CLI路线。其余两路线阳光overview/records均PASS。Direct完整门禁仍受阻，不能把WebVPN成功替代Direct通过。

上述时间为顺序Core-live累计完成时间，不是缓存首屏、首批、真实App或性能目标测量；验证使用既有RouteClient只读链，也不等于新增持久缓存的真实App验收。日志前缀/tmp/ubaa-p4p-，live-direct.log/live-webvpn.log仅安全摘要，复核日志仅白名单状态/字节数/耗时，无URL、正文或凭据。没有验收媒体或发布证据。本阶段接线完成，P0–P5整体仍有资料持久化、缓存管理、跨范围失效、剩余安全分段/生命周期和多端性能待办，继续执行。


## P4-Q 最小遮罩资料 Core（2026-09-22）

基线c4c71bed。已重新核对冻结旧版userinfo接口/本地实现/DTO/分派测试及另一源user状态接口、request、Cookie和凭据存储，来源对照先于生产改动。新增三字段遮罩载荷、独立本地出口与在线身份双核对；不改学校协议、旧完整资料返回、Bridge v23或CLI合同。

RED：/tmp/ubaa-p4q-red.log为新类型、范围和facade方法不存在；首个测试版本误用未启用的tokio::test已改为既有显式runtime形式后再记录RED。GREEN：green-final.log四项通过，覆盖在线完整返回而持久仅遮罩、路线隔离、503失败保旧时间、合法可选字段缺失替换、401保留离线数据、状态身份与资料身份分别不符、退出迟到拒绝、Unicode短值、额外字段/未遮罩载荷拒绝、票据替代、重开范围及原取得时间。新持久测试起初未创建私有父目录导致Unavailable，补夹具后通过，不归因为产品缺陷。

clippy指出三个私有字段同前缀；内部字段简化命名，serde/getter仍明确masked语义，未增加allow例外。clippy-final.log通过；完整阶段门禁待收尾。短日志名前缀均/tmp/ubaa-p4q-。本阶段Core-only，无新增Flutter/原生/真实学校请求；P4-P的双路线事实仍只属于当时旧RouteClient只读验证，Direct希冀HTTP502阻塞不被本阶段覆盖为通过。Bridge/App和完整P0–P5继续。

审查追加missing-red.log：空身份响应原被误认另一账号并关闭缓存。增加显式身份可用性判定后，状态或资料缺身份均返回UpstreamChanged且保留旧内容和时间，userinfo已建票据时记录失败观察。green-final.log五项通过。初轮完整check已退出0，但此语义修正后的完整门禁另行复跑，不能沿用初轮结果。

最终check-final.log退出0：Core两配置各253、facade63、Bridge124通过/2既有忽略、CLI端到端16；fmt/clippy、Shell合同、layout零baseline违例、build/doc全部通过。refs固定两SHA校验通过，敏感扫描5289文件通过，diff无空白错误。原工作区ubaa2保持干净，冻结源未改。Core-only未改Bridge/Dart，未重复Flutter/原生测试；上一阶段证据不计为本阶段新测。本阶段可独立提交，下一项继续资料Bridge/App接线及既定P0–P5余项，目标未完成。


## P4-R 资料 Bridge/App 与个人页（2026-09-22）

基线6796c7de。来源补录在实现前，Bridge v24新增三字段遮罩DTO、本地读取与缓存刷新；App独立展示副本/后台调度/失败保留，个人页来源时间与稳定本机归属接线。原userinfo、认证user、提醒账号与所有学校写流程保持。

RED日志前缀/tmp/ubaa-p4r-：bridge-red为新入口缺失；schema-red为生成只读DTO缺失；app-red为App接口缺失；controller-behavior-red为本地资料未展示；late-red为迟到缓存错误误标成功在线资料失败；ui-red为缺保存提示；navigation-red为遮罩变在线文本导致退出个人页；identity-red为Core明确accountMismatch被当普通错误保留展示；nocache-behavior-red为缓存不可用阻断在线资料；logout-red为退出首条同步通知仍返回旧资料。错误目录下执行Flutter的未加载结果不作为行为RED，已从实际package目录重跑。

聚焦GREEN覆盖独立网络锁/路线/退出及pending写意图、Bridge schema白名单、资料实际路线/时间、原接口分流、控制器独立身份与首帧恢复后自动刷新、晚到/失败/退出/前后台/待确认操作保护、同次去重、个人页路线位置与联系人默认隐藏。完整门禁和原生结果待收尾记录，不将此确定性结果冒充真实App或性能。

初轮just check在生成libubaa_flutter_bridge.a时因磁盘不足退出101；当时仅约248MiB空闲。确认没有运行中的cargo/rustc后，只删除本隔离区Git忽略的target/debug/incremental，未动源工作区、会话、冻结材料或验收媒体，恢复约8.5GiB空闲。最终复跑使用CARGO_INCREMENTAL=0限制该可重建缓存增长；这不是修改产品存储或放宽门禁。

收尾审查追加manual-red.log：手动登录的原userInfo已取得新资料，随后开启的缓存却把展示倒退为旧遮罩。修正为保留该次已核实的在线展示，缺少原路线元数据时不补造来源；app-final.log共13项通过，包含3项Bridge适配和10项控制器场景。该修正未改Core/Bridge/学校协议，Flutter最终候选完整复验另记。

CARGO_INCREMENTAL=0的check-final.log退出0：Core两配置各253、facade63、Bridge125通过/2既有忽略、CLI端到端16；fmt/clippy/Shell/build/doc与layout通过。FRB v24生成零漂移（codegen-final.log）。初轮完整Flutter892项、之后895和896项分别是当时候选的通过记录，不能替代最终手动登录保护修正后的候选。

最终Flutter候选flutter-final-reviewed.log退出0，57/66/397/270/21/32/54共897项及静态分析通过；手动登录保护后的layout-final零baseline违例、敏感扫描5296文件、暂存diff空白检查通过。macOS合成集成1项通过（native.log），v24实际执行新增本地空资料与缺会话缓存读取，并保持原跨句柄退出测试；仍有Failed to foreground app; open returned 1，不算实窗视觉、非空资料DTO原生渲染或真实账号业务。

本阶段未进行真实学校请求/业务写入，没有新增验收媒体、启动耗时或发布证据。P4-P的WebVPN40项通过、Direct希冀HTTP502仅保留其原候选证据，不扩大为本阶段新增链路通过。源工作区ubaa2仍干净。资料本地/后台接线已完成本阶段，缓存管理、精确范围补全、剩余生命周期/安全分段及多端性能继续，整体目标不标完成。


## P4-S Core 缓存管理与代次轮换（2026-09-22）

基线92c028a3，refs通过。先补本地管理来源对照，无学校协议变更。新增数值用量、原子清理/返回新句柄、跨连接generation及v1到v2控制记录迁移；原CLI、Bridge v24形状与学校写流程不变。

日志前缀/tmp/ubaa-p4s-：red.log为usage/clear_for_reopen缺失；facade-red.log为clear_and_reopen/usage缺失；judge-red.log复现旧句柄启动Judge仍发1次认证请求，补公共扫描入口的代次保护后归零；storage-red.log复现新预检把Corrupt阻断为读取错误，调整后保留完整在线资料且save_error=Corrupt。

management-final.log六项通过：用量不解密业务行、实际文件回收、独立连接/旧票据拒绝、清除事务回滚、v1迁移保原条目时间、旧AAD无法解密v2、错误密钥不改v1、迁移保留退出状态、提交后维护失败分列。维护Capacity通过私有维护回调注入，不冒称真实磁盘满；清除失败通过SQLite触发器事务中止验证。facade-final.log三项通过：旧clone/独立句柄拒绝、认证未返回时清理不允许旧链取新票据、新句柄继续使用原会话、普通缓存损坏仍允许在线读取。

初次用u64直接从SQLite取数编译失败，改为i64加检查转换；clippy指出首页方法101行和冗余闭包，提取原查询校验并使用方法引用后通过，未增加allow或扩大baseline。完整门禁待收尾。本阶段Core-only，未新增Flutter/原生/学校live/性能证据，设置接线与其余P0–P5继续。

最终CARGO_INCREMENTAL=0 just check退出0（check.log）：Core两配置各259、facade66、Bridge125通过/2既有忽略、CLI端到端16；fmt/clippy/Shell/build/doc及layout零baseline违例通过。refs固定SHA已校验，暂存敏感扫描5299文件通过，diff无空白错误。Core-only未改Bridge形状/Dart，未重复Flutter或原生测试，旧897项Flutter与原生结果不充当本阶段新增证据。当前没有真实学校请求/写入或性能数据；Core管理能力可独立提交，Bridge/App设置、宿主清理代次、保留优先级和损坏文件重建仍继续。


## P4-T Bridge 管理合同与 App 后端代际（2026-09-22）

基线21bd104f。先记录来源边界。日志前缀/tmp/ubaa-p4t-：bridge-red.log缺usage/clearAndReopen，schema-red.log缺生成文件，schema-shape-red.log复现结果被生成为可变opaque而不是明确DTO；non_opaque修正后生成不可变新句柄与报告。app-red.log为缺失管理合同/方法，初轮测试自身枚举与错误构造笔误已先修正，最终RED仅保留待实现缺口。

bridge-final.log本地清理在网络锁占用下完成1项通过；app-focused.log共12项，包括维护失败移交、事务失败保旧、排队读取失效、迟到结果拒绝、退出继任句柄、待切换账号拒绝旧确认、多步阳光概览不能用新句柄请求记录及原固定路线回读。schema与完整Flutter/原生/根门禁正在收尾。初次layout发现Bridge api目录新增第17个平铺文件，改为cache_management/mod.rs，未新增baseline。

当前仅完成Bridge与backend管理边界，不冒称设置页、控制器内存清理、原生可见界面或性能验收。无学校live调用、写入或验收媒体。


完整flutter-final.log退出0：57/66/403/270/22/32/54，共904项及静态分析通过；初轮仅因新增schema测试格式未整理而退出，格式修正后全量复验。check.log退出0：Core两配置各259、facade66、Bridge126通过/2既有忽略、CLI端到端16，以及fmt/clippy/Shell/build/doc、layout零baseline违例通过。暂存敏感扫描5304文件通过，原工作区ubaa2仍干净。

native.log原生合成1项通过，实际序列化v25新句柄、读取数值报告并拒绝旧句柄；仍出现Failed to foreground app; open returned 1，因此不计为实窗渲染/真实App验收。生成复核初轮发现Rust注释新增空格造成生成注释/内容hash漂移，更新生成产物后再次执行严格一致性检查。此变动仅为注释，非业务行为。

最终codegen-reviewed.log退出0，FRB v25严格生成零漂移。本阶段独立提交范围为本地管理Bridge与App backend代际保护；下一阶段接控制器及设置入口，整体P0–P5仍未完成。


## P4-U 控制器与设置缓存清理（2026-09-22）

基线f7f554f5，refs固定SHA通过。controller-red.log为缺失控制器合同；初轮测试误用了不存在的查询枚举，改用实际FeatureQuery后重新获取缺失合同RED。ui-red.log为Shell缺失cacheAccountId接线。usage-red.log复现恢复期间用量读取错误返回operation_conflict，拆分条件后controller-reviewed.log六项通过。

ui-focused.log十一项通过：四项设置确认/失败/防重复/账号切换，七项导航回归含清理后父子页查询与未应用草稿保留且旧数据不复活。host.log一项通过，生产宿主回调确实进入控制器并保留安全账号与登录；初轮误把retain返回的LocalAccountState当作LocalAccount，修正测试取account字段后运行，不算产品RED。

首次完整Flutter为914项，新增写意图保护和宿主接线后为916项；用量读取条件审查修正后的最终候选再次复验。layout.log零baseline违例。native.log初始候选原生合成宿主1项通过，仍有Failed to foreground app; open returned 1；不算可见界面或真实账号数据。最终候选原生与完整门禁正在收尾。没有真实学校请求/写入、验收媒体或启动指标。


原生可见补验：CUA最初选中了上轮测试结束留下的空白实例；通过菜单退出旧实例后，持续检查模式成功显示首页和设置。没有绕过锁屏或操作真实账号。最终使用明确合成backend与内存安全材料，实际完成设置用量、清理确认及清理结果三个场景，三入口、顶栏和设置位置保持。截图逐张复核，中文与控件完整、无布局溢出。截图来自macOS实际窗口，不是phone/tablet验收，也不是生产数据/性能证据。

视觉反馈触发两项修正：units-red.log复现小用量显示0.0 MB，改为B/KB/MB自适应；result-red.log复现用量尚未返回时清理失败仍显示内容已清除，改为独立“用量暂无统计”，result-green.log五项通过。最终结果文案通过原生hot reload再次可见复核，不把reload耗时算启动性能。

媒体仅在仓库外私有目录 /Users/moorefoss/.local/share/ubaa-private-evidence/offline-home-20260917/p4u/，目录0700、图片和manifest.json为0600。共3场景、6个捕获文件（同场景辅助窗口副本不算新场景），均1824×1488。设置主图settings-w399.png SHA256 512b2a7eee7db42bc241f90c6197730489da80133ef22d870eeb44839a0b237d；确认confirm-w399.png为66c0863390f8b63e0a9cffda7961e39cca653fc877de1222422aa10dfe39fb84；结果result-w399.png为7dd6f8c00d8d0b9da871f7c64b951070333034b6a333a4d2ab0b4aad4df81fa3。单个辅助window-id捕获失败后使用按应用捕获成功，没有把失败文件计作证据。合成检查应用已经退出。

check.log退出0：Core两配置各259、facade66、Bridge126通过/2既有忽略、CLI端到端16，fmt/clippy/Shell/build/doc通过。无Rust/Bridge形状变化，未重复codegen，版本仍v25。用量条件修正后native-reviewed.log原生合成宿主1项通过；最终可见界面证据由上述CUA实窗补验提供。最后完整Flutter及暂存结构/敏感门禁另记。

最终flutter-final-result.log退出0：57/66/409/276/22/33/54共917项及静态分析通过。layout-final.log零baseline违例，sensitive-final.log扫描5311文件通过，暂存diff无空白错误。源工作区ubaa2保持干净。此阶段仅清理设置流程可独立提交；保留优先级/90天历史规则、无法打开的损坏数据库重建、学期覆盖、其他领域UI细节与最终15场景/多端性能仍按完整目标推进。


## P4-V Core 容量保留策略（2026-09-22）

基线5f1318d0，refs固定SHA通过。先核对双来源边界和规范化日期，来源记录见P4-V。日志前缀/tmp/ubaa-p4v-：red.log为缺retention模块，初轮测试ConnectionMode导入位置已先修正；首个GREEN尝试因测试未创建根目录返回Unavailable，修正测试环境后cache.log原35项加初4项共39项通过。环境错误不当作行为RED。

context-red.log复现两项真实缺口：没有学期索引的未来考试仍为Stable、当前学期切换被旧索引锁住容量而返回Capacity。加入未来日期保护与即将提交索引上下文后8项通过；final-focused.log包括多selected（含空项）不可信、路线隔离、24小时新鲜度、90天精确边界、未知/非法日期、跨年活跃任务、混合订单旧项后新项、旧课程复查索引保留、容量失败不丢活跃内容、插入前回收与插入失败回滚。SQLite触发器是确定性顺序/故障注入，不是实际满盘测量。

check.log初轮clippy拒绝wildcard import及可折叠if，已显式导入和合并判断，不加allow；check-final.log正在运行。本阶段只改Core本地保存策略，不新增学校请求/写入、Flutter/原生媒体、Core-live或启动性能证据，旧阶段通过不扩大为本阶段新证据。

最终check-final.log退出0：Core两配置各267、facade66、Bridge126通过/2既有忽略、CLI端到端16，fmt/clippy/Shell/build/doc和layout零baseline违例通过。敏感扫描5313文件、暂存diff空白检查通过。Schema v2、Bridge v25、CLI v10未变；本次Core-only未重复Flutter或原生测试，不把旧917项/原生截图扩大为新增证据。源工作区ubaa2仍干净。完整目标继续，损坏文件重建、学期完整覆盖、剩余安全分段/生命周期及多端容量/性能验收未完成。


## P4-W 损坏缓存显式重建（2026-09-22）

基线ad3ce9c1，冻结引用纯校验通过。日志前缀/tmp/ubaa-p4w-：red.log缺Core重建合同；post-red.log缺清除后初始化故障注入；bridge-red.log缺新静态RPC；controller-red.log缺恢复backend与cacheReady字段。均先观察缺口，再最小实现。无学校协议更改，来源及SQLite原生合同已先记录。

rebuild-green.log六项通过：独立数据库身份拒绝旧票据、损坏头重建且其他账号/会话字节不变、未知版本仅显式清理、独立读事务阻塞且失败保原文件、v2条目和退出状态迁移及旧AAD拒绝、清除提交后初始化失败准确分列。故障注入不等于设备磁盘满。bridge-green.log一项证明网络锁占用时本地重建仍完成、坏密钥长度不触碰原文件。app-focused.log十六项覆盖失败打开后恢复、临时密钥使用及归零、空继任句柄、旧读取/排队退出和账号归属；ui.log六项通过。

flutter.log完整923项（57/66/414/277/22/33/54）及静态分析通过。native.log一项macOS原生合成验证Bridge v26可空句柄与损坏文件重建；仍有Failed to foreground app，不能计作可见渲染或真实App。没有新增验收媒体。check.log首轮clippy指出报告按值传递，改借用；check-final.log最终退出0：Core两配置各273、facade66、Bridge127通过/2既有忽略、CLI端到端16及fmt/clippy/Shell/build/doc通过。

当前未执行真实学校请求或写入，未测启动/容量性能。生成一致性、最终暂存结构和敏感扫描收尾后独立提交，完整P0–P5继续。

最终codegen-check.log退出0，FRB v26严格生成零漂移。原生绑定可用与完整App验收保持分列；本阶段不关闭性能和多端余项。

最终layout零baseline违例，敏感扫描5316文件、暂存diff检查通过。源工作区ubaa2干净，所有新增文件限实施隔离区。


## P4-X 跨学期成绩本地统计（2026-09-22）

基线c7365355，refs通过。red.log为App缺onProgress；ui-red.log为UI回调合同缺渐进参数；isolation-red.log复现单学期磁盘异常丢掉整个本地集合，逐项捕获后保留其他学期。index-red.log复现在线学期索引完整度丢失、部分列表被当成完整统计；透传evidence并纳入GradesAggregate判定后通过。首轮脚本工作目录错误未写入文件，不计产品RED。首个在线测试因自动首页refreshHome代次改变而返回operation_conflict，改为明确独立恢复观测，不改变生产代次规则。

final-focused.log117项通过，包含9项新增聚合、学期选项和原控制器回归；ui-reviewed.log5项通过，含刷新中已保存数值/时间可见和原路线/筛选行为；host.log1项通过，真实宿主回调接控制器，在挂起恢复时收到本地统计、失败后保留。测试账号与成绩全部合成，不读取真实凭据或学校网络。

flutter.log最终934项（57/66/423/278/22/34/54）和静态分析通过。根门禁与macOS原生合成场景收尾中；没有本阶段真实App、Core-live、性能或发布证据。学期日期显示特意保留年份，未复用首页省略年份的显示方式。

额外生命周期待办：初始化密钥读取尚未完成时立即切路线，会使原缓存打开被代次栅栏取消；路线隔离测试先等待打开以独立测隔离，不能据此宣称该启动竞态已修复，后续单独RED和修复。

check.log退出0：Core两配置各273、facade66、Bridge127通过/2既有忽略、CLI端到端16及fmt/clippy/Shell/build/doc通过。native.log原生合成6项通过，仍有Failed to foreground app，不计可见实窗验收。Bridge与生成文件未改变，保持v26，不重复codegen。

最终敏感扫描5320文件、暂存diff通过，根门禁layout零baseline违例。源工作区ubaa2干净。当前只完成本阶段跨学期本地统计；整学期课表、其余生命周期/写后跨范围刷新及P5最终验收继续。


## P2-F 启动缓存打开与路线生命周期（2026-09-22）

基线8a22e0f7，冻结refs通过。/tmp/ubaa-p2f-red.log两项真实失败：密钥返回前切路线不再打开账号库、首页磁盘读取途中换路线后没有新范围重读；旧退出保护先通过。加入独立仓库所有权代次后，延迟密钥、延迟投影、退出及同账号重登保护通过。clear-red.log复现清理后旧读取重试复活内容，清理在打开后轮换本地所有权后修复。

final-focused.log57项通过，包括六项新生命周期及既有清理、首页、查询、资料、成绩隔离。profile-red.log另复现本轮抽取流程将遮罩资料错误地排到首页磁盘之后；恢复其独立启动、投影前再次核对页面代次后profile-green.log17项通过。删除了P4-X路线隔离测试中等待初次打开的临时前置，现在同一路径无需等待也能通过。没有学校协议/Bridge/CLI合同变更。

根check.log退出0，Core两配置各273、facade66、Bridge127通过/2既有忽略、CLI端到端16及fmt/clippy/Shell/build/doc/layout通过。Flutter初轮通过后因资料独立性修正再次全量复验，最终结果另记。没有本阶段新增原生/真实App/Core-live/性能或发布证据。

最终flutter-final.log退出0：57/66/430/278/22/34/54共941项与静态分析通过。敏感扫描5321文件、暂存diff通过；Bridge v26未变，未重复生成。P2-F可独立提交，整学期课表与完整P0–P5继续。


## P4-Y 完整学期快照与离线日期覆盖（2026-09-22）

基线f8326600，refs通过。本阶段只实现Core本地基础，生产分段导入/Bridge/App入口尚未接通。red-contract.log为缺完整学期类型、独立范围及发布/投影合同；初版测试缺既有类型导入的编译噪声已单独修正后保留合同RED。首批4项通过后，protection-red.log复现普通缓存压力淘汰导入集合，以及日期规范化接受带加号年份；migration-red.log复现仅升版本不能阻止旧已打开连接继续操作；exit-red.log复现错误载荷先于退出栅栏；empty-red.log复现空周索引被称为完整；weeks-red.log复现当前周标记未按日期更新。

最终final-focused.log11项通过：完整学期跨重开/路线/周次隔离及原时间、缺周/重复周/错学期/非法日期拒绝、未知星期/未覆盖日期不冒充无课、有效空周、部分失败和迟到保护、导入集合容量保留、严格日期形状、跨学期覆盖选择、v3迁移保留内容/退出且拒绝旧连接、退出错误优先、空周索引保护、当前周标记按校园日期计算。模型保留本科WeeklySchedule.code，未错误要求等于学期。

cache-green.log此前8项模型加现有缓存57项通过；最终全量根门禁另记。check.log首次clippy拒绝文档InvalidInput缺反引号，已修正，不增allow或baseline。实现替换脚本一次因格式化后文本不匹配中止，未写入计划的代码修改；之后按实际内容完成。Schema升v4，控制AAD仍v3；新版本额外轮换仓库generation/epoch。没有学校请求或写入，没有本阶段Flutter/原生/真实App/性能证据。

最终check-final.log退出0：Core两配置各284、facade66、Bridge127通过/2既有忽略、CLI端到端16；fmt/clippy/Shell/build/doc和layout零baseline违例通过。暂存敏感扫描5323文件及diff通过。新生产代码仅Core本地模型，Bridge v26形状未改，未重复Flutter/生成/原生检查；最新941项Flutter是P2-F证据，不能当成本阶段新原生证据。完整学期生产导入和全部P0–P5继续。


## P4-Z 完整学期分段读取 facade（2026-09-22）

基线af4c03a8，refs通过。/tmp/ubaa-p4z-red.log为缺begin/next；green.log首3项通过。observation-red.log复现未知包装code仍被完整导入接纳，增加导入专用完整度检查并保持普通API容错后5项通过。local-red.log缺facade本地投影出口；term-red.log复现不同学期租约相互取消；week-red.log复现导入收尾时间压过后来完成的精确周结果（包含时钟回退）；time-red.log缺逐查询取得依据；today-red.log复现今日缺精确快照时未使用完整导入覆盖。

final-focused.log：新的facade确定性9项通过，包括Direct/WebVPN注入运输的逐批边界、完整发布/部分失败、不自动重发、在途取消、较新同学期/清理保护、不同学期交错保留、普通包装容错与严格导入区分、精确周/日期/路线本地恢复、较新单周优先及今日覆盖回退。另1项Core私有生命周期测试确认原运行时清理/路线往返均使旧计划失效、弱引用不延长原客户端寿命；初轮该测试FeatureRouteConfig导入路径错误已修正，不计产品RED。cache-green.log12项模型测试通过，包含加密保存后每周与周次索引的原时间。

check.log首轮clippy只拒绝测试中可合并if，合并后check-final.log退出0：Core两配置各286、facade75、Bridge127通过/2既有忽略、CLI端到端16及fmt/clippy/Shell/build/doc/layout零baseline违例。没有新增Bridge形状、真实学校调用或写入，没有本阶段原生/性能证据；学校普通接口和CLI保持，导入Bridge/App入口尚未完成。

P4-Z最终暂存敏感扫描5327文件及diff通过，源工作区ubaa2保持干净。Core阶段独立提交；并行发现的App辅助读取账号冲突处于单独P2-G修复，未纳入本次Core代码提交。


## P2-G 辅助读身份冲突与写入口保护（2026-09-22）

已在P4-Z收尾期间先做来源核对及RED；生产改动单独提交。/tmp/ubaa-p2g-red.log复现学期和成绩辅助读收到明确accountMismatch后仍停留home；旧路线迟到错误隔离先通过。green.log120项通过，初轮flutter.log944项与分析通过。随后审查write-guard-red.log确认未保留本机账号的宿主关闭身份后仍调用准备回调（预期0，实际1）；首次write-red.log回调抛错已复现执行，捕获合成异常后重新保留次数断言RED。

增加home/当前身份的统一准备条件，write-green.log138项通过，包含四项身份/准备保护、原控制器和WriteCoordinator回归。所有prepare使用脱敏回调，真实学校写入0。最终完整Flutter与根门禁进行中；此阶段无Bridge版本或协议变化，无新增原生/真实App/性能证据。

完整flutter-final.log在新的身份/home守卫下暴露19项旧测试前置不成立：未初始化/未登录即注入意图，或期待注销后立即恢复写入；其中4项因此等待未发生的回读而超时。保留生产保护，写生命周期/回读重入测试先建立合成已认证会话；无认证不接受意图、注销后必须重新登录另有断言。lifecycle-green.log34项通过，原提交次数、回读和重入断言均保留。正在重新执行全部Flutter。根check.log已退出0（同Core候选286×2、facade75、Bridge127/2忽略、CLI16及其余门禁）。

最终flutter-reviewed.log退出0：57/66/434/278/22/34/54共945项及分析通过；旧测试按真实认证前提重跑，实际学校写入仍为0。后续整学期导入Bridge/App、跨范围写后刷新、其他长读取与最终多端性能继续。

P2-G最终暂存敏感扫描5327文件与diff检查通过；源工作区保持干净。本阶段单独提交，不含随后新增的整学期Bridge测试。

## P4-AA 整学期导入 Bridge/App/课表页（2026-09-22）

基线41bf5f4e，refs通过。/tmp/ubaa-p4aa-bridge-red.log缺begin/next；初版MockTransport断言方法名错误先修正后重新记录。bridge-green.log一项通过，实际在两批之间取得同一客户端锁执行所需路线恢复，并确认写意图、取消、dispose阻止下一批。App-red.log缺backend导入合同；初轮错误工作目录及枚举名噪声已修正，正式RED后app-green.log四项通过。

controller-red.log缺任务入口、进度状态和取消合同；最终final-focused.log十项通过，包括后台/写意图暂停、逐批让位签到、同学期合并、当前查询保持、取消/路线/退出/清理迟到保护、首页刷新不取消、失败不重发和明确身份冲突。ui-red.log缺shell参数（初次非const构造噪声先移除），ui-green.log三项覆盖390/834/1280宽度与1.3倍文字、进度/取消/容量失败/重试/已保存状态。host-red.log真实断言保存回调为null，接线后host-green.log一项通过。全部合成，无真实学校写入。

codegen-check.log退出0，Bridge v27 FRB严格生成零漂移；layout零baseline违例。完整Flutter、根门禁和原生测试分别进行中，尚无本阶段真实App、Core-live或启动性能证据。

完整flutter.log首次因一个ContractVersionClient仍传26失败；修正测试候选为27，flutter-final.log退出0：57/66/444/281/22/35/54共959项及分析通过。check.log首次停在五份当前版本文档未升27，已同步并重跑check-final.log。native.log首个真实FFI用例通过，第二个runner启动时调试连接失败；确认无遗留App进程后单独重跑native-retry.log，四项合成宿主/三宽度场景通过。两次原生均有Failed to foreground app，记录为原生功能测试，不能算可见实窗或真实账号App验收。没有新增媒体、学校写入或性能测量。

最终check-final.log退出0：Core两配置各286、facade75、Bridge128通过/2既有忽略、CLI端到端16，fmt/clippy/Shell/build/doc和layout零baseline违例通过。暂存敏感扫描及diff通过，源工作区ubaa2仍干净。完整P0–P5继续，离线周次自动导航与日期、跨范围写后刷新、其他安全分段及多端性能尚未关闭。

## P4-AB 离线课表自动导航与日期投影（2026-09-22）

基线438390d8，refs通过。/tmp/ubaa-p4ab-ui-red.log两项真实失败：loading/stale中已有完整离线索引只发scheduleTerms，未继续教学周和周课表；部分索引保护先通过。修复后第一轮green仅因顶栏与周导航均显示同一周名而断言数量不符，明确验证两个既有位置，ui-final.log13项通过，含原父子返回和保存进度回归。

core-red.log复现完整导入无学期索引退路及普通周缓存仍标记旧周/未知日期/错学期（[1,3,4]而非[2]）。最初测试命令误用不存在的test-support特性，修正为test-contract后保留实际RED。time-red.log缺索引独立观察方法；添加后模型测试证明索引取得时间100、逐周120和导入收尾999不混淆。固定UTC边界单测另覆盖校园午夜跨周和无覆盖日期，不依赖设备时区。Core、Flutter及原生最终门禁随后记录。

cache-green.log最终14项通过（初轮私有计划测试构造缺新增可选字段，补齐后重跑）；core-final.log11项通过，含导入中途完成的较新普通学期索引优先。flutter.log完整57/66/444/284/22/35/54共962项及分析通过。native.log七项合成宿主/界面测试通过，仍有前台窗口警告，不计可见实窗、真实账号或性能。check.log因advance_schedule_import达到104/100行被clippy拒绝，抽取三处完全相同的精确查询票据申请，保持返回边界后重跑根门禁，不增allow或baseline。

最终check-final.log退出0：Core两配置各288、facade77、Bridge128通过/2既有忽略、CLI端到端16，fmt/clippy/Shell/build/doc/layout通过。敏感扫描5341文件及暂存diff通过。

P4-AB候选重新执行双路线Core-live，原工作区只读凭据经stdin进入新临时会话，未复制旧运行会话、未执行学校业务写入。Direct累计23.784秒：35 PASS、2 FAIL、3 BLOCKED；希冀include_expired及复用diagnostics为upstream_unavailable，current/detail/details_batch受阻。该轮未额外取得HTTP状态，不将P4-P的502当作本次直接观察。WebVPN累计25.384秒40 PASS。此标准门禁验证既有只读协议，不验证新加密导入或真实App/启动性能；Direct完整门禁仍未通过。

## P4-AC 关联缓存与在途读取失效 Core（2026-09-22）

基线771f7a04，refs通过。/tmp/ubaa-p4ac-red.log为缺typed失效合同和仓库方法，包含六领域已知/未知范围用例；green.log首三项通过，final-focused.log扩为六项，验证无旧条目的迟到请求被撤销、其他目标/账号/路线保留、新读可继续、所有相关资源分页、事务注入失败回滚、损坏请求范围不部分清除和v4迁移业务密文不变/退出状态保留/旧连接拒绝。所有操作为本地脱敏数据库，不调用学校写入或真实账号。

Core业务缓存升schema v5，Bridge v27/CLI v10不变；学校提交接线尚未完成。该阶段未新增真实App、Core-live或启动性能事实，P4-AB双路线结论保留原候选边界。完整门禁随后记录。

check.log首轮clippy要求合并相同match分支，并将103行测试表拆成数据与执行段，未增加allow。随后corrupt-red.log复现两个审查缺口：新增范围密文损坏仍可验证票据，以及无关坏条目阻断合法目标失效。验证/续租/发布统一核对范围，失效扫描只解析已认证scope、坏条目留给原单条隔离后corrupt-green.log八项通过。native.log此前一项macOS真实FFI/SQLite合成用例通过，前台窗口警告仍在；最终根门禁及新guard候选原生复验继续。

最终check-final.log退出0：Core两配置各296、facade77、Bridge128通过/2既有忽略、CLI端到端16及fmt/clippy/Shell/build/doc/layout零baseline违例通过。native-final.log再次验证新请求范围guard候选，macOS真实FFI/SQLite合成一项通过，仍不计可见实窗。暂存敏感扫描和diff通过。Core-only阶段未改变Bridge形状或Flutter生产代码，不将P4-AB的962项扩记为本阶段新增Flutter证据；生产commit和跨入口内存失效继续。

## P4-AD 写提交关联失效与只读补刷新（2026-09-22）

基线2715377a。Bridge RED见/tmp/ubaa-p4ad-bridge-red.log（缺新提交合同）；实际路线测试route-red.log复现准备Direct、结果WebVPN却失效Direct的缺口，修正后bridge-reviewed.log五项通过，覆盖同意图不可重用、发送前资格拒绝不清缓存、未知结果不重发、部分评教及本地失败不覆盖学校成功。App RED见app-red.log及controller-red.log；focused.log共39项通过，覆盖原账号句柄、后台暂停补刷新、注销迟到结果、回读失败和未知结果。

宿主真实点击准备/确认、单次脱敏提交、回读及后续同步失败：host-verified.log一项通过。此前host测试失败来自fixture初始列表未提供、通知后尚未pump以及把保留的禁用备用按钮误当旧资格；修正fixture和断言，未为此隐藏原版界面。原生FFI/合成宿主与最终门禁结果另记。上述均不是真实学校写入、真实App账号或性能证据。

最终check-final.log退出0：Core两配置各296、facade77、Bridge133通过/2既有忽略、CLI端到端16，fmt/clippy/引用/Shell/构建/doc/layout零baseline违例通过。flutter-final.log退出0：七包分别57/66/453/284/22/36/54，共972项；格式和analyze通过。生成合同v28及严格codegen-check通过。native.log退出0：macOS真实FFI与脱敏宿主两项通过，仍有Failed to foreground app警告，不计可见实窗。sensitive.log扫描5351个文件通过；暂存审查未含冻结输入、真实业务正文或验收媒体。本阶段未重跑Core-live或测量冷启动，最近双路线事实仍限定P4-AB候选。

## P4-AE 阳光概览学期与周期范围（2026-09-22）

基线2bbe3a12。RED见/tmp/ubaa-p4ae-red.log（缺周期读取/发布模块）。green.log的Unavailable来自新fixture未建立根目录；修正fixture后green-final.log暴露子票据发布即消费、索引不能再用已消费子票据校验的实现错误，改为原父票据发布后green-verified.log四项通过。focused.log扩为五项通过，覆盖学期/分类/路线/周、日月投影不改正文、未知学期/部分失败、迟到父票据不撤销新子读、写后失效、旧单例不猜归属、非法范围/载荷与重开。

facade-final.log两项Mock协议接线通过；学期接口失败的新未知范围Stored与旧已知范围Preserved分开断言，旧已知正文/时间和首页索引保持。没有新增学校请求或真实写入。首轮check.log由单函数116行触发clippy，抽出持久发布职责后重跑完整门禁；最终结果另记。

最终check-final.log退出0：Core两配置各301、facade77、Bridge133通过/2既有忽略、CLI端到端16及fmt/clippy/Shell/build/doc/layout零baseline违例通过。refs通过，sensitive.log扫描5353个文件通过。native-final.log在发布职责拆分后的候选重跑：macOS真实FFI/SQLite合成一项通过，前台化警告仍在，不计可见实窗。此Core-only阶段未改变Flutter生产形状，不将P4-AD的972项重记为本阶段新增Flutter测试；Core-live、真实App、启动性能均未新增。

## P2-H 前台退避与网络变化恢复（2026-09-22）

基线1af52ba7。/tmp/ubaa-p2h-red.log为缺onNetworkChanged；monitor-red.log为缺只读接口观察器；host-red.log为缺宿主stream接线。retry.log初八项通过，app-verified.log含新写保护及原恢复回归44项通过；query-verified.log十项退避/网络专项通过，包含失败学期查询原位更新和重复提示合并。写保护fixture先恢复合法会话才允许准备意图；首次fixture在未认证时setIntent被正确拒绝，不将该测试失败记作产品绕过保护。

监视器原widget计时测试在长pump收尾挂起，终止本任务测试进程后改用直接fake_async时钟，不改生产网络判定；host-verified.log两项监视器及一项宿主生命周期测试通过。首轮flutter.log因FeatureQuery使用对象身份相等的错误断言失败；修正为既有hasSameQuery语义后flutter-final.log退出0：57/66/463/284/22/39/54，共985项，格式/analyze通过。所有测试数据均合成，没有真实学校写入或真实登录材料。

native.log退出0：macOS系统NetworkInterface只读枚举调用与脱敏宿主网络提示恢复一项通过，未输出地址。仍有窗口前台化警告，只算原生合成功能；没有断开设备网络或验证真实学校恢复。check.log退出0：Core两配置各301、facade77、Bridge133通过/2既有忽略、CLI端到端16及完整根门禁通过，refs和敏感扫描通过。OHOS无签名构建结果另记。

空间维护只删除隔离区target/debug/deps中六小时前的本任务Core/Bridge可重建旧产物，84,819个文件，文件长度合计21.32 GiB；源工作区仍干净/ahead7，未删除冻结材料、运行会话或当前候选产物。

OHOS：/tmp/ubaa-p2h-ohos.log退出0，锁定fork analyze、两项入口测试、API26工具链、无签名debug HAP与arm64 ELF门禁通过。构建删除的buildinfo及生成的本机SDK相对锁路径经diff核对后恢复HEAD原值；其余生成产物保持忽略。未在OHOS设备运行网络枚举/HUKS，不作为签名或发布证据。暂存diff和敏感扫描通过，原工作区仍未修改。

## P2-I 无持久缓存希冀分段 facade（2026-09-22）

基线f8ac79d8。/tmp/ubaa-p2i-red.log为缺新选项与begin/next合同；green.log首两项通过，路线测试因注入客户端没有可写配置目录失败，随后把路线往返/清理/弱引用用例放入可控制真实配置目录的Core单测，未修改生产路由权限。guard.log一项通过。facade-green.log三项、focused.log五项通过。身份审查新增identity-red.log（缺expected_identity），最小校验后identity-green.log六项通过，冲突只发UC状态请求、不继续课程读取。

六项Mock覆盖旧项后新项、两次扫描都复查旧课程、逐批返回、显式目标/去重/课内顺序/空及缺失目标、取消迟到结果、普通课程失败与整体认证失败。请求仍由原runtime执行并在每次详情前重选课程；不创建OfflineCache或复制Cookie。尚无生产Bridge/App接线、真实账户、原生或性能证据。完整门禁结果另记。

check.log首轮因可避免的err().expect触发clippy的panic文档和err_expect规则，改为直接match传播错误，不新增allow或panic合同。最终check-final.log退出0：Core两配置各302、facade83、Bridge133通过/2既有忽略、CLI端到端16，fmt/clippy/Shell/构建/doc/layout零baseline违例通过。refs及5361文件敏感扫描通过。本阶段不把P2-H的985项Flutter、macOS原生/OHOS构建或P4-AB的Core-live结果继承为新在线计划端到端证明；生产接线继续。

## P2-J 无缓存希冀 Bridge/App 接线（2026-09-22）

基线e53024dd。/tmp/ubaa-p2j-bridge-red.log缺begin/next/options，bridge-green.log一项Mock通过：真实共享锁在索引后可供另一Bridge检查使用；待确认意图存在时begin/next无新增请求且意图不丢，取消后不继续，dispose保持原错误。app-red.log三项行为失败均为旧beginFeatureRead返回null；app-green.log五项通过，含原持久投影回归。

app-final-focused.log七项通过：无缓存摘要/单详情/批量渐进、原输入顺序投影、迟到代次拒绝、预期身份与非持久来源、缺密钥控制器仍传账号，以及生产Bridge投影经原调度器在首批后按索引→签到只读→详情执行。账户fixture首轮遗漏FeatureQueryBackend，导致查询按原合同unsupported，补齐fixture后通过。app-verified.log含既有恢复回归16项通过。

Bridgev29生成codegen-final.log零漂移；首轮仅FRB生成后rustfmt导入顺序未暂存，重新暂存规范格式后验证通过。原生与全量门禁结果另记；无真实学校写入、无真实账号及性能结论。

最终check-final.log退出0：Core两配置各302、facade83、Bridge134通过/2既有忽略、CLI端到端16及fmt/clippy/Shell/build/doc/layout通过。首轮check.log测试函数108行，抽出请求表后修复。flutter.log退出0：57/66/470/284/22/39/54，共992项及格式/analyze通过。native.log五项macOS原生FFI/合成投影/调度通过，仍有前台化警告，不计可见实窗。refs及5369文件敏感扫描通过。

双路线标准Core-live：live-direct.log退出0，40PASS，累计26.569秒；live-webvpn.log退出0，38PASS/2NOT_APPLICABLE，累计29.215秒。WebVPN旧聚合include_expired208项、current0，故单详情/批量详情没有可用当前ID而不适用；Direct对应92/9且详情/批量通过。这个差异仅为本轮白名单观察，不推断两路线业务数据本应相同或新计划已经验证。均通过原.env.local→stdin及新临时会话，无复制运行会话、无真实写入；日志无正文/凭据。新分段与加密缓存真实App、冷启动和全部更新性能仍待独立验收。
