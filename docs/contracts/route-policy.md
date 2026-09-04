# 路由策略合同

状态：确定性实现已完成；当前 Direct/WebVPN/auto 实时证据单独记录在
`docs/migration/status.md`。

`RoutePolicy` 是宿主可选择的策略（`auto`、`direct` 或 `webvpn`）；`ConnectionMode` 是 Core
内部解析出的路线。普通 CLI 帮助不暴露 `--mode`；隐藏覆盖项仅保留给确定性测试、实时验证和
诊断使用。

## 配置

`config.toml` 仅允许所有者读取，不包含账号、密码、Cookie、CAS execution、交互式验证材料、
令牌或响应正文：

```toml
schema_version = 1

[route]
default = "auto"

[route.features]
schedule = "auto"
exam = "auto"
grades = "auto"
classroom = "auto"
spoc = "auto"
judge = "auto"
```

未知字段、功能名、非 `1` 版本以及三个注册值之外的路线值都会被拒绝并返回
`invalid_input`。文件缺失时使用 `auto`。

配置加载/保存拒绝符号链接和非普通文件目标。写入使用同目录唯一临时文件并原子替换；Unix
确定性测试覆盖并发写入以及目录/文件的所有者权限。这些是本地安全证据，不代表实时路线可用。

## 网关可达性

可注入的生产探测器测试到 `gw.buaa.edu.cn:80` 的 TCP 连通性。单个 500 ms 总期限覆盖域名
解析和每个解析地址的连接尝试；每次尝试只能使用剩余预算。任一连接成功即为 `Campus`。
解析失败、无地址、拒绝/不可达连接和普通超时均为 `OffCampus`。只有内部探测失败（包括故意
注入的诊断失败）才是 `Unknown`。

结果由聚合 Core facade 在当前进程内以 single-flight 方式缓存 60 秒；探测器、时钟和缓存行为
均可在测试中注入。CLI 不拥有解析器或缓存。探测器不发送 HTTP/TLS 请求、不读取凭据，也不
硬编码地址或 IP 段。目标、端口和时长来自 `examples/buaa-api/src/utils/net.rs`；单一总预算和
`Unknown` 边界是 UBAA 2 产品约束。

`Campus` 将 `auto` 解析为 Direct；`OffCampus` 将其解析为 WebVPN。`Unknown` 使用功能路由行的 `unknown_default`，并保留在 `RouteDiagnostic` 中。所有标准及扩展功能路由行都使用 `unknown_default=Direct` 的共同映射；历史 Judge 命令曾到达两条路线，因此没有充分证据设置功能专属的 auto 覆盖，但其数量/详情语义差异仍需持续观察。显式路线不回退。

初始矩阵对每个操作都关闭“已有路线回退”和“网络错误回退”。这是有意的：只有冻结实现和实时
证据证明操作幂等且可安全重放后，功能才可在另一条路线重试。修正后的 2026-08-26 实时矩阵
通过了当时的完整聚合，但不足以证明跨路线重放安全，因此不授权任何回退或功能覆盖。

Schema-v6 只读 CLI 成功结果和路线解析后的错误都暴露相同的安全诊断元数据：`routePolicy`、
`networkState`、`initialRoute`、`resolvedRoute`、`usedFallback` 和 `feature`。显式 Direct/WebVPN
策略不会运行网关探测，因此其 `networkState` 为 `unknown`；这表示“未探测或不确定”，不等于
校外。宿主将 facade 返回的不可变诊断直接交给渲染层。Core facade 负责配置加载、探测缓存、
路线解析、就绪预检和业务执行；宿主不能重建或覆盖普通路线选择。隐藏显式模式仍是独立的
诊断/测试入口。隐藏 SPOC/Judge 诊断命令也调用 facade，只暴露 `readonly-features.md` 记录的
安全元数据，不把路线所有权转回 CLI。

## 会话槽位

`session.json` schema 版本 2 在一个文件锁和 revision CAS 下保存相互独立的 `direct` 与 `webvpn`
槽位。聚合协调器拥有完整快照和 revision，私有 runtime 只接收路线本地状态。旧版单路线快照
只迁移到其记录的 `mode` 槽位；Cookie 不会复制到另一槽位。Execution 及其他临时登录状态仅
保留在内存中。

普通 `UbaaClient` 聚合 facade 按 Direct、WebVPN 顺序准备并提交，分别使用私有 `AuthWorkflow`
和 Cookie/runtime 状态。第二条路线失败时返回 `partial` `LoginOutcome` 并保留第一槽位。聚合
JSON 只暴露路线状态和稳定错误字段。交互式验证页面返回 `upstream_changed`，不暴露挑战或
图片。
