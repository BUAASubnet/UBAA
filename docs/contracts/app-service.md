# 应用服务合同

状态：已实施，生产部署未执行。测试结果见[应用服务验收对照](../project/status.md#应用服务验收对照)，决策依据见 [ADR 0008](../adr/0008-app-service-worker.md)。本合同定义客户端（Rust Core `app_service` 模块及其宿主）与 Cloudflare Worker（`services/app_service/`）之间的行为。接口载荷版本为 `schema: 1`，[JSON Schema](app-service.schema.json) 纳入 `just contract-version-check`。

## 1. 范围

应用服务提供三项能力：

| 能力 | 接口 | 性质 |
|---|---|---|
| 遥测 | `POST /v1/telemetry`、`POST /v1/telemetry/erase` | 用户同意且开关开启时才上传，按天聚合 |
| 启动配置 | `GET /v1/bootstrap` | 更新检查和公告；属于功能请求，不带任何标识 |
| 更新门控 | 无独立接口 | Core 根据最近一次成功的启动配置，决定是否拒绝学校请求 |

应用服务与学校协议完全隔离：

- 不经过 Direct/WebVPN 路线转换；
- 不携带学校 Cookie、会话或凭据；
- 使用独立的 transport 实例，TLS 校验开启，只访问配置的服务地址，不跟随跳转到其他主机。

本地诊断报告不经过应用服务，[本地诊断](../runbooks/local-diagnostics.md)中“不会自动上传”的承诺保持不变。

## 2. 配置与硬关闭

| 配置 | 来源 | 说明 |
|---|---|---|
| 服务地址 | 构建参数 `UBAA_APP_SERVICE_URL` | Release 构建必须是 HTTPS 自定义域名，不使用 `*.workers.dev`。为空时完全停用应用服务 |
| 分发渠道 | 构建参数 `UBAA_DISTRIBUTION_CHANNEL` | 取值为 `github`、`app_store`、`app_gallery`。未设置时完全停用应用服务 |
| 平台 | 运行时检测 | 取值为 `android`、`ios`、`ohos`、`macos`、`windows`、`linux` |
| 版本 | 安装包 | `PlatformAppInformation.version()` 的结果，格式见第 5.2 节的 `app_version` |

满足以下任一条件时，完全停用应用服务，遥测、启动配置和门控都不工作：

- 服务地址或渠道未配置；
- 版本无法读取，或不符合第 5.2 节的 `app_version` 格式。客户端不能发出注定被服务端拒绝的请求；
- 非 Release 构建（Debug、Profile），而服务地址不是本机回环地址。非 Release 构建只能指向本机的 `wrangler dev` 用于联调，回环地址可以使用 HTTP。Release 构建拒绝 HTTP 地址。任何构建都不放宽 TLS 证书校验。

满足以下任一条件时，遥测的入队和上传硬关闭，用户开关无法打开，启动配置不受影响：

- 环境变量 `UBAA_TELEMETRY=0`；
- 环境变量 `CI` 非空。

测试与联调：

- 应用服务是否可用，只由构建期配置决定，不在运行时探测是否处于测试环境。上面的运行时条件只能关闭，不能开启。不得增加任何能够开启应用服务的环境变量。
- 单元测试和集成测试通过可注入 transport 构造客户端，永不访问真实服务。
- 本地端到端联调使用非 Release 构建加本机回环地址，只能显式运行，不进入 CI。联调必须断言本地 D1 中确实写入了数据，防止应用服务因硬关闭而静默通过。

硬关闭时，设置页按[统计开关对照](../protocol/source-parity-ui-telemetry-control.md)的规则不显示开关，不得误报为已开启。

## 3. 同意与开关

### 3.1 状态

| 状态 | 应用服务请求 | 进入方式 |
|---|---|---|
| `unasked` | 无 | 首次安装 |
| `agreed(policy_version)` | 允许启动配置；遥测按开关决定 | 首启弹窗、政策更新弹窗或设置页点击“同意” |
| `reconsent_required(policy_version)` | 无。唯一例外是删除请求（第 6 节） | 隐私政策版本升级，而用户此前同意的是旧版本 |
| `basic` | 无。唯一例外是删除请求 | 任一弹窗点击“不同意”，或在设置中撤回同意 |

- **遥测开关是独立保存的值。** 只有在第一次进入 `agreed`、且本机从未保存过开关值时，才初始化为开启。政策升级后重新同意、撤回后重新同意，都保留原来的开关值；用户关闭过统计，重新同意后仍然是关闭。
- **安装 ID** 在第一次进入 `agreed` 时生成（本机还没有的话），是随机 UUIDv4。
- **首启弹窗**必须明确说明：遥测默认开启并可以关闭；数据传输至境外服务（Cloudflare）；收集项目链接到隐私政策全文。政策更新弹窗另外说明变更要点和当前开关状态。
- **隐私政策只有一份来源**，即 `docs/site/tech/privacy-policy.md`：
  - frontmatter 中的 `policy_version` 是正整数，`policy_body_sha256` 是去掉 frontmatter 后正文的 SHA-256；
  - frontmatter 中的 `policy_changes` 是非空纯文本字符串列表，记录当前版本相对上一版的变更要点，供政策更新弹窗显示；
  - 构建时把正文、版本和变更要点嵌入应用，首次选择之前不联网也能查看全文；GUI 和命令模式使用同一构建中的同一个版本号；
  - 收集项目、目的、接收方、存储地点、保留期或用户权利发生变化时，`policy_version` 加一，已同意旧版本的用户进入 `reconsent_required`；
  - 错别字和措辞修订不升版，但正文的任何改动都必须同步更新 `policy_body_sha256`。仓库检查强制这一点，使每次修改在审阅时都可见，由审阅者判断是否应当升版。
- **非 `agreed` 状态**下，除应用服务以外的功能照常可用，不得因此拒绝提供学校功能。更新门控只在 `agreed` 状态下生效（第 9 节）。
- **设置页**提供以下入口：查看隐私政策、同意或撤回同意、“产品改进统计”开关、“删除已上传的统计数据”。

### 3.2 转换

“待发数据”指待发计数，加上全部尚未确认完成的批次。“尚未确认完成”包括从未发送的批次，也包括发送后收到 429、5xx 或网络失败、正在等待重试的批次。只有收到第 4.2 节中会删除批次的响应，批次才算完成。本合同中的清理和容量统计都使用这个定义。

| 操作 | 结果 |
|---|---|
| 关闭遥测 | 立即停止入队，清空待发数据。启动配置照常请求 |
| 重新开启遥测 | 恢复入队，安装 ID 不变 |
| 政策升级 | `agreed` → `reconsent_required`。停止全部应用服务请求和入队，已有待发数据保留但不上传，门控停用 |
| 重新同意 | `reconsent_required` 或 `basic` → `agreed(新版本)`。开关保持原值；立即请求一次启动配置，用来刷新门控（第 9 节） |
| 拒绝或撤回同意 | 进入 `basic`。清空待发数据，停止应用服务请求，门控停用；已保存的门控记录保留但不生效 |
| 删除已上传数据 | 按第 6 节的协调流程执行，遥测开关保持原状 |

### 3.3 共享与命令模式

- 同意状态、遥测开关、安装 ID、待发数据、删除进行中标记和门控记录都保存在 Core 管理的 SQLite 中。GUI 和 App 命令模式共用一份，跨进程写入使用 SQLite 事务。
- 命令模式只读取同意状态，从不弹出询问。状态不是 `agreed` 时，不发出任何应用服务请求。
- 命令模式不请求启动配置，但在 `agreed` 状态下遵守已保存的门控记录（第 9 节）。
- GUI 与命令模式打开共享库时，会等待另一进程完成短事务。共享库仍无法打开时，本次打开的客户端继续提供学校功能，遵循第 9 节的故障规则。

## 4. 本地队列与上传节奏

### 4.1 入队

- 宿主调用现有 `TelemetryClient.track`。事件先经过 Dart 白名单 `TelemetryPolicy` 过滤，再通过 Bridge 交给 Core。
- Core 只接受第 5 节列出的维度，在本机按“校园日期（Asia/Shanghai）× 版本 × 维度”累加计数，不保存原始事件流。
- **按“校园日期 × 版本 × 账号”登记用户。** 每次入队计数时，如果当前进程已经绑定了确认过的账号，而这个组合还没有登记，Core 就在该日期和当前版本的条目下登记该账号的派生标识和年级（第 7 节）。同一天升级后，新版本的第一次入队会为同一账号再登记一次，因此服务端两个版本的 `active_days` 行都有客户端数据支撑。
  - 确认来源包括：认证成功；会话恢复通过，即按本机账号索引的 `expectedUsername` 绑定账号；沿用已绑定账号的离线查看。不要求重新登录。
  - 跨过午夜继续使用时，下一次入队会自动补登新的一天。
  - 每个校园日最多登记 3 个不同账号，按账号计数而不是按条目计数。同一账号在多个版本下的登记只占一个名额。
- 遥测入队和上传都不能改变业务结果，异常只记录到本地。现有的两秒截止预算继续适用于 `track` 调用。

### 4.2 批次

- **冻结。** 上传时，Core 从待发计数中取出一个合法子集，冻结成批次，记录当时的安装 ID，分配随机 `batch_id` 并持久化。取不下的计数留在待发区，下次再处理。子集的上限：
  - 至多 8 个“日期 × 版本”组合，按校园日期从旧到新取；
  - 每个组合的 `counters`、`errors`、`timings` 各至多 512 项；
  - 序列化后的正文不超过 120 KiB，比服务端上限少 8 KiB 余量。
- **每次上传的批次数。** GUI 一次上传至多依次发送 4 个批次，命令模式至多 1 个。
- **按服务端响应处理批次：**

| 响应 | 处理 |
|---|---|
| 204 | 删除批次 |
| 410 `install_erased` | 删除批次，不重试 |
| 400 / 413 | 删除批次，不重试，并记录本地诊断。拆分规则正确时不应出现 |
| 429 / 5xx / 网络失败 | 保留批次，用同一个 `batch_id` 在下次上传时重发 |

- **处理响应只作用于仍然存在的批次。** 删除或更新批次时按 `batch_id` 操作，不重新插入。另一个进程可能在请求期间完成删除（第 6 节）并清掉了这个批次，此时晚到的 5xx 或网络失败不会让旧批次复活。
- **同一批次可能被并发发送。** GUI 和命令进程共用冻结队列，可能同时发出同一个批次。客户端不为此加锁，由服务端按 `batch_id` 去重（第 11.1 节）。

- **过期。** 校园日期早于今天 7 天以上的待发计数直接丢弃。已冻结的批次内容不变，只有当它的全部日期都过期时才删除；部分过期的批次照常发送，由服务端忽略过期的日期。
- **容量。** 待发数据（第 3.2 节的定义，含等待重试的批次）总大小上限为 256 KiB。超出上限时，当天新增的计数丢弃，已冻结的批次保留。
- **删除进行中**（第 6 节）不冻结、不发送任何批次。

### 4.3 触发时机

| 宿主 | 触发 | 预算 |
|---|---|---|
| GUI | 同意后启动时；前台时距上次尝试满 6 小时；移动端进入后台时尽力发送一次 | 单次请求 10 秒 |
| 命令模式 | 命令输出和退出码写出之后，如果距上次尝试满 6 小时 | 2 秒，超时直接放弃，不影响退出码 |

GUI 与命令模式共用 Core 持久化的最近请求尝试时间；没有发出请求时不更新。GUI 启动和移动端进入后台可跳过六小时间隔。

GUI 在前台每 30 分钟检查上传、待删除任务和启动配置。Core 按保存的最近请求尝试时间判断六小时间隔是否已满。已打开应用服务后端时，首次状态读取失败不停止后续检查。

## 5. 遥测上报 `POST /v1/telemetry`

### 5.1 请求

请求要求如下：
- `Content-Type: application/json`；
- 正文不超过 128 KiB；
- 不携带 Cookie 或认证头。

```json
{
  "schema": 1,
  "batch_id": "6f1c0d4e-1b2a-4c3d-9e8f-0a1b2c3d4e5f",
  "install_id": "0b6a8f3e-5c4d-4e2f-8a1b-9c0d1e2f3a4b",
  "platform": "android",
  "channel": "github",
  "days": [
    {
      "day": "2026-11-10",
      "app_version": "2.0.0+12",
      "surfaces": ["gui"],
      "users": [
        {"key": "<64 位小写十六进制>", "cohort_type": "undergrad", "cohort_year": 2024}
      ],
      "counters": [
        {"event": "feature_loaded", "feature": "schedule", "route": "direct", "result": "success", "count": 3}
      ],
      "errors": [
        {"event": "feature_failed", "feature": "grades", "route": "webvpn", "error_code": "parse_error", "error_kind": "upstream", "retryable": false, "source": "package:ubaa_app/src/bridge/read/grades.dart:120", "count": 1}
      ],
      "timings": [
        {"metric": "feature_load", "feature": "schedule", "route": "direct", "bucket": "lt_1000", "count": 2}
      ]
    }
  ]
}
```

### 5.2 字段白名单

除下表列出的字段外，任何字段都会被 Worker 拒绝（`additionalProperties: false`）。

| 字段 | 约束 |
|---|---|
| `batch_id`、`install_id` | 小写 UUIDv4 |
| `platform` | 第 2 节的六个取值 |
| `channel` | 第 2 节的三个取值 |
| `days` | 1–8 项。`day` 为 `YYYY-MM-DD`，同一批次内 `day` 与 `app_version` 的组合不重复 |
| `app_version` | `^\d+\.\d+\.\d+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+\d+)?$`，最长 48 字符。预发布后缀按[开发约定](../development/conventions.md#版本号与依赖)使用，比较规则见第 8 节 |
| `surfaces` | `gui`、`command` 的非空子集 |
| `users` | 0–3 项，`key` 匹配 `^[0-9a-f]{64}$`，年级字段见第 7 节 |
| `counters[].event` | `app_started`、`auth_started`、`auth_succeeded`、`session_expired`、`route_resolved`、`feature_loaded` |
| `errors[].event` | `auth_failed`、`feature_failed`、`ui_error_shown`、`crash` |
| `feature` | `FeatureId.wireName` 的取值，或 `app`、`auth`。完整列表随 JSON Schema 维护，仓库检查保证它与 `FeatureId` 一致 |
| `route` | `direct`、`webvpn`、`none` |
| `result` | `success`、`empty`、`failure` |
| `error_code` | Core 稳定机器码，`^[a-z][a-z0-9_]{0,47}$`。`crash` 事件中为 Dart 异常类型名 `^[A-Za-z_][A-Za-z0-9_]{0,63}$`（去掉泛型参数），Rust panic 固定为 `panic` |
| `error_kind` | Core 错误分类枚举，随 JSON Schema 维护，仓库检查保证它与 Core `ErrorKind` 的序列化取值一致 |
| `retryable` | 布尔值 |
| `source` | 可选，至多一项安全源码位置：`^package:ubaa_[a-z_]+/[A-Za-z0-9_/]+\.dart:\d+$`，或 `^crates/ubaa_[a-z_]+/src/[A-Za-z0-9_/]+\.rs:\d+$`，最长 128 字符 |
| `timings[].metric` | `cold_start`、`first_content`、`auth`、`feature_load` |
| `bucket` | `lt_250`、`lt_500`、`lt_1000`、`lt_2000`、`lt_5000`、`lt_10000`、`ge_10000` |
| `count` | 整数 1–100000 |
| 各数组长度 | `counters`、`errors`、`timings` 各不超过 512 项 |

不得上报的内容：学号原文、姓名、错误消息原文、URL、HTTP 正文、课程、成绩、文件名、照片、位置、诊断报告、本机路径、完整堆栈和 panic 消息。

上游健康度由带 `route` 的 `counters` 和 `errors` 合并计算，不另设事件。Rust panic 只上报 `crates/ubaa_*` 内的位置；panic 钩子由 Bridge 实现，实现时须核实 FRB 现有的 panic 处理方式。原生崩溃（例如信号）不在本合同范围内。

### 5.3 发布顺序

新增 `feature`、`error_kind` 等枚举值时，先部署接受新值的 Worker，再发布使用新值的客户端。否则旧 Worker 会以 400 拒绝整个批次，客户端按第 4.2 节删除该批次，其中最多 8 个“日期 × 版本”组合的数据随之丢失。

### 5.4 响应

| 状态 | 含义 |
|---|---|
| 204 | 已接受，包括重复的 `batch_id` |
| 410 | 该安装 ID 已删除（第 6 节），正文只含机器码 `install_erased` |
| 400 | 校验失败。响应正文只含机器码 `invalid_payload`，不回显输入 |
| 413 | 正文过大 |
| 415 | `Content-Type` 不是 JSON |
| 429 | 限流 |
| 5xx | 服务端错误 |

校园日期不在 `[今天 − 7, 今天 + 1]` 范围内的 `days` 项会被静默忽略，其余项照常处理，仍然返回 204。

## 6. 删除 `POST /v1/telemetry/erase`

```json
{"schema": 1, "install_id": "0b6a8f3e-5c4d-4e2f-8a1b-9c0d1e2f3a4b"}
```

删除不受遥测开关或同意状态的限制。只要本机有安装 ID，即使处于 `reconsent_required` 或已经撤回同意进入 `basic`，用户也可以在设置页发起删除，这时只发送这一个请求。

删除与聚合表的关系：
- 删除只清除明细，不直接修改任何聚合表。
- 尚未定稿的日表和月表（第 11.3 节的重算窗口内）由后续定时任务按剩余明细重算，因此会反映这次删除。
- 已经定稿的聚合表保留原值。它们不含安装 ID 或用户标识，无法也不需要按设备追溯。

### 6.1 客户端协调

GUI 和命令进程可能同时运行，删除按以下顺序执行：

1. Core 在共享 SQLite 的一个事务中写入删除进行中标记，记录旧安装 ID。从此刻起，两个进程都不再冻结或发送批次，新的计数直接丢弃。
2. 发送删除请求。
3. 收到 204 后，在同一个事务中完成以下操作：删除旧安装 ID 的全部批次和待发计数；生成新的安装 ID；清除标记。
4. 失败或结果未知时保留标记，界面提示删除尚未完成。删除接口是幂等的，删除成功之前不上传任何数据。重试时机如下：
   - GUI 按第 4.3 节的 GUI 触发时机重试删除。这条在任何同意状态下都执行，非 `agreed` 状态下只发送删除请求。设置页也可以手动重试。
   - `agreed` 状态下，命令模式在自己的上传时机先重试删除。
   - 命令模式在非 `agreed` 状态下不重试，遵守第 3.3 节不发应用服务请求的规则。

本地协调只能阻止尚未发出的请求。删除开始前已经离开设备的旧批次，由服务端拒收（6.2）。

### 6.2 服务端规则

- **删除。** 在一个 D1 batch 中执行两件事：写入 `erased_installs(install_id, erased_at)`；删除该 ID 在全部明细表（第 11 节）中的行。完成后返回 204。不存在的 ID 同样返回 204。
- **上报的写入。** `batches` 和各明细表的写入都带条件 `WHERE NOT EXISTS (SELECT 1 FROM erased_installs WHERE install_id = ?)`，并且放在同一个 D1 batch 中执行。
  - D1 的 batch 以 SQL 事务执行，同一数据库的写入串行进行。
  - 因此晚到的上报只有两种结果：在删除之前整体写入，随后被删除清掉；或在删除之后整体不生效。不会留下已删除 ID 的明细。
- **拒收响应。** 上报前，Worker 先查询 `erased_installs`，命中时返回 410。这次查询只决定响应码，数据是否写入仍由上面的条件保证。
- **墓碑保留期。** `erased_installs` 保留 30 天。理由：客户端在删除成功时已经删掉旧 ID 的全部批次，之后不会再用旧 ID 发起请求；残留的只有删除前已经发出的请求，它们受客户端单次请求超时（10 秒）约束。30 天远超这一时限。

## 7. 用户派生标识与年级

### 7.1 派生标识

客户端（Core）计算：

```text
key = hex(SHA-256(UTF-8("ubaa-telemetry-user-v1:" + normalize(学号))))
normalize = 去掉首尾空白，字母转为大写
```

Worker 计算：

```text
user_key = hex(HMAC-SHA256(USER_KEY_SECRET, key))
```

- `USER_KEY_SECRET` 只存在于 Worker Secret，不进入仓库、CI 或客户端，也不轮换。泄露时更换，并在决策记录中登记去重连续性断开的日期。
- 数据库只保存 `user_key`，客户端上传的 `key` 不落盘。
- `key` 和 `user_key` 都不得出现在日志、诊断报告、测试证据或提交内容中。测试只使用合成学号。

### 7.2 年级

| 学号格式 | `cohort_type` | `cohort_year` |
|---|---|---|
| 全部为数字，前两位 `YY` 构成合理年份 | `undergrad` | `2000 + YY` |
| 前两位为大写字母 `XX`，第 3、4 位 `YY` 为数字且构成合理年份 | `XX` 原样上报 | `2000 + YY` |
| 其他格式（包括教职工号） | `unknown` | `null` |

- 合理年份指 `2000 ≤ 年份 ≤ 当前校园年份 + 1`。
- 研究生字母前缀的含义在看板里映射，客户端不解释。
- 本科学号的长度规则目前没有可靠证据，暂不校验长度。有证据后更新本表和决策记录。
- 登记时机见第 4.1 节：每个活跃日，对已经确认的当前账号登记一次，不要求重新登录。没有绑定账号的设备只计入设备活跃数。

## 8. 启动配置 `GET /v1/bootstrap`

### 8.1 请求

请求格式为 `GET /v1/bootstrap?schema=1&platform=android&channel=github&version=2.0.0%2B12`。
- 只带上面列出的四个参数，不带安装 ID、用户标识或 Cookie。
- GUI 在 `agreed` 状态下启动时请求一次，前台时最多每 6 小时请求一次，单次超时 5 秒，失败时静默。
- 命令模式不请求，非 `agreed` 状态也不请求。

### 8.2 响应

```json
{
  "schema": 1,
  "update": {
    "status": "update_available",
    "latest_version": "2.1.0+15",
    "min_supported_version": "2.0.0",
    "url": "https://github.com/BUAASubnet/UBAA/releases/latest",
    "release_notes": "纯文本更新说明"
  },
  "announcements": [
    {
      "id": "2026-11-10-001",
      "level": "popup",
      "title": "标题",
      "body": "纯文本正文，段落之间用空行分隔。",
      "link_url": "https://example.invalid/detail",
      "link_text": "查看详情",
      "confirm_text": "知道了",
      "starts_at": "2026-11-10T08:00:00+08:00",
      "ends_at": "2026-11-17T00:00:00+08:00"
    }
  ]
}
```

| 字段 | 约束 |
|---|---|
| `update.status` | `up_to_date`、`update_available`、`update_required`、`unknown`。渠道没有配置时为 `unknown`，其余字段为 null |
| `latest_version`、`min_supported_version` | 只能是正式版本，即不带预发布后缀，可以带 `+BUILD`；可以为 null |
| `url` | HTTPS。商店渠道只能是对应商店的链接 |
| `release_notes` | 纯文本，不超过 2000 字符，可以为 null。只在 `update_available` 或 `update_required` 时返回 |
| `announcements` | 已按平台、渠道、版本和时间过滤，最多 5 条 |
| `level` | `popup`：弹窗，确认后本地记为已读，不再弹出。`banner`：首页横幅，可以关闭，关闭后记为已读 |
| `title` | 不超过 40 字符 |
| `body` | 纯文本，不超过 1000 字符 |
| `link_url`、`link_text`、`confirm_text` | 可选。`link_url` 只允许 HTTPS，并交给系统浏览器打开 |
| `starts_at`、`ends_at` | ISO 8601，`ends_at` 可选 |

其他规则：

- **向前兼容。** 上表约束的是已知字段，客户端解析响应时按以下规则处理：
  - 严格校验已知字段的类型和取值，忽略未知字段；
  - `update.status` 出现不认识的取值时，按 `unknown` 处理；
  - 某条公告的 `level` 无法识别，或缺少必需字段时，只丢弃这一条公告；
  - 只有响应顶层或 `update` 中的已知字段不合法（例如 `schema` 不是 1、版本格式错误），整个响应才视为校验失败。

  服务端只能在响应中新增可选字段或新的枚举取值。删除字段或改变已有字段的含义，必须提升 `schema`。这样旧客户端在服务端扩展响应后，仍然能识别更新要求。
- 版本比较分两步：
  1. 按 [SemVer 2.0.0](https://semver.org/spec/v2.0.0.html) 第 11 条比较 `MAJOR.MINOR.PATCH` 和预发布后缀：先比较三段数值；带预发布后缀的版本低于同号正式版本；预发布标识逐段比较，纯数字段按数值比较，其余按 ASCII 比较，数字段低于非数字段，段数少的低于段数多的。
  2. 上一步相等时，再按数值比较 `+BUILD`，缺少时视为 0。SemVer 本身忽略构建元数据，这里比较它，是因为平台构建号在同一发布序列中单调递增。
- 示例：`2.1.0-rc.1+15` < `2.1.0+16`；`2.1.0-rc.1+15` > `2.0.5+14`。所以只要渠道配置的正式版本按上述规则高于当前版本，就提示更新：`2.1.0-rc.1` 的用户会收到 `2.1.0` 或 `2.2.0` 正式版的提示，不会收到 `2.0.x` 的提示。
- 缓存：Worker 以四个参数为键，用 Cache API 缓存响应 300 秒。客户端把最近一次成功的响应保存在共享 SQLite 中，显示公告时再按本机时间检查一次 `ends_at`。
- 已读状态：公告已读 ID 保存在本机，不上传。

## 9. 更新门控

- 收到 `update_required` 的成功响应后，Core 在共享 SQLite 中保存门控记录 `{channel, min_supported_version}`。
- 同时满足以下三个条件时，门控生效：
  - 同意状态为 `agreed`；
  - 当前版本低于记录中的最低版本；
  - 渠道与记录一致。

门控生效时：
  - 所有会向学校发送请求的 facade 操作都返回 typed 错误 `update_required`（`retryable=false`）；
  - 本地日程、缓存查看和数据导出照常可用；
  - GUI 在首页顶部显示不可关闭的更新横幅，说明学校功能暂不可用、本地数据仍可查看，并提供跳转到 `url` 的按钮；
  - 功能页照常显示本地缓存。用户主动发起登录、刷新等需要访问学校的操作时，GUI 弹出更新提示，提供“返回”和“前往更新”；
  - 自动刷新、后台同步等不是用户发起的学校请求被拒绝时，不弹窗，只由横幅说明；
  - 设置页、隐私选择、本地日程、缓存查看和数据导出不受影响；
  - 命令模式输出错误并以对应退出码结束。
- 设置与解除按成功响应的 `update.status` 决定：
  - `update_required` 设置或更新门控记录；
  - `up_to_date` 或 `update_available` 解除门控；
  - `unknown`，包括按第 8.2 节当作 `unknown` 处理的未知取值，保持原状，因为服务端没有给出判断。
- 升级后，当前版本不再低于已保存的最低版本时，门控同样解除。
- 网络失败、超时、非 2xx 响应或校验失败都不会设置或解除门控。
- 本地门控状态读取失败时，本次学校请求照常执行，仅记录不含敏感数据的诊断，不改写已保存的门控。之后读取成功时，继续按保存的状态判断。
- **非 `agreed` 状态下门控停用。** 进入 `reconsent_required` 或 `basic` 后，客户端不再请求启动配置，无法得知服务端是否已经撤销最低版本要求，所以门控停用，记录保留但不生效。这样基础模式下学校功能照常可用。
- **重新同意后刷新。** 重新同意时立即请求一次启动配置。结果返回之前，以及请求失败时，沿用已保存的记录。这与 `agreed` 状态下的一般网络失败规则一致。
- 用户撤回同意就能绕过门控。门控用来在学校协议失效时防止错误请求，不是强制升级手段，这一点已经接受。
- `update_required` 错误码随实现加入 CLI 与 Bridge 合同，并相应提升版本号。

## 10. 公告与渠道配置的来源

### 10.1 公告文件

公告保存为 `docs/site/announcements/YYYY-MM-DD-NNN.md`，文件名去掉扩展名后就是 `id`。

```markdown
---
title: 标题
level: popup
app: true
platforms: [android, ios, ohos]
channels: [github]
min_version: 2.0.0
max_version: 2.0.9
starts_at: 2026-11-10T08:00:00+08:00
ends_at: 2026-11-17T00:00:00+08:00
link_url: https://example.invalid/detail
link_text: 查看详情
confirm_text: 知道了
---

纯文本正文。段落之间用空行分隔。
```

- `app: false` 表示只在网站显示，不推送给 App。
- `platforms`、`channels`、`min_version`、`max_version`、`ends_at` 和三个链接或按钮字段都是可选的，省略表示不限制或不显示。
- 版本区间包含两端。若 `max_version` 不带构建号，上限包含相同 SemVer 版本的所有构建，例如 `2.0.9` 包含 `2.0.9+12`；若带构建号，则按第 8 节的完整版本规则比较。`min_version` 始终按完整版本规则比较。
- 正文只允许纯文本段落。发布脚本遇到标题、列表、链接、图片、代码或 HTML 语法时报错，不会截断后继续发布。

### 10.2 渠道配置

渠道配置保存在 `services/app_service/config/channels.json`：

```json
{
  "github": {
    "latest_version": "2.0.0+12",
    "min_supported_version": null,
    "url": "https://github.com/BUAASubnet/UBAA/releases/latest",
    "release_notes": "纯文本更新说明",
    "platforms": {}
  },
  "app_store": null,
  "app_gallery": null
}
```

- `platforms` 可以按平台覆盖同一组字段。
- 值为 `null` 的渠道返回 `status: unknown`。
- 商店版本只有在审核通过、确实可以下载之后，才能更新 `latest_version`。

### 10.3 发布

- 内容发布先校验公告和渠道配置，再与目标 Workers KV 中的 `channels` 和 `announcements` 比较；内容相同跳过写入，内容缺失或不同才同步。
- Worker 部署先检查并构建 Worker，确认目标自定义域名和 `USER_KEY_SECRET`，然后应用 D1 迁移。迁移失败时停止，成功后才部署。自定义域名由维护者首次绑定，自动部署不修改绑定。
- 维护者可显式执行 `just app-service-deploy` 与 `just app-service-publish`。CD 仅处理指定分支的主仓库 push，同一提交的全部 CI 检查通过后，在受保护的 GitHub Environment 中部署 Worker 并同步内容。Cloudflare API Token 只交给这两个远端入口，普通检查不接收。操作见[部署手册](../runbooks/app-service.md)。
- 这两个命令的副作用在实现时登记到[命令的副作用](../development/commands.md#网络与写入边界)和[脚本说明](../../scripts/README.md)。

## 11. Worker 处理与存储

### 11.1 处理规则

- 用 JSON Schema 校验请求，校验器在构建时预编译，因为 Workers 禁止运行时生成代码。
- 不支持 CORS，不接受浏览器跨域请求。
- 不保存 IP。Workers Logs 和 Logpush 保持关闭，代码不输出请求内容。
- 限流使用 Workers Rate Limiting 绑定：

| 接口 | 限流键 | 上限 |
|---|---|---|
| 遥测上报 | 安装 ID | 每 60 秒 5 次 |
| 删除 | 安装 ID | 每 60 秒 3 次 |
| 启动配置 | IP（只在内存中使用） | 每 60 秒 600 次 |

- 依据 [Cloudflare 官方文档](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/)，该绑定只支持 10 秒或 60 秒窗口，在每个 Cloudflare 节点分别近似计数，计数在后台同步，短时间内可能超过阈值。所以表中的上限是各节点的近似防护，不是全局精确配额。
- 正常客户端每 6 小时才上传一次，上述上限只用来拦截异常重试和刷量。需要更长窗口或全局精确配额时，另行评估 D1 计数或 Durable Objects，并修订本合同。
- 启动配置按 IP 限流，阈值定得很高，因为校园网出口存在大量 NAT 共享，官方文档也不建议用 IP 做限流键。主要负载由 Cache API 承担。

- 客户端不内置任何密钥，因为内置的都能被提取出来。防止伪造数据只能依靠校验和限流。这一风险已经接受。
- 遥测上报在一个 D1 batch（SQL 事务）中完成。D1 的 batch 不能根据前一条语句是否生效决定是否执行后一条，所以按以下方式去重：
  1. 第一条语句以 `INSERT OR IGNORE` 写入 `batches(batch_id, nonce, received_at)`，`nonce` 是 Worker 为本次请求随机生成的值；
  2. 其余每条明细 upsert 都附加条件 `EXISTS (SELECT 1 FROM batches WHERE batch_id = ? AND nonce = ?)`，累加 `count`；
  3. 所有写入同时带第 6.2 节的墓碑条件。

  同一 `batch_id` 的多次请求，无论先后到达还是同时到达，只有成功写入自己 `nonce` 的那一次会累加，其余请求不改变任何计数，照常返回 204。不能在 batch 之外先查询再决定是否写入，因为查询和写入之间可能有另一个请求已经完成写入。

### 11.2 D1 表结构

维度缺失时一律存空字符串，便于建立主键。

| 表 | 主键 | 其他列 | 保留期 |
|---|---|---|---|
| `batches` | `batch_id` | `nonce, received_at` | 14 天 |
| `erased_installs` | `install_id` | `erased_at` | 30 天 |
| `active_days` | `day, install_id, user_key, app_version` | `platform, channel, cohort_type, cohort_year, surface_mask` | 13 个月 |
| `counter_days` | `day, install_id, app_version, event, feature, route, result` | `platform, channel, count` | 90 天 |
| `error_days` | `day, install_id, app_version, event, feature, route, error_code, error_kind, retryable, source` | `platform, channel, count` | 90 天 |
| `timing_days` | `day, install_id, app_version, metric, feature, route, bucket` | `platform, channel, count` | 90 天 |
| `active_daily` | `day, dimension, value` | `users, devices` | 长期 |
| `active_monthly` | `month, dimension, value` | `users, devices` | 长期 |
| `counter_daily` / `error_daily` / `timing_daily` | 对应明细表的主键去掉 `install_id` | `count, devices` | 长期 |
| `job_state` | `job` | `last_success_day` | 长期 |

- **`active_days`**：没有绑定账号的设备也写一行，`user_key` 为空字符串。同一用户同一天使用多个版本时，每个版本各占一行，迟到的旧版本批次不会覆盖新版本的记录。`surface_mask` 中 GUI 为 `1`，命令模式为 `2`；合并同一行的使用方式时按位或。
- **活跃聚合**：`users` 是非空 `user_key` 的去重数，`devices` 是 `install_id` 的去重数。`dimension` 有以下取值：

| `dimension` | `value` |
|---|---|
| `all` | 空字符串，表示跨平台、渠道和版本的整体去重 |
| `platform` | 平台取值 |
| `channel` | 渠道取值 |
| `app_version` | 版本 |
| `cohort` | `类型:入学年`，例如 `undergrad:2024`、`SY:2024`、`unknown:` |

- **分组计数不能相加。** 同一用户可能同时出现在多个平台、渠道或版本的分组里，所以同一 `dimension` 下各 `value` 的计数相加不等于总数。整体日活和月活只看 `dimension = all` 这一行。`counter_daily` 等表的 `devices` 列同理。
- 必须在明细超过保留期被清理之前，算好 `all` 维度的去重结果。13 个月后 `user_key` 被删除，就无法再重新去重。
- 聚合表不含 `install_id` 和 `user_key`。

### 11.3 定时任务

任务每天 03:00（Asia/Shanghai）运行，以下记运行当天为 D。D 由触发器的计划时间换算为校园日期，不读取运行时的当前时间，因此延迟执行不会改变 D。

**哪些日期还可能变化。** 上报只接受校园日期在 `[今天 − 7, 今天 + 1]` 范围内的数据。上一次任务在 D − 1 的 03:00 运行，此后到本次运行之间：
- D − 1 当天还能收到 D − 8 至 D 的数据；
- D 当天 00:00 至 03:00 还能收到 D − 7 至 D + 1 的数据。

**每次运行按以下顺序执行：**

1. 重新计算 `[D − 8, D + 1]` 共 10 个校园日的全部日表。本次运行之后，D − 8 不会再收到数据，它的日表就此定稿。
2. 重新计算与 `[D − 8, D + 1]` 有交集的每个月份的 `active_monthly`。上个月的最后一天 L 最晚在 L + 7 还能收到数据，所以上个月会在每月 1 日至 8 日的运行中持续重算，8 日的运行之后定稿。
3. 完成汇总后，按上表的保留期删除过期明细、`batches` 和 `erased_installs`。清理必须排在汇总之后。
4. 以上三步全部成功后，在 D1 中记录本次的 D，作为“上次成功日期” L。

**漏跑后的补算。** 定时任务失败或漏跑不会自动重试。若本次运行时 L 早于 D − 1，重算起点从 D − 8 提前到 L − 7：L 那次运行之后，L − 7 及以后的日期仍可能收到数据。月份范围相应扩大。起点不早于明细保留期内的最早日期。没有 L 记录的首次运行按正常窗口执行。任一步失败时不更新 L，下次运行会再次覆盖这段日期。

日表和月表可分批覆盖，同一范围的删除旧聚合与写入新结果在同一事务中完成。所有汇总批次成功后，才在同一批次内清理过期明细并推进 L。汇总失败时已完成的覆盖可保留，下次重算时覆盖原值，不累加。

数据通过 `wrangler d1 execute` 或 Cloudflare 控制台查询，不提供公开看板或管理接口。

## 12. 隐私政策须列明的事项

- 收集项目：
  - 安装 ID；
  - 学号派生标识（加盐哈希）；
  - 年级类型与入学年份；
  - 平台、渠道和版本；
  - 按天汇总的功能使用、错误码、耗时分桶和安全源码位置。
- 目的：上游接口健康监测、缺陷定位、功能改进、活跃度与年级分布统计。
- 境外接收方：Cloudflare, Inc.。须写明处理方式、存储地点在境外，以及第 11 节的保留期。
- 用户权利：关闭统计、撤回同意、应用内删除已上传数据，以及联系方式。
- 不收集的内容：第 5.2 节列出的不得上报内容。

## 13. 验收

| 层 | 要求 |
|---|---|
| Core | 使用可注入 transport 的确定性测试，覆盖第 3 节全部状态转换、第 2 节的停用与硬关闭条件、批次拆分上限、批次重发与 `batch_id` 去重、队列上限、7 天丢弃、门控的设置与解除条件、启动配置响应的向前兼容解析、派生标识与年级解析（合成学号）、请求不含 Cookie 且不跟随跳转 |
| Bridge / Dart | 白名单过滤、开关和删除流程、设置页文案、首启弹窗和基础模式、门控横幅与学校操作拦截，以及 Noop 不误报开启 |
| Worker | 用本地 Workers 运行时测试：Schema 正反例、未知字段拒绝、重复与并发批次、限流、删除、定时汇总、清理与漏跑补算、启动配置的过滤与版本比较（含预发布版本）。测试不访问真实 Cloudflare 资源 |
| 仓库检查 | Schema 的 `feature`、`error_kind` 枚举分别与 `FeatureId`、Core `ErrorKind` 一致；隐私政策正文与 `policy_body_sha256` 一致，`policy_changes` 是字符串列表，应用内嵌入的正文、版本和变更要点与来源一致 |
| 端到端 | 对本地 `wrangler dev` 的联调另行记录，必须断言本地 D1 有写入，不能代替真实部署的验收 |

以下场景必须有专门的测试：

| 场景 | 预期 |
|---|---|
| 用户关闭统计后，接受新版隐私政策 | 开关保持关闭，不入队、不上传 |
| 收到 `update_required` 后撤回同意 | 门控停用，学校请求照常可用 |
| 重新同意后刷新门控 | 立即请求启动配置；成功时按结果设置或解除门控，失败时沿用已保存的记录 |
| 删除与上传交错：A 进程已发出旧 ID 批次，B 进程删除成功后，A 的请求才到达 Worker | 旧 ID 不留下任何明细，A 收到 410 或 204 且数据未写入 |
| 删除结果未知后重启 | 删除进行中标记仍在，先重试删除，成功前不上传 |
| 前一天登录，第二天复用会话；或 App 跨过午夜继续使用 | 新的一天登记同一用户，年级随之计入 |
| 同一天升级版本，旧版本批次晚到 | 客户端在两个版本条目下各登记一次同一账号，只占一个名额；服务端两个版本的 `active_days` 行都保留 |
| 关闭统计时，有批次正在等待重试；随后重新开启 | 等待重试的批次随关闭一起清除，重新开启后不会上传 |
| 某设备昨天的数据已进入未定稿日表，今天删除 | 下一轮重算后，未定稿日表和月表不再包含该设备；已定稿的聚合表不变 |
| 同一用户当天使用两个平台 | `all` 维度计 1 人，`platform` 维度两组各计 1 人 |
| 某日数据在第 7 天晚间上传；上月最后一天的数据在下月初上传 | 分别进入日表和上月的月表 |
| 离线 8 天且期间升级，产生 9 个“日期 × 版本”组合 | 拆成多个合法批次，没有 400 或 413 |
| 上报版本为 `2.1.0-rc.1+15` | 校验通过，更新比较结果符合第 8 节示例 |
| 同一 `batch_id` 由两个请求同时发送 | 两次都返回 204，各明细计数只累加一次 |
| 进程 A 发送批次期间，进程 B 删除成功；A 随后收到 503 | 旧批次不复活，新安装 ID 下没有旧数据 |
| `basic` 状态下删除失败，随后重启 GUI；同时运行命令模式 | GUI 只重试删除请求；命令模式不发任何应用服务请求 |
| 启动配置响应含未知字段、未知 `update.status`、一条未知 `level` 的公告 | 已知字段照常生效；未知状态不改变门控；只丢弃那一条公告 |
| 门控生效时，用户点击刷新；同时有一次自动刷新 | 用户操作弹出更新提示且学校 transport 未收到请求；自动刷新不弹窗；本地日程和缓存可用 |
| 定时任务漏跑一天，漏跑期间有第 7 天的迟到数据 | 下次运行扩大重算起点，迟到数据进入对应日表 |
| 版本读取失败，或非 Release 构建配置了非回环地址 | 完全停用应用服务，没有任何请求 |

以下任一情况都是失败：非 `agreed` 状态下发出删除以外的应用服务请求；关闭遥测后仍在入队或上传；重新同意后打开了用户已关闭的统计；删除成功后服务端仍有旧安装 ID 的明细；非 `agreed` 状态下门控仍然生效；上传内容出现白名单以外的字段；服务不可达时阻断功能；应用服务请求携带学校 Cookie；日志或诊断报告中出现学号派生标识；非 Release 构建访问非回环地址；客户端因启动配置响应中的未知字段或未知枚举值放弃整个响应。
