# Reqwest 传输诊断来源与行为边界

日期：2026-09-07；生产修改前记录，当前源码基线
`2f56a4530e6e2a590df4b415b9674363f6e9f72f`。

冻结引用已通过 `just refs`：`ubaa_old`
`6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`，`examples/buaa-api`
`efb7976bf513f38364b88aeb83d704586cff9b2a`。

## 已核对来源

- 现行 `crates/ubaa-core/src/ports/reqwest_transport.rs` 与
  `crates/ubaa-core/src/ports/mod.rs`：生产传输启用 TLS 校验、禁用自动重定向，
  连接/整体超时为 10/30 秒，单次发送 GET 或 POST，并以 8 MiB 为完整响应预算。
- 旧版
  `shared/src/commonMain/kotlin/cn/edu/ubaa/api/auth/NetworkUtils.kt` 及其测试：
  `ApiCallException` 保留状态与机器码；只把 Ktor 的三类明确超时异常映射为超时文案，
  其余异常使用稳定网络文案。它没有当前 Rust `HttpTransport` 的等价端口或
  Reqwest 错误分类。
- 旧版
  `server/src/main/kotlin/cn/edu/ubaa/auth/api/UserFacingErrors.kt`：服务端日志会记录
  完整请求 URI 和原始异常。这属于服务端受控环境的诊断，不等价于本机客户端安全日志，
  本轮不复制 URI、异常或服务端错误映射。
- 示例 `src/error.rs` 与 `src/request.rs`：示例错误包含 source 链，格式化和日志会输出
  原始 source 或响应体；客户端也允许调用方通过 `danger_accept_invalid_certs` 关闭 TLS
  校验。两项都违反现行安全合同，本轮不采用。
- 现行 `crates/ubaa-flutter-bridge/src/api/simple.rs` 只在 FRB 初始化时调用
  `setup_default_user_utils()`。锁定的 `flutter_rust_bridge 2.13.0`
  `src/misc/user_utils.rs` 表明该函数只初始化 `log` 门面和 backtrace，不安装
  `tracing` subscriber；仓库中只有 CLI 与 `core-live` 安装 subscriber。因此新增
  `ubaa::transport` 事件在当前 App 进程没有接收器，必须由 Bridge 初始化补齐。

## 九列保持约束

| 对照列 | 现行 Reqwest 传输合同 | 本轮保持约束 |
|---|---|---|
| CAS/bootstrap/service | 传输接收 Core 已解析的完整 URL，不选择业务入口或 service。 | 不增加、替换或推断 URL/service，不新增学校请求。 |
| 重定向/最终 URL | Reqwest 使用 `Policy::none()`；返回 `response.url()`，重定向由 Core 处理。 | 不改变重定向策略、跳数、白名单或最终 URL 语义。 |
| Cookie/session | 此传输不配置 Cookie store；会话、账号与路线范围由 Core 管理。 | 不读取或记录 Cookie/Session，不改变隔离和仲裁。 |
| HTTP 方法/参数 | `HttpMethod::Get/Post` 一一映射；请求恰好发送一次。 | 不改方法、参数、顺序、发送次数或重试策略。 |
| headers/编码 | 逐项传递现有 headers，非空 body 原样发送；固定浏览器 UA。 | 不改 header、UA、正文编码或表单内容，不记录值和正文。 |
| 加密/签名 | 传输不实现业务加密/签名；Reqwest 默认 TLS 校验保持开启。 | 不改算法/常量，不加入关闭 TLS 校验的入口。 |
| DTO/parser | 返回原始状态、最终 URL、多值 headers 和有界字节正文，不做业务解析。 | 不改 `HttpRequest`、`HttpResponse`、FRB wire DTO 或 parser。 |
| 缓存/并发 | 克隆 Reqwest client；无业务缓存、fallback、自动重试或额外锁。 | 诊断只发 tracing 事件，不参与结果、并发或路线决策。 |
| 错误/退出 | 明确超时为 `timeout/network/true/上游请求超时`；其它 Reqwest 失败为 `network_error/network/true/上游网络请求失败`；超预算为 `upstream_changed/upstream/false/上游响应体超过允许大小`。 | `UbaaError` 的 code/kind/retryable/message 与宿主退出语义全部不变。 |

## 私有诊断合同

传输失败事件只包含以下白名单字段：

- `message`：固定为 `HTTP 传输失败`；
- `stage`：`send` 或 `receive`；
- `reason`：由稳定的 Reqwest 判断方法或有限错误链中的
  `std::io::ErrorKind` 得出的保守类别；
- `elapsed_ms`：从本次 `execute` 开始计算的饱和毫秒值。

分类不检查错误字符串。无法由上述类型信息确认的 DNS、TLS 或代理细节统一保持
`unknown` 或 Reqwest 的宽泛阶段类别，不按文案猜测。事件不得包含 URL、header 值、
请求/响应正文、Cookie、token、原始 `reqwest::Error`、source 的 `Display/Debug` 输出或
个人数据。

