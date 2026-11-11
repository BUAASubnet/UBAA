# 独立工程审查修复：Dart 认证终态与状态所有权来源对照

日期：2026-10-07。改动前基线 `06e4dfdb91303d1d723cbf570bd0fc49b55bf73e`。本记录只覆盖 I03/I04 与 I06 的有限状态边界收敛；不调整 Core/FRB 协议、DTO、持久格式、真实账户或学校请求。

## 冻结核对与权威

实现前 `just refs` 通过：旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`，独立示例 `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`，目录均只读。

直接核对旧版：`composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/auth/AuthViewModel.kt` 的登录/失败/退出终态，`composeApp/src/commonTest/kotlin/cn/edu/ubaa/ui/{AuthViewModelTest,AuthViewModelInitializeAppTest}.kt`；`shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalConnectionAuth.kt`、`api/feature/{GradeApi,ScheduleApi}.kt`、`api/local/{LocalGradeApi,LocalScheduleApi}.kt`、`model/dto/{Auth,Grade,Schedule}.kt`，以及 `shared/src/commonTest/kotlin/cn/edu/ubaa/api/{LocalAuthServiceBackendTest,LocalAuthSessionStoreTest,LocalScheduleApiBackendTest}.kt`。旧 ViewModel 在普通失败退出 loading；其单模式界面没有当前双路线完成 token 或安全材料失败后的原位换号合同，不能照搬其全局重置。

直接核对独立示例：`src/api/sso/auth.rs`、`src/api/user/{auth,opt}.rs`、`src/api/aas/{core,opt,data}.rs`、`src/context.rs`、`src/request.rs`、`src/store/{cookies,cred}.rs`。示例没有同构 Flutter 交互完成、加密业务仓库或当前 buaascore 成绩接口；其 Cookie/凭据文件及可选忽略证书开关不能移植。未发现本次需选择的新上游冲突；现有协议差异仍由下列现行逐操作矩阵决定。

完整既有协议依据：[主矩阵](source-parity.md)、[离线/恢复矩阵](source-parity-offline-recovery-2026-09-17.md)、[交互认证矩阵](source-parity-interactive-integration-2026-10-02.md)。此处逐操作列出九项边界，N/A 仅表示本次纯本地动作不发相应请求，不表示来源可省略。

## 逐操作对照

| 操作 | CAS/bootstrap/service | 重定向/最终 URL | Cookie/Session | 方法与精确参数 | Header/正文编码 | 加密/签名 | DTO/解析 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|---|
| 非交互登录最终完成 | 旧 SSO `/login` 与 UC 激活；示例同 SSO、用户模块仅激活；本次继续既有 backend.login/userInfo，不增 URL/service | Core 既有同路线跳转/最终 UC 验证不变；Dart 不解析 URL | 旧模式隔离，示例共享上下文；当前 Core 双槽位不变 | 原 username/password/execution/_eventId/submit/type 及当前认证流程均不变；不新增参数 | 旧/示例 form-urlencoded；本次不接触 HTTP | 登录无新增加密；WebVPN 编解码不变 | 保留 UserSummary username/schoolId 与既有字段，身份不符不接纳 | 新完成 scope 只接受同 backend/生命周期；不创建第二客户端、缓存或写状态机 | 明确错配回 login，失败可重试输入但不自动重发认证；旧成功路径与凭据保存顺序保持 |
| 交互登录最终完成/原位换账号 | 沿交互专项既有 SSO/UC；旧支持 captcha，示例无同构验证，不借其流程 | 原 Core 有界路线与 ready 选择不变 | 挑战仍仅原后端/路线使用，完成 token 与已释放挑战分离 | 原 begin/submit/continue 参数不变；不重复提交验证码/密码 | 原编码不变，像素/答案不落盘 | 不新增算法/常量 | 仍用 InteractiveLoginCompletion(user,settings)，不公开挑战内部 | 旧账号关闭后才换本地身份；scope 隔离迟到成功/失败；原位页面与草稿保留 | 关闭旧安全索引/缓存失败必须报告并结束 loading，禁止把当前错误当过期挑战吞掉；不得冒充登录成功 |
| 注销及恢复后路线设置投影 | routeSettings 是 Core 本地状态，不发 CAS；旧有切模式重置，示例无同构双槽位 | N/A：本地 DTO 读取不产生跳转 | 不改变 Core 清 Session；仅阻止已退出/换代后的 DTO 写回 UI | routeSettings() 参数不变；logout 调用次数及顺序不变 | N/A：本地 DTO | N/A：无新增加密 | defaultPolicy/activeRoutes 类型不变 | scope 统一核对 backend/生命周期；路线变更推进该生命周期，成功和异常都不能污染新状态 | 旧快照不恢复活动路线/策略；当前读取失败仍清不确定槽位并记安全诊断；CLI 不改 |
| 学期索引与当前学期消费 | 旧 LocalScheduleApi 的 AAS 激活/currentUser，示例有另一 AAS 配置；沿现有 Core，不借示例 service | 原 AAS 最终 URL/本科判断不变 | 当前实际路线单会话 | 旧 GET schoolCalendars.do，无业务参数；请求与调用次数不变 | 既有 AJAX Accept/X-Requested-With/Referer | 无新增加密 | Term itemCode/itemName/selected/itemIndex 不变；唯一 selected 才作当前学期，不猜第一项 | 由明确 CurrentTermsReader/cache owner 持有结果与读取 scope；同代在途合并、force 绕过已完成缓存保持 | 原认证/不支持/解析错误不变；失效返回 operationConflict，不借过期学期 |
| 成绩按学期读取/聚合 | 旧 GET `https://app.buaa.edu.cn/buaascore/wap/default/index` 激活；示例 AAS 非同协议，无等价成绩实现 | 原 SSO/401/登录 HTML 仲裁不变 | 原账号/实际路线，不从展示缓存赋予会话 | 同 URL POST，xq/year 沿 term 解析，完全不改 | 原 HTML/AJAX Accept、XHR、Referer、form-urlencoded | 无新增加密 | e/m/d 与 courseName/code/score/credit/courseType/scoreType/term 映射不变 | 成绩仅消费窄学期读取能力与 ReadScope；在途共享、优先级提升、完整统计、离线证据不变 | 错学期/不完整/认证失败不成为出分基线，原 UiError/CLI 语义保持 |
| 业务内存缓存清理与 backend 重建 | N/A：本地失效，无学校请求；旧 ScheduleRepository/缓存为领域级，示例只有认证存储 | N/A | 清业务缓存保留账号/会话；重建沿既有 backend 释放顺序，不迁移 Cookie | N/A：不添加网络请求；只统一既有清单到 owner.invalidate | N/A | SQLite/AES-GCM/安全密钥及清理次序完全不改 | 现有 FeatureSnapshot/展示字段、查询位置不变 | 集中领域缓存 owner 及 academic owner 失效，取消旧计划、serial 防晚到清理；保留原 stale/空投影策略差异 | 原清理失败保旧、事务/维护错误区分不变；不自动补发读取或真实写入 |

