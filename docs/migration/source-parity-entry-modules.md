# Core 入口职责整理来源对照

日期：2026-09-05。

移动基线：`b6ff2c7d`（Phase 11K）。本记录先于生产文件移动建立；本阶段只整理两个入口，
不改变协议、公开 DTO、宿主 API、schema、fixture、写入授权或任何请求表达式。

## 移动范围

| 原实现 | 目标实现 | 保留边界 |
|---|---|---|
| `crates/ubaa-core/src/features/mod.rs` | `features/http.rs` | 整体移动 `require_session/get_with_headers/get_with_redirects/post_form/post_json/body/check_response` 及私有 `safe_feature_url/resolve_feature_redirect/feature_redirect_error`；原 `crate::features::*` 路径以相同可见性重导出，调用方不改。 |
| `crates/ubaa-core/src/ports/mod.rs` | `ports/reqwest_transport.rs` | 整体移动 `ReqwestTransport`、其构造和 `HttpTransport` 实现、响应预算、收包与错误映射、3 个既有测试；`crate::ports::ReqwestTransport` 继续重导出同一类型。 |
| `features/mod.rs` 留存 | 原位置 | 领域声明、路线状态导出及只组合 `FeatureResult` 的 `feature_result` 保持原样。 |
| `ports/mod.rs` 留存 | 原位置 | `HttpMethod/HttpRequest/HttpResponse/HttpTransport`、DTO 构造方法和脱敏 `Debug` 实现保持原样；不拆出无独立职责的 DTO 层。 |

两个新子模块均为私有模块；所有原函数签名、返回类型、trait 约束、常量、函数体、错误文案和
执行顺序均保持。新增内容仅为模块声明、导入/重导出和中文模块说明，不新增通用协议抽象。

## 冻结来源适用边界

两份引用以 [references.md](references.md) 为准，移动前 `just refs` 已纯校验通过：

- `ubaa_old @ 6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`。
- `examples/buaa-api @ efb7976bf513f38364b88aeb83d704586cff9b2a`。

本轮沿用 [source-parity.md](source-parity.md) 的逐操作九列和
[source-parity-code-organization.md](source-parity-code-organization.md) 的冻结文件映射。
冻结来源实现的是具体认证或业务操作，不存在与当前 Rust helper 拆分一一对应的公共模块合同；
不能仅因共用 HTTP helper 就把一个领域的 URL、Cookie、加密或错误规则借给另一个领域。

| 现行使用范围 | 旧版参考的适用性 | 示例参考的适用性与限制 |
|---|---|---|
| SSO、用户资料与所选路线的本地会话预检 | 沿用“准备/登录”“用户资料”“双路线加载/保存/退出”的普通认证和模式隔离对照。 | 沿用同表的 SSO、请求和共享 Cookie/凭据证据；示例的自动重定向、共享存储和用户状态接口不等价于当前固定路线资料查询，不复制。 |
| 课表、考试、成绩、空教室 | 沿用对应只读操作和空教室同步的冻结 URL、参数、UA 与会话证据。 | 严格保留原矩阵的适用/不等价结论；iClass 示例不替代旧版空教室协议。 |
| SPOC、Judge | 沿用“认证/列表/详情/批量与缓存”及既有复杂领域文件映射。 | SPOC 示例缺少等价角色建立和主会话仲裁；Judge 无等价协议。不能由共享 helper 弥补这些差异。 |
| Bykc、Cgyy、LibBook、Ygdk、Signin、Evaluation | 现有 session guard、共享 HTTP 调用及专属实现继续使用各自操作级来源，不改专属 helper。 | 沿用各领域原矩阵：Cgyy、Ygdk 等无等价协议项保持不适用；Bykc/Evaluation 等部分等价实现仍受原差异约束，不混用请求、加密或提交顺序。 |
| Reqwest 具体传输 | 冻结实现的路线/业务行为仅按上方操作对照适用，不把旧客户端实现细节视为当前 Rust adapter 的替换方案。 | 示例使用 reqwest 并不证明其重定向、Cookie 或错误策略与 Core 相同；本轮不采用其默认策略。8 MiB 缓冲上限、10 秒连接/30 秒请求预算是当前 Core 实现预算，不声称来自上游协议。 |

## 九列保持条件

以下条件分别适用于上表每个现有操作；具体字段值仍以既有逐操作矩阵为准，本表不另造字段。

| 协议列 | 本次移动约束 |
|---|---|
| CAS/bootstrap URL 与 service | 原业务调用方与 URL 常量不动；helper 仍接收原调用参数。 |
| 重定向与最终 URL | 原 8 跳上限、主机白名单、相对地址解析、WebVPN 转换及日志条件逐字移动；Reqwest 继续禁用自动跳转。 |
| Cookie/session 范围 | 原 `ClientRuntime` 会话检查、请求调用和路线归属不动；adapter 不新增 Cookie 存储。 |
| HTTP 方法与精确参数 | GET/POST、参数顺序、正文构造、空正文处理和 request 次数不动。 |
| headers/body 编码 | 原 header 插入、表单序列化、JSON Content-Type、UA 与响应头提取不动。 |
| 加密/签名 | 本次不移动或修改任何领域加密/签名函数或常量；TLS 校验保持开启。 |
| DTO/parser 字段与类型 | 所有端口和公开 DTO 原位；`body/check_response` 的既有字符串、状态和 URL 判定逐字移动。 |
| 缓存/并发 | 不新增状态、锁、缓存、重试或 fallback；同一 runtime 和 transport 继续执行原调用。 |
| 错误/退出语义 | 原 code/kind/retryable/中文消息、响应大小拒绝与超时映射不动；CLI 退出策略仍由宿主拥有。 |

## 验证记录

- 前置：四个 Rust 目标路径相对 Phase 11K 基线无差异；`just refs` 通过。
- 本次是机械移动，不新增行为，不伪造业务 RED；以原函数/测试块逐字比较和现有行为测试证明等价。
- 逐字比较通过：10 个共享 HTTP helper、`feature_result`、端口 DTO/trait 与其构造/`Debug`、脱敏 header helper、响应预算、Reqwest 实现、3 个原测试，共 7 组原始源码块；仅忽略块尾空行，不归一化表达式或函数体。
- 四个 Rust 目标文件的定向 `rustfmt --check --edition 2024 --config skip_children=true` 通过；`git diff --check` 通过。整理后 `features/mod.rs` 为 34 行、`features/http.rs` 为 221 行、`ports/mod.rs` 为 130 行、`ports/reqwest_transport.rs` 为 216 行。
- `cargo test --locked -p ubaa-core --lib ports::reqwest_transport::tests`：原 Reqwest 3 项单测通过，0 失败。
- `cargo test --locked -p ubaa-test-support --test auth --test readonly`：认证 28 项、只读 61 项通过，0 失败。
- refs、零例外 layout、敏感扫描和完整 `just check` 已通过；Flutter 374 项、FRB 零漂移和 macOS integration 复跑 7 项通过，独立 Rust/Dart 复审无高/中问题。
- 首次全量 Rust 检查因旧 Debug 缓存的严重启动延迟而主动终止，退出 143；保留原日志与完整缓存后，在新缓存中从头执行 `just check`，最终退出 0。中断运行不记为通过。
- 以上为本地阶段证据，不宣称最终候选、实时 Direct/WebVPN、真实写入或正式发布通过；冻结输入未改动。
