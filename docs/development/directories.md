# 目录命名

项目自有目录统一用下划线分隔单词，例如 `apps/ubaa_cli`、`crates/ubaa_core`、`scripts/live/offline_startup`。新目录也遵循这条规则。文件名、Cargo 包名、发布名称、命令名和外部链接不属于目录命名，不随目录迁移改名。

以下路径保留原名：

- `examples/` 是固定提交的只读参考源码。
- `packages/ubaa_bindings/cargokit/` 是第三方工具源码。
- Android 的 `res/drawable-v21`、`res/mipmap-hdpi` 等资源限定目录由框架识别。
- `docs/design/evidence/ui-ux/` 是历史证据归档，其目录名对应仓库外原图和原哈希清单。新增自有代码或新证据批次不得借此例外继续使用连字符目录。

`just layout-check` 检查 Git 跟踪文件和非忽略的新文件所在目录。`just script-test` 验证规则，确保例外不会扩展到同级自有目录或资源目录中的任意子目录。构建缓存、临时目录、其他 worktree 和仓库外材料不在检查范围内。

## 2026-10-26 迁移

| 原目录 | 当前目录 |
|---|---|
| `apps/ubaa-cli` | `apps/ubaa_cli` |
| `crates/ubaa-core` | `crates/ubaa_core` |
| `crates/ubaa-flutter-bridge` | `crates/ubaa_flutter_bridge` |
| `crates/ubaa-test-support` | `crates/ubaa_test_support` |
| `scripts/live/offline-startup` | `scripts/live/offline_startup` |

Cargo workspace 和相对依赖、FRB 配置、Cargokit 调用位置、平台构建配置、CI 路径过滤、校验脚本及当前文档引用同步更新。Cargo 包名 `ubaa-core` 等保持原值。历史证据目录及其原始 JSON、哈希清单不改写。

已有本地 checkout 在升级后若 CocoaPods 仍使用旧构建脚本，在 `apps/ubaa_flutter/macos` 或 `apps/ubaa_flutter/ios` 执行 `pod install --no-repo-update`，然后重新构建。本次两个 Podfile.lock 只更新本地 ubaa_bindings podspec 的校验值，没有升级依赖。

验证完成：冻结引用、目录命名、布局、敏感扫描、完整 Rust 与脚本门禁、七包 1474 项 Flutter 测试和静态分析、FRB 零漂移及 macOS Debug 构建通过。iOS 仅重新生成 Pods 配置，其他平台原生运行未在此次目录迁移中验收。
