# iOS离线原生合成验收

日期：2026-09-23。候选为P2-R `950c8192` 的Bridge v34与App；设备是iPhone 17 Pro/iOS26.5模拟器，不是实体设备。

`cache_bridge_test.dart` 一项通过：真实Rust FFI打开/重开加密库、账号退出栅栏、缓存维护与受控重建，以及新批量RPC的缺会话/参数分类和dispose后的clientDisposed分类。测试未登录学校、未发送业务写入。它不证明真实App双路线或30次进程冷启动性能，也不单独证明安全材料通道。

首次CocoaPods准备因官方CDN重定向下载超时失败；验证本机已配置代理 `127.0.0.1:7897` 能以TLS成功取回同一文件后，仅为构建进程设置HTTP(S)_PROXY及loopback的NO_PROXY。依赖准备1.526秒，首次Xcode构建244.3秒，随后测试通过。未改TLS校验、未修改全局网络配置。Podfile.lock补上pubspec已锁定的flutter_secure_storage_darwin 10.0.0依赖，未升级包版本。

日志保存在仓库外私有目录 `/Users/moorefoss/.local/share/ubaa-private-evidence/offline-home-20260917/p2r-backend-recovery-20260923/`。

| 日志 | SHA-256 |
|---|---|
| ubaa-p2r-native-iphone.log | `83db6a6ff88dc15d98f426529494f2135d8a5feac94dcd22c172d6ff09f17255` |
| ubaa-p2r-native-iphone-proxy.log | `1158fb0dea7b723aff47559f0889a9f3d6ede6f50206512b95a5992afcbc715d` |


P4-AG后续：iPhone 17 Pro的系统安全材料保存/重开/删除单项通过。Bridge v35候选在iPad Pro 13-inch (M5)/iOS26.5模拟器通过同一缓存FFI及安全材料两项，包含提示读取/无效ID/退出分类。日志、SHA-256见[执行记录P4-AG](2026-09-17-offline-home.md#p4-ag未知结果最小重启核对提示2026-09-23)。这些不是实体设备和冷启动性能证据。
