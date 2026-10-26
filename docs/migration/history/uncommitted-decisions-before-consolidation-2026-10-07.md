# 整合前未提交文档归档

归档日期：2026-10-07。以下为旧工作树原始记录，仅保留历史依据；其中冻结版本、接口版本、待提交状态和验收结果不代表当前候选。当前合同见[goal.md](../../../goal.md)，当前状态见[迁移状态](../status.md)。

---


## 2026-09-15：新手动交互登录与旧账号会话隔离

Task3E接线时发现，现有AuthWorkflow在prepare收到3xx并验证既有会话后，会将authenticated_ready置真；随后login直接返回该会话资料，不核对输入账号。因此新手动输入账号B时，不能让账号A留下的Cookie或准备状态进入新的交互上下文。定位为`crates/ubaa_core/src/auth/mod.rs:74–125`。冻结旧AuthViewModel:90–107同样把preload返回的userData直接作为已登录，未提供与新输入账号绑定的挑战机制；固定示例`src/api/sso/auth.rs`只有普通SSO/VPN认证，也没有新交互句柄和双路线所有权机制。不能把旧会话恢复当作账号B的新认证成功。

裁决：只在用户明确发起一次新的手动交互登录、创建新账号上下文时，允许通过当前Core实例已有的会话所有权/CAS机制清理其两路本地旧槽位、Cookie、待准备认证状态和旧交互句柄；不调用远端logout、不修改凭据保险箱或其他账号偏好。普通启动的已有会话恢复保持原行为；同一交互上下文的刷新、答案提交、补全另一条路线和“使用已就绪连接”不得重新清理成功槽位。任何所有权冲突或清理失败必须在新网络请求前安全失败，不采用外部新会话或报告假成功。清理仅作用于调用实例所属配置目录，不触碰其他实例/默认用户目录。

| 操作 | CAS/bootstrap/service | redirect/finalURL | Cookie/session | HTTP/精确参数 | headers/body | crypto | DTO/parser | cache/concurrency | error/exit |
|---|---|---|---|---|---|---|---|---|---|
| 创建新手动交互上下文 | 继续专用显示来源已有地址，无新service | 原有有界规则不变，不借旧Cookie的3xx跳过本次身份建立 | 当前实例所有权校验后清两路旧本地槽位与认证内存；同上下文成功槽位保持 | 不增加远端logout或其他学校请求，后续准备沿已证GET | 不变 | 不变 | 上游id/execution仍不出Core；新句柄绑定当前输入账号代次 | 同步作废旧句柄，复用clear_both原子CAS并更新两路revision；冲突不可接管外部快照 | 清理/所有权失败在请求前拒绝；旧非交互CLI合同不变 |

实施必须先补合成回归：带账号A旧Cookie/已准备状态时发起账号B新上下文，不能返回A成功；刷新或补全第二路不清第一路成功；旧所有权失效时零新HTTP。上述是本地身份隔离决定，不声称证明新的上游协议。若决定过严，成本是用户明确重新登录时无法复用旧会话、需重新认证；可以在未发布专用接口内凭更精确身份依据收窄清理，但不能以复用错账号为代价。

## 2026-09-15：Auto部分就绪继续的可用性

Task3E扩展合成用例实际发现：Auto探测为Campus而仅WebVPN就绪时，原继续实现保持Auto/partial/profile后，`get_user_info()`仍以Direct返回AuthenticationRequired。主线核对`config.rs:432–442`：所有读取的SAFE_DEFAULT都禁止ready-route fallback；`facade/routing.rs:52–85`按现有探测选择路线，再拒绝未就绪路线。两个固定策略不匹配方向的配置切换及随后facade合成资料读取已通过。这是“无条件保持Auto仍可直接进入可用主页”的计划假设错误，不是新发现全局路由应当开启fallback。

旧SettingsScreen只有用户明确选择连接模式后的确认与取消，没有本项目双路线部分就绪的Auto继续机制；固定示例的共享Context普通认证也没有该交互。继续沿既有[连接生命周期对照](../source-parity-ui-route-lifecycle.md)与[专用显示来源](../source-parity-ui-sensitive-displays.md)，不从两源推导自动跨路线回退。