Flutter Bridge 只安装默认安全 subscriber：精确允许 target 为 `ubaa::transport`、级别为
DEBUG 的四字段事件，写入标准错误输出，不读取 `RUST_LOG`，不启用其它 Core 或第三方
target，不写文件、不上传。
安装使用 `set_global_default` 的失败关闭语义；宿主已经安装 subscriber 时保持宿主配置，
不得替换。

本轮只用本地回环 TCP 与断开的本地端口验证传输和诊断，不读取凭据/Session，
不访问学校。

## RED/GREEN 与确定性验证

首次 Core RED 的历史执行记录为：程序 `cargo`，子命令 `test`，参数
`-p ubaa-core ports::reqwest_transport::tests -- --nocapture --test-threads=1`。该次执行未显式
传入锁定参数，只作为当时 TDD 失败证据，不作为当前锁定依赖门禁。生产代码尚未发出诊断
事件时退出码为 101：7 项中 5 项通过，发送失败和截断收包两项均因捕获事件为空而按预期
失败。独立日志：`/tmp/ubaa-maintainability-task3-red.log`。

首次 focused GREEN 复用了上述程序、子命令和参数，同样未显式传入锁定参数；退出码为
0，7 项全部通过，只作为历史实现证据。独立日志：
`/tmp/ubaa-maintainability-task3-green-focused.log`。

扩展确定性验证：

| 命令 | 结果 | 独立日志 |
|---|---|---|
| 程序 `cargo`；子命令 `test`；参数 `-p ubaa-core --features test-contract`；首次未显式锁定 | 退出码 0；Core 单元、集成与文档测试通过；仅为历史证据。 | `/tmp/ubaa-maintainability-task3-core.log` |
| 程序 `cargo`；子命令 `test`；参数 `-p ubaa-test-support`；首次未显式锁定 | 退出码 0；96 项 Mock/fixture 合同测试通过；仅为历史证据。 | `/tmp/ubaa-maintainability-task3-mock.log` |
| 程序 `cargo`；子命令 `clippy`；参数 `-p ubaa-core --all-targets --features test-contract -- -D warnings`；首次未显式锁定 | 退出码 0；仅为历史证据。 | `/tmp/ubaa-maintainability-task3-clippy.log` |
| 程序 `cargo`；子命令 `fmt`；参数 `--all -- --check` | 退出码 0。 | `/tmp/ubaa-maintainability-task3-fmt.log` |
| `just check-sensitive` | 退出码 0；执行时 825 个仓库文件通过。 | `/tmp/ubaa-maintainability-task3-final-sensitive.log` |
| `just layout-check` | 退出码 0；0 个精确 baseline 违例。 | `/tmp/ubaa-maintainability-task3-layout.log` |

这些结果只证明当前本地源码的确定性合同与安全诊断；真实 App、Core-live、Direct、
WebVPN、学校上游和正式发布均未执行、未验证。

本地回环 GET/POST/截断响应测试显式构造禁用系统代理的测试客户端，仍执行真实
`ReqwestTransport::execute` 链路，避免 `HTTP(S)_PROXY` 改变本地证据。断开端口使用
不可监听的 `127.0.0.1:0`；平台可将其分类为 `address_unavailable` 或
`connection_refused`，测试只接受这两个具体 `std::io::ErrorKind` 类别。

Bridge subscriber RED 的历史执行记录为：程序 `cargo`，子命令 `test`，参数
`-p ubaa_flutter_bridge api::simple::tests::bridge_initialization -- --nocapture`。该次执行未显式
传入锁定参数，只作为当时 TDD 失败证据。接线前退出码为 101：两项中宿主 subscriber
保留测试通过，安全 transport 输出测试因 stderr 不含事件而按预期失败。独立日志：
`/tmp/ubaa-maintainability-task3-bridge-red.log`。

Bridge subscriber 首次 focused GREEN 复用了上述未显式锁定的历史程序和参数，退出码为
0，2 项全部通过；当时精确验证 `ubaa::transport` 的 WARN 四字段事件可见，其它 Core、
第三方及同 target 额外字段事件均不可见，且已有宿主 subscriber 不被替换。独立日志：
`/tmp/ubaa-maintainability-task3-bridge-green.log`。

补充验证：

| 命令 | 结果 | 独立日志 |
|---|---|---|
| 程序 `cargo`；子命令 `test`；参数 `-p ubaa_flutter_bridge`；首次未显式锁定 | 退出码 0；110 项通过，2 项隔离子进程用例按声明忽略；仅为历史证据。 | `/tmp/ubaa-maintainability-task3-bridge-full.log` |
| 程序 `cargo`；子命令 `clippy`；参数 `-p ubaa_flutter_bridge --all-targets -- -D warnings`；首次未显式锁定 | 退出码 0；仅为历史证据。 | `/tmp/ubaa-maintainability-task3-bridge-clippy.log` |
| 程序 `cargo`；子命令 `test`；参数 `-p ubaa-core ports::reqwest_transport::tests`；首次未显式锁定 | 退出码 0；禁代理后的 7 项通过；仅为历史证据。 | `/tmp/ubaa-maintainability-task3-core-no-proxy.log` |
| 程序 `cargo`；子命令 `fmt`；参数 `--all -- --check` | 退出码 0。 | `/tmp/ubaa-maintainability-task3-final-fmt.log` |
| `just check-sensitive` | 退出码 0；执行时 828 个仓库文件通过。 | `/tmp/ubaa-maintainability-task3-bridge-sensitive.log` |
| `just layout-check` | 退出码 0；0 个精确 baseline 违例。 | `/tmp/ubaa-maintainability-task3-bridge-layout.log` |

