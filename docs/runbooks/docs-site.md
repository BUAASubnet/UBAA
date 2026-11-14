# 文档网站维护

本手册供维护用户网站 [www.ubaa.top](https://www.ubaa.top) 的维护者使用，说明如何在本机编辑预览、如何部署到自有服务器和 Cloudflare CDN，以及部署失败时如何处理。

## 何时使用

- 修改 `docs/site/` 下的用户说明、公告、隐私政策或更新日志。
- 修改网站导航、主题或 VitePress 配置。
- 配置或排查文档站的 服务器部署。

## 前提

- Node.js 与 npm：主版本与 CI 一致，见 `scripts/tools/versions.env`。依赖由根目录 `package-lock.json` 锁定。
- 网站内容的分工：
  - `docs/site/` 保存面向用户的使用说明，首页、安装指南和新版变化页是主要入口。
  - `docs/site/.vitepress/config.mts` 维护导航、全站共用的侧栏、中文主题、搜索、站点地图、规范地址与分享卡片；`docs/site/.vitepress/theme/` 维护品牌色和首页标题区样式。
  - 截图页显示 `public/screenshots/` 中的 WebP，点击打开同名 PNG 原图；链接分享图是 `public/og.jpg`。这些网站用图由 `bash scripts/release/site-images.sh` 生成，见[发布手册](flutter-release.md#生成商店宣传图)。`docs/site/store_assets/` 保存 AppGallery 截图和横版宣传图等商店素材，不在 `public/` 下，不随网站部署。
  - 每页在 frontmatter 写一句 `description`，用于搜索结果和链接分享。
  - [下载页](../site/download.md)在浏览器中读取 `/release-data.json`，只展示已经公开发布且完成服务器、云盘分发的版本。发布同步流程见[发布手册](flutter-release.md#5-构建与手动发布)。
  - `docs/` 的其他目录是工程文档，不参与网站构建。
- 内容的放置：README 介绍项目和主要功能，使用步骤放在网站功能页，发布操作放在运行手册。[新版变化页](../site/guide/ubaa2.md)对照 `ubaa1` 说明已经实现的改进，[更新日志](../site/changelog/index.md)按发布版本记录变化。版本开放下载前在更新日志中标注“待发布”；开放下载后写明日期和可下载的平台，并同步[下载页](../site/download.md)与[升级说明](../site/guide/ubaa2.md#upgrade)。

## 步骤

### 本地编辑与预览

```bash
npm ci
npm run docs:dev
npm run docs:build
npm run docs:preview
```

- 基础路径默认为 `/`，与正式站点一致。配置仍支持通过 `DOCS_BASE` 环境变量指定其他基础路径。
- 站内链接使用网站路由；源码链接使用 `blob/main` 或 `tree/main`；旧版引用使用 `ubaa1` 或固定提交。
- `node_modules`、VitePress 缓存和生成的静态文件不提交。预览截图保存在 `.ubaa_local/` 的任务目录。

### 部署到服务器

正式站点为 `https://www.ubaa.top`。Nginx 从 `/srv/ubaa/docs/current` 提供 VitePress 静态文件，Cloudflare CDN 通过 HTTPS 10443 回源，并严格校验证书。HTML 缓存 300 秒，带内容摘要的静态资源缓存一年，并跨版本保留在服务器的共享 assets 目录，供缓存中的旧页面继续读取。下载会话页和发布信息不缓存。

[文档工作流](../../.github/workflows/docs.yml)在 dev 的站点相关改动或 dev 手动触发时构建并部署，PR 只构建。`docs-production` 只允许 dev，保存专用部署密钥 `UBAA_DEPLOY_KEY` 和固定主机公钥 `UBAA_DEPLOY_HOST_KEYS`。

Actions 保存静态网站 artifact，再通过 SSH 发送本次运行的临时下载地址。服务器直连下载、解包并切换当前目录。部署前核对候选仍是 dev 的最新提交。文档源代码不在服务器编译。

## 验证

- 本地：`npm run docs:build` 检查站内死链；预览时核对首页、下载页、安装指南、新版变化、功能页、窄屏菜单与搜索。
- 部署后：在 https://www.ubaa.top 检查首页、安装指南、公告、搜索和静态资源；不存在的路径应返回网站的 404 页面。

## 故障处理

- 构建报死链：修正对应页面的站内路由后重新构建。
- 部署作业失败：核对 `docs-production` 的变量与 Secret、SSH 密钥和主机公钥，以及候选是否仍为 dev 最新提交；未修改源码时可以重新运行失败作业。
- CDN 返回源站错误时，检查 Origin Rule 的 10443 端口、Nginx 和证书续期。

### Actions 入口维护

开发检查、合并验收、文档部署和应用服务部署分别维护，原生矩阵由合并验收复用；完整范围见[当前 CI 的实际范围](../development/commands.md#当前-ci-的实际范围)。

GitHub 可能保留源码中已删除工作流的历史入口。移除入口前，先确认它没有在途运行或当前调用方，再清理对应的旧运行记录；保留当前发布候选的检查、构建关联与发布资产。GitHub 自动创建的 Copilot 等入口可能在功能再次使用时出现。

## 依据

- [VitePress 部署说明](https://vitepress.dev/guide/deploy)
- [Cloudflare Origin Rules](https://developers.cloudflare.com/rules/origin-rules/)
