# 通用依赖复用审计

日期：2026-10-07。基线：`ubaa2` / `af41e218`。范围：当前 Rust/Flutter 产品线，冻结旧版只作来源比较。结论来自当前源码、依赖清单、维护者文档及一项实际代码的合成回归，不继承历史 App 验收。

## 结论与范围

确认七类值得收敛的通用能力：Cookie 标准处理、加密模式与填充、照片选择与拍照、平台目录、普通偏好持久化、网络变化监听、OHOS 版本/外链通道。前三类优先；Cookie 已复现标准语义错误，其余主要是维护成本或能力差异，不能统称为已经发生的故障。

另有四项区别处理：multipart 可替换但受传输端口约束；定位是尚未接通的能力；桌面组件只能复用部分插件能力；OHOS 安全存储已统一接口但仍有本地 fork 维护面。无需历史数据迁移也给清理旧成绩基线迁移链提供了机会。

本轮只提交审计文档，不替换依赖、不改变生产行为。P1 表示优先处理正确性或高维护成本基础能力，P2 表示常规收敛，P3 表示有条件再做。

审查覆盖 workspace Cargo、各包/宿主 pubspec、平台默认装配、原生通道、调用方及相关测试；深读 Cookie、目录、照片、偏好文件、网络监听、协议加密、multipart、缓存加密、会话文件安全、组件存储、读取调度与恢复入口，抽查 UI 通用控件和脚本职责。对 Rust/Dart/Kotlin/Swift/ArkTS 按目录与关键能力检索；FRB 生成代码、cargokit 第三方工具和测试替身不计为自研基础功能。没有把检索文件数量当成逐行审计覆盖率。

新增插件只核实候选、接口及支持范围，没有安装或完成工具链/设备验收。未访问真实学校接口、用户会话、凭据或媒体，冻结来源保持只读。

## R1 / P1：Cookie 标准处理

位置：`crates/ubaa-core/src/session/cookies.rs:38`（解析）、`:103`（过期）、`:160` 起（保存/发送）；域和路径工具在 `session/file_safety.rs:122`。

现状：自行拆分 Set-Cookie、处理 Domain/Path/Expires/Max-Age、替换、发送和序列化。`is_expired` 对 Expires 与 Max-Age 取逻辑或，插入前也独立检查 Expires。

