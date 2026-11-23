# 应用服务部署

应用服务运行在 `ssh ubaa` 对应的 Debian 服务器，通过 Nginx 提供 HTTPS。数据库使用 PostgreSQL 17，应用运行时使用 Node.js 26。客户端接口与请求 Schema 见[应用服务合同](../contracts/app-service.md)。

相关资料包括[应用服务合同样例](../../fixtures/app_service/README.md)和[匿名分钟计数的决策](../adr/0009-minute-telemetry-counts.md)。

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

文档站的 `/release-data.json` 是公开安装包清单。Nginx 为成功响应设置 `Cache-Control: public, max-age=60`，Cloudflare 的文档缓存规则包含该路径，并遵循源站期限。`/downloads/` 下的临时下载会话继续禁止缓存。浏览器在首页和下载页之间共用清单，一分钟内复用已取得的数据，过期后再次进入页面时更新。加载失败时保留已有下载入口。

修改 Nginx 模板后，通过 SSH 同步到 `/etc/nginx/sites-available/ubaa.conf`，运行 `nginx -t` 后重载 Nginx。文档部署工作流只更新网站文件，不会同步 Nginx 配置或 Cloudflare 缓存规则。

## 部署应用

[部署工作流](../../.github/workflows/worker.yml)在 main 的相关改动或手动触发时执行服务测试、构建应用和云盘发布工具，然后保存同一次运行的 artifact。部署作业通过 SSH 传递运行编号、源码提交和短期下载地址，服务器直接从 GitHub 下载，不经过代理，不使用 Actions 上传大文件。

部署前再次核对 main 的最新提交。`app-service-production` 环境保存 `UBAA_DEPLOY_KEY` 和 `UBAA_DEPLOY_HOST_KEYS`。专用 `ubaa-deploy` 用户只能运行固定部署入口，不能取得交互 Shell。学校凭据不进入 GitHub Actions。

服务器按顺序解包、安装生产依赖、以应用账号应用 PostgreSQL Schema、切换 `current`、重启应用并检查 `/healthz`。健康检查失败时恢复原应用指针。数据库变更采用可被上一应用版本读取的方式；回退应用不会自动撤销数据库变更。应用部署不改写已发布的渠道和公告，只有服务器上还没有 `/var/lib/ubaa/content.json` 时才用包内内容初始化。

维护者运行 `just app-service-deploy` 校验本地内容并触发 main 的完整部署工作流。

## 发布渠道与公告

正式公告和渠道来源分别为 `docs/site/announcements/` 和 `services/app_service/config/channels.json`，从 dev 发布，不必等待合入 main。[内容发布工作流](../../.github/workflows/app-content.yml)在 dev 的相关改动或手动触发时先运行 `just app-service-content-check`，再把渠道和应用内公告随运行描述发给服务器。维护者也可以运行 `just app-service-publish` 手动触发。

服务器只替换 `/var/lib/ubaa/content.json` 中的渠道和公告，不更换应用代码，然后重启应用清空响应缓存并检查 `/healthz`，失败时恢复原内容。GitHub 渠道由正式发布事件维护；已有公开发布记录时，内容发布保留线上的 GitHub 渠道。

内容发布与文档站共用只允许 dev 的 `docs-production` 环境和同一部署密钥。内容发布使用单独的 `app-content-production` 并发组，避免排队时被应用部署取消；服务器部署锁使两者串行。内容发布不跳过旧提交，因为后续不改内容的提交不会再次触发发布。服务器端的 `content` 操作随 main 的应用部署安装到 `/usr/local/lib/ubaa/deploy.py`，安装前内容发布会被服务器拒绝。

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

Grafana 使用内置 PostgreSQL 数据源。匿名访问和自行注册关闭，管理员账号单独配置。

- `just app-service-dashboard` 生成使用情况看板，使用 `ubaa-postgres`。可公开分享此看板，其结果仅包含汇总，不返回安装 ID、用户标识或单个安装的明细。
- `just app-service-diagnostics-dashboard` 生成维护者错误看板，按版本、功能、路线和错误码筛选。将看板放入单独的维护者文件夹，只向维护者授予查看权限，不开启外部分享。为数据源 `ubaa-diagnostics` 配置单独的只读 PostgreSQL 角色，仅授予查询 `counter_days`、`error_days` 和 `error_samples` 所需的权限。确保普通看板的数据源角色无法读取 `error_samples`，并且普通用户无法查询维护数据源。

