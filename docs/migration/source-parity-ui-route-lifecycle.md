# 连接策略切换与后台重建的迟到结果

2026-09-15，保留实施前 RED，并补 Task3E 修复事实。RED 时涉及的 `AppController.setRoutePolicy`、`rebuildBackend` 和认证辅助文件与 `a85d111cf5552ae4a1580e677caa1b32f20d6ae4` 一致；没有将博雅修改当成此缺陷来源。

## 已复现问题

当前设置回调先等待旧backend的 `prepareLogin`。其间后台可以重建backend，并从新实例恢复已保存的WebVPN策略和就绪会话。旧实例随后失败时，`setRoutePolicy` 只检查controller是否销毁，没有核对backend/认证代次，因而把表单策略改回旧直连值并带入过期错误。实际已保存策略仍是WebVPN，界面却显示直连。

独立合成探针调用真实AppController公开方法：初始直连就绪→延迟切换WebVPN→成功后台重建并确认新策略WebVPN→释放旧调用的失败。最后预期WebVPN，实际直连，成功编译后的断言失败，退出1。未调用真实学校接口或读取账号。

精确命令如下，运行目录为专项工作区 `packages/ubaa_app`：

```sh
just flutter test '<private-evidence>/macos-ui-20260915/route-lifecycle/late_policy_probe_test.dart' --no-pub --reporter expanded
```

日志为同私有目录的 `late-policy-probe-red.log`。探针及日志不进入Git。Task3E 已补正式
`packages/ubaa_app/test/auth/route_lifecycle_regression_test.dart`：旧成功/失败分别覆盖重建、新选择和退出。
首次修复后六项正式用例及原外部探针共七项退出 0，日志为同一专项私有目录下
`interactive-auth/route-lifecycle-initial-green.log`。设置回调只向捕获的 backend 读取，并在每次
await 后匹配 backend、认证代次、凭据修订和最新请求；原准备调用、默认解析与认证次数保持。

随后补充“旧切换在途时再次选择原策略”的两项行为回归：旧实现把该选择当作无变化而忽略，
成功编译后两项均失败（`interactive-auth/route-original-choice-red.log`，退出 1）。修复保留
`_routePolicyInFlight`，让用户的这次选择也成为新请求；八项正式回归加未修改的外部探针共九项通过
（`interactive-auth/route-lifecycle-final-green.log`，退出 0）。本批三个新增 App 测试最终统一归入
`test/auth/`；移动前后内容哈希一致，旧日志中的直属路径保留原始命令事实。

## 双来源与操作边界

旧版固定SHA为 `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`。`composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/menu/SettingsScreen.kt` 的当前模式由调用者传入，确认后通过 `onModeSelected` 回调；`ui/navigation/MainAppScreen.kt:557–571` 按模式变化重置领域状态，`:831–833` 将当前模式和切换回调传给设置页。旧版没有当前Flutter后台backend重建接口，不能照搬旧ViewModel的异步行为作为新实例的写入授权。

示例固定SHA为 `efb7976bf513f38364b88aeb83d704586cff9b2a`，没有Flutter设置页、AppController或宿主后台重建的对应操作。示例认证/URL包装不构成本次迟到UI回写的依据。

| 操作/来源 | CAS/bootstrap/service | redirect/finalURL | Cookie/session | HTTP/精确参数 | headers/body | crypto | DTO/parser | cache/concurrency | error/exit |
|---|---|---|---|---|---|---|---|---|---|
| 旧设置模式选择 | 沿既有认证合同，不新增请求值 | 不增加规则 | 旧模式变化重置对应领域状态 | 仅调用已存在模式切换回调 | 不适用新增编码 | 不变 | 当前模式由上层状态传入 | 未实现Flutter后台backend重建 | 不提供本项目CLI退出语义 |
| 示例 | 无对应UI/重建操作 | 不适用 | 不适用 | 不适用 | 不适用 | 不适用 | 不适用 | 不适用 | 不适用 |
| 本次修复 | 保留原准备和策略保存调用，不新增上游地址/service | 不变 | 不复制会话、不授权旧backend影响新实例 | 原参数/次数不因迟到结果而重发 | 不变 | 不变 | 保持BackendRouteSettings和既有公开版本 | 回写须属于当前backend、账号/认证代次及当前切换；旧成功/失败都不能覆盖新的状态 | 丢弃失效结果，当前失败仍如实反馈；不把旧错误写入新页面 |

本项纳入Task3E的认证/路线生命周期接线，需保留普通无验证码的行为回归，并覆盖旧失败、旧成功、后续新选择、退出及重建。不能只保护新验证码图片而继续让普通路线回调覆盖新会话。没有要求改变旧学校协议、默认路线选择规则或公开配置格式。


## 2026-10-02整合后的接续

当前冻结来源中设置页未变化，MainAppScreen只额外加入账号变化时重置；以上无新增学校请求的对照保持适用。新离线合同禁止路线变更在途时重建backend，因此正式测试对该分支验证“在途拒绝、收尾后重建重新核对”；同一backend的先后选择、再次原值选择、退出后的迟到成功/失败仍必须丢弃。只增加请求修订及当前账号/实例边界，不改变路线优先级、缓存来源或学校字段。
