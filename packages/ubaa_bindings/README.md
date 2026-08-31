# ubaa_bindings

本 package 保存 `flutter_rust_bridge` 生成的 Dart API，以及 Cargokit 在
Android、iOS、macOS、Linux 和 Windows 的构建接线。Rust 输入只来自
`../../crates/ubaa-flutter-bridge`，生成文件禁止手改。

固定版本为 FRB `2.13.0`。重新生成必须在本目录执行：

```sh
flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
```

`lib/src/rust/` 与 Rust 的 `src/frb_generated.rs` 应可重复生成且零漂移。根级
`just flutter-codegen-check` 会在生成后使用锁定 Rust toolchain 机械执行
`cargo fmt --all`，禁止以手工修改生成文件修复格式。
HarmonyOS 使用同一 Dart API，但 native library 的打包由 OHOS runner 单独接线。
