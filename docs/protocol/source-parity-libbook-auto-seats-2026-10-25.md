# 图书馆预约座位自动加载

## 实施前核对

冻结旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 的 `LibBookApi.kt`、`LocalLibBookApi.kt`、DTO `LibBook.kt`、`LibBookViewModel.kt`、`LibBookReserveScreen.kt` 及 Backend/ScreenLogic 测试确认：进入分区默认首日首时段并自动读取，`visibleLibBookSeats` 仅保留 `isAvailable`，该值来自原始 `status == 1`。当前 UI 将日期时段移入查询面板，且展示全部座位，造成多余操作与不可预约条目。

冻结 `buaa-api` 的 `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`：已检查 `src/api.rs` 与 API 模块目录，无同一图书馆协议；`srs` 为选课接口，不借用其 URL、字段或错误语义。逐日关联继续采用已经核对的 [日期与时段关系](source-parity-ui-libbook-dates.md)，不从旧版展平字段跨日拼接。

| 操作 | CAS/bootstrap 与跳转 | 会话范围 | 方法、参数和编码 | 请求头与加密 | DTO、缓存、并发和错误 |
| --- | --- | --- | --- | --- | --- |
| 楼馆 | SSO service=`https://booking.lib.buaa.edu.cn/v4/login/cas`；已有 8 跳、最终地址和 cas 提取规则 | 原账号和路线内图书馆 token | POST JSON `space/pcTopFor`，`day` | 复用 service.rs 的 Accept、固定 UA、Authorization、Origin、Referer、XHR；只读无 AES/新签名 | 原馆/楼层 id、名称和余量；沿原缓存、代次与错误，不改 CLI 退出语义 |
| 分区 | 同楼馆，保持原引导和跳转 | 同楼馆 | POST JSON `space/pick`，`premisesIds/categoryIds=[]/storeyIds/boutiqueIds=[]/date` | 同楼馆 | 缺省父 id 允许，明确冲突或重复 id 不选；切父项清旧座位；错误可重试 |
| 分区日程 | 同楼馆，保持原引导和跳转 | 同楼馆 | POST JSON `Space/map`，仅 `id` | 同楼馆 | 保留同一 date.list 条目的 day 与 times(id/start/end/label)；自动取首个有效日期及其首个有效时段；重复日期、空时段不猜；隐藏页与迟到响应保护保留 |
| 座位 | 同楼馆，保持原引导和跳转 | 同楼馆 | POST JSON `Space/seat`，`id/day/label_id=[]/start_time/end_time/begdate=""/enddate=""`；segment 只用于本地预约上下文 | 同楼馆 | UI 仅显示原整数 status=1；缓存仍可只读显示，预约继续要求完整 typed allowed action 和匹配上下文；网络错误不伪装为空 |

本轮不改 Core/Bridge 协议与公开 DTO；移除预约页搜索入口，将必要馆/楼层/分区选择留在正文。日期时段默认自动选取；多项时允许正文切换并自动查询。预约仍经 prepare、用户确认、一次 commit 和回读，本轮不提交真实预约。

## 验证

失败反例：原应用测试期待进入 `libbookSeats`，实际停在 `libbookAreaDetail`（`<private-evidence>/legacy-tmp/ubaa-libbook-red.log`）；实现后同一反例转绿。聚焦应用 20 项通过，覆盖自动首日首时段、只显示 status=1、换馆/楼层/分区/日期/时段、明确空结果、失败原参数重试、隐藏页和迟到结果、canonical 预约准备与取消。

覆盖迁移：移除预约页查询面板后，删除 UI `query_test.dart` 的手填馆区与空时段测试；分别由 `flow_test.dart` 的 typed 父项选择和应用 `dates_test.dart` 的不完整日程阻断、完整参数及 canonical 准备覆盖。旧应用测试的面板打开/关闭、手填日期、更多查询、跨分区手填重试和本地搜索场景改为正文自动查询；保留父字段缺省/冲突、换父项清选择、空结果不复活、隐藏页无后台链、迟到响应、同日时段关联与失败原参数重试覆盖。`refresh_continuity_test.dart` 的图书馆手填/键盘场景迁至应用测试的窄屏大字、键盘占位下选择座位并取消准备；研讨室原检查保留。另修正导航辅助函数，使上一轮紧凑侧栏的设置 Tooltip 可被既有详情测试操作。旧合成日程改用生产已在使用的逐日 DTO；地图、预约取消与记录分页原生覆盖保留。

Direct/WebVPN `verify-live feature=libbook` 均通过 prepare/login/status、楼馆、分区、详情、座位和我的预约。该命令验证原协议读取，自动首日时段与 UI 过滤另由应用测试及实际窗口检查。没有提交真实预约。验证收尾：七包分别完成静态分析与测试，计 1371 项（Domain 53、Platform 87、App 660、UI 377、Bindings 20、Host 101、Flutter App 73）。最终相关 UI 30 项复核通过。macOS 合成明暗 24 项通过，包含地图、父项切换、加载/失败、长名称、大量座位及准备后取消；没有真实提交。正式 Debug 构建、产物结构和签名权限通过，实际窗口验证进入原分区自动出现空闲座位、切换另一分区自动刷新、返回原分区；未打开查询面板或选择真实座位。

`just check` 在本轮实现检查点通过，`just refs` 通过。末次全工作区 `layout-check` 遇到并行 iHome 新文件引起的 domain/facade/bridge-api 目录登记违例；一次 Bindings 分析也遇到并行生成过程的 ihome.dart 暂未落盘，文件生成后复跑该包通过。iHome 修改与新增来源记录不纳入图书馆提交，整体工作区门禁仍由对应新增功能任务收尾。
