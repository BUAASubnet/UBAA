# Android 桌面课表组件对照与实施

状态：功能已实现，原生及Launcher实测已取得；整体项目验收仍受桌面锁屏和外部数据条件限制。两冻结来源及提交沿用 references.md：ubaa_old `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`，buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。本轮起点的Flutter Android只有主Activity和选图通道，缺少三种桌面课表Provider；本轮已补齐。

## 依据与行为

已核对旧版 `composeApp/src/androidMain/kotlin/cn/edu/ubaa/widget/` 下 Provider、Renderer、Activity，以及对应 layout/XML；共享 `repository/ScheduleRepository.kt`、`SavedScheduleWeek.kt` 提供持久化与选周规则，`model/dto/Schedule.kt` 提供课程及时间轴。示例的 `api/aas` 有在线课表协议，无Android桌面组件/本地学期库/UI/同周跳转，不借用其字段或网络请求补组件。

| 操作 | CAS/bootstrap/service | 重定向/final URL | Cookie/会话 | 方法/参数 | headers/body | 加密/签名 | DTO/解析 | 缓存/并发 | 错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| 发布本地课表 | 无新增网络 | 不适用 | 绑定当前本地随机账号别名，不导出用户名/秘密 | 只用既有OfflineQueryBackend精确本地读取 | 本机typed MethodChannel，无HTTP | 复用Core已加密课表投影，Android宿主副本另用Keystore AES-GCM，无明文降级 | 学期/周/课程/节次仅既有投影字段；未知时间不补猜 | 完整覆盖学期才发布，scope/epoch改变后旧异步结果拒绝 | 缺数据/系统存储不可用如实空态，不伪装在线成功 |
| 周组件上一周/下一周/本周 | 无 | 不适用 | 账号别名+当前周一anchor绑定选择 | 本机PendingIntent步长-1/0/1，不查询学校 | 不适用 | 不新增上游签名 | 按旧版学期日期选择、周编号排序；保留真实空周 | 同账号同anchor保留选择；换账号/跨周重置 | 首末周禁用越界按钮 |
| 今日/未来三天 | 无 | 不适用 | 同一当前账号 | 本地上海日期起1/3天 | 不适用 | 同上 | 按实际周日期和weekday筛课、按开始时间排序；跨周/学期单独选周 | 使用已发布加密本地投影，系统周期刷新 | 日期未覆盖不展示其他周课程 |
| 点击组件 | 无新增网络 | 不适用 | 核对widget owner与当前本地账号 | 打开相同term/week的离线视图；外部intent不授予登录/写资格 | 不适用 | 不适用 | 原始term/week，不从显示文字重建 | 冷/热启动均消费明确目标；账号错配拒绝 | 不等待在线认证、不发学校写请求 |
| 退出/切账号/清缓存 | 无新增网络 | 不适用 | 旧owner失效 | 本机清理与刷新 | 不适用 | 删除宿主副本，系统密钥失败不降级 | 不保留旧文字/图片 | native scope令牌阻止迟到发布；组件显式清图与文字 | 清理失败如实报告，旧账号不再可见 |

## 实现边界

不新增Bridge/CLI/HTTP协议。共享Dart层只从现有加密缓存抽取只读课表，生产只有Android启用宿主组件；其他平台不增加空壳入口。Android三种Provider沿旧版RemoteViews+Canvas和紧凑布局自适配；周选择与点击保持旧语义。宿主用系统Keystore生成AES-256-GCM密钥，随机IV、完整性校验与私有原子文件；不写日志/明文SharedPreferences中的课程或个人字段。账号以现有随机LocalAccount.id绑定，避免导出真实账号。持久化失效与后台发布的先后顺序由Dart竞态测试和原生Keystore测试验证。

Android实现依据官方[组件指南](https://developer.android.com/develop/ui/views/appwidgets)、[更新机制](https://developer.android.com/develop/ui/views/appwidgets/advanced)与[密码学指南](https://developer.android.com/privacy-and-security/cryptography)。系统API说明只用于宿主接线，不作为学校协议证据。

## 原生启动问题与裁决

正式Android入口实测另发现平台目录解析只为iOS接原生路径，而Android假定HOME存在；无HOME的真实应用进程抛出“应用私有目录暂不可用”，不能由APK构建通过抵消。这是宿主启动问题，不新增学校协议；冻结旧版使用其Android平台持久化宿主，buaa-api无Android应用目录。沿当前iOS的既有 `paths.config` MethodChannel契约，为Android返回系统 `noBackupFilesDir/UBAA`，只创建自身私有目录、不读取或迁移原用户数据；失败继续明确报错，不改用公共目录。空环境行为测试已复现RED。

目录修复后真实Android的Bridge.open仍失败；直接FRB测试取得稳定错误 `internalError/internal could not lock session`。本机锁定Rust1.95标准库 `sys/fs/unix.rs` 证实File::lock的目标列表不含Android，落入Unsupported分支；不是学校协议或账号失败。冻结两来源没有当前Rust双路线会话修订锁实现。仅Android采用fs2的flock封装，保留操作系统排他锁与原进程Mutex，其他平台沿原File::lock；不删除锁、改内存会话或明文降级。对应[标准库问题](https://github.com/rust-lang/rust/issues/148325)及[fs2接口](https://docs.rs/fs2/0.4.3/fs2/trait.FileExt.html)。

真实Android网络准备进一步失败。当前reqwest锁定依赖rustls-platform-verifier 0.7.0，源码Android验证路径要求先登记JVM、Context和ClassLoader；当前宿主未提供初始化，也未打包其Kotlin证书验证组件。遵循锁定依赖[官方Android说明](https://docs.rs/rustls-platform-verifier/0.7.0/rustls_platform_verifier/android/index.html)补宿主JNI初始化及由`cargo metadata --locked`定位的本地AAR，不更换根证书、不关闭TLS。两冻结参考没有Rustls宿主初始化实现，此处不借用学校URL、字段或签名。旧prepareLogin本身准备双槽，试验只判定WebVPN槽，绝不将Direct尝试记为Direct验证通过。

已建立独立Android 36 arm64模拟器，不放入真实账号。投影和详情字段先RED后GREEN；2项原生加密/代次测试、1项渲染与账号错配测试、2项Flutter→原生通道/Core启动测试，以及Launcher真实添加/翻周/同周跳转/课程详情/学期与周选择/滑动/拉伸/跨周三天均取得证据。完整记录见[Android阶段证据](evidence/project-android-widgets-2026-10-03.md)。系统widget不等同macOS按钮验证。
