# macOS 系统凭据存储的双来源核对

日期：2026-09-15。此记录先于生产代码修改；`just refs` 已核验冻结旧版
`6e75e120a26b0eefb3ab4a6f8251d1230db4a62e` 与示例
`efb7976bf513f38364b88aeb83d704586cff9b2a`。

## 来源与范围

- 旧版 UI：`composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/auth/LoginScreen.kt`
  与同目录 `AuthViewModel.kt`。记住密码恢复用户名和密码；开启自动登录会开启记住密码，
  取消记住密码会关闭自动登录；只有业务认证成功后才保存选项与凭据。
- 旧版本地实现：`shared/src/commonMain/kotlin/cn/edu/ubaa/api/storage/CredentialStore.kt`。
  `Settings` 分别保存两个字符串和两个布尔值；`clear()` 只清除自身四键。
  `AuthViewModel.logout()` 负责认证/表单复位，不等同于此存储的 `clear()`；本次不改变当前
  App 区分退出与清除本机账号的生命周期。
- 旧版测试：`composeApp/src/commonTest/kotlin/cn/edu/ubaa/ui/AuthViewModelTest.kt`
  验证表单与认证状态数据；`AuthViewModelInitializeAppTest.kt` 验证初始化、持久会话和
  上游超时不重登，并在前后清除旧版凭据。它们不构成 Keychain、原子保存或安全存储失败证明。
- 示例：`src/store/cred.rs` 的 `CredentialStore` 用 `Option<String>` 保存用户名/密码，
  `from_file/to_file` 使用普通 JSON 文件；`src/context.rs` 以 `AtomicCell` 持有凭据，
  `set_account/get_cred/load_auth/save_auth` 访问它。没有当前的记住/自动开关、Keychain
  或清除单个安全条目的接口；不可类比补出不存在的协议。
- 当前边界：`packages/ubaa_platform/lib/src/credentials.dart` 已定义
  `credentials.capability/read/write/clear`，默认命名空间为
  `com.buaa.ubaa.credentials.v1`。此前 macOS `PhotoChannel` 仅处理照片与权限，能力探测
  因方法缺失安全返回 `false`。本次只补平台实现，不改 AppController、Bridge 或上游协议。

## 逐操作九列

| 操作 | CAS/bootstrap 与 service | 重定向与最终 URL | Cookie/session 范围 | HTTP 方法与精确参数 | 请求头与正文编码 | 加密/签名常量 | DTO 与解析字段/类型 | 缓存与并发 | 错误与退出语义 |
|---|---|---|---|---|---|---|---|---|---|
| 保存/更新 | 两来源此本地操作无 URL；沿既有认证合同，不新增 service | 本地存储无跳转 | 旧版仅自身 Settings；示例凭据与 Cookie 分容器；当前 Keychain 不接触 Core session | 不发 HTTP；旧版 username/password 加独立开关；当前方法参数为 namespace、username、password、autoLogin | 无请求头；旧版 Settings、示例 JSON；当前三字段二进制 plist 仅交给 Keychain | 两来源无系统 Keychain 协议；使用 macOS 系统密钥链，不复制明文存储或添加业务加密常量 | username/password 必须为 String；用户名 trim 后非空、密码非空；autoLogin 必须为真正 Bool，数字 0/1 不代替 Bool | 旧版依序写四键，示例 AtomicCell 后整文件序列化；当前原生串行队列，精确更新同一条目，不存在才新增，重复新增竞争只重试一次更新；无明文缓存 | 缺字段/错类型/无效值返回稳定输入错误；系统拒绝返回不可用或存储失败；真实写入成功才回复成功，不影响既有业务认证语义 |
| 读取 | 两来源无 URL；不调用登录 | 无跳转 | 不读取或导入 Cookie、Token、旧 Settings、示例文件或 Core 会话 | 不发 HTTP；只接受明确 namespace 字符串，不回退默认值 | 无请求头；从 Keychain 的数据字段解码二进制 plist | 由 macOS Keychain 解密；不自造密钥/算法 | 无记录为 null；有记录只返回 username:String、password:String、autoLogin:Bool；损坏/不匹配拒绝 | 旧版按 remember 恢复表单，示例访问 AtomicCell；当前每次精确查询，不保留跨调用明文缓存；新适配器可读取同一条目 | 无记录不是错误；损坏数据为稳定存储失败；锁定/拒绝为稳定不可用；不自动清除、重登或记录正文 |
| 清除 | 两来源无 URL；不追加注销 HTTP | 无跳转 | 旧版只移除四键；示例无对应安全条目删除接口；当前只删除 namespace 对应的本应用条目，不清系统 Keychain/其他账号 | 不发 HTTP；只接受明确 namespace 字符串 | 不涉及正文编码 | 使用系统 SecItemDelete，不操作密钥材料 | 无返回凭据；缺失/无效 namespace 拒绝，不能成为宽查询 | 串行、幂等；存在时删除精确条目，无记录视为已清除；无内存影子记录 | errSecItemNotFound 为成功；其他系统失败归约并返回，不能虚报删除完成；App 退出/清除失败恢复由独立任务处理 |

实际业务认证九列继续以 [主对照](source-parity.md) 为准。UI 的联动与失败恢复另见
[登录选项对照](source-parity-ui-login-options.md)，本任务不修改这些状态机行为。

## 系统实现决策与验证边界

采用 macOS 系统 Keychain 的 generic-password 条目；固定应用服务
`cn.edu.buaa.ubaa.credentials` 与调用者传入的 namespace 作为 account，所有查询、更新、
新增、删除均精确带上两者及 `synchronizable=false`。不启用 iCloud 同步，不查询整个密钥链，
不将真实用户名作为可检索属性，不提供文件回退。macOS 登录 Keychain 采用系统现有保护与
应用访问控制；操作禁止弹出认证界面，受锁定/访问拒绝影响时明确失败。能力探测仅说明原生
实现已注册，不读取任何已保存凭据，也不保证某次系统操作必然获准。

统一 `PlatformChannel` 拥有 `cn.edu.buaa.ubaa/platform`，组合照片处理器和凭据处理器；
不重复注册同名 handler。Keychain 接线不依赖照片的 macOS 11 最低版本，保留项目 macOS 10.15
构建目标；照片仍仅在 macOS 11+ 注册。原生失败类别固定为 `credentials_invalid_input`、
`credentials_unavailable`、`credentials_storage_failure`，不返回 OSStatus、原始错误或秘密。
上层 `PlatformCredentialVault` 仍使用现有稳定领域错误归约。

先运行原生 integration 测试，预期旧实现的 `probe()` 为 false；再最小实现并重跑同一测试。
真实测试只使用本次唯一的 `com.buaa.ubaa.credentials.test.<unique>` 与合成值，所有写入均
由 finally 精确清除；覆盖新适配器读取、更新、无记录、输入拒绝及照片探测。系统错误和精确
寻址另由注入 Security 调用的原生测试验证。真实 native、确定性测试、锁屏状态与真实 App
业务验收分开记录，不能互相替代。
