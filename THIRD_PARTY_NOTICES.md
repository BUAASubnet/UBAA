# 第三方声明

项目自身按 [MIT 许可证](LICENSE)发布。以下列出协议参考、移植代码和随仓库保留的第三方源码。普通 Rust、Dart 和 npm 依赖的完整清单以锁文件和发布依赖报告为准。

## 协议参考与移植代码

`buaa-api` 仅作为冻结协议参考，来源为 [fontlos/buaa-api](https://github.com/fontlos/buaa-api)，提交 `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`，Copyright (c) 2024 Fontlos。MIT 许可证原文随仓库保存在 [buaa-api-MIT.txt](docs/licenses/buaa-api-MIT.txt)，不依赖本地冻结目录。

参考范围包括 `src/api/sso/auth.rs` 的 Direct/WebVPN SSO 入口、表单与一次密码风险继续流程，`src/api/user/auth.rs`、`opt.rs` 的用户中心行为，`src/store/cookies.rs` 的 Cookie 作用域和替换规则，以及 `src/api/class/data.rs` 的 WebVPN HTTP/HTTPS 协议段。UBAA 2 在自身合同下独立实现已获证据支持的行为。

UBAA v1 的冻结来源为 [BUAASubnet/UBAA](https://github.com/BUAASubnet/UBAA)，提交 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`。认证、WebVPN、会话和 DTO 的对照范围见[冻结引用记录](docs/migration/references.md)。Android 桌面课表的 `widgets/WidgetRenderer.kt`、`schedule_widget` 布局、背景和组件元数据移植自该版本，并适配当前只读模型与日期类型。Copyright (c) 2026 BUAASubnet，MIT 全文见 [ubaa-old-MIT.txt](docs/licenses/ubaa-old-MIT.txt)。

## 随仓库保留的源码

| 组件与位置 | 来源与版本依据 | 许可证及声明 |
|---|---|---|
| `packages/ubaa_bindings/cargokit/` | Cargokit，Copyright 2022 Matej Knopp；随 FRB 集成模板复制，来源说明保存在 [README](packages/ubaa_bindings/cargokit/README)，集成说明为 [FRB Cargokit](https://fzyzcjy.github.io/flutter_rust_bridge/manual/integrate/builtin)。当前仓库没有可核验的单独上游 commit，不推定版本 | [LICENSE](packages/ubaa_bindings/cargokit/LICENSE) 同时保留 MIT 和 Apache-2.0 原文；本地 OHOS CMake 适配不改变上游版权声明 |
| `packages/connectivity_plus_ohos/` | [CPF-Flutter/flutter_plus_plugins](https://gitcode.com/CPF-Flutter/flutter_plus_plugins.git)，提交 `9571de239933ab2893dbd49037e128135b050a7c` 的 `packages/connectivity_plus/connectivity_plus`；逐文件摘要见 [UPSTREAM.json](packages/connectivity_plus_ohos/UPSTREAM.json) | 原插件 BSD-3-Clause [LICENSE](packages/connectivity_plus_ohos/LICENSE)，Copyright 2017 The Chromium Authors；OHOS Apache-2.0 [LICENSE-OHOS](packages/connectivity_plus_ohos/LICENSE-OHOS)，保留源码版权头 |
| `packages/package_info_plus_ohos/` | 同一 CPF-Flutter 仓库与提交的 `packages/package_info_plus/package_info_plus`；逐文件摘要见 [UPSTREAM.json](packages/package_info_plus_ohos/UPSTREAM.json) | 原插件 BSD-3-Clause [LICENSE](packages/package_info_plus_ohos/LICENSE)，Copyright 2017 The Chromium Authors；OHOS Apache-2.0 [LICENSE-OHOS](packages/package_info_plus_ohos/LICENSE-OHOS)，保留源码版权头 |
| `packages/flutter_secure_storage_ohos/` | Csy_Gitee HUKS fork `f1a8ada0a000f3c3d0e2ad51eed3b86b57969652` 和 CPF-Flutter 工具代码 `67c7b82e85b08a649dfd4f2bb0c455011a9384fa`；来源指纹与修改说明保存在插件目录 | Apache-2.0，并保留原插件 BSD 声明；[插件说明](packages/flutter_secure_storage_ohos/README.md)及目录内许可证全文 |

OHOS 宿主中通过 Git 依赖引用的其他 CPF-Flutter 包按普通依赖记录，不属于本仓库直接保留的源码。发布时还应核对依赖报告中的许可证与源码可用状态。
