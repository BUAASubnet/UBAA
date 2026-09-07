# 可维护性治理来源与行为边界

日期：2026-09-07；生产修改前记录，源码基线 `95705fdcf1095ad42d1c85b25e208ca302263a0f`。

冻结引用已通过 just refs：ubaa_old `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`，buaa-api `efb7976bf513f38364b88aeb83d704586cff9b2a`。

已读取旧版 `shared/src/commonMain/kotlin/cn/edu/ubaa/api/auth/NetworkUtils.kt` 的 ApiErrorDetails/ApiCallException 和展示映射、对应 `shared/src/commonTest/kotlin/cn/edu/ubaa/api/NetworkUtilsTest.kt`，以及服务端 `server/src/main/kotlin/cn/edu/ubaa/auth/api/UserFacingErrors.kt`。旧版区分机器错误代码与展示文本，并保留异常处理上下文，但其服务器错误码和请求 URI 日志不能直接移植到当前本地客户端。

已读取示例 `src/error.rs` 和 `src/request.rs`：示例具有 kind/source 链，但会打印原始响应，客户端也存在可关闭 TLS 验证的配置。两者与当前安全合同不等价，本轮不复制原始日志、TLS 配置、请求重定向和错误码。

本次 Dart 修复的权威是现行 [Bridge 错误合同](../contracts/flutter-bridge.md#3-错误合同)：已有 code/kind/retryable/resolved_route 被宿主丢弃。本轮恢复这些字段的传播，保持 CLI v10/Bridge v9，不发明新的上游错误。

## 操作级覆盖

认证准备/登录/状态、用户资料、课表、考试、成绩、空教室、SPOC 列表/详情、Judge 列表/详情/批量、Bykc、Signin、LibBook、Cgyy、Ygdk、Evaluation 各操作的来源分别沿用 [逐操作矩阵](source-parity.md) 与 [入口模块来源](source-parity-entry-modules.md)。没有等价协议的参考继续保持不适用，不按类似名称借用。

| 对照列 | 每个上述操作的保持约束 |
|---|---|
| CAS/bootstrap/service | URL、service 和现有业务入口不改。 |
| 重定向/最终 URL | 不改跳数、白名单、WebVPN 转换、禁用自动跳转规则。 |
| Cookie/session | 不改存储、账号、路线范围、世代仲裁与锁。 |
| HTTP 方法/参数 | 不改方法、参数、请求顺序和发送次数；不新增学校请求。 |
| headers/编码 | 不改 UA、头、正文编码与响应读取预算。 |
| 加密/签名 | 不改常量和算法，保持 TLS 校验开启。 |
| DTO/parser | 不改 Rust/FRB wire DTO 或解析；Dart 内部模型增加可选诊断和既有错误字段。 |
| 缓存/并发 | 不新增业务缓存/重试/fallback；诊断为有界本机内存，不参与业务锁和路线决策。 |
| 错误/退出 | Core/CLI/Bridge 的 code/kind/retryable/message 不变；Dart 保留其原始意义和失败路线，不以文案反推。 |

Rust 传输诊断的具体前置比较和 RED/GREEN 另记 `source-parity-maintainability-transport.md`。本轮新增的诊断并不证明任何上游功能或真实 App 已通过验证。
