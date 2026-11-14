# 应用服务部署

应用服务运行在 `ssh ubaa` 对应的 Debian 服务器，通过 Nginx 提供 HTTPS。数据库使用 PostgreSQL 17，应用运行时使用 Node.js 26。客户端接口与请求 Schema 见[应用服务合同](../contracts/app-service.md)。

## 入口与目录

| 用途 | 地址或目录 |
|---|---|
| 应用接口 | `https://app.ubaa.top:10443` |
| 文档站 | `https://www.ubaa.top`，Cloudflare CDN 回源 10443 |
| 安装包 | `https://download.ubaa.top:10443/releases/<tag>/<构建号>/` |
| 使用情况看板 | `https://stats.ubaa.top:10443`，需要登录 |
| 应用版本与当前指针 | `/srv/ubaa/app_service/`、`current` |
| 文档版本与当前指针 | `/srv/ubaa/docs/`、`current` |
| 分发文件 | `/srv/ubaa/downloads/releases/` |
| 私有服务配置 | `/etc/ubaa/service.env`、`/etc/ubaa/bhpan.env` |
| 已发布清单和运行状态 | `/var/lib/ubaa/` |

只有 Nginx 监听公网 HTTPS 10443。Node.js 监听回环 10080，Grafana 监听回环 3000，PostgreSQL 使用回环连接。配置模板位于 [scripts/server](../../scripts/server/)。

## 部署应用

[部署工作流](../../.github/workflows/worker.yml)在 main 的相关改动或手动触发时执行服务测试、构建应用和云盘发布工具，然后保存同一次运行的 artifact。部署作业通过 SSH 传递运行编号、源码提交和短期下载地址，服务器直接从 GitHub 下载，不经过代理，不使用 Actions 上传大文件。

部署前再次核对 main 的最新提交。`app-service-production` 环境保存 `UBAA_DEPLOY_KEY` 和 `UBAA_DEPLOY_HOST_KEYS`。专用 `ubaa-deploy` 用户只能运行固定部署入口，不能取得交互 Shell。学校凭据不进入 GitHub Actions。

服务器按顺序解包、安装生产依赖、以应用账号应用 PostgreSQL Schema、切换 `current`、重启应用并检查 `/healthz`。健康检查失败时恢复原应用指针。数据库变更采用可被上一应用版本读取的方式；回退应用不会自动撤销数据库变更。

维护者可以运行 `just app-service-deploy` 或 `just app-service-publish`，两者均校验本地内容并触发 main 的完整部署工作流。正式公告和渠道来源分别为 `docs/site/announcements/` 和 `services/app_service/config/channels.json`。

## PostgreSQL 与定时汇总

数据库为 `ubaa`。应用角色 `ubaa` 管理应用表，`ubaa_grafana` 只有读取权限。数据库连接信息不提交。初始化脚本位于 `services/app_service/migrations/`，执行记录保存在 `schema_versions`。

同一安装的上报与删除使用事务级 advisory lock 串行处理。批次去重、明细写入和拒收结果在同一事务中完成，失败时全部回滚。汇总保留期与客户端协议不变。

`ubaa-aggregate.timer` 每天北京时间 03:00 运行汇总，错过触发后补跑。检查命令：

```bash
ssh ubaa 'systemctl status ubaa-app ubaa-aggregate.timer'
ssh ubaa 'journalctl -u ubaa-app -u ubaa-aggregate --since today'
```

日志不记录请求正文、学校凭据或遥测标识。`just app-service-check` 自动启动隔离 PostgreSQL 集群，验证 Schema、请求、事务、并发、清理和 Grafana SQL。显式的 `just app-service-e2e` 联调 Core、Dart FFI 和本地服务，使用合成数据。

## 使用情况看板

Grafana 使用内置 PostgreSQL 数据源 `ubaa-postgres`。匿名访问和自行注册关闭，管理员账号单独配置。看板由 `just app-service-dashboard` 生成，包含活跃、功能、错误、耗时、分钟曲线和汇总状态。

数据源配置在 `/etc/grafana/provisioning/datasources/ubaa.yaml`，看板在 `/var/lib/grafana/dashboards/ubaa.json`。修改生成器后运行应用服务检查，所有查询会在 PostgreSQL 上执行。

## 云盘分发

`bhpan-publish` 通过 Core facade 使用 Direct 登录和云盘上传。服务器的 `bhpan.env` 只包含发布账号、密码和已核对的目标目录标识 `UBAA_BHPAN_TARGET`。目标对应公开发布分享 `AA61B7EDC6F2BC4AF5B040FAF0563AD160`，程序从个人授权文档库逐级定位目标，不以分享临时 Token 创建目录。

文件按 `v版本/构建号` 保存。旧版本保留，商店专用 IPA 和 HarmonyOS APP 不进入公开下载。上传前记录 pending，成功后记录 complete；未知结果先读取目录，不自动重复上传。再次分发已成功的文件时核对远端名称和长度并跳过。已有同名文件但缺少成功状态时停止，维护者核对后再恢复。

服务器文件下载与云盘上传均完成后才写入 `distribution.json`。手动公开 GitHub Release 后，[发布同步工作流](../../.github/workflows/release-published.yml)核对公开 `release.json` 与服务器完整分发记录，再更新下载页和 GitHub 渠道。App Store 与 AppGallery 渠道仍在商店实际可下载后更新。

## 证书与网络

acme.sh 使用 Cloudflare DNS 验证申请 `ubaa.top` 与 `*.ubaa.top` 的证书，证书安装到 `/etc/nginx/ssl/ubaa.top/`，续期后先检查 Nginx 配置再重载。DNS Token 只拥有 `ubaa.top` 的 DNS 写入权限，保存在服务器私有 acme.sh 配置中。

证书任务使用 `http://192.168.6.2:7890`，部署下载保持直连。代理配置仅作用于 acme.sh。文档域名开启 Cloudflare 代理，Origin Rule 将 HTTPS 回源端口设为 10443，并使用严格证书验证；应用、下载与看板域名使用 DNS 解析直连。
