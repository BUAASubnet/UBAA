---
description: 下载 UBAA，按设备选择 Android、Windows、macOS 和 Linux 安装包。
---

# 下载 UBAA

当前可直接下载 **v2.0.0 · 构建 2004**。选择设备对应的平台和架构即可下载安装包。

[Android](#android) · [Windows](#windows) · [macOS](#macos) · [Linux](#linux) · [iOS](#ios) · [HarmonyOS](#ohos)

安装后可按[安装与首次登录](/guide/start)开始使用。新版功能见 [v2.0 升级说明](/guide/ubaa2)。

## Android {#android}

一般手机和平板优先选择 **ARM64**。如果设备只支持 32 位应用，选择 ARMv7；x86_64 适用于对应架构的设备或模拟器。

| 设备架构 | 下载 | 大小 |
| --- | --- | --- |
| ARM64（arm64-v8a） | [APK](https://r2.ubaa.top/releases/v2.0.0/2004/UBAA-2.0.0-android-arm64-v8a.apk) | 39.4 MiB |
| ARMv7（armeabi-v7a） | [APK](https://r2.ubaa.top/releases/v2.0.0/2004/UBAA-2.0.0-android-armeabi-v7a.apk) | 36.8 MiB |
| x86_64 | [APK](https://r2.ubaa.top/releases/v2.0.0/2004/UBAA-2.0.0-android-x86_64.apk) | 41.6 MiB |

下载后打开 APK，按系统提示允许当前浏览器或文件管理器安装应用。

## Windows {#windows}

适用于 x64 架构的 Windows 设备。可在“设置 → 系统 → 系统信息”中查看系统类型。

| 设备架构 | 下载 | 大小 |
| --- | --- | --- |
| x64（Intel / AMD） | [EXE](https://r2.ubaa.top/releases/v2.0.0/2004/UBAA-2.0.0-windows-x64.exe) | 35.4 MiB |

下载后运行安装程序，按照提示完成安装。

## macOS {#macos}

打开苹果菜单中的“关于本机”：显示“芯片”的设备选择 **Apple Silicon**，显示 Intel 处理器的设备选择 **Intel**。

| 设备类型 | 下载 | 大小 |
| --- | --- | --- |
| Apple Silicon（ARM64） | [DMG](https://r2.ubaa.top/releases/v2.0.0/2004/UBAA-2.0.0-macos-arm64.dmg) | 54.5 MiB |
| Intel（x86_64） | [DMG](https://r2.ubaa.top/releases/v2.0.0/2004/UBAA-2.0.0-macos-x86_64.dmg) | 59.9 MiB |

打开 DMG，将 UBAA 拖入“应用程序”文件夹。

## Linux {#linux}

在终端运行 `uname -m` 查看架构：`x86_64` 选择 x64，`aarch64` 选择 ARM64。

| 设备架构 | 下载 | 大小 |
| --- | --- | --- |
| x64（x86_64） | [tar.gz](https://r2.ubaa.top/releases/v2.0.0/2004/UBAA-2.0.0-linux-x64.tar.gz) | 48.2 MiB |
| ARM64（aarch64） | [tar.gz](https://r2.ubaa.top/releases/v2.0.0/2004/UBAA-2.0.0-linux-arm64.tar.gz) | 48.5 MiB |

解压后保留整个目录，再运行其中的应用。命令行使用方式见[桌面命令模式](/features/command)。

## iOS {#ios}

iPhone 和 iPad 通过 App Store 安装。商店下载链接将在上架后提供。

## HarmonyOS {#ohos}

HarmonyOS 通过 AppGallery 安装。商店下载链接将在上架后提供。

## 升级与其他下载

- 从旧版 v1.x 切换前，请阅读[升级说明](/guide/start#从旧版切换)，保留所需数据并准备重新登录。
- [GitHub Releases](https://github.com/BUAASubnet/UBAA/releases) 提供已发布版本和历史记录。
- [第三方软件许可证](https://r2.ubaa.top/releases/v2.0.0/2004/licenses.zip)随当前安装包一同提供。
- 安装或登录遇到问题，可查看[常见问题](/tech/troubleshooting)。
