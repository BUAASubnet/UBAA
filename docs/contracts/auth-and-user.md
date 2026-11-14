# 认证与用户合同

本合同供修改登录、会话恢复、用户资料和 CLI 认证输出的开发者使用，定义 Core facade 的认证行为、CLI JSON envelope 与退出码、交互验证码和学业身份规则。

## 共同凭据与恢复目标

GUI 与 App 命令模式共用凭据策略、会话及无感恢复，同机退出或切号时协调旧任务；Linux 另覆盖 SSH 无图形会话。实施顺序见[共享服务计划](../design/desktop-shared-state.md)。旧独立 CLI 账号方案不再扩展。

会话过期后的恢复不放宽主动退出、自动登录设置、验证码和学校写入规则，下文的协议与输出合同继续有效。

## 聚合认证

`UbaaClient` 是普通的聚合 Core facade，拥有：

- 经过校验的路由配置；
- 围绕 `gw.buaa.edu.cn:80` TCP 探测的进程内 60 秒缓存；
- 相互独立的 Direct/WebVPN runtime；
- 一个原子双路线会话协调器，以及路线专属功能状态。

锁定路线客户端仅是内部实现或明确的诊断/测试入口。

聚合登录按 Direct、WebVPN 顺序准备并提交，两条路线各自维护 Cookie 和 CAS 状态，返回 `all_ready`、`partial` 或 `none_ready`，不丢弃已成功的会话槽位：

- `all_ready` 与 `partial` 始终携带就绪路线返回的资料；`none_ready` 不携带资料。
- 失败路线携带一个稳定的安全错误，就绪路线不携带错误。
- 上游登录页要求 `config.captcha` 等交互式验证时，普通非交互 Core 接口返回 `upstream_changed`，不下载、提示或提交验证材料。
- Core 拒绝破坏这些关系的聚合 envelope。

## CLI JSON envelope 版本

稳定 DTO、错误码及输出关系由本文与 [CLI JSON Schema](cli-json.schema.json)定义。每个 CLI 成功、失败、参数错误、聚合认证结果和隐藏诊断结果都使用 `docs/contracts/cli-json.schema.json` 定义的当前 CLI JSON schema v17；CLI 不再输出 schema-v9 或更早 envelope。

v17 允许网络流量的 `remainingExcludesPackages=false`，免费剩余包含套餐可用流量。

v16 增加更新门控错误：评教批次发出部分课程后遇到门控时，保留已发课程结果，将未发出的后缀标为 `unattempted`。

