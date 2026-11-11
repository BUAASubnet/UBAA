# 2026-10-28 原生集成测试精简

> 本文是 2026-10-28 的历史快照。后续提交继续收窄原生入口，当前清单以
> [`scripts/integration-tests.json`](../../../scripts/integration-tests.json) 为准；本文中的入口数量和路径不代表当前状态。

## 范围与依据

用户要求检查全部测试并删除不必要的部分。基线 `637d4740`，开始时工作区另有一份来自其他会话、未提交的同类删除，按用户选择先全部恢复，再独立评估。

实测各层成本：Flutter 七包 1481 项测试合计约 2.5 分钟（`ubaa_app` 676 项 28 秒，`ubaa_ui` 454 项 64 秒），Rust 测试以协议、安全与 facade 边界回归为主，均由 `just check` 一次执行。两者已在 [2026-10-15 整理](test-value-cleanup-2026-10-15.md)中去除自证断言和重复执行，本轮未再删除。

成本集中在 `apps/ubaa_flutter/integration_test`：76 个登记入口中只有 5 个进入默认 CI，其余需要设备或模拟器手动运行，且随 UI 改动反复失效（见 [2026-10-27 修复](integration-repair-2026-10-27.md)）。本轮只精简这一层，不改产品代码、包内测试或 Rust 测试。

## 删除项与保留覆盖

入口由 76 个减到 17 个，Dart 文件由 136 个减到 49 个。

| 删除项 | 理由 | 保留覆盖 |
| --- | --- | --- |
| `platform/cache/acceptance_matrix_test.dart`，以及 synthetic 下 `cache/settings`、`schedule/import`、`judge/online`、`grades/cache`、`spoc/progressive`、`evaluation/progressive`、`write/cache`、`app/render` | 只 import 包内测试或其他入口的 `main()` 在设备上重跑，无独有断言 | 被导入的 `ubaa_app`、`ubaa_host`、`ubaa_ui` 包内测试；真实 FFI 缓存由 CI 入口 `synthetic/cache/bridge_test.dart` 保留 |
| synthetic 领域流程：学业（含签到查询）、账号、全域展示、作业、博雅、研讨室、教室、成绩（展示与提醒）、首页（流程与刷新）、图书馆、课表（导航与展示）、写确认、阳光打卡、拍照 UI | 使用合成 backend 的 Widget 流程，按明暗主题和状态矩阵在设备上重复包内场景；不在 CI，最常因导航调整失效 | `apps/ubaa_flutter/test/features/*` 复用同一批 backend 跑导航、读取和写后回读；`ubaa_ui/test/features/*` 覆盖状态、动作资格和表单；`ubaa_app/test/write/*` 覆盖单次写入与 unknown 禁止重发；设备上的端到端接线由 CI 入口 `synthetic/app/flow_test.dart` 保留（登录、全部功能分组、查询、写入次数与回读） |
| 14 个按领域划分的 live 只读入口（学业、账号、博雅、研讨室×2、教室、评教、成绩×2、首页、图书馆、课表×2、SPOC、阳光） | 每个都需要真实账号手动运行；协议真实性按 AGENTS.md 由 CLI 端到端与 `just verify-live mode=direct/webvpn` 验收 | `live/app/readonly_test.dart` 保留生产 App 全域真实只读路径；`live/recovery/startup_test.dart`、`live/schedule/widget_channel_test.dart`、`live/performance/cold_start_driver.dart` 保留恢复、桌面小组件通道和冷启动测量 |
| 16 个领域人工巡检 driver（`manual/*` 除 `app/flow_driver.dart`） | 只为截图巡检启动上述 synthetic 场景，随其删除而失去入口 | `manual/app/flow_driver.dart` 通过 `synthetic/app/flow` 的 `runInspection` 继续提供全应用人工巡检 |
| 28 个仅被上述入口引用的 support、fixture、form 和 scenario 文件 | 删除后无任何引用 | 被 `apps/ubaa_flutter/test` 引用的 backend、data 文件保留 |

保留的 17 个入口：CI 5 个（应用主流程、真实 FFI 缓存、启动锁、网络恢复、平台插件），以及只有真机才能验证的平台能力（安全存储插件、材料与 Linux 专项、关于页安装包版本、照片能力、iPad 旋转、iOS 真实软键盘）、4 个 live 入口和 1 个人工 driver。

## 验证

`just refs`、`just layout-check`、`just check-sensitive`、`just check` 与 `just flutter-check` 通过；七包静态分析无问题，1481 项测试数与删除前一致（领域 60、平台 87、App 676、UI 454、绑定 20、Host 101、官方应用 83），`just integration-check` 确认 17 个入口分类与路径完整。未运行 FRB codegen 检查（无 Rust 或绑定改动），未在设备上执行保留的原生入口，也未运行真实账号验证。
