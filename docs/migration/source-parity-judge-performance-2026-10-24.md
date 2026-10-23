# 希冀读取去重：实施前双来源核对

冻结引用：ubaa_old `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`；buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`，本轮 `just refs` 通过。

已读旧版 `shared/.../api/feature/JudgeApi.kt`、`model/dto/Judge.kt`、`api/local/LocalJudgeApi.kt`、`commonTest/.../LocalJudgeApiBackendTest.kt` 及服务端 `JudgeClient.kt`。旧实现将课程选择与索引/详情置于同一互斥区，客户端激活复用；课程 worker 隔离业务 Cookie。每份详情都先选课，未做同课程选择去重。

已读 buaa-api 的 `api.rs`、最接近的 `api/class/core.rs`、`context.rs`、`request.rs`、`store/{cred,cookies}.rs`、`crypto/mod.rs` 和 `error.rs`。它没有 Judge 协议；课堂模块的 token、URL 和 DTO 不适用于希冀。本轮不借用示例的 TLS 配置或凭据规则。

当前 Core 分批扫描每项详情再次 GET 选课，同课程连续 2 项详情也重复选择。本轮只在同一 runtime 已成功选择、功能代次相同且期间没有课程入口、重新激活或其他 worker 使用时省略重复选择。跨批持有的是已确认课程标识，不复用 Cookie 或复制客户端；不同课程仍须选择。保留 WebVPN 整课程串行和 Direct 的既有隔离 worker 上限。

| 操作 | CAS/bootstrap、service | 重定向/最终地址 | Cookie/会话 | 方法和精确参数 | 头/编码 | 加密/签名 | DTO/解析 | 缓存/并发 | 错误语义 |
|---|---|---|---|---|---|---|---|---|---|
| 激活/课程目录 | 现有 HTTPS SSO service=HTTPS Judge 根地址，沿既有在线认证证据 | 原 get_with_redirects 和业务登录页检测 | 原路线 runtime；激活清除已选课程 | GET courselist.jsp?courseID=0 | 原浏览器头，无正文 | 无新增 | 原 Course | 原目录 TTL；真实目录请求清除选课标识 | 原三次业务重激活与 UC 仲裁 |
| 课程作业索引 | 沿用激活 | 原校验 | 同 runtime 选课上下文 | GET courselist.jsp?courseID=ID，再 GET assignment/index.jsp | 同上 | 无新增 | 原 AssignmentList | 相同课程且状态有效才去重选课；索引读取与缓存语义不变 | 请求失败使选课记忆失效 |
| 作业详情/批量 | 沿用激活 | 原校验 | 相同课程复用选课；跨课程重新选择 | GET assignment/index.jsp?assignID=ID，参数不变 | 同上 | 无新增 | 完整 detail、题目、成绩和状态均不变 | 原详情 TTL；分批强制读取仍强制取详情；派生 worker 时父状态失效 | 重激活后必须重新选课；原错误分类、取消、账号与路线代次保持 |

这是对旧版重复请求的显式优化，不宣称旧版已实现去重。上线前必须通过选课状态严格校验的 Mock、跨计划交错与失效回归，并以两条真实路线确认完整读取结果。未从缓存列表推断服务端当前课程。

## RED、实现与保留覆盖

生产代码修改前，`segmented_cached_scan_reuses_activation_without_skipping_selection_or_data` 将课程 12 的选课请求期望改为 1，实际为 3，退出 101。完整日志保存在仓库外本轮私有性能目录的 `judge-red.log`。

选课记录属于 ClientRuntime，不进入共享 RouteFeatureState 或持久会话；记录同时保存 Judge 功能代次。派生 worker 撤销父记录并从空记录开始，既有 Cookie 过滤不变。课程入口、激活和请求错误清空记录；重激活后的重试仍恢复目标课程。不同计划交错时以 runtime 的当前课程为准，不以计划游标推断服务器状态。

新增交错扫描回归，继续通过传输层的课程 Cookie 检查验证每份详情归属；为同课程详情去掉旧测试中多余的选课请求期望，保留激活、索引、详情、历史过滤、主登录失效、网关地址与完整队列耗尽断言。没有删除业务测试。分批扫描 30 项、readonly 中 Judge 31 项通过。

## 实时前后样本

同一隔离验证入口 `just verify-live mode=<route> feature=judge`，每条路线修改前后各一次。均为新进程、新隔离会话；依次认证、包含过期的完整集合、当前集合、详情和批量详情。

| 路线 | 修改前到当前列表就绪 / ms | 修改后 / ms | 完整集合 / 当前集合 |
|---|---:|---:|---:|
| Direct | 7070 | 4833 | 96 / 42 |
| WebVPN | 17744 | 15744 | 96 / 42 |

两路线各步骤 PASS，课程数均为 6，解析原始锚点数 104。累计时间包含认证及前置集合读取；这是单次网络样本，不作为 P95 或原生首页完整加载时间。确定性收益是同课程连续索引与详情只选课一次；示例两课程三详情的选课请求从 5 次降为 2 次，索引和详情数量保持。

完整 Flutter 格式、分析和七包测试通过：domain 53、platform 87、app 660、UI 380、bindings 20、host 101、官方应用 79，共 1380 项。FRB 生成零漂移，macOS Debug 构建通过。

最终全功能真实只读 `just verify-live mode=direct` 和 `mode=webvpn` 均退出 0，各 40 PASS、0 FAIL。首次 Rust 全量检查发现三个 Bridge 脚本仍期望冗余选课，已只删除详情前的重复请求期望，保留批次让位、写意图保留、取消零请求、数据保存与队列耗尽断言，随后重新执行完整门禁。

最终 `just check` 退出 0，包含 Rust/Shell、CLI 端到端、布局、模块与文档门禁；`just flutter-check`、`just flutter-codegen-check`、`just refs`、敏感扫描和 `git diff --check` 全部通过。Bridge 四项扫描回归通过，所有原业务断言保留。最终生产逻辑已包含于本轮构建的 macOS Debug；本轮没有测量完整原生首页冷启动分位数。
