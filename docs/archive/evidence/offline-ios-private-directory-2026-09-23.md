# iOS 空环境私有目录修复证据

日期：2026-09-23。P5-B1独立实现；不代表整体目标完成。

## P5-B1 当前产品修复

iPhone17Pro/iOS26.5 模拟器真实进程的 Dart 环境表为空。原实现从 HOME 推导默认路径，预跑因此无法进入首页。新增平台解析器共用初始化 Future，显式绝对目录优先，未配置的iOS从原生 FileManager.applicationSupportDirectory/UBAA取得路径。生产平台能力初始化已调用该入口。两来源对照已先记录到[来源记录](../source-parity-offline-recovery-2026-09-17.md)。

三项行为RED覆盖空环境原生路径、畸形原生路径、显式配置优先及非法相对路径；修复后连同原路径测试4项GREEN。当前`just check`通过（含CLI16项），refs/layout/sensitive通过；完整Flutter1069项（57+69+540+287+23+39+54）和7包分析通过。iOS原生编译成功，新的只读入口使用原生目录成功准备五来源并完成一次进程启动；新增独立合成目录测试与安全材料重开/清理在 iPhone 17 Pro/iOS26.5 模拟器实际运行，两项均通过。

上述门禁日志在仓库外私有目录`~/.local/share/ubaa-private-evidence/offline-home-20260917/p5b1-ios-private-directory-20260923/`，只提交摘要：

| 文件 | SHA-256 |
|---|---|
| `ubaa-p5b1-directory-red.log` | `253561ea4e5f6915b65c4971d8ddf7ff4e8c2e4aa1007230391fcecd1167eb65` |
| `ubaa-p5b1-directory-green.log` | `e27265e2376cf40069b27294a3948d01932b565243a61d2b902113882ccbb693` |
| `ubaa-p5b1-check.log` | `8771932f624785143adcc10a1692f94546c084db44293b1f595b381464aaa000` |
| `ubaa-p5b1-refs.log` | `534334fd86cb3a1e18d73f92643100e7433d193d4d49b1552ec9d7a1dd5639b3` |
| `ubaa-p5b1-layout.log` | `4f00b00a68dd8c9e6e16234e025883051e3585b02de206ac445d05f4d7b39498` |
| `ubaa-p5b1-sensitive.log` | `ec36f703a2e47dc0f2a4adfd741039b3b09e68ccea9e2cd2457dc342557eaa64` |
| `ubaa-p5b1-flutter.log` | `c590ca5f323d21fd3684e3eeac80e00cfd4a51a897a64c3219a9b16983bcdb56` |
| `ubaa-p5b1-build-ios.log` | `f1b29ca8719873338aaa3767539bd92e55844e2978924414cf9aef5df44228b2` |
| `ubaa-p5b1-build-macos.log` | `b9f26d0e69dbbb7a7f6247b5617ee88f7f1bd9acd5daf9718a75ec1bc87c5646` |

## 实施前双来源核对

### P5-B1：iOS 无环境变量时的私有目录（2026-09-23）

原生 iPhone 17 Pro/iOS26.5 预跑中，Dart `_Platform._environmentCache` 是长度0的Map；默认目录仅依赖 HOME，因而无法定位配置库。该观察是本机宿主证据，不是学校协议证据。old固定1f4b8f84的 `shared/.../storage/CredentialStore.kt`、`repository/ScheduleSnapshotStorage.kt` 使用平台 Settings，未定义 Flutter/iOS 文件目录合同；buaa-api固定a63712fa的 `src/store/cred.rs:93/103`、`cookies.rs:157/168` 接收调用者 Path，也未实现 iOS 默认目录。不能借用其明文凭据存储作为降级。

逐操作范围为“取得本 App 私有配置目录”和“初始化宿主平台能力”。两者均不发送学校请求：CAS/bootstrap/service、redirect/final URL、Cookie/session scope、HTTP method/参数/头/body、签名常量与上游DTO均不适用且不改变。仅由 iOS FileManager.applicationSupportDirectory 提供本 App 容器内的 UBAA 路径；Dart 仍校验绝对路径，不猜 HOME、公共 tmp 或工作目录。已显式配置的绝对目录继续优先，原生返回缺失/相对路径保留明确失败，不改加密和账号隔离；两份来源没有对应接口。先以空环境+原生目录的脱敏平台测试复现，再接生产初始化与原生方法，最终在模拟器实际验证。



新增原生目录与安全材料两项运行日志`ubaa-p5b1-native-ios.log`，SHA-256：`a4d97355e20ee63bdc89b016ec53836a1c702632eab5f7e1750dc828ff74ed42`。只操作本轮唯一合成子目录和随机安全材料键，不读取真实账号。
