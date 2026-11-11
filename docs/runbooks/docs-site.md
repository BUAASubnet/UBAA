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

## GitHub Pages 配置

1. 在仓库 Settings → Pages 中将 Source 设为 GitHub Actions。
2. 在 Actions Variables 设置 `DOCS_PUBLISH_BRANCH=main`。
3. 核对 `github-pages` 环境允许 `main` 部署，再从 `main` 手动运行“文档构建与发布”。
4. 打开部署作业返回的网址，验证首页、深层页面、资源和搜索。
5. 使用自定义域名时，先在 Pages 绑定并验证域名，再调整 DNS，等待证书就绪后开启 HTTPS。切换前核对旧站仍在使用的外链及旧公告地址。

未设置发布分支时只构建。PR 始终只构建，`main`、`dev` 的相关推送触发检查，只有指定发布分支上传并部署 Pages。构建通过 `actions/configure-pages` 获取基础路径。

发布配置、DNS 与线上站点分别按发布任务修改。旧站 SSH/rsync 流程已归档，Pages 不使用对应的服务器密钥。清理旧服务器或凭据前核对是否仍被其他服务使用。

## Actions 维护

保留源码中的 CI、Flutter 原生平台构建和文档构建与发布。应用服务 CD 随 CI 执行，不另设重复部署工作流。完整检查范围见[开发命令](../development/commands.md#当前-ci-的实际范围)。

GitHub 可能保留源码已删除工作流的历史入口。移除入口时先核对它没有在途运行或当前调用方，再清理对应旧运行记录；保留当前发布候选的检查、构建关联与发布资产。GitHub 自动创建的 Copilot 等入口可在功能再次使用时出现。

## 依据

- [VitePress 部署说明](https://vitepress.dev/guide/deploy)
- [GitHub Pages 自定义工作流](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)
- [GitHub Pages 自定义域名](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site)