CLI envelope 版本不改变 `config.toml` 或 `session.json` 的版本化迁移读取器，磁盘 `session.json` 仍为 schema v2。密码不进入持久化会话或普通输出。早期 schema 版本承载的内容见文末[版本历史](#版本历史)。

## facade 边界与认证流程


公共 facade 暴露认证、标准只读功能和扩展功能，传输、会话存储、单路线客户端及上游解析器保持在 Core 内部：

- `open` 负责加载配置；每个普通方法都在 Core 内解析策略和路线，并返回安全路线诊断及稳定 DTO。
- 宿主不检查存储细节、不运行探测，也不自行计算路线。
- SPOC/Judge 诊断 facade 方法仅供确定性测试和实时验证使用，复用普通读取链，只附带安全的页数/数量元数据。
- `RouteClient` 仅用于 core-live 和测试，已标记为隐藏文档 API，不属于 SDK 或普通宿主的稳定边界。

模块分工：

- `auth` 模块负责 CAS 表单、一次性密码风险继续、SSO 取票验票、网关激活、重定向和注销。
- `features/user` 负责按需读取 UC 资料。
- 各功能模块负责其冻结协议要求的额外 CAS/引导激活，例如本科课表读取前的 AAS 服务激活。
- 主会话状态由 SSO 独立验票确认。`WebVPN` 模式把所有认证请求和重定向转换到 WebVPN 路线。

认证跳转与验票：

- 认证及业务跳转先还原 WebVPN 包装并核对各自的上游白名单，只将精确 SSO 主机的默认 HTTP 端口升级到 HTTPS，再按固定路线包装。嵌套 service 编码保持。
- SSO 302、门户 HTML 200 都不代表登录完成。
- 主登录使用既有教务 service 取得一次性票据，再向 SSO `/serviceValidate` 验证账号，不请求 UC 或教务落地页。
- WebVPN 另外使用网关自己的 CAS service 建立网关会话，验证网关根地址后再保存该路线。
- UC 只在读取资料时激活，UC 失败不直接撤销 SSO 会话。
- 本科教务还需 homeapp currentUser 返回字符串 `code="0"` 与有效 `datas.userId`，不增加学校写入或自动重放凭据。

持久化冲突与注销：

- 每次持久化变更都经过同一个双路线会话协调器，并且只对其持有的 revision 执行一次 compare-exchange。
- 发生冲突时，当前 facade 清除内存 Cookie、待处理登录和路线功能状态，保留更新后的完整持久化快照，并返回可重试的 `internal_error`。
- 由于冻结实现证明了顺序，远程注销在本地清理前尽力执行；聚合持久化清理只进行一次双槽 CAS，删除前不采用更新的 revision。

研讨室预约（Cgyy）属于扩展功能，公共读写入口同样由 facade 解析路线并绑定对应 runtime。WebVPN 的 Cgyy 业务登录在 SSO 重定向后按当前 HAR 证据读取 `d.buaa.edu.cn/wengine-vpn/cookie` 的纯文本快照，仅在当前请求内存中取得 `sso_buaa_zhjs_token`，不会把业务令牌写入会话文件。冻结 `ubaa_old` 与固定 `examples/buaa-api` 对该 WebVPN 网关同步没有等价实现；具体证据和边界记录在[来源对照](../protocol/README.md)与[决策记录](../protocol/decision-log.md)中。

CLI JSON Schema 的标识为 `urn:ubaa:cli:json:schema:16`，消费者从受跟踪的 [Schema 文件](cli-json.schema.json)加载定义。URN 表示该版本的身份，不是网络下载地址；Schema 内的局部 `$ref` 继续在同一文件解析。

## CLI 宿主

`ubaa-cli` 二进制暴露认证、用户信息、全部标准只读命令组和扩展只读命令；扩展写命令仍要求显式确认并受真实验证器阻止。普通 `auth login` 会尝试两条路线；隐藏的 `--mode`、`spoc diagnostics` 和 `judge diagnostics` 仅供测试与实时验证，不属于稳定用户命令合同。人类模式可以提示用户名，除非选择 `--password-stdin`，否则使用隐藏密码输入。JSON 模式绝不执行隐藏交互。需要交互式验证的登录页会安全返回 `upstream_changed`；CLI 没有验证码选项、图片路径、提示或挑战持久化能力。

`--json` 对命令成功、命令失败或参数解析失败都只向 stdout 写入一个带版本 envelope；help 和
version 保留普通文本行为。无效参数文本会归约为安全的 `invalid_input` envelope，不回显调用
方提供的值。手机号和证件号在人工或 JSON 渲染前会脱敏。`--config-dir` 选择包含
`config.toml`、`session.json` 及其锁文件的目录；未指定时使用平台用户配置目录。需要认证的
命令在发起网络请求前拒绝缺少本地会话；`auth status` 向 SSO 取得新票据并验证身份后再报告成功。

稳定退出类别：

| 退出码 | 含义 |
|---|---|
| 0 | 调用成功完成 |
| 2 | 输入无效 |
| 3 | 认证失败（包括拒绝密码风险继续） |
| 5 | 网络/可用性错误；发送后不确定结果 `outcome_unknown` 也使用 5 |
| 6 | 上游合同或解析变化 |
| 7 | 内部失败 |
| 8 | 更新门控生效（`update_required`，`kind=upstream`，`retryable=false`） |

课堂签到的确定业务拒绝以外层 `ok=true`、退出码 0 和内层 `data.success=false` 表达；调用方需要同时检查 `data.success`，不能只凭退出码认定签到成功。`docs/contracts/cli-json.schema.json` 已通过实际 dispatcher 序列化的签到 true/false/unknown、其它成功和失败 envelope 验证。

本机日程通过 App 命令入口使用同一安全索引、随机别名和资料空间，不创建学校客户端。普通显式聚合登录在认证完成后，以 Core 不可构造的身份能力核实并一次性消费登记。`agendaRegistration` 与原有认证 `ok/data/error` 分开报告，登记失败保持认证结果并返回非零退出码。固定路线诊断登录不产生登记。Core 身份能力绑定双路线认证代次，新交互意图或依赖会话清理立即使旧能力失效，正常活动刷新和临时错误保持原行为。共享身份、缓存缺口与本机错误码见[日程命令合同](agenda.md#app-日程命令)。

## 手动交互验证码

Flutter 手动登录、已授权的自动登录与会话恢复使用 Bridge v54 起的静默验证码流程：

- 本地模型最多尝试三次，耗尽后提供当前路线的受限像素图、答案提交、刷新与取消。
- 服务器 challenge id、execution、URL、Cookie 及 token 只留在 Core。
- 句柄绑定实例、账号、路线、会话修订和单调期限，直接提交当前取图页的 execution，拒绝后使用新挑战。协议依据见[来源裁决](../protocol/decision-log.md#2026-11-06sso-图像验证码按当前准备状态直接提交)。
- 旧非交互 Core-live/CLI 入口保持交互拒绝；App 命令模式的恢复可使用相同自动识别，耗尽后要求在界面完成验证。

原位登录与路线：

- 原位登录保留离线页面，挑战等待不产生写资格；隐藏、返回、账号变化、退出与销毁撤销上下文，迟到结果不再发布。
- 固定路线就绪后复用该结果进入。Auto 在校园网只认证 Direct，校外并发认证两条独立路线。
- 校外任一路线就绪即可进入应用，不因另一条路线的验证码阻塞；业务按[域名路线规则](route-policy.md)选择。

细节与证据见[整合来源](../protocol/parity/auth-session.md)与[阶段验证](../archive/evidence/project-interactive-auth-2026-10-02.md)。


## H1-a 的恢复操作控制前置单元

Core/Bridge 增加独立的单次恢复控制，期限从构造时按单调时钟计算，最大两分钟。控制覆盖 Bridge 锁排队与 Core 请求边界，取消不依赖 `dispose` 取得网络锁。中断清理目标路线的准备状态并拒绝后续请求，保留已原子保存的会话，不执行共享注销。具体接口和错误分类见[Bridge v46 合同](flutter-bridge.md#v46所需路线恢复的按操作控制)。

本单元为共同无感恢复提供底层能力；共同 Dart 服务、GUI 与命令消费者接入、自动登录许可核对和跨进程协调详见[共享服务计划](../design/desktop-shared-state.md)。原凭据策略、账号别名、CacheKey、业务缓存加密和日程明文规则保持。

## 学业身份

课表、成绩和考试按信息门户 `d.info.identity` 的明确身份分类选择数据源。该资料读取独立于 SSO 登录，不改变主认证成功条件。分类结果仅在对应路线和认证代次中复用；未知身份返回 `unsupported`，不使用账号名称或学号推断学籍。具体操作见[只读功能合同](readonly-features.md)。

## 版本历史

CLI JSON envelope 的早期版本依次承载以下合同，当前输出只使用上文声明的版本：

| schema | 首次承载 |
|---|---|
| v4 | Signin typed 写结果 |
| v5–v7 | LibBook 预约、LibBook 取消与 Cgyy 预约 |
| v8 | Cgyy typed 取消资格与安全结果 |
| v9 | Ygdk typed 提交资格、请求、安全结果和 caller-pinned 回读 |
| v10 | Evaluation typed target、四态批量结果与 caller-pinned 回读 |
| v16 | 更新门控错误与评教批次 `unattempted` 后缀 |
| v17 | 网络免费剩余包含套餐可用流量，保留是否含套餐的布尔标志 |
