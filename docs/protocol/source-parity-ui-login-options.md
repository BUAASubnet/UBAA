# 登录选项与凭据失败恢复的双来源核对

日期：2026-09-15；生产修改前记录。旧版固定 `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`，示例固定 `efb7976bf513f38364b88aeb83d704586cff9b2a`，本次均经 `just refs` 核验。

## 已确认的行为差异

| 操作 | 冻结旧版 | 冻结示例 | 当前差异与修复要求 |
|---|---|---|---|
| 取消记住密码 | `composeApp/.../auth/AuthViewModel.kt:76–84` 同时关闭自动登录；`shared/.../api/storage/CredentialStore.kt:30–38` 清除保存值并关闭自动登录 | `src/store/cred.rs` 和 `context.rs` 没有两个UI选项联动 | 当前 `AppController.setRememberPassword(false)` 只改一项，可能形成不记密码却勾选自动登录的矛盾表单；恢复旧联动。是否清除已保存值仍按当前显式提交/清除契约，不额外产生即时磁盘副作用。 |
| 记住密码但不自动登录时恢复 | `AuthViewModel.kt:41–58` 同次恢复用户名与密码，只在auto时自动提交 | 示例凭据容器支持读取用户名和密码，没有手动登录页面 | 当前initialize只恢复用户名，密码仅在auto分支读取，因此“记住密码”不能用于下次手动提交。安全保险箱可用且确有保存值时，在登录表单恢复遮罩密码；auto=false不能隐式登录。认证成功或离开账号上下文释放密码。 |
| 成功登录后的本地保存失败 | 旧版先将isLoggedIn设为true，再保存选项/密码；本地Settings失败没有稳定领域错误 | 示例普通文件I/O返回错误，无UI行为 | 当前保存异常被统一catch成登录失败，即使上游已经认证。应保持已经确认的认证状态，明确提示未能保存，不自动再次登录或夸大“已记住”。需先写行为测试验证最终产品反馈。 |
| 退出并清除的本地删除失败 | 旧版CredentialStore.clear只删除自身四键，没有统一失败恢复测试 | 示例没有当前的用户退出/清除双操作 | 当前logout在清保险箱后才清用户/页面，删除异常可让已注销界面保留用户和业务数据。应在本地删除失败时仍完成会话及内存展示清理，并向调用者报告本机保存内容未清除；不能宣称删除成功。 |
| 无效凭据后的清除失败 | 旧版没有当前稳定保险箱错误接口 | 无对应UI恢复契约 | 当前invalidCredentials处理先await保险箱clear；若再抛错，可能跳过登录错误与阶段恢复。应始终回到可重试登录页并保留原认证失败类别；本地删除错误单独以脱敏诊断记录，不能导致转圈卡住或自动重试。 |

## 逐操作协议边界

以上五项都是本地表单/状态/系统存储操作，每项的业务 CAS/bootstrap URL、service 参数、重定向/最终URL、Cookie/session范围、HTTP方法/参数、请求头/编码及加密/签名常量均不增加、不替换。实际认证仍严格沿 [准备登录/登录九列](source-parity.md) 和 [登录/资料旧布局补充](source-parity-ui-profile.md) 的既有协议；不能把示例的普通凭据文件当成安全保险箱。

本地数据仅采用现有 `Credential(username: String,password: String,autoLogin: bool)`；不增加上游DTO、会话文件字段、公开Bridge schema或日志字段。联动不发请求；非自动恢复不发登录请求；失败不重发认证。异步恢复/保存/清除仍受controller销毁及账号生命周期保护，不能把迟到凭据回填到新账号。

旧版接口为AuthApi/LocalConnectionAuth，DTO为LoginPreloadResponse/LoginResponse及CredentialStore中的两个字符串/两个开关；旧测试定位AuthViewModelTest.kt、AuthViewModelInitializeAppTest.kt。示例最近模块为src/api/sso/auth.rs、src/api/user/auth.rs、src/store/cred.rs、src/context.rs：SSO请求/跳转/错误沿已有比较，不具有本地UI选项、Keychain或当前注销状态机，不按类比引入其文件存储。

缓存与并发变更只允许恢复已授权保存的同一账号凭据；未选记住密码、不可用保险箱、清除本机账号或账号切换后不能恢复旧密码。新增测试必须使用合成值，并先观察上述差异的行为失败。当前本页仅记录来源与待修要求，不是修复或验收通过证明。

## 登录页项目入口与选项点击范围

冻结 `examples/ubaa_old/composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/auth/LoginScreen.kt:227–236` 的项目文本具有clickable，并将固定公开项目地址交给LocalUriHandler；当前 `packages/ubaa_ui/lib/src/app/login.dart` 对应位置只有Text，无点击回调。当前About页已有typed `AppLink.project`、宿主 `PlatformAppInformation.open` 与系统浏览器能力；恢复登录入口复用该白名单和已有失败反馈，不由UI拼学校URL、不携带账号或会话、不触发登录。

同一冻结LoginScreen的两个选项Row可点击，Checkbox另有回调；当前_LoginOptions的文字没有动作。应使文字与复选框等价、一次点击只触发一次更改，busy/能力不可用时整行保持禁用。示例项目是API库，没有项目链接或复选框交互；两项均无学校HTTP、重定向、Cookie、加密或DTO变更，也不新增网络读取缓存。外链目标沿现有AppLink公开常量，失败不能静默无效。

已新增两个宿主层行为回归（只用合成backend和注入的AppInformation），从实际可见文字点击，而非直接调用UI回调；RED/GREEN结果另记。


追加清除边界：冻结AuthViewModel.logout成功时以LoginFormState()清空表单；当前明确“退出并清除本机账号”成功后仅清密码，仍残留用户名/记住/自动选项。这也是本地状态缺口；应清空明确要求删除的表单信息，同时普通退出继续保留已授权的系统保存值，不混淆两种操作。对应新增第六项App回归，协议九列不变。