普通数据源配置在 `/etc/grafana/provisioning/datasources/ubaa.yaml`，普通看板在 `/var/lib/grafana/dashboards/ubaa.json`。应用服务检查会在隔离的 PostgreSQL 上执行查询。

## 云盘分发

`bhpan-publish` 通过 Core facade 使用 Direct 登录和云盘上传。服务器的 `bhpan.env` 只包含发布账号、密码和已核对的目标目录标识 `UBAA_BHPAN_TARGET`。目标对应公开发布分享 `AA61B7EDC6F2BC4AF5B040FAF0563AD160`，程序从个人授权文档库逐级定位目标，不以分享临时 Token 创建目录。

文件按 `v版本/构建号` 保存。旧版本保留，商店专用 IPA 和 HarmonyOS APP 不进入公开下载。上传前记录 pending，成功后记录 complete；未知结果先读取目录，不自动重复上传。再次分发已成功的文件时核对远端名称和长度并跳过。已有同名文件但缺少成功状态时停止，维护者核对后再恢复。

服务器文件下载与云盘上传均完成后才写入 `distribution.json`。手动公开 GitHub Release 后，[发布同步工作流](../../.github/workflows/release-published.yml)核对公开 `release.json` 与服务器完整分发记录，再在线上内容的基础上更新下载页和 GitHub 渠道。App Store 与 AppGallery 渠道在商店实际可下载后修改 `channels.json`，从 dev 发布。

## 证书与网络

acme.sh 使用 Cloudflare DNS 验证申请 `ubaa.top` 与 `*.ubaa.top` 的证书，证书安装到 `/etc/nginx/ssl/ubaa.top/`，续期后先检查 Nginx 配置再重载。DNS Token 只拥有 `ubaa.top` 的 DNS 写入权限，保存在服务器私有 acme.sh 配置中。

证书任务使用 `http://192.168.6.2:7890`，部署下载保持直连。代理配置仅作用于 acme.sh。文档域名开启 Cloudflare 代理，Origin Rule 将 HTTPS 回源端口设为 10443，并使用严格证书验证；应用、下载与看板域名使用 DNS 解析直连。

## 文档站留言区

文档站首页直接展示留言框和留言记录，`/community` 保留独立页面，两处共用 `/community` 讨论标识。留言服务使用 Artalk 2.10.1，前端版本固定在根目录 npm 锁文件。服务运行在 `ubaa-comments.service`，以独立的 `ubaa-comments` 用户监听 `127.0.0.1:23366`。Nginx 将同域 `/comments-api/` 转发到留言服务，并禁止缓存响应。

服务端二进制来自 [Artalk 官方发布](https://github.com/ArtalkJS/Artalk/releases/tag/v2.10.1)，安装在 `/opt/ubaa/artalk/artalk`。配置模板见 `scripts/server/comments.yml`，实际配置位于 `/etc/ubaa-comments/artalk.yml`，由服务用户读取，权限为 `600`。部署时需生成独立的随机 `app_key`，不得用模板覆盖已有密钥。systemd 单元见 `scripts/server/ubaa-comments.service`。

留言允许访客仅填写昵称和内容后发布，支持回复和点赞。浏览器保存随机访客标识，使用 `@guest.invalid` 保留域名传给 Artalk 的邮箱字段，不收集访客邮箱或网址。服务保留默认的频率验证码，关闭图片上传、邮件通知和社交登录。维护者打开 `https://www.ubaa.top/community?manage=1`，填写管理员昵称和邮箱后登录，可审核、置顶和删除留言。管理员由服务器上的 `artalk admin` 命令创建，账号凭据保存在服务器私有的 `/var/lib/ubaa-comments/admin-access.json`，不得提交。

数据库位于 `/var/lib/ubaa-comments/artalk.db`。`ubaa-comments-backup.timer` 每天北京时间 04:00 使用 SQLite 在线备份接口生成副本，保留最近 14 天，文件在同目录的 `backups/`。这些副本用于误删恢复，服务器磁盘损坏仍会同时影响原库和备份。删除申请需要同时考虑备份的保留周期。

```bash
ssh ubaa 'systemctl status ubaa-comments ubaa-comments-backup.timer'
ssh ubaa 'systemctl start ubaa-comments-backup.service'
ssh ubaa 'journalctl -u ubaa-comments --since today'
```

更新文档站使用原有构建与部署入口。更新 Artalk 前先执行备份，前后端版本一并更新。回滚文档站不会删除留言数据库；停用服务时关闭 `ubaa-comments.service`，保留数据库供后续恢复。