**已复现**：固定时间 `2_000_000_000` 秒收到合成 Cookie `AUDIT=synthetic; Path=/; Max-Age=3600; Expires=Thu, 01 Jan 1970 00:00:00 GMT`，实际发送头为空；应按 Max-Age 保留。标准规定 Max-Age 优先，见 [RFC 6265 §4.1.2.2 / §5.3](https://www.rfc-editor.org/rfc/rfc6265.html#section-4.1.2.2)。尚无真实学校响应证明它造成过某次掉线。

建议在现有会话边界内复用 [cookie_store](https://docs.rs/cookie_store/latest/cookie_store/) 与 `cookie` 的解析/匹配/过期规则。库提供序列化和公共后缀支持，接入仍需确认实际后缀列表配置。不要仅开启 Reqwest `.cookie_store(true)`：账号/路线隔离、会话代次、手动跳转、受控持久化和测试时钟仍由 Core 管理。还须核对时间注入、同名不同路径排序、删除、序列化及脱敏日志策略。

来源冲突：冻结 old `1f4b8f84` 的 `shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalConnectionAuth.kt:150` 起采用 Ktor 接口但自行过期判断，同样先看 Expires；冻结 buaa-api `a63712fa` 的 `src/store/cookies.rs:1` 明确不处理 Max-Age/Expires。两者都不是完整标准实现，不能因沿用旧版而免审。后续修改前须补逐操作九列裁决，明确标准与旧行为冲突的处理；本轮停留在审计边界。

## R2 / P1：加密模式与填充

位置：`crates/ubaa-core/src/connection_codec.rs:38` 自行 CFB 反馈/XOR；`features/spoc/crypto.rs:7` 自行 CBC 链与零填充；`features/libbook/crypto.rs:22` 自行 CBC 与 PKCS#7；`features/cgyy/crypto.rs:22` 自行 ECB 遍历与 PKCS#7。

项目已使用 RustCrypto AES 原语，问题是继续手工维护标准模式和填充，并非自创 AES。可复用 RustCrypto [cbc](https://docs.rs/cbc/0.1.2/cbc/)、[cfb-mode](https://docs.rs/cfb-mode/latest/cfb_mode/)、[ecb](https://docs.rs/ecb/0.1.2/ecb/) 与现有 `cipher::block_padding`。博雅已经使用 `encrypt_padded_mut::<Pkcs7>`，无需各业务重复手算填充。

保留学校规定的密钥来源、IV、反馈宽度、序列化、编码、截断及 SPOC 整块输入不追加零块的行为。先做冻结来源向量及空/整块/跨块/中文输入的字节差分，再替换循环。不能借重构直接把学校协议改为 GCM。选择与当前 `aes 0.8` / `cipher 0.4` 兼容的版本，不照抄最新版 API 混用类型。当前未证明这些循环产生错误密文；这是明确可移除的标准算法维护负担。

## R3 / P1：照片选择与拍照

位置：`apps/ubaa_flutter/macos/Runner/Platform/PhotoHandler.swift`、`ios/Runner/Platform/PhotoChannel.swift`、`android/app/src/main/kotlin/cn/edu/ubaa/ubaa_flutter/platform/{PhotoChannel,CameraPhoto}.kt`、`apps/ubaa_ohos/ohos/entry/src/main/ets/platform/PhotoChannel.ets`；共享校验在 `packages/ubaa_platform/native/apple/PhotoPayload.swift` 和 `lib/src/media.dart`。

上述五个宿主文件共 429 行，另有共享校验/Dart 包装；Android/iOS 文件还混有目录/权限处理，不把全部行数都视为可删除。Windows/Linux 已用 file_selector，macOS 却再次实现 NSOpenPanel。

建议 Android/iOS 使用 Flutter 官方 [image_picker](https://pub.dev/packages/image_picker)，macOS 复用已依赖的 [file_selector](https://pub.dev/packages/file_selector)，在 PlatformPhotoPicker 内统一返回规范字节。OHOS 有 SIG 适配候选，兼容性见后文。

具体差异：Android `PhotoChannel.kt:80` 起只从 Intent 的 `data` extra 读 Bitmap，没有完整照片输出 URI；冻结旧版 `composeApp/src/androidMain/kotlin/cn/edu/ubaa/ui/common/util/PlatformImagePicker.android.kt:34` 确实使用 TakePicturePreview，不能当成已确认的产品缺陷或擅自改为原图。pending 回调只在内存，无丢失结果恢复链；image_picker 提供 `retrieveLostData`。iOS 当前只有选图，没有拍照方法，插件可承载后续能力；桌面不能因 API 有 camera 枚举就声称能拍照。

保留 10 MiB 流式上限、图片有效性/MIME/文件名验证、取消、错误归约与账号切换丢弃结果。插件可能生成临时照片，须确定清理时机；恢复结果须绑定当前表单/账号，不能恢复后直接上传。系统选择器的单文件授权不应被无条件整库权限挡住。

## R4 / P2：平台目录

位置：`packages/ubaa_platform/lib/src/paths.dart:12`；Android/iOS 的 paths.config 混在照片通道。桌面读取 HOME/APPDATA/XDG_STATE_HOME 并拼接路径；OHOS 没有同等原生目录分支，依赖环境约定。

建议用官方 [path_provider](https://pub.dev/packages/path_provider) 获取系统目录，路径拼接可用 `path`。CLI 已用 directories，无需更换。保留绝对 UBAA_CONFIG_DIR 覆盖以隔离测试。

不能无条件替换：Android 当前明确使用 noBackupFilesDir，一般 Application Support 不自动等价；iOS 当前返回系统 Application Support 下的 UBAA，所查通道未设置排除备份标记，不能把私有目录与不参与备份混为一谈。插件不提供既有同语义能力时保留专门薄适配。OHOS 要验证 filesDir/沙箱，不从桌面 HOME 类推。不需要旧目录搬迁，也不主动删除现有真实目录。

## R5 / P2：普通 UI 偏好

位置：`packages/ubaa_platform/lib/src/bykc_filters.dart:43`、`reminders.dart:29`，均实际接到 Host。两者分别维护 JSON schema、账号表、队列、临时写入与 rename；博雅还启动 chmod 子进程。提醒用固定 `.pending` 和实例内队列，博雅用按路径共享队列/唯一临时目录，机制不一致；跨实例并发有冲突风险，本轮未复现。

建议用 [shared_preferences](https://pub.dev/packages/shared_preferences) 的 SharedPreferencesAsync 保存筛选偏好、提醒开关/消除标记，按账号独立键，保留应用层串行及注销清除代次。异步 API 避免多 isolate/engine 缓存旧值，**不等于**多键事务或读改写原子性；强事务数据应进入既有 Core 数据库。

该插件明确不适合关键数据：密码、Cookie、缓存密钥和成绩不能搬进去。当前提醒是应用内偏好，不是系统通知调度器，不应为替换此文件增加后台任务/本地通知插件。

## R6 / P2：网络变化监听

位置：`packages/ubaa_host/lib/src/network_monitor.dart:25` 每 5 秒枚举网卡地址；异常静默保留原状态。变化到发现存在轮询等待，同地址但路由/连通状态变化时集合可能不变。

建议用 [connectivity_plus](https://pub.dev/packages/connectivity_plus) 变化流，保留前台恢复复查、去重/节流、退避和账号代次。连接类型不是校园服务可达性或已登录证据。插件也可能不报告同类型 Wi-Fi 切换，不能声称覆盖每次 IP/路线变化；先定义恢复信号，必要时保留低频兜底。

## R7 / P2：OHOS 关于页

位置：`packages/ubaa_platform/lib/src/app_information.dart:13` 官方端使用 package_info_plus/url_launcher，OHOS 改走 `apps/ubaa_ohos/ohos/entry/src/main/ets/platform/AboutChannel.ets`（47 行），自行读 bundle、启动浏览器、重复定义两份项目 URL。

候选：[package_info_plus_ohos](https://pub.dev/packages/package_info_plus_ohos/versions) 和 [url_launcher_ohos](https://gitee.com/openharmony-sig/flutter_packages/blob/7f392a6b4d6cadd8534905b6bcbc1535ca69374b/packages/url_launcher/url_launcher_ohos/pubspec.yaml)。复用标准实现，在 Dart 保留 AppLink 白名单和版本展示格式。代码量小，排在照片/目录/偏好之后；核对 interface、engine 解绑及失败返回。

## 有条件候选与应保留内容

| 项目 | 当前事实与裁决 |
|---|---|
| multipart / P3 | `crates/ubaa-core/src/features/ygdk/upload.rs:14` 手拼正文、boundary 和头。可评估 [Reqwest multipart](https://docs.rs/reqwest/latest/reqwest/multipart/struct.Form.html)，但 HttpRequest 端口只接收 bytes，不能为上传绕过 HttpTransport/会话/一次性写入。先决定结构化 body 端口是否值得引入；当前单一三部分上传已有校验，未证实编码故障。 |
| 定位/权限 / 后续开发 | `packages/ubaa_platform/lib/src/location.dart:40` 只有通道门面，所查生产原生通道没有 location 方法。属于未完成能力，不是已完成定位引擎。启用时优先 [geolocator](https://pub.dev/packages/geolocator) 和适用 OHOS 实现；确需额外权限管理才评估 [permission_handler](https://pub.dev/packages/permission_handler)。不因占位类存在便增加无用权限。 |
| Android 组件 / P3 | `widgets/{WidgetChannel,WidgetStore,WidgetRenderer,ScheduleWidgetProvider}.kt` 可用 [home_widget](https://pub.dev/packages/home_widget) 简化发布/更新，原生布局、课表投影、跨周选择、注销撤销和加密仍须保留。WidgetStore 已用 AndroidKeyStore、AES-GCM、AtomicFile，不能改为普通偏好明文。home_widget 不会消除原生组件实现。 |
| OHOS 安全存储 fork | `packages/flutter_secure_storage_ohos/README.md`、UPSTREAM.json 与 ArkTS 源码：官方端已用发布插件；OHOS 仍是有来源的本地分支，负责 HUKS/GCM、错误、代次和并发合同。保留上游/许可证/补丁记录，跟进满足合同的社区发布版。本轮没有验证到可无补丁替换的版本，不能因名称统一就声称维护负担消失。 |
| 旧成绩迁移 | Host `lifecycle.dart:54` 仍创建 FileGradeScoreStore，`app_controller/grades/baseline_store.dart:57` 仍 migrate。当前成绩基线已在 Core 加密缓存，这是历史兼容负担。按无需已有数据的方向，另阶段删除迁移读取/清除及测试，不主动删除真实旧文件。 |
| 会话文件事务 | session/file_store.rs、file_safety.rs、storage.rs 包含锁、版本比较、禁止符号链接、私有权限与目录同步；标准库/fs2 已实现锁。tempfile 可减少临时文件 RAII，但不能替代整个事务合同。 |
| Core 缓存 | 已用 rusqlite、aes-gcm、hmac、sha2、zeroize；自行定义的是业务数据域、AAD、账号隔离/失效，不是数据库或 AES 算法。SQLCipher 与当前载荷加密目标不同，不为统一依赖搬到 Flutter 数据库。 |
| 网络/解析/CLI | 已用 reqwest、url、scraper、serde、chrono/chrono-tz、clap、directories、rpassword、tracing。不要增加 Dart Dio 形成第二套学校会话；字段解析/登录页识别与错误映射属于业务。 |
| 调度/认证/写协调 | ReadScheduler、恢复退避、WriteCoordinator 包含优先级、安全返回点、账号/路线代次、一次提交和未知结果禁止重放。通用 queue/retry 或状态管理库不替代这些合同。 |
| UI/Bridge/脚本 | UI 主要用 Flutter 标准导航、日期选择、控件和本地化，保留旧版业务布局；FRB 已生成跨语言层，typed mapper 是业务转换。脚本编排既有构建工具和项目门禁。没有支持整体更换 UI/路由/状态管理框架的充分证据。 |

## OHOS 与依赖准入

- 已核实 image_picker 的 [SIG 适配示例](https://gitee.com/openharmony-sig/flutter_packages/blob/master/packages/image_picker/image_picker_ohos/example/lib/main.dart)、url_launcher_ohos 固定提交清单及 pub.dev 的 package_info_plus_ohos、[connectivity_plus_ohos](https://pub.dev/packages/connectivity_plus_ohos) 发布文档。
- connectivity_plus_ohos 示例仍搭配 5.0.2，不能承诺兼容官方 7.x；package_info_plus_ohos 发布也较旧。path_provider/shared_preferences 的 SIG/TPC 适配继续列评估项，本轮对应源码页读取失败，未确认最新源码兼容性。
- 官方支持五端、OHOS fork 存在、工程解析/编译通过、设备运行正确是四个独立结论。此次未安装上述新增依赖，没有候选设备验收。
- 优先标准 federated interface，OHOS 实现仅由 OHOS 宿主引入并固定提交，避免全局替换官方五端依赖。确需补丁时记录来源、许可证、差异、维护与移除条件。
- 本报告引用查询时可见文档，不是锁定升级单。接入时另查 Dart/Flutter、Gradle、Xcode、系统最低版本、依赖树和许可证；成熟项目不代表任意最新版适合当前工具链。

## 实施顺序和验收

| 顺序 | 工作 | 完成证据 |
|---|---|---|
| 1 | 裁决/修复 Cookie 标准差异，评估 cookie_store 替换范围 | 合成 RED→GREEN；过期/域/path/删除/同名/路线/持久化/时钟；双来源记录。学校影响另需 WebVPN 实证。 |
| 2 | 替换 CBC/CFB/填充循环 | 冻结来源向量与字节差分、既有业务合同，学校参数不变。 |
| 3 | 官方图片插件、macOS file_selector 与 OHOS 适配评估 | 取消/超限/无效图片/临时清理/Android 回收/账号切换；逐平台原生记录。 |
| 4 | 目录、偏好、网络、OHOS 关于页逐项收敛 | noBackup/私有目录/独立配置/账号隔离/损坏/注销竞态/前后台恢复；OHOS 构建与设备分别记录。 |
| 5 | 删除无需历史数据的成绩迁移链，再评估小通道 | 新账号启动、成绩比较、注销清理；不读取/删除真实旧文件。组件与 multipart 收益明确时再做。 |

## 本轮验证

- 初始工作树干净，just refs 确认 old `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`、buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。
- 临时追加完全合成的 Cookie 测试，执行 `cargo test -p ubaa-core --lib audit_max_age_must_override_past_expires`（后续复现加 --locked）：1 项按预期失败、退出 101，实际空字符串、预期 AUDIT=synthetic。随后逐字节恢复测试文件，未留下失败测试或生产修改。
- 恢复后运行 `cargo test -p ubaa-core --lib session::cookies::tests`（后续复现加 --locked）：既有 4 项通过。这说明当前测试未覆盖该标准边界，不证明缺陷消失。
- 仓库外证据：`~/Library/Application Support/UBAA-private-evidence/dependency-audit-20261007/` 的 cookie-regression.rs、cookie-red.log。上文保留输入及命令供后续 TDD 接续。
- 文档门禁通过：just refs、just layout-check（0 个 baseline 违例）、just check-sensitive（5645 个仓库文件）、git diff --check。未重跑全量构建或真实学校接口，本轮不构成新插件兼容性验收。
