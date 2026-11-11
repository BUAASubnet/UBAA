# 通用安全存储插件收敛

日期：2026-10-07。分支：`ubaa2`；起点 `e88ce9bf`。用户明确开发阶段不考虑已有数据迁移，使用新材料前缀v2，保留旧材料且不导入。来源与实施前九列裁决见[决策记录](../history/2026-10-30-decisions-through-quality-phase3.md#2026-10-07开发阶段统一安全存储插件)。

## 最终实现

官方五端的凭据、账号索引及缓存密钥统一经 `MaterialCredentialStore/SecureMaterialStore` 进入flutter_secure_storage 10.0.0。删除旧macOS credentials.*通道、Swift存储/交互策略及其专属测试；保留插件自己的macOS登录Keychain选项。原安全能力写/读/删闭环仍必需，Android明确关闭resetOnError与算法自动迁移，失败不回退明文。

OHOS宿主引入 `packages/flutter_secure_storage_ohos`，以社区HUKS fork的原生实现适配当前Dart/插件接口；相同标准插件通道承载操作，移除宿主SecureMaterialChannel。HUKS RSA-OAEP保护AES-256-GCM数据密钥，密文绑定键名，丢失密钥时拒绝读取或覆盖；插件错误不返回空值或假成功，不自动reset。来源指纹、许可证和局部修订说明保存在插件包。

安全材料/凭据错误采用明确中文提示与diagnostic cause，保留已有Core错误码兼容性；不再把已知凭据异常仅归为unknown。学校URL、认证字段、Core会话及业务缓存加密实现未改。

## 验证结果

| 类别 | 本次证据 |
|---|---|
| RED→GREEN | 旧通道被优先选择、凭据错误误报应用异常两项RED；OHOS原插件写入异常仍success(null)的RED；对应修复后通过 |
| Flutter | 7包分析及1339项测试全部通过：57/98/636/350/31/92/75；移除旧原生实现专属测试，新增统一插件接线、OHOS选项和类型诊断回归 |
| OHOS确定性 | 实际ArkTS源码经DevEco TypeScript加载，合成Preferences/HUKS边界；六类失败传播、后继操作、引擎串行、卸载保护、重开/Unicode/空值、篡改/跨键复制、落盘失败、HUKS拒绝及密钥丢失保全通过 |
| 工程 | refs、敏感扫描、结构与完整just check（含Rust/Bridge/CLI端到端、构建及文档）通过 |
| macOS原生 | 唯一合成凭据的插件写入、独立适配器读回、更新、非法输入拒绝、删除读回及照片能力回归2项通过；测试启动置前警告未影响测试完成，不据此冒称桌面鼠标验收 |
| macOS生产App | Release正式入口构建通过；独立文件配置启动，Computer Use实际确认登录表单可见、记住密码/自动登录可用且无应用内部错误提示。未登录学校账号 |
| OHOS构建 | 锁定Flutter 3.41.10-ohos-1.0.1/API26；Dart分析/测试及无签名Debug HAP构建通过，包含arm64 Rust动态库和生成注册的安全存储插件 |
| 未覆盖 | hdc无连接设备，不能声称OHOS设备HUKS、签名/发布或其他桌面设备安全存储本轮通过；没有真实学校登录/读取/写入 |

## 证据目录

`~/Library/Application Support/UBAA-private-evidence/unified-storage-20261007/`。原始日志、配置路径及运行材料不提交Git。构建产生的非本轮源码变更已还原，新插件的构建目录、HAR、oh_modules和本机锁文件已忽略。

| 日志 | SHA-256 |
|---|---|
| `plugin-red.log` | `e1506b9ea3641303238184c6c82910e2cbec61e7d171fb95def0766e9a62537f` |
| `plugin-green.log` | `71785c734e9c042f76d8ee01701e45b743345de85ed681032327fcc4f15c191d` |
| `ohos-channel-red.log` | `f870e70575b374eed106714ca1174aeabb30cab3c53aa79cbada35fab47e2e93` |
| `ohos-contracts.log` | `2f3dcc197a2082b9fafbed25a39f8e7d48640fd60d566c9875b8846e086162cc` |
| `flutter-check.log` | `ad07dbb56ac93d3212689fdb8972219af469dbbff949ec997956360de93c6777` |
| `core-check.log` | `d0b1c19c41c83dad5bceeb4009614e3b0326a13ea6ca688c48628d9e1a843fe1` |
| `macos-native.log` | `da18de5c5206f8cca87ddedddf8e1db74205d2b71da351739d047a7c39f069ff` |
| `macos-build.log` | `00b1196e2857df4ada421c17e57b230ceefd88eced218a250ee5c8fe6dd546c2` |
| `ohos-check.log` | `5dedcda0c788b481e0a1e5b03cbb547deeefef6a14952cb4f1f29fa3068f66ab` |

最终复核补充：新增引擎卸载后同一插件重新挂载场景，原在途回调与旧排队操作错误进入继任引擎的回归先RED；增加插件代次检查后GREEN。已经开始的系统写入不伪装可撤销，旧排队操作不会再执行，迟到结果不会报告成功。最终OHOS完整门禁及HAP再次通过，原生生产逻辑此后仅整理行尾空白。

- `ohos-generation-red.log`：SHA-256 `3aeffa004f3df667ae2983d558624e0125df1867bd29f5b2a40ab4f1756a9ecf`。
- `ohos-check-final.log`：SHA-256 `9884242f2867d822936d310ee6c6a1900809ed88ed8ddae73da584faab9e261c`。
