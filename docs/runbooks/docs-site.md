# 文档网站维护

网站使用 VitePress 2.0.0-alpha.21，Node.js 22.12 及以上版本可运行。依赖版本由根目录 `package-lock.json` 锁定。

## 目录与内容

- `docs/site/`：面向用户的网站内容，沿用旧站的功能页与技术页地址，正文按 UBAA v2.0 更新。
- `docs/site/.vitepress/config.mts`：导航、侧栏、中文主题、搜索与基础路径。
- `docs/` 其余目录：工程文档、公开合同与历史证据，不参与网站构建。

旧站使用 Kotlin、Compose、服务器中转和 Web/Wasm 的说明已改为当前 Rust、Flutter、Direct/WebVPN 实现。没有复制旧版文档归档、二维码图片或审计记录。旧公告的具体日期链接未迁移，正式切换域名前应核对仍在使用的外链。

## 本地编辑与验证

```bash
npm ci
npm run docs:dev
npm run docs:build
npm run docs:preview
```

构建默认检查站内死链，禁止用 `ignoreDeadLinks` 绕过。预览时核对首页、功能页、导航、窄屏菜单与搜索。截图保存到仓库外私有目录。

默认本地基础路径为 `/`。模拟项目站点时使用以下命令，并通过 `/UBAA/` 打开预览：

```bash
DOCS_BASE=/UBAA/ npm run docs:build
DOCS_BASE=/UBAA/ npm run docs:preview
```

`node_modules`、VitePress 缓存和生成的静态文件均已忽略，不提交 Git。

## GitHub Pages 启用

1. 在仓库 Settings → Pages 中将 Source 设为 GitHub Actions。
2. 在 Settings → Secrets and variables → Actions → Variables 设置 `DOCS_PUBLISH_BRANCH=ubaa2`。
3. 核对 `github-pages` 环境允许该分支部署，再从该分支手动运行“文档构建与发布”。
4. 打开部署作业返回的网址，验证首页、深层页面、资源和搜索。
5. 如果继续使用 `www.buaa.team`，先在 Pages 绑定并验证域名，再修改 DNS 指向 Pages，等待证书就绪后开启 HTTPS。
6. 新站验收后停用旧 `dev` 上的 SSH 文档部署工作流，再按实际用途清理旧部署密钥和服务器目录。旧服务器若还有其他业务，不随文档迁移关闭。

未设置发布分支变量时，工作流只构建。PR 始终只构建；`ubaa2`、`main`、`dev` 的相关 push 会触发检查，只有指定发布分支上传并部署 Pages。

发布时通过 `actions/configure-pages` 读取基础路径，因此自定义域名与默认项目路径无需分别维护配置。纯静态托管无需旧站的 SSH、rsync 或 Cloudflare API 凭据。如果域名仍通过外部代理缓存，按实际缓存配置处理更新。

本次迁移只提供代码和本地验证，不修改仓库 Pages 设置、DNS 或线上站点。

## 分支改名

分支使用与提交遵守[开发约定](../development/conventions.md#分支与提交)，本手册不另设合并流程。若用户另行决定将 `ubaa2` 改名为 `main`，还须同步调整 `DOCS_PUBLISH_BRANCH`、Pages 环境的部署分支规则，以及网站中指向源码 `blob/ubaa2`、`tree/ubaa2` 的链接；这些发布设置不随文档修改自动变更。

## 依据

- [VitePress 部署说明](https://vitepress.dev/guide/deploy)
- [GitHub Pages 自定义工作流](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)
- [GitHub Pages 自定义域名](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site)
