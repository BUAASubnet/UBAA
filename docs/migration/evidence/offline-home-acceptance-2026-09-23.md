# 离线首页最终验收索引

更新：2026-09-23。活动实施区为 `codex/offline-home-20260917`；目标仍执行中。此表按产品行为核对，历史阶段编号不代表最终通过。旧记录见[实施证据](2026-09-17-offline-home.md)。

## 当前代码审查

- P2-P已提交为`e09e63f4`：Bridge v33、本地缓存错误分列、同客户端分段在线回退和取消保护。该阶段完整Flutter1032项、Rust/CLI、FRB和macOS合成FFI通过。
- P2-Q已通过确定性门禁：实测部分希冀批次把旧范围清空且用占位覆盖旧详情，已按同账号/路线/查询和稳定ID修复，5项新增控制器测试通过；完整Flutter1037项与Rust/CLI门禁通过。接续修改状态文档时缺少版本门禁要求的完整名称，已补回 `Flutter bridge contract v33` 并重新运行完整门禁。
- 尚待落实：希冀批量详情在线读取后的持久保存与离线批量投影；客户端失效自动恢复边界逐项审查；长读取/重复认证与缓存命中的实际耗时；最终候选的新App双路线与多端测量。

## 十五类场景

下列路径是可复跑的确定性入口，不能替代真实App或设备结果。最终运行证据和差距将在每项实际执行后补入。

| 场景 | 当前确定性入口 | 原生/真实App与最终候选状态 |
|---|---|---|
| 1 无网缓存与原位恢复 | App `offline/cache_startup_test.dart`、`query_cache_test.dart`；Host `offline/startup_test.dart` | 历史双路线有功能证据，最终候选待复验 |
| 2 恢复挂起/失败且页面可操作 | App `offline/startup_test.dart`、`retry/recovery_test.dart` | 同上 |
| 3 首帧后恢复与autoLogin边界 | App/Host `offline/startup_test.dart`、`required_recovery_test.dart` | 首帧后200ms需要进程测量 |
| 4 长读取让位与零自动写入 | Core `facade/judge_scan.rs`、`judge_scan/online.rs`；App `offline/progressive_controller_test.dart` | 最终原生调度矩阵待执行；真实写入禁止 |
| 5 跨日/周/学期/假期 | Core `cache/schedule/tests.rs`；App `offline/academic_options_test.dart`、UI `offline/home_cache_test.dart` | 多端时间场景待核对 |
| 6 同ID更新与旧课新增 | Core `facade/judge_scan.rs`、持久刷新策略测试 | 最终合成原生覆盖待执行 |
| 7 无序/长周期/未知日期 | 同上及`facade/judge_scan/online.rs` | 不假定上游有序 |
| 8 空集合/部分分页/失败/移除 | Core `facade/home_cache/spoc_scan.rs`、`evaluation_cache/scan.rs`；App P2-Q | 最终原生覆盖待执行 |
| 9 去重与前后台 | App `offline/resume_test.dart`、`read_scheduler_test.dart`、`retry/business_test.dart`；Host `offline/network/host_test.dart` | 最终多端生命周期待执行 |
| 10 账号/退出/清理/迟到结果 | App `offline/cache_management/`、`judge_fallback/lifecycle_test.dart`；Core `cache/store/rebuild_tests.rs` | P2-P原生合成退出/清理/重建通过；多端待验 |
| 11 缓存不恢复写资格 | App `offline/startup_test.dart`、`write_cache/`；Bridge write tests | 仅脱敏测试，真实业务写入禁止 |
| 12 写后失败/未知/重启 | App `write_cache/`、唯一WriteCoordinator；Bridge write tests | 完整未知结果重启矩阵待核对 |
| 13 路线来源与固定写路线 | App `offline/judge_fallback/stability_test.dart`、`scheduled_recovery_test.dart`；Core route/authority tests | 最终双路线App待验 |
| 14 损坏/版本/容量/密钥 | Core `cache/store/`；App `cache_management/`、P2-P；原生`cache_bridge_test.dart` | macOS合成通过；iOS/Android/其他平台运行待验 |
| 15 尺寸/主题/文字/草稿/返回 | UI与Flutter宿主导航/golden测试 | 手机/平板/macOS最终交互矩阵待验 |

## 设备与性能

2026-09-23通过Xcode设备清单与adb核对：macOS 26.6.2可用，iOS26.5的iPhone/iPad模拟器可用；无连接的实体手机/平板。尚无本轮30次进程冷启动样本。模拟器结果将明确标注，不能冒充实体设备发布模式性能。

每次分别记录内核进程启动、首页首帧、缓存内容可见、恢复任务启动、首批数据、全部刷新完成；进程启动不从Dart初始化或宿主装配计时替代。按固定构建/数据规模/磁盘条件统计中位数与P95，异常样本保留。500ms中位数、1s P95及首帧后200ms恢复仍是待验证目标。后台刷新需另列认证、上游、缓存命中、重复请求、调度等待。

## 外部边界

- Direct评教激活近期networkError尚未通过；须最终重验新分段链路并记录稳定分类。
- 当前未连接实体手机/平板；不以模拟器或构建成功填充实体设备性能。
- Windows/Linux/OHOS缺少当前原生运行证据；历史可编译不等于平台存储与密钥已运行。
- 上述边界不阻断独立实现、合成验证、macOS和可用模拟器测试。整体目标不得标记完成。
