# 发布与部署

## 应用发布

应用发布包含平台构建、设备验证、签名、安装升级和回退检查。具体流程见仓库[Flutter 发布手册](https://github.com/BUAASubnet/UBAA/blob/ubaa2/docs/runbooks/flutter-release.md)。文档站发布不会自动发布应用安装包。

## 文档站

网站源码位于 `docs/site/`，使用 VitePress 构建，GitHub Actions 上传静态产物到 GitHub Pages。无需 SSH 密钥、服务器目录或 Redis。

```bash
npm ci
npm run docs:dev
npm run docs:build
npm run docs:preview
```

网站构建会检查站内死链，维护时不要关闭死链检查。功能页更新应与实现一起审查，保留有意义的已有页面地址。

仓库所有者需要在 Settings → Pages 中选择 GitHub Actions，并在启用自动发布时设置仓库变量 `DOCS_PUBLISH_BRANCH`。当前分支可填 `ubaa2`；以后更名为 `main` 时同步修改变量。未设置时只构建验证，不部署。

自定义域名在 Pages 设置中绑定。构建使用 Pages 返回的基础路径，兼容默认项目地址和自定义域名。本地模拟项目路径可运行 `DOCS_BASE=/UBAA/ npm run docs:build`。

详细维护与切换步骤见仓库[网站维护手册](https://github.com/BUAASubnet/UBAA/blob/ubaa2/docs/runbooks/docs-site.md)。
