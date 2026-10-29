# ubaa_bindings

本 package 保存 `flutter_rust_bridge` 生成的 Dart API，以及 Cargokit 在
Android、iOS、macOS、Linux 和 Windows 的构建接线。Rust 输入只来自
`../../crates/ubaa_flutter_bridge`，生成文件禁止手改。

工具版本从[版本清单](../../scripts/tools/versions.env)读取，生成入口为根目录的 `just flutter-codegen-check`。生成只写 `lib/src/rust/` 和 Rust 的 `src/frb_generated.rs`，仅格式化生成 Rust 文件，并检查暂存、工作区和未跟踪漂移。

项目没有 Web 宿主，配置关闭 Web。FRB 2.13 仍会输出 Web 条件导入，因此生成脚本通过受测试的机械步骤选择 IO 导入并删除过时 Web 输出；上游导入结构变化时立即失败。禁止手改生成文件。

HarmonyOS 使用同一 Dart API，但 native library 的打包由 OHOS runner 单独接线。
