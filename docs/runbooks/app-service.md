# 应用服务部署与维护

应用服务使用一个 Cloudflare Worker、一个 D1 数据库和一个 Workers KV 命名空间。部署入口应用迁移并发布 Worker；内容发布入口同步渠道和公告。两条命令均需要本机明确指定目标并提供 API Token。普通检查和 CI 只执行本地验证。

## 准备账号和目标

1. 在目标 Cloudflare 账号准备 D1 和 KV，分别记下 D1 数据库 UUID 和 KV 命名空间 ID。`DB` 是 D1 绑定，`APP_CONFIG` 是 KV 绑定。测试环境和生产环境分别使用独立 Worker、D1、KV 与域名。首次创建 D1 时记录实际主库位置或配置的管辖区，按 [ADR 0008](../adr/0008-app-service-worker.md) 核对数据出境说明。
2. 在 Workers & Pages 创建同名 Worker。首次可使用空白 Worker，关闭 `workers.dev` 和 Preview URLs，不配置公开路由。为目标 Worker 添加 `USER_KEY_SECRET`，类型选 **Secret**。使用密码学安全随机值，配置后不保留明文副本。后续部署继承该 Secret；仅在泄露时更换，并记录统计去重连续性中断日期。配置操作会生成并发布 Worker 版本，按 [Cloudflare Secret 文档](https://developers.cloudflare.com/workers/configuration/secrets/#secrets-on-deployed-workers) 执行。
3. 在该账号下选择一个已激活 Zone 的专用主机名作为 [Worker 自定义域名](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/)。确认主机名未被现有 CNAME 或其他业务占用。部署会绑定该域名，由 Cloudflare 管理证书。客户端构建使用 `https://` 加该主机名。
4. 把目标保存到忽略目录 `.ubaa_local/app_service/targets/` 下的 JSON 文件，只填账号和资源标识。`domain` 只填主机名，无协议、端口或路径。以下为格式示例，执行前替换所有字段：

```json
{
  "account_id": "<Cloudflare 账号 ID>",
  "worker_name": "<Worker 名称>",
  "database_id": "<D1 数据库 UUID>",
  "kv_namespace_id": "<KV 命名空间 ID>",
  "domain": "<自定义域名>"
}
```

本机环境变量 `CLOUDFLARE_API_TOKEN` 提供命令凭据。发布内容使用目标账号的 Workers KV Storage Write；部署使用 Workers Scripts Write 和 D1 Write，域名发现需要时再授予目标 Zone 的 Zone Read。只读查库使用 D1 Read。权限名称和作用域见 [Cloudflare API Token 权限](https://developers.cloudflare.com/fundamentals/api/reference/permissions/)及[自定义域名绑定 API](https://developers.cloudflare.com/api/resources/workers/subresources/domains/methods/update/)。凭据由本机密钥管理工具注入，勿写入命令参数、目标文件、`.env.local` 或 CI。初始化或更新 Worker Secret 时，不用同一值充当 API Token。

## 校验、迁移和发布

使用仓库锁定的 Node.js 版本，从仓库根目录执行本地检查。前两条命令分别安装根目录和 Worker 的锁定依赖：

```bash
just app-service-content-check
just app-service-check
npm run docs:build
```

正式公告位于 `docs/site/announcements/YYYY-MM-DD-NNN.md`。网站和 KV 共用这组文件；`app: false` 只在网站展示。渠道配置位于 `services/app_service/config/channels.json`。商店新版本确认可下载后才更新渠道配置。字段格式见[应用服务合同](../contracts/app-service.md#10-公告与渠道配置的来源)。

取得实际部署和发布授权后，核对目标文件和 Cloudflare 控制台资源，再显式执行。部署须使用交互终端，保留 Wrangler 的域名冲突提示，不把标准输入或输出接到管道。出现域名已用于其他业务的提示时停止，重新核对目标。部署配置会更新目标 Worker 的域名与 Cron。

```bash
just app-service-deploy target=.ubaa_local/app_service/targets/production.json
just app-service-publish target=.ubaa_local/app_service/targets/production.json
```

- 部署先校验内容并在本机检查、构建 Worker，然后只读确认目标 Worker 已有 `USER_KEY_SECRET`。随后按文件顺序应用 `services/app_service/migrations/` 中未应用的迁移，成功后才部署构建产物。显式执行部署命令后，D1 迁移不会再交互询问。配置使用明确的 D1/KV ID，关闭资源自动创建、Workers Logs 和 Logpush。Cron 使用 `0 19 * * *`（校园时间每日 03:00）。
- 内容发布先校验全部内容，再向目标命名空间写入 `channels` 和 `announcements` 两个键。同一发布的 App 公告集合整体替换旧集合；没有 App 公告时写入空数组。客户端读到新内容需等待 KV 传播和最多 300 秒的 Worker 缓存过期。网站构建时读取同一组公告文件，访问公告中心时按当前时间筛选。
- 更新前核对当前 Worker 版本、D1 迁移列表及现有内容来源。D1 迁移失败时不部署。后续部署或触发器配置失败时，已应用的迁移和已成功的配置变更仍在。先核对远端迁移、Worker 版本、域名和 Cron，再判断从哪个命令恢复。

在控制台确认域名证书、Cron、D1/KV 绑定和 Worker 版本。首次启用前，用授权的合成输入确认 bootstrap、上报、去重、删除和定时结果。客户端只有在目标服务验证通过后才配置该 HTTPS 地址并发布。

## 查询汇总

在目标 D1 的控制台执行下列查询，或以 `CLOUDFLARE_ACCOUNT_ID` 和 `CLOUDFLARE_API_TOKEN` 指定账号和凭据，使用仓库锁定的 Wrangler：

```bash
services/app_service/node_modules/.bin/wrangler d1 execute "$UBAA_APP_SERVICE_D1_ID" \
  --remote --env-file /dev/null \
  --command 'SELECT job, last_success_day FROM job_state'
```

`UBAA_APP_SERVICE_D1_ID` 使用目标数据库 UUID。上述 `/dev/null` 用法适用于 macOS 和 Linux，避免 Wrangler 默认加载当前目录的 dotenv 文件。下列 SQL 只查聚合表和任务状态：

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
