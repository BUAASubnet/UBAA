# 目录命名

本页供新增或移动目录的贡献者使用，说明目录命名规则、保留原名的例外和检查方式。

项目自有目录统一用下划线分隔单词，例如 `crates/ubaa_core`、`crates/ubaa_flutter_bridge`、`scripts/live/offline_startup`。新目录也遵循这条规则。文件名、Cargo 包名、发布名称、命令名和外部链接不属于目录命名，不随目录迁移改名。

以下路径保留原名：

- `examples/` 是固定提交的只读参考源码。
- `packages/ubaa_bindings/cargokit/` 是第三方工具源码。
- Android 的 `res/drawable-v21`、`res/mipmap-hdpi` 等资源限定目录由框架识别。
- `docs/design/evidence/ui-ux/` 是历史证据归档，其目录名对应仓库外原图和原哈希清单。新增自有代码或新证据批次不得借此例外继续使用连字符目录。

`just layout-check` 检查 Git 跟踪文件和非忽略的新文件所在目录。`just script-test` 验证规则，确保例外不会扩展到同级自有目录或资源目录中的任意子目录。构建缓存、临时目录、其他 worktree 和仓库外材料不在检查范围内。

## 已迁移的旧目录

以下目录在 2026-10-26 由连字符改为下划线：

| 原目录 | 当前目录 |
|---|---|
| `apps/ubaa-cli` | `apps/ubaa_cli`（后已删除，命令功能移入 `crates/ubaa_command`） |
| `crates/ubaa-core` | `crates/ubaa_core` |
| `crates/ubaa-flutter-bridge` | `crates/ubaa_flutter_bridge` |
| `crates/ubaa-test-support` | `crates/ubaa_test_support` |
| `scripts/live/offline-startup` | `scripts/live/offline_startup` |

Cargo 包名 `ubaa-core` 等保持原值。历史证据目录及其原始 JSON、哈希清单不改写。

较早的本地 checkout 如果 CocoaPods 仍使用旧构建脚本，在 `apps/ubaa_flutter/macos` 或 `apps/ubaa_flutter/ios` 执行 `pod install --no-repo-update`，然后重新构建。
