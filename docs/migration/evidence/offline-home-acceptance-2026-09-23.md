# 离线首页最终验收索引

更新：2026-09-24。活动实施区为 `codex/offline-home-20260917`；目标仍执行中。此表按产品行为核对，历史阶段编号不代表最终通过。旧记录见[实施证据](2026-09-17-offline-home.md)。

## 当前代码审查

- P2-P已提交为`e09e63f4`：Bridge v33、本地缓存错误分列、同客户端分段在线回退和取消保护。该阶段完整Flutter1032项、Rust/CLI、FRB和macOS合成FFI通过。
- P2-Q已通过确定性门禁：实测部分希冀批次把旧范围清空且用占位覆盖旧详情，已按同账号/路线/查询和稳定ID修复，5项新增控制器测试通过；完整Flutter1037项与Rust/CLI门禁通过。接续修改状态文档时缺少版本门禁要求的完整名称，已补回 `Flutter bridge contract v33` 并重新运行完整门禁。
- P3-B补齐明确批量详情的持久保存与离线投影，完整Flutter1044项、Rust/CLI、FRB零漂移和macOS原生合成FFI通过，Bridge v34。
- P2-R明确失效句柄已原位重建，13项新增行为测试、完整Flutter1057项/Rust/CLI及macOS原生FFI通过；等待写意图、后台与迟到结果有确定性覆盖。
- P4-AG已接通未知写结果重启最小核对线索，完整Flutter1066项、Rust/CLI、FRB及macOS/iPad原生合成通过。后续P2-S已复用希冀任务内激活，仍需实际分阶段成本与最终候选双路线及多端测量。

- P5-B1 iOS私有目录与P2-S激活复用已提交；P2-T可见无焦点恢复已完成3项RED→GREEN、当前完整Flutter1072项/7包分析、just check及三端各83项原生合成，见[本轮证据](offline-visible-resume-2026-09-23.md)。

P2-U自动成绩优先级/同学期合并及P4-AH成绩基线加密均已落实。P4-AH完整Flutter1099项、7包分析、just check/CLI16/Bridge140和FRB零漂移通过，三端各100项原生矩阵、macOS原成绩交互12项通过，见[基线证据](offline-grade-baseline-2026-09-23.md)。P4-AI已进一步补齐提醒清理和本地迟到回调，见[清理证据](offline-local-clear-2026-09-23.md)。P5-B2现已将完整首页计时扩大为五个主领域加四个补充来源，并把成绩检查本地收尾、调度等待/运行和阶段成本写入独立入口；全量Flutter1112项、7包分析、生成/敏感门禁和`just check`通过。三端各30次 WebVPN 只读启动和新App WebVPN准备已完成，结果见[测量证据](offline-startup-measurement-2026-09-24.md)；当前合成门禁不替代实体设备、发布模式或 Direct 上游可达性。

## 十五类场景

下列路径是可复跑的确定性入口，不能替代真实App或设备结果。P4-AI后的macOS、iPhone、iPad模拟器原生矩阵各111项通过；真实App和设备差距单独记录。

