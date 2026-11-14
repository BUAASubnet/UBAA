---
description: 下载 UBAA：Android、Windows、macOS 和 Linux 安装包，以及各平台的系统要求与安装步骤。
---

<script setup>
import { provide, ref } from 'vue'
import { useRelease } from './components/use_release.js'
const release = useRelease()
provide('release', release)
import DownloadSuggest from './components/DownloadSuggest.vue'
import DownloadOptions from './components/DownloadOptions.vue'
import PlatformGrid from './components/PlatformGrid.vue'

const useBhpan = ref(true)
provide('useBhpan', useBhpan)
</script>

# 下载 UBAA

<p v-if="release">当前版本 v{{ release.version }}（构建 {{ release.build }}）。</p>
<p v-else>安装包尚未发布或发布信息暂时不可用，请稍后重试。</p>

<label v-if="release" class="download-source-toggle">
  <input v-model="useBhpan" type="checkbox" role="switch" />
  使用北航云盘下载
</label>
<p class="download-source-note">{{ useBhpan ? '当前使用北航云盘。下载遇到问题时，可关闭开关改用备用下载。' : '当前使用备用下载。开启开关可切换到北航云盘。' }}</p>

<DownloadSuggest />

<PlatformGrid />

装好后按[安装与首次登录](/guide/start)开始使用。用过旧版 v1.x，请先看[从 v1.x 升级](/guide/ubaa2#upgrade)。

## Android {#android}

需要 Android 7.0 或更高版本。一般手机和平板选择 **ARM64**。

<DownloadOptions platform="android" />

下载后打开 APK，按系统提示允许浏览器或文件管理器安装应用。已经装有旧版 v1.x 时，新版会直接覆盖升级，首次打开需要重新登录。

## Windows {#windows}

需要 64 位 Windows 10 或 11。

<DownloadOptions platform="windows" />

- 运行安装程序，按提示完成安装。程序装在当前用户目录下，不需要管理员权限；以后升级时运行新的安装程序即可。
- 安装程序暂未进行代码签名，Windows 可能提示“Windows 已保护你的电脑”。确认文件是从本页下载的，点“更多信息”→“仍要运行”。

## macOS {#macos}

需要 macOS 12 或更高版本。在苹果菜单的“关于本机”中查看：显示 M 系列芯片选择 **Apple Silicon**，显示 Intel 处理器选择 **Intel**。

<DownloadOptions platform="macos" />

打开 DMG，将 UBAA 拖入“应用程序”文件夹。应用已经过 Apple 签名和公证，首次打开时按系统提示确认即可。

## Linux {#linux}

在终端运行 `uname -m` 查看架构。安装包在 Ubuntu 24.04 环境构建，需要 GTK 3；较旧的发行版可能无法运行。

<DownloadOptions platform="linux" />

- 解压后得到 `bundle` 目录，运行其中的 `UBAA` 打开应用，`ubaa-cli` 是命令行程序，用法见[桌面命令模式](/features/command)。
- 保留整个目录，不要单独移动其中的可执行文件。
- “记住密码”需要已解锁的 Secret Service（如 GNOME 钥匙环）。

## iOS {#ios}

需要 iOS 15 或更高版本，iPhone 和 iPad 都可以使用。iOS 版将通过 App Store 提供，上架后在这里给出链接。

## HarmonyOS {#ohos}

HarmonyOS 版将通过 AppGallery 提供，上架后在这里给出链接。

## 其他下载

- <a :href="useBhpan ? release?.licenses.url : release?.licenses.mirrorUrl" target="_self">第三方软件许可证</a>（{{ release?.licenses.size }}）随当前安装包一同提供。
- 旧版 v1.x 的安装包和历史记录保留在 [GitHub Releases](https://github.com/BUAASubnet/UBAA/releases)。
- 安装或登录遇到问题，可查看[常见问题](/tech/troubleshooting)。

<style scoped>
.download-source-toggle { display: inline-flex; align-items: center; gap: 0.5rem; cursor: pointer; font-weight: 600; }
.download-source-toggle input { appearance: none; position: relative; width: 2.5rem; height: 1.5rem; margin: 0; border: 1px solid var(--vp-c-divider); border-radius: 1rem; background: var(--vp-c-default-3); cursor: pointer; transition: background 0.2s; }
.download-source-toggle input::after { content: ''; position: absolute; top: 3px; left: 3px; width: 1rem; height: 1rem; border-radius: 50%; background: var(--vp-c-white); box-shadow: 0 1px 3px #0003; transition: transform 0.2s; }
.download-source-toggle input:checked { background: var(--vp-c-brand-1); }
.download-source-toggle input:checked::after { transform: translateX(1rem); }
.download-source-toggle input:focus-visible { outline: 2px solid var(--vp-c-brand-1); outline-offset: 3px; }
.download-source-note { margin-top: 0.5rem; color: var(--vp-c-text-2); font-size: 0.875rem; }
</style>