## 行为与验证约束

正式回归从独立审查的五个纯 fake 反例开始，必须先记录 RED。另覆盖完成阶段退出/销毁/关闭缓存失败、迟到路线失败不清新状态、学期 owner 失效和成绩查询共享、清理/重建字段保持。测试不读取凭据、不启动原生设备、不联网。

保留公开 AppController 构造/方法、ChangeNotifier 实例、WriteCoordinator 单一权威、Bridge contract v40、CLI v11 与 cache schema v6。新内部 scope/owner 不由 package barrel 导出。UI/Host 行为通过既有 package suites 验证；此次确定性通过不替代原 B2/C2/C3/D 真实/设备欠验。

## 落地范围与本轮确定性证据

- `session/completion.dart` 是认证完成终态的唯一局部实现，私有 token 与挑战 engaged 分离。身份不符结束 loading、清活动路线并关闭本地旧账号入口；旧完成或存储错误不影响退出后新表单。已明确区分“关闭旧账号失败”与“成功在线登录但保存本机材料失败”，后者沿原合同保留成功及反馈。
- `state/read_scope.dart` 集中后端/会话/读缓存代次有效性；路线快照的成功及异常均先核对同一 SessionScope。退出/销毁独立释放 loading 和表单密码，不等待迟到任务。
- `state/academic_terms.dart` 私有持有学期结果、在途 Future、优先级 demand 与 serial；成绩只经 `CurrentTermsReader` 和 `ReadScope` 获取当前学期。`state/read_caches.dart` 提供唯一内存缓存失效入口，业务清理和 backend 重建继续分别控制空投影与 stale 投影。
- 生产改动仅在 `packages/ubaa_app/lib/src/controller/`。新增测试为 `test/session/completion_boundary_test.dart`、`test/reads/cache_ownership_test.dart`；既有 `test/session/preferences_test.dart` 仅增加两项“销毁立即清密码”断言，没有删除旧断言。没有 Host/Platform/UI/FRB/Core 生产改动来自本阶段。

日志根目录：仓库外 `<private-evidence>/legacy-tmp/ubaa2-engineering-dart-fix-20261007`，只含合成身份与安全断言。

| 阶段/命令（在 packages/ubaa_app 下） | 实际结果 |
|---|---|
| 原五个正式反例 `flutter test --no-pub --reporter expanded test/session/completion_boundary_test.dart` | RED，5 失败；`red.log` |
| 仅补充“迟到错误不能覆盖退出后的新表单” | RED，拒绝身份清理/保存账号两项失败；`red-completion-late.log` |
| 身份拒绝后的活动路线断言 | RED，交互错配仍显示两个旧活动路线；`red-rejected-routes.log` |
| 初始修复 + 原 auth/interactive 测试 | 23 项通过，五个原反例全部 GREEN |
| 新反例、独立缓存 owner、academic、grades、cache/management、recovery/backend_rebuild | 120 项通过；`focused-green.log` |
| `flutter test --no-pub --reporter expanded` | 首轮 645 通过/2 失败；原有销毁后密码释放断言发现原 finally 被 scope 取消后销毁尚未主动清密码，记录 `app-full.log`，没有删改失败断言 |
| 修正销毁立即释放后，preferences + completion_boundary | 35 项通过；`session-final.log`。新边界文件现共 8 场景，缓存 owner 3 场景 |
| `flutter analyze --no-pub` | 最终通过，无诊断 |
| `git diff --check` | 通过 |

完整工作区 Flutter、Rust/Shell/敏感检查及原生集合由主任务在合并候选上统一执行并记录；本表不预先声称它们通过。未执行真实账号、Direct、WebVPN、学校写入或设备验收。App 既有原位草稿、写资格、单次写入、失效/重建与成绩来源测试均保留。