裁决：普通Auto继续先使用现有解析规则确认其选中路线就绪，成功才结束交互且保持Auto。未就绪时保留原Auto、成功槽位、资料和交互上下文，返回可恢复提示；UI另提供明确“改用直连/WebVPN并继续”，用户点击后才原子保存对应固定策略并继续。也允许用户完成另一条路线后继续Auto。全局SAFE_DEFAULT、无网络回放和其他操作的路由规则不变；不引入隐藏临时覆盖。保存失败同样保留可恢复交互，不重发已完成认证。

本地操作九列沿前项：CAS/service、URL/redirect、HTTP参数、Header/body和加密不变；Cookie只继续已有就绪槽位，不新增认证；新增的是本地typed继续选择及按原策略验证可用性；代次/所有权和取消规则不变；失败留在交互，不把cached profile当成当前策略可读取的证明。原失败用例必须保留实际读取断言，改为验证普通Auto继续受控拒绝，以及用户明确改用WebVPN后同一上下文读取成功且零新增认证POST；同时覆盖相反方向、Auto本已选中ready和保存失败。

本裁决修正之前“Auto一律保持即可继续”的范围。若交互取舍不合适，成本为部分就绪时多一次明确选择，选择固定路线后需要用户稍后改回Auto；这些成本可在未发布UI/API内调整，但不能以静默改变全局路由或让用户进入不可用主页替代。


## 2026-09-24：安全材料写入闭环与成绩基线保存根因

用户现场看到“成绩可在线查看，本机变化记录暂不可用”。追查发现，`SecureMaterialStore.probe()` 只读探测键；而宿主只判断 `secureMaterials != null`，没有判断 `isAvailable`。因此安全材料读探测失败时仍可能构造 `SecureLocalAccountStore`，首页可以继续在线读取，但本地账号密钥或成绩基线写入在真正的 Core 加密边界才失败并返回 `unavailable`。这不是学校成绩读取失败，也不是允许改成明文保存的理由。

先新增“只读可用、写入失败不得报告可用”的行为测试，旧实现按预期失败，日志`/tmp/ubaa-secure-material-probe-red-20260924.log`，SHA-256=`200b02714ca1b4b2494708853554f45f85bb600cf2fb36ccfc1702462d98c8b4`。最小修复让探测键执行写入、读回、删除闭环，并在失败时清理后返回不可用；平台默认能力和宿主同时以 `isAvailable` 为接线条件。GREEN 平台测试日志`/tmp/ubaa-secure-material-probe-green-20260924.log`，SHA-256=`313c5a613d0620ecfef024089d3db325d7f410dcaad73f8aa8f587248c5c0b1f`；宿主不可用接线 RED/GREEN 分别为`/tmp/ubaa-secure-material-wiring-red-20260924.log`（`ff2b7964ef183121f332ed1be04af1a84bdcf34f90475ed6ed55001ba122a4c1`）和`/tmp/ubaa-secure-material-wiring-green-20260924.log`（`c437ee4ba1944d81ce85a977ce27d556849c71c60c99947ce069bac4af097ef4`）。

另一个独立边界是退出、重建或清理期间的迟到成绩观察。`operation_conflict` 表示本次本机保存已被生命周期撤销，不应变成“本机加密保存故障”；对应 RED/GREEN 日志为`/tmp/ubaa-grade-conflict-red-20260924.log`（`2ed0a62612a40cca8292736fd7d72acae97a7c9bf57209d47a66834fdd121219`）和`/tmp/ubaa-grade-conflict-green-20260924.log`（`c313dc58cc99752857ca31b52db306b4070183f51cd1864c73532d53268e2fc8`）。成绩基线仍由 Core AES-GCM 仓库保存，密钥或本地存储不可用时继续在线只读，但不生成替代明文。

现场提示的文案处理另已提交`f89dc2d5`：成绩基线的次级保存失败不再冒充全局连接状态；首页只在内容已显示后以简短说明提示暂未保存，希冀过渡状态改为“在线读取中，离线保存稍后重试”。这项文案调整不替代上述根因修复。平台真实 macOS 安全材料写入、读回和清理集成测试通过，日志`/tmp/ubaa-secure-material-macos-green-20260924.log`，SHA-256=`50e254d22a20fa3e6e57adb97dc932853346ef74c1970c5b28ae92781a583b4f`。本批没有改变认证、学校只读 URL、参数、Cookie 或 Bridge 协议，因此无需新增冻结来源协议对照。
