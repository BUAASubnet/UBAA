# 文档网站维护

网站使用 VitePress，依赖由根目录 `package-lock.json` 锁定，Node 主版本与 CI 保持一致，见 `scripts/tools/versions.env`。

## 目录与内容

- `docs/site/` 保存面向用户的使用说明，首页、安装指南和新版变化页构成主要入口。
- `docs/site/.vitepress/config.mts` 维护导航、侧栏、中文主题、搜索与基础路径。
- `docs/` 其余目录保存工程文档、公开合同与历史证据，不参与网站构建。

README 介绍项目和主要功能，使用步骤放在网站功能页，发布操作放在运行手册。[新版变化页](../site/guide/ubaa2.md)对照 `ubaa1` 归档说明已经实现的改进，[更新日志](../site/changelog/index.md)按发布版本记录变化。候选仍待发布时保留“待发布”标记，正式分发后同步日期、平台和升级说明。

## 本地编辑与验证

```bash
npm ci
npm run docs:dev
npm run docs:build
npm run docs:preview
```

构建检查站内死链。预览核对首页、安装指南、新版变化、功能页、窄屏菜单与搜索。截图保存在 `.ubaa_local/` 的任务目录。

默认基础路径为 `/`。使用默认 GitHub 项目地址时，通过 `/UBAA/` 打开预览：

```bash
DOCS_BASE=/UBAA/ npm run docs:build
DOCS_BASE=/UBAA/ npm run docs:preview
```

`node_modules`、VitePress 缓存和生成的静态文件不提交 Git。站内链接使用网站路由，源码链接使用 `blob/main` 或 `tree/main`；旧版引用使用 `ubaa1` 或固定提交。

## Cloudflare 部署

文档站发布到 Cloudflare Workers Static Assets，正式地址为 `https://ubaa.top`，Worker 名称为 `ubaa-docs`。[Wrangler 配置](../site/wrangler.json) 指向 VitePress 的静态输出，使用应用服务锁定的 Wrangler 版本。

[文档工作流](../../.github/workflows/docs.yml) 在 dev 的站点相关改动后构建并部署。目标为 dev 的 PR 只构建，main PR 的文档构建由完整验收负责。手动发布时选择 dev 分支。

`docs-production` Environment 仅允许 dev，变量 `CLOUDFLARE_ACCOUNT_ID` 指定账号，Secret `CLOUDFLARE_API_TOKEN` 只用于部署步骤。构建产物通过同一次运行的 artifact 交给部署作业，部署前确认候选仍为 dev 最新提交。域名首次绑定由维护者完成，日常部署不更改域名或 DNS。

部署后检查首页、安装指南、公告、搜索和静态资源。404 请求返回网站的 404 页面。旧站 SSH/rsync 和 GitHub Pages 凭据不参与这条工作流。

## Actions 维护

开发检查、合并验收、文档部署和应用服务部署分别维护。原生矩阵由合并验收复用。完整检查范围见[开发命令](../development/commands.md#当前-ci-的实际范围)。

GitHub 可能保留源码已删除工作流的历史入口。移除入口时先核对它没有在途运行或当前调用方，再清理对应旧运行记录；保留当前发布候选的检查、构建关联与发布资产。GitHub 自动创建的 Copilot 等入口可在功能再次使用时出现。

## 依据

- [VitePress 部署说明](https://vitepress.dev/guide/deploy)
- [Cloudflare 静态站点路由](https://developers.cloudflare.com/workers/static-assets/routing/static-site-generation/)
- [Worker 自定义域名](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/)