Bridge 只引用锁文件中已有的 `tracing 0.1.44` 与 `tracing-subscriber 0.3.23`；
`Cargo.lock` 仅增加当前 workspace 包对这两项的依赖边，没有新增解析版本。FRB 方法、DTO、
Bridge v9 和生成文件保持不变。已有宿主 subscriber 的过滤与输出策略归宿主所有，Bridge
无法且不会覆盖；Bridge 自己安装默认值时才应用上述严格安全过滤。

### DEBUG 兼容回归

完整 `just check-strict` 首次验证发现 CLI JSON 登录/登出的三个既有二进制合同因 stderr
出现 transport WARN 而失败；CLI 默认 subscriber 级别为 `info`，因此会输出 WARN。
失败探测是路线决策的正常输入，默认 JSON stderr 应保持为空，安全传输诊断改为 DEBUG；
CLI 只在显式设置 `RUST_LOG=ubaa::transport=debug` 时输出该诊断。原始失败保留在
该整轮日志路径随后用于最终复验，不作为独立保留的 RED；下方两个锁定定向用例分别保存了修复前证据。

级别 RED 均使用锁定依赖：

- `cargo test --locked -p ubaa-core ports::reqwest_transport::tests::send_failure_emits_redacted_diagnostic_and_preserves_public_error -- --nocapture`：退出码 101，实际 WARN、期望 DEBUG；日志 `/tmp/ubaa-maintainability-task3-debug-core-red.log`。
- `cargo test --locked -p ubaa_flutter_bridge api::simple::tests::bridge_initialization_只接收安全传输_target -- --nocapture`：退出码 101，Bridge 的 WARN 过滤拒绝 DEBUG 测试事件；日志 `/tmp/ubaa-maintainability-task3-debug-bridge-red.log`。

实现只把 Core 安全事件和 Bridge 精确过滤同步改为 DEBUG，不改四字段 schema、错误分类、
CLI 代码或公开输出合同。当前推荐复验必须使用下列锁定命令，并以本节后续记录的实际结果
为准：

- `cargo test --locked -p ubaa-core ports::reqwest_transport::tests`
- `cargo test --locked -p ubaa_flutter_bridge api::simple::tests::bridge_initialization -- --nocapture`
- `cargo test --locked -p ubaa-cli --test binary_e2e`
- `cargo test --locked -p ubaa_flutter_bridge`
- `cargo clippy --locked -p ubaa_flutter_bridge --all-targets -- -D warnings`

锁定 GREEN 与兼容结果：

| 命令 | 结果 | 独立日志 |
|---|---|---|
| `cargo test --locked -p ubaa-core ports::reqwest_transport::tests` | 退出码 0；7 项通过，事件级别为 DEBUG。 | `/tmp/ubaa-maintainability-task3-debug-core-green.log` |
| `cargo test --locked -p ubaa_flutter_bridge api::simple::tests::bridge_initialization -- --nocapture` | 退出码 0；2 项通过，Bridge 接收 DEBUG 安全事件并保留宿主 subscriber。 | `/tmp/ubaa-maintainability-task3-debug-bridge-green.log` |
| `cargo test --locked -p ubaa-cli --test binary_e2e` | 退出码 0；16 项通过，包含三项 JSON stderr 合同和仓库 Cargo 锁定扫描。 | `/tmp/ubaa-maintainability-task3-debug-cli-binary-e2e.log` |
| `cargo test --locked -p ubaa_flutter_bridge` | 退出码 0；110 项通过，2 项隔离子进程用例按声明忽略。 | `/tmp/ubaa-maintainability-task3-debug-bridge-full.log` |
| `cargo clippy --locked -p ubaa_flutter_bridge --all-targets -- -D warnings` | 退出码 0。 | `/tmp/ubaa-maintainability-task3-debug-bridge-clippy.log` |

另以无凭据、无 Session 的本地代理 `auth logout` 验证 CLI 显式诊断：所有代理变量均指向
`127.0.0.1` 的临时监听器，未访问学校。设置 `RUST_LOG=ubaa::transport=debug` 后退出码为
0，stdout 为 schema v10 成功 JSON，stderr 恰有两条 DEBUG 事件且只含安全 target、固定
message、`stage/reason/elapsed_ms`；不含 URL、header 或正文。证据分别为
`/tmp/ubaa-maintainability-task3-cli-debug.stdout` 与
`/tmp/ubaa-maintainability-task3-cli-debug.stderr`。本地监听器已终止。
