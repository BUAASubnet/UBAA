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
解析和每个解析地址的连接尝试；每次尝试只能使用剩余预算。只尝试落在 `10.0.0.0/8` 的 IPv4
地址，其中任一连接成功即为 `Campus`。解析失败、无地址、只解析到其他地址（如代理 fake-ip 的
`198.18.0.0/15`）、拒绝/不可达连接和普通超时均为 `OffCampus`。只有内部探测失败（包括故意
注入的诊断失败）才是 `Unknown`。

结果由聚合 Core facade 在当前进程内以 single-flight 方式缓存 60 秒；探测器、时钟和缓存行为
均可在测试中注入。CLI 不拥有解析器或缓存。探测器不发送 HTTP/TLS 请求、不读取凭据。目标、
端口和时长来自 `examples/buaa-api/src/utils/net.rs`；单一总预算、`Unknown` 边界和
`10.0.0.0/8` 地址过滤是 UBAA 2 产品约束（见 2026-10-28 决策）。

Auto 在校园网使用 Direct；校外首次访问业务域名也使用 Direct。只有读取遇到网络不可达或超时，才在独立 WebVPN 运行时重试一次。SSO、Cookie、业务 Token 和认证状态不跨路线复制。认证、权限、业务拒绝、解析错误及 HTTP 5xx 不触发网络回退。显式 Direct/WebVPN 策略不回退。写入只在发送前选择路线，最终写请求及发送后回读保持已确认路线，不自动重发。

校外 Auto 登录并发认证 Direct 和 WebVPN。至少一条路线就绪即可进入应用，另一路线的验证码失败不强制弹窗阻塞；功能实际需要未就绪路线时交给共同恢复服务。校园网只认证 Direct。已有会话恢复只核验当前所需路线，其他槽位继续保留。

`domain_routes.json` 在配置目录保存域名和过期时间，不包含账号、URL 参数或认证材料。只有 Direct 发生网络错误且同域名 WebVPN 读取成功后，才记录 24 小时的 WebVPN 偏好。期限从这次确认开始，后续使用不延长；到期后重新尝试 Direct。校园网探测成功时清除校外偏好。并行只读实例共享进程内记录，新进程从本机文件加载。保存失败保留当前在线结果。课程、考试和成绩共用教务域名记录，SPOC 与评教共用同域名记录；记录按实际失败主机保存，不能将一次 SSO 故障写成所有业务域名不可达。

业务缓存按账号及精确查询共用，记录保留最近成功的实际来源路线。路线切换不拆分或清空课表、作业等业务内容。缓存不能授予写资格，提交目标与句柄仍绑定实际路线。北航云盘继续使用已有 Direct 协议，WebVPN 文件传输能力尚未验证，不把普通网页回退扩展到对象上传和下载。

Schema-v7 只读 CLI 成功结果和路线解析后的错误都暴露相同的安全诊断元数据：`routePolicy`、
`networkState`、`initialRoute`、`resolvedRoute`、`usedFallback` 和 `feature`。显式 Direct/WebVPN
策略不会运行网关探测，因此其 `networkState` 为 `unknown`；这表示“未探测或不确定”，不等于
校外。宿主将 facade 返回的不可变诊断直接交给渲染层。Core facade 负责配置加载、探测缓存、
路线解析、就绪预检和业务执行；宿主不能重建或覆盖普通路线选择。隐藏显式模式仍是独立的
诊断/测试入口。隐藏 SPOC/Judge 诊断命令也调用 facade，只暴露 `readonly-features.md` 记录的
安全元数据，不把路线所有权转回 CLI。

## 会话槽位

首页本地待办投影复用 App 的路线切换与读取生命周期。路线设置在途时撤销旧投影，收尾后按实际策略重新计算。切换前的签到读取只能恢复只读展示，动作需要切换后的新读取及原在线资格核对，详细规则见 [Bridge v45](flutter-bridge.md#v45首页统一本地投影)。本规则不增加学校请求或改变 Core 的路线选择。

`session.json` schema 版本 2 在一个文件锁和 revision CAS 下保存相互独立的 `direct` 与 `webvpn`
槽位。聚合协调器拥有完整快照和 revision，私有 runtime 只接收路线本地状态。旧版单路线快照
只迁移到其记录的 `mode` 槽位；Cookie 不会复制到另一槽位。Execution 及其他临时登录状态仅
保留在内存中。

普通 `UbaaClient` 聚合 facade 按 Direct、WebVPN 顺序准备并提交，分别使用私有 `AuthWorkflow`
和 Cookie/runtime 状态。第二条路线失败时返回 `partial` `LoginOutcome` 并保留第一槽位。聚合
JSON 只暴露路线状态和稳定错误字段。交互式验证页面返回 `upstream_changed`，不暴露挑战或
图片。
