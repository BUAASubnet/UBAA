# 文档网站维护

本手册供维护用户网站 [www.ubaa.top](https://www.ubaa.top) 的维护者使用，说明如何在本机编辑预览、如何部署到 Cloudflare，以及部署失败时如何处理。

## 何时使用

- 修改 `docs/site/` 下的用户说明、公告、隐私政策或更新日志。
- 修改网站导航、主题或 VitePress 配置。
- 配置或排查文档站的 Cloudflare 部署。

## 前提

- Node.js 与 npm：主版本与 CI 一致，见 `scripts/tools/versions.env`。依赖由根目录 `package-lock.json` 锁定。
- 网站内容的分工：
  - `docs/site/` 保存面向用户的使用说明，首页、安装指南和新版变化页是主要入口。
  - `docs/site/.vitepress/config.mts` 维护导航、侧栏、中文主题、搜索与基础路径。
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

### 部署到 Cloudflare

文档站发布到 Cloudflare Workers Static Assets，正式地址为 `https://www.ubaa.top`，Worker 名称为 `ubaa-docs`。[Wrangler 配置](../site/wrangler.json)指向 VitePress 的静态输出，使用应用服务锁定的 Wrangler 版本。

[文档工作流](../../.github/workflows/docs.yml)的行为：

| 触发 | 动作 |
|---|---|
| dev 分支上的站点相关改动 | 构建并部署 |
| 目标为 dev 的 PR | 只构建 |
| 目标为 main 的 PR | 文档构建由完整验收负责 |
| 手动运行 | 选择 dev 分支后构建并部署 |

部署配置：

- `docs-production` Environment 只允许 dev 分支。变量 `CLOUDFLARE_ACCOUNT_ID` 指定账号，Secret `CLOUDFLARE_API_TOKEN` 只用于部署步骤。
- 构建产物通过同一次运行的 artifact 交给部署作业，部署前确认候选仍是 dev 的最新提交。
- 维护者保留 CNAME，并将 `www.ubaa.top/*` 路由指向 `ubaa-docs`。日常部署不更改路由或 DNS。

## 验证

- 本地：`npm run docs:build` 检查站内死链；预览时核对首页、安装指南、新版变化、功能页、窄屏菜单与搜索。
- 部署后：在 https://www.ubaa.top 检查首页、安装指南、公告、搜索和静态资源；不存在的路径应返回网站的 404 页面。

## 故障处理

- 构建报死链：修正对应页面的站内路由后重新构建。
- 部署作业失败：核对 `docs-production` 的变量与 Secret、Token 权限，以及候选是否仍为 dev 最新提交；未修改源码时可以重新运行失败作业。
- 旧站的 SSH/rsync 和 GitHub Pages 凭据不参与这条工作流，排障时不需要也不应恢复它们。

### Actions 入口维护

开发检查、合并验收、文档部署和应用服务部署分别维护，原生矩阵由合并验收复用；完整范围见[当前 CI 的实际范围](../development/commands.md#当前-ci-的实际范围)。

GitHub 可能保留源码中已删除工作流的历史入口。移除入口前，先确认它没有在途运行或当前调用方，再清理对应的旧运行记录；保留当前发布候选的检查、构建关联与发布资产。GitHub 自动创建的 Copilot 等入口可能在功能再次使用时出现。

## 依据

- [VitePress 部署说明](https://vitepress.dev/guide/deploy)
- [Cloudflare 静态站点路由](https://developers.cloudflare.com/workers/static-assets/routing/static-site-generation/)
- [Worker Route](https://developers.cloudflare.com/workers/configuration/routing/routes/)
