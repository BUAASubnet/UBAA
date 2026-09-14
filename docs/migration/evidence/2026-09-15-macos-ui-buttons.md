# macOS App 逐按钮专项证据

日期：2026-09-15。目标保持旧版完整功能对照与真实macOS逐按钮验收；本页按阶段区分证据，不代表整体完成。

## 基线与真实前置操作

- 开始源码：ea288d4e2efd0ac936efaeaf2e8630df2004a48c；原工作区SECURITY.md删除保留，本专项使用独立worktree。
- 两冻结引用重新校验通过，旧版6e75e120a26b0eefb3ab4a6f8251d1230db4a62e、示例efb7976bf513f38364b88aeb83d704586cff9b2a。
- 锁定Flutter 3.41.9下重建生产macOS Debug App退出0；使用独立配置目录和授权凭据，computer use分步聚焦/输入/提交后真实登录成功，首页课程、待办及各来源实际直连路线已观察。
- 首次前置产物的登录失败保留：辅助功能setValue未同步Flutter显示，离线截图识别证实仍是合成示例账号；同凭据Core认证通过，重建产物自然输入后App成功。不把工具输入差异判成账号无效。
- 后续路线策略下拉时Mac锁屏，工具明确返回无法解锁；已请求用户手动解锁，剩余真实UI按钮尚未通过。没有绕过锁屏。
- 全部运行媒体与原始输出在仓库外私有目录，仓库仅记脱敏结论；未提交真实账号、照片、会话或响应正文。

| 基线命令 | 退出码/范围 |
|---|---|
| just refs | 0，两个引用 |
| just flutter-check | 0，723项：54/59/270/248/15/23/54 |
| just verify-live mode=direct | 0，40 PASS |
| just verify-live mode=webvpn | 0，38 PASS；希冀单项和批量详情因父列表无作业ID，2 NOT_APPLICABLE |

两路线均未执行学校业务写入；研讨室用途的static_fallback保留来源标记，不能当成实时数据读取。

## K1：macOS安全凭据通道

源码缺口为macOS没有credentials.*原生handler，导致记住密码/自动登录被永久禁用。现统一PlatformChannel分发CredentialHandler与PhotoHandler；Keychain固定服务+namespace精确定位单项，禁止同步和明文回退，错误不含系统正文或凭据。

| 验证 | 结果 |
|---|---|
| native RED，旧生产代码 | credentials.capability预期true而实际false；1失败，照片1通过，退出1 |
| 同一native测试GREEN | 2/2通过，退出0；唯一合成namespace保存→新适配器读→更新→拒绝非法输入→清除→finally读null，照片探测保留 |
| availability调整后native重验 | 2/2通过，退出0；Keychain不被照片macOS11要求限制 |
| Swift注入Security测试 | 退出0；精确查询/no-sync/严格Bool/损坏值/系统拒绝/新增更新竞争，不访问系统Keychain |
| 平台与既有相关回归 | platform60、host23、controller105、Flutter host3、账号UI6通过；四包analyze无问题 |
| refs/layout/sensitive/check | 全部退出0；layout无baseline违例，敏感检查5158文件；check含CLI和Bridge现有合同 |
| lib/main.dart macOS Debug重建与产物检查 | 退出0；实际签名Sandbox和network.client为true；未将测试入口产物作为生产产物 |

产物检查SHA-256：27ec671b08b6f663d818f8c8a4efb22d0e613e6ea1ea7f4f60f4c88e816738d0。证据逻辑路径分别为keychain/native-red.Wf8FyP、native-final.mruiWB、native-unit.QMVoPh、flutter-checks.dHr4Lx、account-ui.n2e17Q、repo-gates.YzAMak；本机私有绝对路径仅存在外部运行记录。

主线独立检查原生实现、通道路由、Xcode Sources、错误/数据边界和实际日志，未发现本批未解决的实现问题。该阶段不宣称真实账号记住密码、自动登录、跨进程重启或最终全部UI通过。上游协议和公开Bridge/CLI版本未修改。

## L1：登录按钮与失败恢复RED

新增login_preferences_regression_test.dart五项均按预期失败：取消记住未关自动、非自动恢复缺密码、保存失败错误回登录、清除失败退出保留主界面、认证失败时删除异常未被隔离。新增login_buttons_regression_test.dart两项均按预期失败：项目文字未调用宿主打开、选项文字点击无效。

这些是已复现的待修问题，不能将上一轮723项基线作为新增测试通过。修复后需同用例GREEN、宿主反馈验证及computer use复测。


### K1独立复审追加

阶段提交708a6250之后，独立审查提出两项待修问题：当前使用legacy登录Keychain，仅设置LAContext不能充分保证拒绝访问时无系统弹窗；原生照片测试对所有macOS要求可用，与10.15生产分支不一致。后续修复前K1不视作最终关闭。既有2/2native结果仍仅证明当时测试覆盖路径，不扩展为锁定/旧系统证明。

### K1修复轮1与限定复审

两项问题均已修复并通过独立限定复审。查询显式设置 `kSecUseDataProtectionKeychain=false`，共享进程锁覆盖获取原策略、关闭交互、Security操作和恢复；策略失败不继续存储，恢复失败保留待恢复原值并停止后续操作。照片native测试独立读取系统版本，分别验证10.15不可用和11+可用。

- 新增行为RED分别覆盖后端限定、交互包装顺序和10.15照片期望，随后均GREEN；编译错误没有计为行为RED。
- 当前native为2/2，平台61项、Flutter宿主聚焦6项通过；analyze、refs、layout、sensitive、check和macOS产物校验均退出0。Bridge仍为110通过、2个既有隔离子用例ignored。
- 正常路径native后已重建默认 `lib/main.dart`；复审逐文件核对11个修复文件及对应日志。私有日志位于专项证据目录 `keychain/repair1-*`。
- 仍未取得锁定Keychain/授权拒绝实机、10.15实机、签名变化或真实账号记住/自动登录的跨进程证据；这些边界不因限定复审而转为通过。

### L1追加RED

“退出并清除成功后表单不残留账号及记住/自动选项”新增回归也按预期失败；App r2为6项RED，加Host 2项，合计8项行为失败，继续修复。
