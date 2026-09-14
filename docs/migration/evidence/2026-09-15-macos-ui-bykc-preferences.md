# macOS逐按钮专项：博雅按账号筛选偏好

日期：2026-09-15。工作分支 `codex/macos-ui-20260915`，本批基点
`189bedef5bfa567a63155fbfe76e23d793b262d6`。

## 当前结论

博雅状态、类别、校区筛选的按账号保存与恢复已在 `d4507adbec6e460459475cce7f497fad5670659f` 提交。新增32项回归、完整Flutter865项和仓库门禁通过，独立规范与质量审查通过，无返工项。本记录不关闭最终macOS逐按钮验收。

实施前依据为[博雅来源对照](../source-parity-ui-bykc-details.md)第6、10节：冻结旧版确有按schoolid保存与恢复，示例未实现同等UI偏好。不读取旧版运行数据作迁移，不改变学校接口、Core配置、Session或CLI。

## 候选行为

- 状态、类别、校区使用独立不可变模型。显式空状态集合保留“状态不限”，整个偏好缺失才采用默认四状态。
- 同账号普通退出后恢复选择；新宿主与新文件存储实例可恢复同一临时文件。默认按钮清本账号偏好，账号间隔离。
- 读取迟到不能覆盖已编辑选择或新账号；保存失败仍保留本次筛选并明确提示。偏好读取和编辑不增加学校请求。
- 明确退出清除时依次尝试凭据、成绩与本账号筛选清理，单项失败不跳过后项，并如实汇总；完整清理期间推迟后台重建。
- 生产文件为已有配置目录下的 `ui-bykc-filters.json`，只存三维偏好；写入数据前设置私有权限，再原子替换。同一isolate内同绝对路径的实例共享操作顺序，不宣称支持多个进程同时写入。

显式合成backend的宿主默认使用内存存储。后续macOS跨进程按钮验收须显式注入真实文件存储，使用App Sandbox内独立合成目录，不得以重启即清空的内存实例替代。

## 已取得的确定性证据

全部日志保存于仓库外私有目录的 `macos-ui-20260915/bykc-preferences/`。
Flutter使用 `/Users/moorefoss/Dev/flutter-3.41.9/bin/flutter`。

| 验证 | 工作目录与命令 | 结果 | 日志 |
|---|---|---|---|
| 原行为RED | `packages/ubaa_host`：`flutter test test/bykc_preferences_test.dart` | 退出1；同账号普通退出重登后“美育”未恢复，成功编译后行为断言失败 | `red-host-relogin.log` |
| 原行为GREEN | 同上 | 退出0 | `green-host-relogin-v2.log` |
| 存储 | `packages/ubaa_platform`：`flutter test test/bykc_filters_test.dart` | 退出0，14项 | `green-platform.log` |
| 宿主及登录生命周期 | `packages/ubaa_host`：`flutter test test/bykc_preferences_test.dart test/login_buttons_regression_test.dart test/lifecycle_test.dart` | 退出0，32项，其中新增10项 | `green-host-v2.log` |
| UI、详情与资料 | `packages/ubaa_ui`：`flutter test test/navigation/bykc_preferences_test.dart test/navigation/bykc_full_detail_test.dart test/profile_details_test.dart` | 退出0，20项，其中新增8项 | `green-ui-v2.log` |
| 冻结引用、结构、敏感扫描 | 根目录：分别运行 `just refs`、`just layout-check`、`just check-sensitive` | 均退出0 | `refs-final.log`、`layout-final.log`、`sensitive-final.log` |
| Rust、CLI与脚本 | 根目录：`just check` | 退出0，含CLI端到端16项 | `check-final.log` |
| 完整Flutter | 根目录：`just flutter-check` | 退出0，865项，七包分析无警告 | `flutter-check-v3.log` |

完整Flutter计数：Domain54、Platform75、App304、UI292、Bindings18、Host49、Flutter宿主73。
无Rust接口或生成绑定变化，本批不重复FRB代码生成。

## 候选与尚未完成

16个候选Git文件的SHA256已逐一核对；独立审查包摘要为
`edd3dc6bc4112a7d7c3a6a857d2f3131a12bdcf033a54741af9a856b5136a900`。
审查另外核对账号fallback、完整清理期间的后台恢复、根Messenger的失败反馈和生产默认存储入口，均未发现缺口。实施前来源第6、10节已存在于本批基点；主线复核冻结引用及最终门禁日志，未将独立审查当成新的测试运行。
本批没有进行真实账号登录、原生Keychain、App Sandbox文件权限或CUA跨进程实操。
相关检查点继续保留待验，不以临时文件Widget测试代替真实App运行。
