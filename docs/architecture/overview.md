# 架构概览

当前产品边界是与平台无关的 Rust Core、Rust CLI 宿主和 Flutter/FRB 六平台客户端。`UbaaClient` 是普通聚合 facade，
负责经过校验的路由配置、带缓存的网关可达性探测、独立的 Direct/WebVPN runtime 以及一个
原子双路线会话协调器。`UbaaClient::open` 从一个带 revision 的 schema-v2 快照加载两个槽位，
不会向宿主暴露会话存储。`RouteClient` 是锁定路线的诊断/测试入口，不是普通宿主 API。每次
上游请求前都会应用 Direct 或 WebVPN URL 策略；原始传输既不自动跟随重定向，也不拥有全局
Cookie 存储。

```text
CLI                  Flutter/OHOS
 |                       |
 |                 Dart domain/app/UI
 |                       |
 |                    FRB bridge
 +----------+------------+
            |
       稳定 facade
            |
      认证 + 功能/用户
            |
     私有运行时 + 会话
            |
   上游解析器和已验证 URL
            |
   连接与端口（HTTP、持久化）
```

CLI 与 Rust bridge 的生产业务调用只经 facade；CLI 在自身 `command/backend/execute/io` 边界拥有参数解析、
JSON/human 渲染和退出策略。Dart 与平台宿主只经 bridge 使用 Core，不处理 URL、Cookie、Session、加密或
上游正文；`upstream` 解析/URL 模块为 crate-private。当前公开版本为 CLI JSON schema v9 与
Flutter bridge contract v8；实际 envelope 的 JSON Schema 校验、schema-v9 聚合
登录输出、参数错误 envelope、不支持交互式登录步骤的显式
拒绝、脱敏展示、带 revision 的原子双路线会话、Core 所有的 TCP 路由诊断和非交互式本地验证器
均已实现。Flutter 侧 typed bridge、共享 domain/app/UI、十二项读取页面、十项写入确认和无签名六平台宿主的
确定性证据目前绑定阶段 11H；Phase 11I 的 Ygdk typed 变更已进入工作树但最终门禁待完成。Direct/WebVPN 的真实 Core-live 只读验证、无签名平台构建、
实体设备、签名发布和真实写入是彼此独立的证据层级；当前不包含服务器中继，真实写入仍须逐操作授权。

CLI envelope 的 schema v9 与磁盘 Session 版本相互独立：前者描述 stdout 的封闭公开合同，后者仍是
`session.json` schema v2 双路线快照，`config.toml` 仍为版本 1；本次 CLI 升级不迁移或改写本地持久化。
Flutter bridge contract v8 在 v7 的 Cgyy caller-pinned 取消合同之上，新增 Ygdk typed
`submitEligibility/submitTarget`、完整 typed 请求、安全结果和 caller-pinned 概览/记录回读；同时继续承载
LibBook seat 与 booking 的可空整数状态，以及 typed
`reserveEligibility/reserveTarget` 和 `cancelEligibility/cancelTarget`。取消 action 在本地携带
`id/page/limit` 以固定 prepare、commit 与 readback 的同一页 authority，最终 wire 仍只有 `{id}`；bridge
不读取或改写磁盘 Session 合同。Cgyy 时段的 `reservationStatus` 也为可空整数，只有 Core 明确签发的
`allowed`/`reservationTarget` 才能形成 Flutter action；App、Bridge 与 Core 逐层失败关闭。预约 prepare 与
commit 都 fresh 读取目标资格，最终请求只越过一次 non-idempotent 发送边界；成功结果至多附带安全收据，
发送后无法判定时返回不可重试的 `outcome_unknown`，两者都不携带验证码、完整订单或个人信息。
Cgyy 订单另携带 typed `cancelEligibility/cancelTarget/cancelledTarget`；取消 prepare/commit 均 fresh 复核
同 ID 订单，commit 在 Core 内以单次路线解析绑定同一 runtime 和一次最终发送。成功或结果未知后
只在 intent 原路线读取 0-based 首页列表与同 ID 详情，并仅用本次两个局部 `cancelledTarget` 证明标记已核对。
Ygdk prepare 只保存 fresh overview 签发的 typed target，不上传；commit 由 Core expected-route 原子入口把
单次路线解析、活跃 Session/credential generation、fresh authority、一次 upload 与一次 final 固定在同一
runtime。upload/final 均不自动重试；确定成功和结果未知后只执行 caller-pinned 概览与 records 首页读取，
安全收据仅允许可选正 `recordId`，回读结果不能把 unknown 升级为 success。
