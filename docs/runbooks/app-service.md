# 应用服务部署与维护

应用服务使用一个 Cloudflare Worker、一个 D1 数据库和一个 Workers KV 命名空间。维护者可在本机部署 Worker 或单独发布内容。GitHub CD 在指定分支的同一提交通过全部检查后，部署 Worker 并同步渠道和公告。

## 准备账号和目标

1. 在目标 Cloudflare 账号准备 D1 和 KV，分别记下 D1 数据库 UUID 和 KV 命名空间 ID。Worker 使用 `DB` 和 `APP_CONFIG` 绑定这两个资源。测试与生产使用不同的 Worker、D1、KV 和域名。记录 D1 的实际数据位置或配置的管辖区，按 [ADR 0008](../adr/0008-app-service-worker.md) 核对数据出境说明。
2. 在 Workers & Pages 创建目标 Worker。首次可以使用空白 Worker，关闭 `workers.dev` 和 Preview URLs。添加名为 `USER_KEY_SECRET`、类型为 **Secret** 的密码学随机值。部署只检查该 Secret 是否存在并保留它。除泄露外不更换；更换后记录统计去重连续性中断的日期。参见 [Worker Secret 配置](https://developers.cloudflare.com/workers/configuration/secrets/#secrets-on-deployed-workers)。
3. 选择同一账号下已激活 Zone 的专用主机名，先确认 DNS 中无冲突记录、主机名未被其他业务占用。由维护者在目标 Worker 的 **Settings → Domains & Routes** 首次绑定 [Custom Domain](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/)。Cloudflare 创建所需的 DNS 记录和证书；已有 CNAME 的主机名不能直接创建 Custom Domain。等待证书和绑定生效后再部署。
4. 本机在仓库根 `.env` 中填写下列值。CD 使用同名的 GitHub Environment 变量：

| 键 | 值 |
|---|---|
| `UBAA_APP_SERVICE_ACCOUNT_ID` | Cloudflare 账号 ID |
| `UBAA_APP_SERVICE_WORKER_NAME` | 上述 Worker 的名称 |
| `UBAA_APP_SERVICE_D1_ID` | 目标 D1 数据库 UUID |
| `UBAA_APP_SERVICE_KV_NAMESPACE_ID` | 目标 KV 命名空间 ID |
| `UBAA_APP_SERVICE_DOMAIN` | 已绑定的主机名，不含协议、端口、路径 |

`CLOUDFLARE_API_TOKEN` 本机可放在私有 `.env` 或由密钥管理工具注入。部署 Token 只授予目标账号的 **Workers Scripts Write**、**D1 Write**、**Workers KV Storage Write**。单独发布内容只需 **Workers KV Storage Write**。域名和 DNS 的首次配置使用维护者权限，部署 Token 无需修改 Zone 路由或 DNS。参见 [Cloudflare API Token 权限](https://developers.cloudflare.com/fundamentals/api/reference/permissions/)、[Workers 权限](https://developers.cloudflare.com/workers/authorization/workers/)和 [KV 批量读取 API](https://developers.cloudflare.com/api/resources/kv/subresources/namespaces/methods/bulk_get/)。

## 配置 GitHub CD

1. 在仓库 **Settings → Environments** 创建 `app-service-production`。设置允许部署的分支，配置 **Required reviewers**，并启用 **Prevent self-review**。参见 [GitHub Environment 配置](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments)。
2. 在该 Environment 的 **Variables** 中设置上表的五个目标值，在 **Secrets** 中设置 `CLOUDFLARE_API_TOKEN`。Token 不放在仓库级 Secret。学校账号与 `USER_KEY_SECRET` 均不填入 GitHub。
3. 在仓库 **Settings → Secrets and variables → Actions → Variables** 设置仓库变量 `APP_SERVICE_DEPLOY_BRANCH`，从 CI 的 push 分支 `ubaa2`、`main`、`dev` 中选一个，与 Environment 放行的分支一致。变量为空时跳过部署。确认 Cloudflare 目标准备完毕后再启用该变量。

CD 作业位于 [CI 工作流](../../.github/workflows/ci.yml)。它通过 [`needs`](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#jobsjob_idneeds) 等待同一运行的所有检查和矩阵项成功，再部署该提交。这样无需跨工作流匹配分支、提交与检查结果，工作流定义也随触发提交一起检出。其他分支、PR、fork 和检查未通过的运行不进入部署。生产作业串行执行，写入前核对提交仍是目标分支的分支头。需要审批时，在 GitHub Actions 对应运行中核对提交后批准。

## 校验、迁移和发布

使用仓库锁定的 Node.js 版本，从仓库根目录运行本地检查。前两条命令分别安装站点和 Worker 的锁定依赖：

```bash
just app-service-content-check
just app-service-check
npm run docs:build
```

正式公告位于 `docs/site/announcements/YYYY-MM-DD-NNN.md`。网站和 App 使用同一组文件；`app: false` 只在网站展示。渠道配置位于 `services/app_service/config/channels.json`。商店新版本确认可下载后才更新渠道配置。字段见[应用服务合同](../contracts/app-service.md#10-公告与渠道配置的来源)。

维护者取得实际操作授权并核对目标后，可在本机显式执行以下命令。CD 按同一顺序执行：

```bash
just app-service-deploy
just app-service-publish
```

- 部署先校验内容并检查、构建 Worker。部署写入前通过 [Workers Domains API](https://developers.cloudflare.com/api/resources/workers/subresources/domains/methods/list/) 确认目标域名已启用并绑定给指定 Worker，并确认 `USER_KEY_SECRET` 存在。域名未绑定、归属不符或无法验证时停止。在锁定的 [Wrangler 4.160.0 源码](https://github.com/cloudflare/workers-sdk/blob/wrangler%404.160.0/packages/deploy-helpers/src/triggers/publish-routes.ts) 中，非交互自定义域名发布会允许覆盖 DNS 或现有绑定。本项目的部署配置省略 `route` 和 `routes`，[触发器部署](https://github.com/cloudflare/workers-sdk/blob/wrangler%404.160.0/packages/deploy-helpers/src/triggers/deploy.ts) 不会调用域名或路由更新。
- 远端操作先按文件顺序应用 `services/app_service/migrations/` 中未应用的迁移，成功后才部署已构建的 Worker。使用指定的 D1/KV ID，关闭资源自动创建、Workers Logs 和 Logpush。Cron 使用 `0 19 * * *`（校园时间每日 03:00）。部署日志只报告步骤状态，不记录 Token、Secret 或请求正文。
- 内容发布重新生成已校验的 `channels` 和 `announcements`，读取目标 KV 并比较，只写入有变化的键。没有 App 公告时，公告集合为空数组。每次发布都比较远端当前内容，因此失败后重跑会补上尚未同步的内容。客户端读到新内容需等待 KV 传播和最多 300 秒的 Worker 缓存过期。
- D1 迁移失败时停止部署和后续 CD 内容发布。Worker 部署、Cron 更新或内容发布失败时，先在控制台核对已应用的迁移、Worker 版本、Cron 和 KV，再重跑对应操作。已应用的迁移不会随部署失败回滚。

在控制台确认域名证书、Cron、D1/KV 绑定和 Worker 版本。首次启用前，用授权的合成输入确认 bootstrap、上报、去重、删除和定时结果。验证通过后，在客户端构建的 `.env` 设置 `UBAA_APP_SERVICE_URL=https://<已验证主机名>` 和相应的 `UBAA_DISTRIBUTION_CHANNEL`；任一留空时停用应用服务。

## 查询汇总

在目标 D1 的 Cloudflare 控制台执行下列只读查询：

```sql
SELECT job, last_success_day FROM job_state;
SELECT day, users, devices FROM active_daily
  WHERE dimension = 'all' ORDER BY day DESC LIMIT 14;
SELECT month, users, devices FROM active_monthly
  WHERE dimension = 'all' ORDER BY month DESC LIMIT 13;
```

`all` 行是全平台、渠道和版本的整体去重结果。按平台、渠道、版本或年级分析时查询相应维度；各分组计数可能重叠。`last_success_day` 是最近一次成功处理的校园日期。漏跑后任务会扩大重算范围。持续落后时，核对 Worker 版本、Cron 和 D1 状态；查询或诊断材料只保留必要的脱敏汇总。

## 回退

- 内容错误：恢复上一个有效的渠道和公告源，使用原目标重新执行 `just app-service-publish`。如网站内容也有变化，按[网站维护手册](docs-site.md)重新构建发布。最低支持版本配置会触发客户端门控，恢复后核对实际 bootstrap 响应。
- Worker 回归：在目标 Worker 的 Deployments 选择与当前 D1 Schema 兼容的已知可用版本，执行 [Worker 版本回退](https://developers.cloudflare.com/workers/versions-and-deployments/rollbacks/)。单独核对域名和 Cron。Worker 回退不会撤销 D1 迁移或恢复 KV 内容。
- D1 迁移问题：保留当前库，优先用兼容的后续迁移修复。需要 [D1 Time Travel](https://developers.cloudflare.com/d1/reference/time-travel/) 时单独评估时间点、恢复范围及对用户删除请求的影响，避免恢复已删除的明细；按数据库恢复授权操作。
- 客户端需要停用服务时，从后续安装包构建配置移除 `UBAA_APP_SERVICE_URL`，安装该构建后进入 Noop。对已安装版本，移除服务路由会让请求失败，不能主动清除客户端已保存的最低版本要求。先发布能解除门控的有效渠道配置，并核对客户端成功刷新后，再退出服务。
