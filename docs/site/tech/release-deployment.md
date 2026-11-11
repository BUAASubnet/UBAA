# 发布与部署

## 应用发布

当前准备发布的版本为 **v2.0.0**。应用发布包括平台构建、设备验证、签名、旧版覆盖安装和回退检查。实际安装包与支持平台以 [GitHub Releases](https://github.com/BUAASubnet/UBAA/releases) 为准。

`main` 保存发布主线，`dev` 用于开发，`ubaa1` 保存旧版历史。正式发布前核对候选提交、版本与构建号，并完成仓库[Flutter 发布流程](https://github.com/BUAASubnet/UBAA/blob/main/docs/runbooks/flutter-release.md)。签名与旧版升级身份见[应用签名配置](https://github.com/BUAASubnet/UBAA/blob/main/docs/runbooks/app-signing.md)。

## GitHub Actions

当前维护三个源码工作流：

| 工作流 | 用途 |
| --- | --- |
| CI | Rust、Flutter、公开合同、应用服务与依赖检查；配置启用后，在同一次检查通过后部署应用服务 |
| Flutter 原生平台构建 | 构建五个平台的 Debug 产物，执行相应原生检查 |
| 文档构建与发布 | 构建网站、检查站内链接，并按指定分支发布 GitHub Pages |

`main` 和 `dev` 的推送按各工作流的路径规则触发检查。CI 构建产物用于验收，正式安装包另按平台签名与分发流程准备。

## 文档站

网站源码位于 `docs/site/`，使用 VitePress 构建，GitHub Actions 上传静态产物到 GitHub Pages。

```bash
npm ci
npm run docs:dev
npm run docs:build
npm run docs:preview
```

仓库 Settings → Pages 的 Source 使用 GitHub Actions，仓库变量设置 `DOCS_PUBLISH_BRANCH=main`，并允许 `github-pages` 环境从 `main` 部署。变量为空时只构建，PR 始终只构建。

自定义域名在 Pages 设置中绑定。构建使用 Pages 返回的基础路径；本地模拟项目地址可运行 `DOCS_BASE=/UBAA/ npm run docs:build`。详细配置见[网站维护手册](https://github.com/BUAASubnet/UBAA/blob/main/docs/runbooks/docs-site.md)。

## 应用服务

更新检查、公告和可选统计使用独立的应用服务。正式环境通过 `APP_SERVICE_DEPLOY_BRANCH=main` 与受保护的 `app-service-production` 环境启用。目标资源、构建渠道与部署参数见[应用服务手册](https://github.com/BUAASubnet/UBAA/blob/main/docs/runbooks/app-service.md)。

文档站、应用服务与安装包各自发布，完成其中一项不会自动发布另外两项。
