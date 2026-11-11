# 图书馆座位

本文件收录图书馆座位查询、日期时段、自动加载与预约取消的来源对照。

## 逐操作基线矩阵

以下矩阵沿用[逐操作历史矩阵](general.md#逐操作历史矩阵)的取证说明：原始取证版本、换钉后的适用方式和重新核对要求以该节为准。

### 图书馆座位只读查询

2026-10-25 汇总与座位同步刷新、全页手势范围见[刷新记录](../../archive/history/refresh-2026-10-25.md)。

2026-10-25 自动加载及可预约座位展示核对见[本轮来源记录](#图书馆预约座位自动加载)。

2026-09-15完整功能补齐的实施前对照与公开合同裁决见[日期与时段关系](#图书馆日期与时段完整接线实施前来源核对)；下面保留原有协议基线。

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：**业务基址 `https://booking.lib.buaa.edu.cn/v4/`；**示例：**无等价模块；**决定：**只采用冻结旧版。 | **旧版：**SSO 最多 8 跳，从最终 URL、Location 或 fragment 提取 `cas`；**决定：**手动跟随并限制已知主机。 | **旧版：**独立图书馆 token，不复用教务 Cookie；**决定：**路线内存储，禁止持久化令牌。 | **旧版：**所有查询 POST JSON：`space/pcTopFor`、`space/pick`、`Space/map`、`Space/seat`、`member/seat`，参数含日期、区域、时段和分页；**决定：**保持原始 JSON 字段。 | **旧版：**`Accept`、固定 `User-Agent`、Authorization、Origin、Referer 与 `X-Requested-With`；**决定：**逐项保持冻结值，Origin/Referer 按所选路线转换，不输出 token。 | **旧版：**AES 仅用于预约写操作；**决定：**只读查询不引入加密。 | **旧版：**图书馆、楼层、区域、时段、座位及预约分页 DTO；座位 `status == 1` 表示可用。 | **旧版：**token 按用户缓存，失效后清理并重试一次；**决定：**路线隔离状态。 | **旧版：**业务 code 0/1 成功，其他映射错误；**决定：**区分上游错误、未找到和座位不可用，不伪造空结果。 |

当前实现证据：UBAA2 Core 已完成五类图书馆只读查询及独立路线内 token 会话，CLI 已接入五个对应子命令，并有 Mock/CAS 回归测试。预约、取消现已接入 Core/CLI，并以冻结 golden 向量覆盖日期派生 AES-128-CBC、PKCS#7 和固定 IV；CLI 写入口要求显式确认，verify-live 永不调用。`examples/buaa-api` 没有等价实现。历史 Direct 与 WebVPN `feature=libbook` 只读验证曾成功并返回 2 个馆区；分区详情的当前实时验收必须在每日 08:30–23:00（`Asia/Shanghai`）开放窗口内进行，非营业时间的 `code=500` 不作为协议变化结论。

2026-11-07 来源对照补充：冻结旧版 `LocalLibBookApi` 对非 0/1 业务码仅作通用异常映射，没有非预约时段专用错误或时段文案；固定 `examples/buaa-api` 没有图书馆等价模块，相关协议字段和状态码不适用。历史脱敏实时证据记录 HTTP 200、业务 `code=500` 且无 `data` 的非开放时段形态。本次用户说明将当前可展示时段限定为 `8:00–20:00`，该数字不是冻结来源推导值。Core 仅将 `code=500` 且 `data` 缺失或为 null 的图书馆响应映射为 `business_unavailable`，返回 `retryable=true` 与固定文案“当前不在预约时段（8:00–20:00）”；其他非 0/1 响应继续按原错误语义处理。该读取错误允许稍后刷新，不发起真实学校请求。

补充证据（`24acd8b`）：`crates/ubaa_core/tests/libbook.rs` 的 Mock 端到端测试按冻结顺序调用预约确认和取消接口，断言 `aesjson` 非空、取消请求携带预约标识，并复用路线内 bearer 会话。测试仅使用合成会话与脱敏响应，不产生真实预约或取消。

## 专项记录

### 图书馆预约座位自动加载

#### 实施前核对

冻结旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 的 `LibBookApi.kt`、`LocalLibBookApi.kt`、DTO `LibBook.kt`、`LibBookViewModel.kt`、`LibBookReserveScreen.kt` 及 Backend/ScreenLogic 测试确认：进入分区默认首日首时段并自动读取，`visibleLibBookSeats` 仅保留 `isAvailable`，该值来自原始 `status == 1`。当前 UI 将日期时段移入查询面板，且展示全部座位，造成多余操作与不可预约条目。

冻结 `buaa-api` 的 `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`：已检查 `src/api.rs` 与 API 模块目录，无同一图书馆协议；`srs` 为选课接口，不借用其 URL、字段或错误语义。逐日关联继续采用已经核对的 [日期与时段关系](#图书馆日期与时段完整接线实施前来源核对)，不从旧版展平字段跨日拼接。

| 操作 | CAS/bootstrap 与跳转 | 会话范围 | 方法、参数和编码 | 请求头与加密 | DTO、缓存、并发和错误 |
| --- | --- | --- | --- | --- | --- |
| 楼馆 | SSO service=`https://booking.lib.buaa.edu.cn/v4/login/cas`；已有 8 跳、最终地址和 cas 提取规则 | 原账号和路线内图书馆 token | POST JSON `space/pcTopFor`，`day` | 复用 service.rs 的 Accept、固定 UA、Authorization、Origin、Referer、XHR；只读无 AES/新签名 | 原馆/楼层 id、名称和余量；沿原缓存、代次与错误，不改 CLI 退出语义 |
| 分区 | 同楼馆，保持原引导和跳转 | 同楼馆 | POST JSON `space/pick`，`premisesIds/categoryIds=[]/storeyIds/boutiqueIds=[]/date` | 同楼馆 | 缺省父 id 允许，明确冲突或重复 id 不选；切父项清旧座位；错误可重试 |
| 分区日程 | 同楼馆，保持原引导和跳转 | 同楼馆 | POST JSON `Space/map`，仅 `id` | 同楼馆 | 保留同一 date.list 条目的 day 与 times(id/start/end/label)；自动取首个有效日期及其首个有效时段；重复日期、空时段不猜；隐藏页与迟到响应保护保留 |
| 座位 | 同楼馆，保持原引导和跳转 | 同楼馆 | POST JSON `Space/seat`，`id/day/label_id=[]/start_time/end_time/begdate=""/enddate=""`；segment 只用于本地预约上下文 | 同楼馆 | UI 仅显示原整数 status=1；缓存仍可只读显示，预约继续要求完整 typed allowed action 和匹配上下文；网络错误不伪装为空 |

本轮不改 Core/Bridge 协议与公开 DTO；移除预约页搜索入口，将必要馆/楼层/分区选择留在正文。日期时段默认自动选取；多项时允许正文切换并自动查询。预约仍经 prepare、用户确认、一次 commit 和回读，本轮不提交真实预约。

#### 验证

失败反例：原应用测试期待进入 `libbookSeats`，实际停在 `libbookAreaDetail`（`<private-evidence>/legacy-tmp/ubaa-libbook-red.log`）；实现后同一反例转绿。聚焦应用 20 项通过，覆盖自动首日首时段、只显示 status=1、换馆/楼层/分区/日期/时段、明确空结果、失败原参数重试、隐藏页和迟到结果、canonical 预约准备与取消。

覆盖迁移：移除预约页查询面板后，删除 UI `query_test.dart` 的手填馆区与空时段测试；分别由 `flow_test.dart` 的 typed 父项选择和应用 `dates_test.dart` 的不完整日程阻断、完整参数及 canonical 准备覆盖。旧应用测试的面板打开/关闭、手填日期、更多查询、跨分区手填重试和本地搜索场景改为正文自动查询；保留父字段缺省/冲突、换父项清选择、空结果不复活、隐藏页无后台链、迟到响应、同日时段关联与失败原参数重试覆盖。`refresh_continuity_test.dart` 的图书馆手填/键盘场景迁至应用测试的窄屏大字、键盘占位下选择座位并取消准备；研讨室原检查保留。另修正导航辅助函数，使上一轮紧凑侧栏的设置 Tooltip 可被既有详情测试操作。旧合成日程改用生产已在使用的逐日 DTO；地图、预约取消与记录分页原生覆盖保留。

Direct/WebVPN `verify-live feature=libbook` 均通过 prepare/login/status、楼馆、分区、详情、座位和我的预约。该命令验证原协议读取，自动首日时段与 UI 过滤另由应用测试及实际窗口检查。没有提交真实预约。验证收尾：七包分别完成静态分析与测试，计 1371 项（Domain 53、Platform 87、App 660、UI 377、Bindings 20、Host 101、Flutter App 73）。最终相关 UI 30 项复核通过。macOS 合成明暗 24 项通过，包含地图、父项切换、加载/失败、长名称、大量座位及准备后取消；没有真实提交。正式 Debug 构建、产物结构和签名权限通过，实际窗口验证进入原分区自动出现空闲座位、切换另一分区自动刷新、返回原分区；未打开查询面板或选择真实座位。

`just check` 在本轮实现检查点通过，`just refs` 通过。末次全工作区 `layout-check` 遇到并行 iHome 新文件引起的 domain/facade/bridge-api 目录登记违例；一次 Bindings 分析也遇到并行生成过程的 ihome.dart 暂未落盘，文件生成后复跑该包通过。iHome 修改与新增来源记录不纳入图书馆提交，整体工作区门禁仍由对应新增功能任务收尾。

### 图书馆日期与时段完整接线：实施前来源核对

2026-09-15。旧版固定为 `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`，示例固定为 `efb7976bf513f38364b88aeb83d704586cff9b2a`；本轮 `just refs` 已通过。前四节是在实施前记录的来源事实与接口裁决；下方另列本批实现边界。确定性测试不代表实窗或真实上游通过。

#### 按钮级缺口

旧版 `LibBookViewModel.kt:340–359` 从 `availableDates.firstOrNull` 与 `timeSlots.firstOrNull` 初始化日期和时段，然后自动读取座位；`LibBookReserveScreen.kt:328` 只展示 `selectedDay`，没有已证明的跨日日期选择按钮。当前 `features/libbook.dart` 虽写“请明确选择日期”，却只给日期文本框；`reservation_content.dart` 的时段操作只回填编号和起止时间，清除日期，正常路径仍依赖用户手输原始参数。本轮新增显式日期选择、同日时段关联和明确查询按钮，是根据同一 `Space/map` 原始数据做的必要优化，不声称冻结旧 UI 已具备完整跨日选择。

这不是在 UI 中补一个日期控件就能完整解决的问题。冻结 `LocalLibBookApi.kt:466` 从 `data.date.list` 收集非空日期，却只从原列表第一项取 `times`。当前 `features/libbook/parser.rs:152` 保持相同展平结构，另有顶层兼容回退。因此 `availableDates.first` 不能证明它与公开 `timeSlots` 对应：第一项日期为空、第二项有日期时会错配。现有 `parse_area_detail_for_day` 已证明同一原始条目中的日期和时段可以可靠配对，且重复目标日期会被拒绝；它目前只服务预约的内部 fresh 权威校验。

不得把“最终 prepare 会拒绝错误组合”当作前端组合正确的证据，也不得把同一组时段复制给全部日期。

#### 两个冻结来源

- 旧 API：`shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/LibBookApi.kt`。
- 旧 DTO：同根 `model/dto/LibBook.kt`，`LibBookAreaDetailDto`、`LibBookTimeSlotDto`。
- 旧实现：同根 `api/local/LocalLibBookApi.kt` 的 `getAreaInfo`、`requestJson`、`mapAreaDetail`；`getAreaInfo` 原样请求 `Space/map`，只带 `id`。
- 旧测试：`shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalLibBookApiBackendTest.kt` 中 `date.list[].day/times` 的脱敏响应与请求断言；旧 UI 日期、时段和切换父层清理规则见 `LibBookViewModel.kt`。
- 示例：已重新检查 `examples/buaa-api/src/api/` 模块清单，没有 `booking.lib.buaa.edu.cn/v4` 等价实现。该来源对本操作的认证、跳转、会话、请求、编码、加密、DTO、缓存与错误九列均不适用；不能借其它预约业务类比。

#### 逐操作九列

新增能力仍读取同一分区详情响应，不增加新的上游地址或日期参数。完整原有协议矩阵见 [图书馆只读查询](#图书馆座位只读查询)，本表逐项说明本次是否变化。

| 操作 | CAS/bootstrap 与 service | 跳转与最终 URL | Cookie/session 范围 | 方法与精确参数 | Header 与正文 | 加密/签名 | DTO/解析 | 缓存/并发 | 错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| 分区日期时段读取 | 仍为 SSO `login`，service 为 `https://booking.lib.buaa.edu.cn/v4/login/cas`；不新增 bootstrap | 原8跳限制与已知主机校验，按当前路线转换后提取 `cas`；不改 | 复用当前账号、路线内图书馆 token；不向 Host 返回 Cookie/token | POST `https://booking.lib.buaa.edu.cn/v4/Space/map`，JSON仅 `{"id": areaId}`；不向上游添加 day/date | 保持 `service.rs` 的 Accept、固定 UA、Authorization、Origin、Referer、XHR 与 JSON；Origin/Referer 沿当前路线 | 只读无 AES；不触碰预约日期派生 AES、IV 或签名 | 从每个原始 `date.list` 条目同时读取 `day`（旧 `date` 兼容）和它自己的 `times`；每个时段保留原 id/start/end，label仅展示；空日期条目不能把时段转移给后一日期；重复日期不得任取first | 使用现有路线和会话生命周期；一次详情响应构造全部日程，不为每个日期重复登录。App 缓存仍由原 query、epoch、generation 管理，隐藏页不自动续读 | 保持信封和认证错误；无可用日期是真实空结果；含糊重复日期为明确上游结构错误。不得将解析/网络错误伪装成空列表 |
| 选择日期/时段后查询座位 | 同上，沿现有已认证图书馆请求器，不新增认证入口 | 同现有 `Space/seat` 路线规则 | 同一账号与路线，禁止跨父分区拼接时段 | 仍POST `Space/seat`：id/day/label_id=[]/start_time/end_time/begdate=""/enddate=""；segment只保留到本次预约action，不增加到该只读请求 | 原JSON与既有请求头不变 | 只读无新增加密 | 日期、时段编号、起止时间必须取自同一个已接受分区日程条目；座位 status/eligibility/target 完全沿现有 Core | 切馆、楼层、分区或日期，立即清旧时段/座位/action；关闭面板不请求；新查询完成前不能用旧结果赋予新日期。迟到响应保护保留 | 空/未知/不完整日程不能提交查询；失败可重试且保留明确输入；最终预约继续走原 prepare→确认→单次 commit→回读 |

#### 公开合同裁决

用户当前要求“和旧版逐个按钮级别对比，确保功能全都具备且能正常使用”。此前 P4-D/P5-C 只调整视觉的字段上限已经明确留下本缺口，不能继续用该上限把完整功能目标判为完成。

本专项允许新增经过来源核对的 typed 只读 `facade`/Bridge 能力，并将尚未发布的候选 Bridge 合同统一升级为10；CLI schema10、Session2、配置1与现有写入意图、最终权威和确认流程保持原合同。为了保持 CLI 原有输出，优先增加独立的分区日程 DTO/方法，保留旧 `LibBookAreaDetail` 及其方法的形状与语义。Host 不能直接调用内部 parser、发上游请求或读取 raw JSON。

新 DTO 最少包含分区原始 id/name，以及原顺序的日程列表（每项 day 与该日 timeSlots）。如上游缺少分区id，沿旧解析的请求id回退；不得从馆区名称猜id。新日程方法只新增稳定公开数据，不放宽验证码、Cookie、token、锁码或原始响应边界。

#### 行为验证要求

1. 先加两个日期、不同 id/时段的脱敏行为测试并观察失败；另覆首项空日期、重复日期、日期有值但无时段、时段字段不完整。断言来源关联，而非断言某个实现字符串。
2. Mock请求同时固定 `Space/map` 原参数、一次响应构建全部日期及两路线；旧 CLI/旧详情形状继续回归。
3. App投影保留日期与时段的嵌套对应关系；UI日期选择与取消、时段选择/取消、父层变化、关闭再开及返回都要验证。选择第二天必须得到第二天的原id/start/end，不能手工补日期才可用。
4. 保留原手输兼容入口，并让正常楼馆→楼层→分区→日期→时段→查询座位路径无需手输id或日期。只读取，不执行真实预约。
5. 聚焦GREEN后执行敏感检查、`just check`、相关Flutter完整回归与生成绑定一致性检查。最后在实际macOS产物上逐按钮复测；Mock、widget、native合成和真实上游证据分别记账。

#### 本批实现与兼容边界

- Core 新增 `LibBookAreaSchedule {id,name,days}` 和 `LibBookDaySchedule {day,timeSlots}`，`RouteClient` 与 `UbaaClient` 新增 `libbook_area_schedule`。日程读取直接复用现有 `request_json` 的 `Space/map` 路径及原 `id` 正文；不从旧展平 DTO 重建关联，也不更改最终预约的 `parse_area_detail_for_day`。
- Bridge 新增 `libbookAreaSchedule`、两项 DTO 与路线结果；候选合同统一为10。App 只读取此 typed 方法并生成不可变的 `LibbookAreaSchedulePresentation`/`LibbookDaySchedulePresentation` 嵌套列表，保留原日期顺序及原时段 id/start/end。字段与 label 不反向生成写入目标。
- 缺少日期列表、空列表或日期条目没有时段时如实返回空日程/空时段。空日期条目被跳过，其时段不转移；`day` 为空时仍支持同条目的旧 `date` 字段。重复日期、畸形列表、非对象时段或 id/start/end 为空时明确返回 `upstream_changed`；错误信封保留原错误类别。只有旧顶层 `availableDates/timeSlots` 的响应返回空日程，不猜关联。
- 正常页面在楼馆、楼层、分区后提供日期和时段选择及清除按钮；选项仅来自已接受、分区 ID 一致的日程。只有明确点击“查询座位”才读取座位；切父层、日期、时段或清除选择会立即隐藏旧座位并取消原选择。关闭面板保留草稿，不发请求。新日程缺失的旧合成 presentation 继续使用受限的旧入口，提示日期关联未知；“更多查询”手输入口保留。
- 仍拒绝明确冲突的父字段，缺省父字段沿本次查询所属的原始唯一分区 ID 处理。保持 query、epoch、generation 与账号隔离；座位动作还必须匹配当前读取的分区、日期、时段与起止时间。原 `LibbookReserveAction`、资格、canonical target、prepare→确认→单次 commit→既定回读不变。
- 原 Core/Bridge `LibBookAreaDetail` 与旧读取方法继续保持 `id/name/availableDates/timeSlots`，CLI 仍使用旧方法，schema10 不加字段；Session2、配置1不变。图书馆专用 `live_readonly_test.dart` 仅同步新类型和自然选择步骤，本批没有执行此驱动、native 构建、生产只读或真实写入。

可编译 RED 分别记录了旧公开详情不能表达逐日关联/接受重复日期、旧 App 投影不含嵌套关联、组件缺少日期选择。随后独立新 API 的 GREEN 覆盖同响应两个日期的不同原时段、空首日期、重复日期、空/畸形时段、双路线原请求、旧详情形状、App 投影和实际组件选择/清除/切父项/返回与迟到结果。完整命令与退出码保存在本机仓库外私有证据目录 `macos-ui-20260915/libbook-dates/`；最终候选与 macOS 实操仍由主线分别验收。
