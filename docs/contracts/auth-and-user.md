# 认证与用户合同

状态：确定性实现已完成；修正后的 2026-08-26 HEAD 已通过 Direct 与 WebVPN 实时认证。

`UbaaClient` 是普通的聚合 Core facade。它拥有经过校验的路由配置、围绕
`gw.buaa.edu.cn:80` TCP 探测的进程内 60 秒缓存、相互独立的 Direct/WebVPN runtime、一个
原子双路线会话协调器以及路线专属功能状态。锁定路线客户端仅是内部实现或明确的诊断/测试
入口。聚合登录按 Direct、WebVPN 顺序准备并提交，两条路线各自维护 Cookie 和 CAS 状态，
返回 `all_ready`、`partial` 或 `none_ready`，不会丢弃已成功的会话槽位。`all_ready` 与
`partial` 始终携带就绪路线返回的资料；`none_ready` 不携带资料。失败路线携带一个稳定的
安全错误，就绪路线不携带错误。若上游登录页要求 `config.captcha` 等交互式验证，Core 返回
`upstream_changed`，绝不下载、提示或提交验证材料。Core 会拒绝破坏这些关系的聚合 envelope。

稳定 DTO 和错误码由 `goal.md` 第 6 节定义。每个 CLI 成功、失败、参数错误、聚合认证结果和
隐藏诊断结果都使用 `docs/contracts/cli-json.schema.json` 定义的 schema 版本 3；CLI 不再
输出 schema-v2。这不改变 `config.toml` 或 `session.json` 的版本化迁移读取器，磁盘
`session.json` 仍为 schema v2。密码绝不会
进入持久化会话或普通输出。

公共 facade 暴露认证、标准只读功能和扩展功能，同时将传输、会话存储、单路线客户端及上游解析器保持在 Core 内部。`open` 负责加载配置；每个普通方法都在 Core 内解析策略和路线，并返回安全路线诊断及稳定 DTO。宿主不得检查存储细节、运行探测或自行计算路线。SPOC/Judge 诊断 facade 方法仅供确定性测试和实时验证使用，复用普通读取链，只附带安全的页数/数量元数据。`RouteClient` 仅用于 core-live 和测试，已标记为隐藏文档 API，不属于 SDK 或普通宿主的稳定边界。`auth` 模块负责 CAS 表单、一次性密码风险继续、激活、重定向、不支持交互式验证的拒绝和远程注销；`features/user` 负责用户中心状态/资料及失效分类。各功能模块负责其冻结协议要求的额外 CAS/引导激活，例如本科课表读取前的 AAS 服务激活。`WebVPN` 模式会把所有认证请求和重定向转换到 WebVPN 路线。

每次持久化变更都经过同一个双路线会话协调器，并且只对其持有的 revision 执行一次
compare-exchange。发生冲突时，当前 facade 清除内存 Cookie、待处理登录和路线功能状态，保留
更新后的完整持久化快照，并返回可重试的 `internal_error`。由于冻结实现证明了顺序，远程
注销仍在本地清理前尽力执行；聚合持久化清理只进行一次双槽 CAS，删除前绝不采用更新的
revision。

场馆预约（Cgyy）属于扩展功能，公共读写入口同样由 facade 解析路线并绑定对应 runtime。WebVPN 的 Cgyy 业务登录在 SSO 重定向后按当前 HAR 证据读取 `d.buaa.edu.cn/wengine-vpn/cookie` 的纯文本快照，仅在当前请求内存中取得 `sso_buaa_zhjs_token`，不会把业务令牌写入会话文件。冻结 `ubaa_old` 与固定 `examples/buaa-api` 对该 WebVPN 网关同步没有等价实现；具体证据和边界记录在 `docs/migration/source-parity.md` 与决策日志中。

## CLI 宿主

`ubaa` 二进制暴露认证、用户信息、全部标准只读命令组和扩展只读命令；扩展写命令仍要求显式确认并受真实验证器阻止。普通 `auth login` 会尝试两条路线；隐藏的 `--mode`、`spoc diagnostics` 和 `judge diagnostics` 仅供测试与实时验证，不属于稳定用户命令合同。人类模式可以提示用户名，除非选择 `--password-stdin`，否则使用隐藏密码输入。JSON 模式绝不执行隐藏交互。需要交互式验证的登录页会安全返回 `upstream_changed`；CLI 没有验证码选项、图片路径、提示或挑战持久化能力。

`--json` 对命令成功、命令失败或参数解析失败都只向 stdout 写入一个带版本 envelope；help 和
version 保留普通文本行为。无效参数文本会归约为安全的 `invalid_input` envelope，不回显调用
方提供的值。手机号和证件号在人工或 JSON 渲染前会脱敏。`--config-dir` 选择包含
`config.toml`、`session.json` 及其锁文件的目录；未指定时使用平台用户配置目录。需要认证的
命令在发起网络请求前拒绝缺少本地会话；`auth status` 仍会向用户中心校验已有会话后再报告
成功。

稳定退出类别为：0 表示成功，2 表示输入无效，3 表示认证失败（包括拒绝密码风险继续），5 表示网络/可用性错误，6 表示上游合同或解析变化，7 表示内部失败。`docs/contracts/cli-json.schema.json` 已通过实际序列化的成功和失败 envelope 验证。
