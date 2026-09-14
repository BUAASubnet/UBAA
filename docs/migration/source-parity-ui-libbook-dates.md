# 图书馆日期与时段完整接线：实施前来源核对

2026-09-15。旧版固定为 `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`，示例固定为 `efb7976bf513f38364b88aeb83d704586cff9b2a`；本轮 `just refs` 已通过。本页只记录事实、接口裁决和下一批要求，不代表实现或实窗通过。

## 按钮级缺口

旧版 `LibBookReserveScreen.kt`、`LibBookViewModel.kt` 有日期选择、时段选择和座位查询。当前 `features/libbook.dart` 虽写“请明确选择日期”，却只给日期文本框；`reservation_choices.dart` 的时段操作只回填编号和起止时间，清除日期。完整任务依赖用户手输原始参数，旧版的自然选择流程没有保留。

这不是在 UI 中补一个日期控件就能完整解决的问题。冻结 `LocalLibBookApi.kt:466` 从 `data.date.list` 收集非空日期，却只从原列表第一项取 `times`。当前 `features/libbook/parser.rs:152` 保持相同展平结构，另有顶层兼容回退。因此 `availableDates.first` 不能证明它与公开 `timeSlots` 对应：第一项日期为空、第二项有日期时会错配。现有 `parse_area_detail_for_day` 已证明同一原始条目中的日期和时段可以可靠配对，且重复目标日期会被拒绝；它目前只服务预约的内部 fresh 权威校验。

不得把“最终 prepare 会拒绝错误组合”当作前端组合正确的证据，也不得把同一组时段复制给全部日期。

## 两个冻结来源

- 旧 API：`shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/LibBookApi.kt`。
- 旧 DTO：同根 `model/dto/LibBook.kt`，`LibBookAreaDetailDto`、`LibBookTimeSlotDto`。
- 旧实现：同根 `api/local/LocalLibBookApi.kt` 的 `getAreaInfo`、`requestJson`、`mapAreaDetail`；`getAreaInfo` 原样请求 `Space/map`，只带 `id`。
- 旧测试：`shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalLibBookApiBackendTest.kt` 中 `date.list[].day/times` 的脱敏响应与请求断言；旧 UI 日期、时段和切换父层清理规则见 `LibBookViewModel.kt`。
- 示例：已重新检查 `examples/buaa-api/src/api/` 模块清单，没有 `booking.lib.buaa.edu.cn/v4` 等价实现。该来源对本操作的认证、跳转、会话、请求、编码、加密、DTO、缓存与错误九列均不适用；不能借其它预约业务类比。

## 逐操作九列

新增能力仍读取同一分区详情响应，不增加新的上游地址或日期参数。完整原有协议矩阵见 [图书馆只读查询](source-parity.md#图书馆座位只读查询)，本表逐项说明本次是否变化。

| 操作 | CAS/bootstrap 与 service | 跳转与最终 URL | Cookie/session 范围 | 方法与精确参数 | Header 与正文 | 加密/签名 | DTO/解析 | 缓存/并发 | 错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| 分区日期时段读取 | 仍为 SSO `login`，service 为 `https://booking.lib.buaa.edu.cn/v4/login/cas`；不新增 bootstrap | 原8跳限制与已知主机校验，按当前路线转换后提取 `cas`；不改 | 复用当前账号、路线内图书馆 token；不向 Host 返回 Cookie/token | POST `https://booking.lib.buaa.edu.cn/v4/Space/map`，JSON仅 `{"id": areaId}`；不向上游添加 day/date | 保持 `service.rs` 的 Accept、固定 UA、Authorization、Origin、Referer、XHR 与 JSON；Origin/Referer 沿当前路线 | 只读无 AES；不触碰预约日期派生 AES、IV 或签名 | 从每个原始 `date.list` 条目同时读取 `day`（旧 `date` 兼容）和它自己的 `times`；每个时段保留原 id/start/end，label仅展示；空日期条目不能把时段转移给后一日期；重复日期不得任取first | 使用现有路线和会话生命周期；一次详情响应构造全部日程，不为每个日期重复登录。App 缓存仍由原 query、epoch、generation 管理，隐藏页不自动续读 | 保持信封和认证错误；无可用日期是真实空结果；含糊重复日期为明确上游结构错误。不得将解析/网络错误伪装成空列表 |
| 选择日期/时段后查询座位 | 同上，沿现有已认证图书馆请求器，不新增认证入口 | 同现有 `Space/seat` 路线规则 | 同一账号与路线，禁止跨父分区拼接时段 | 仍POST `Space/seat`：id/day/label_id=[]/start_time/end_time/begdate=""/enddate=""；segment只保留到本次预约action，不增加到该只读请求 | 原JSON与既有请求头不变 | 只读无新增加密 | 日期、时段编号、起止时间必须取自同一个已接受分区日程条目；座位 status/eligibility/target 完全沿现有 Core | 切馆、楼层、分区或日期，立即清旧时段/座位/action；关闭面板不请求；新查询完成前不能用旧结果赋予新日期。迟到响应保护保留 | 空/未知/不完整日程不能提交查询；失败可重试且保留明确输入；最终预约继续走原 prepare→确认→单次 commit→回读 |

## 公开合同裁决

用户当前要求“和旧版逐个按钮级别对比，确保功能全都具备且能正常使用”。此前 P4-D/P5-C 只调整视觉的字段上限已经明确留下本缺口，不能继续用该上限把完整功能目标判为完成。

本专项允许新增经过来源核对的 typed 只读 `facade`/Bridge 能力，并将尚未发布的候选 Bridge 合同统一升级为10；CLI schema10、Session2、配置1与现有写入意图、最终权威和确认流程保持原合同。为了保持 CLI 原有输出，优先增加独立的分区日程 DTO/方法，保留旧 `LibBookAreaDetail` 及其方法的形状与语义。Host 不能直接调用内部 parser、发上游请求或读取 raw JSON。

新 DTO 最少包含分区原始 id/name，以及原顺序的日程列表（每项 day 与该日 timeSlots）。如上游缺少分区id，沿旧解析的请求id回退；不得从馆区名称猜id。新日程方法只新增稳定公开数据，不放宽验证码、Cookie、token、锁码或原始响应边界。

## 行为验证要求

1. 先加两个日期、不同 id/时段的脱敏行为测试并观察失败；另覆首项空日期、重复日期、日期有值但无时段、时段字段不完整。断言来源关联，而非断言某个实现字符串。
2. Mock请求同时固定 `Space/map` 原参数、一次响应构建全部日期及两路线；旧 CLI/旧详情形状继续回归。
3. App投影保留日期与时段的嵌套对应关系；UI日期选择与取消、时段选择/取消、父层变化、关闭再开及返回都要验证。选择第二天必须得到第二天的原id/start/end，不能手工补日期才可用。
4. 保留原手输兼容入口，并让正常楼馆→楼层→分区→日期→时段→查询座位路径无需手输id或日期。只读取，不执行真实预约。
5. 聚焦GREEN后执行敏感检查、`just check`、相关Flutter完整回归与生成绑定一致性检查。最后在实际macOS产物上逐按钮复测；Mock、widget、native合成和真实上游证据分别记账。