| 场景 | 当前确定性入口 | 原生/真实App与最终候选状态 |
|---|---|---|
| 1 无网缓存与原位恢复 | App `offline/cache_startup_test.dart`、`query_cache_test.dart`；Host `offline/startup_test.dart` | 三端111项合成通过；三端30次真实App启动均保留缓存并继续只读恢复 |
| 2 恢复挂起/失败且页面可操作 | App `offline/startup_test.dart`、`retry/recovery_test.dart` | 三端111项合成通过；Direct外部SPOC失败时保留准备摘要并停止统计 |
| 3 首帧后恢复与autoLogin边界 | App/Host `offline/startup_test.dart`、`required_recovery_test.dart` | 三端30次首帧后恢复启动中位数/P95均低于200ms |
| 4 长读取让位与零自动写入 | Core `facade/judge_scan.rs`、`judge_scan/online.rs`；App `offline/progressive_controller_test.dart` | 三端111项原生合成含安全批次/写保护；真实写入禁止 |
| 5 跨日/周/学期/假期 | Core `cache/schedule/tests.rs`；App `offline/academic_options_test.dart`、UI `offline/home_cache_test.dart` | 三端原生矩阵包含跨校园午夜；周/学期范围由Core确定性门禁补充 |
| 6 同ID更新与旧课新增 | Core `facade/judge_scan.rs`、持久刷新策略测试 | 本项为当前Core29项专项覆盖，不声称实际学校出现该异常 |
| 7 无序/长周期/未知日期 | 同上及`facade/judge_scan/online.rs` | 不假定上游有序 |
| 8 空集合/部分分页/失败/移除 | Core `facade/home_cache/spoc_scan.rs`、`evaluation_cache/scan.rs`；App P2-Q | 三端原生部分结果/旧内容保留通过，分页算法由Core门禁补充 |
| 9 去重与前后台 | App `offline/resume_test.dart`、`read_scheduler_test.dart`、`retry/business_test.dart`；Host `offline/network/host_test.dart` | 三端111项包含可见恢复/合并/网络触发；真实App窗口恢复已复验 |
| 10 账号/退出/清理/迟到结果 | App `offline/cache_management/`、`judge_fallback/lifecycle_test.dart`；Core `cache/store/rebuild_tests.rs` | 三端111项原生矩阵包含退出/清理/重建/迟到结果 |
| 11 缓存不恢复写资格 | App `offline/startup_test.dart`、`write_cache/`；Bridge write tests | 仅脱敏测试，真实业务写入禁止 |
| 12 写后失败/未知/重启 | App `write_cache/`、唯一WriteCoordinator；Bridge write tests | P4-AG加密最小线索与本机查看/移除已实现，完整确定性门禁通过，原生缓存RPC在macOS/iPad通过；真实写入仍禁止 |
| 13 路线来源与固定写路线 | App `offline/judge_fallback/stability_test.dart`、`scheduled_recovery_test.dart`；Core route/authority tests | 新App WebVPN三端准备与测量通过；Direct因SPOC `network_error`未闭合，不能以旧CLI回退替代 |
| 14 损坏/版本/容量/密钥 | Core `cache/store/`；App `cache_management/`、P2-P；原生`cache_bridge_test.dart` | macOS/iPhone/iPad模拟器原生FFI合成通过，iPhone/iPad安全材料通过；其他平台继续单列 |
| 15 尺寸/主题/文字/草稿/返回 | UI与Flutter宿主导航/golden测试 | 三端111项包含尺寸/放大文字/查询草稿与返回；主题由现有UI门禁补充 |

## 设备与性能

2026-09-24通过Xcode设备清单与adb核对：macOS 26.6.2可用，iOS26.5的iPhone/iPad模拟器可用；无连接的实体手机/平板。[iPhone模拟器原生FFI已通过](offline-ios-native-2026-09-23.md)。本轮 macOS Release、iPhone 17 Pro Debug 模拟器、iPad Pro 13 M5 Debug 模拟器各30次有效样本；模拟器结果明确标注，不能冒充实体设备发布模式性能。

每次分别记录内核进程启动、Dart入口、首页首帧、缓存内容可见、恢复任务启动、首批数据、全部刷新完成；进程启动不从宿主装配计时替代。macOS缓存可见342.145/410.584ms（中位数/P95）达到500ms/1s目标；iPhone为1989.248/2601.328ms，iPad为2112.204/2765.966ms，Debug模拟器未达目标。三端首帧后恢复启动分别为0.384/0.733、12.820/16.993、20.451/39.855ms。后台刷新另列认证、上游、缓存命中、重复请求、调度等待，完整表见[测量证据](offline-startup-measurement-2026-09-24.md)。

## 外部边界

- 新App Direct准备在SPOC阶段因真实上游`unexpected_eof`/`network_error`停止，旧CLI Direct同轮也退出5；须等待上游可达性后重验新分段链路，当前不宣称 Direct 成功。
- 当前未连接实体手机/平板；不以模拟器或构建成功填充实体设备性能。
- Windows/Linux/OHOS缺少当前原生运行证据；历史可编译不等于平台存储与密钥已运行。
- 上述边界不阻断独立实现、合成验证、macOS和可用模拟器测试。整体目标不得标记完成。
