# 杭州校区适配维护手册

本手册供维护杭州校区功能的人和 agent 使用，说明相对上游 `dev` 新增了什么、依据从哪里来、代码在哪一层，以及上游改版后如何重新实录协议并修复。

- 对应提交：`feat/hangzhou-venue` 分支（从 `dev` 的 `d2183f1` 切出，合并过一次上游 `dev`），真机验证的测试包为 v17（2026-11-26）。
- 本文件不含账号、密码、Cookie、Token、学号、姓名、手机号或余额的真实值。写进来的常量都是各站点公开前端代码里的值。
- 协议的九项依据以 [cgyy 对照记录](../protocol/parity/cgyy.md) 和 [campus 对照记录](../protocol/parity/campus.md) 为准；本手册只做导航和操作说明。

---

## 0. 一页速览

| 功能 | 上游 dev | 本分支 | 数据来源 | 实测 |
|---|---|---|---|---|
| 杭州统一认证 hzsso 自动登录 | 无 | 用已有的北航统一认证会话，后台走完 hzsso 的 CAS 插件登录，不用输杭州密码 | `hzsso.buaa.edu.cn`（竹云 IDaaS） | 真机通过 |
| 杭州空间/场馆预约 | 只有北京研讨室 cgyy | 场馆列表、今天/明天/后天三天日表、多时段选择、按人数场地显示"已约/总数"、预约（用户自己拖滑块验证码）、取消、我的预约 | `hzsm.buaa.edu.cn/venue-server`（与北京 cgyy 是同一厂商产品） | 真机预约、取消通过（直连） |
| 杭州校园卡余额 | 只读北京余额（杭州学生显示 0） | 自动识别杭州学生，只显示杭州易通一卡通余额；北京学生不受影响 | 易通 `221.12.169.12:18080` | 真机通过（直连） |
| 杭州网费余额 | 只读北京网费 | 连杭州校园网时，从深澜认证网关免密读取本人余额 | `http://10.60.0.100/cgi-bin/rad_user_info` | 真机通过（直连） |
| 杭州流量 | 北京规则 | 已用流量；免费剩余 = max(0, 70 GB − 已用)；计费剩余 = 网费 × 4 GB | 同上 | 真机通过（直连） |
| 离线显示 | 失败时显示红色错误 | 有上次数据时显示旧值，加灰字"××为 11月26日 16:10 的数据，联网后会自动更新" | 本地快照 | 真机通过 |

提交记录（`feat/hangzhou-venue`，PR [BUAASubnet/UBAA#159](https://github.com/BUAASubnet/UBAA/pull/159)）：

- `e51b63a` hzsso 登录与杭州场馆只读查询
- `26fb68f` 日表、按实录预约与取消
- `ad3c785` 按官网放开时段数量、复用 hzsm 登录
- `9338d92`、`db07f92` 功能说明、按人数场地显示
- `186f468` CLI 契约补 `adminRemark`
- `b899877` 杭州校园卡、网费、流量与离线显示

---

## 1. 背景与依据

### 1.1 为什么能做

杭州校区的日常功能（场馆预约、校园卡、缴费……）都在钉钉工作台里。但钉钉只是一个壳，背后是挂在杭州统一认证 **hzsso** 下的普通网页系统。hzsso 登录页有一个「使用北航统一认证登录」按钮，它是 IDaaS 的 CAS 插件，上游就是北京的 `sso.buaa.edu.cn`。UBAA 本来就持有北航统一认证的会话，所以可以在后台自动登录 hzsso，再从 hzsso 进入各个应用。

### 1.2 依据来源（AGENTS.md 规则 4：字段必须有证据，不能凭空推断）

1. **内置浏览器实录**：用户在 Claude 内置浏览器里亲自登录、预约、取消，agent 读取网络请求记录。
2. **各站点公开的前端 JS**：在页面里用 `fetch` 拉取 JS 源码，再搜索关键字。签名算法、常量和接口表都来自这里。
3. **手机诊断报告**：App 内导出的 `UBAA-report-*.json`。只看结构，即方法、主机、路径、参数名、状态码和 JSON 键名。
4. **电脑在杭州校园网内的 curl 实测**：只用于免密的认证网关。

仓库外的调研笔记（hzsso、场馆、校园卡、网费四份）保存在贡献者本机，只含结构信息；以仓库内的协议记录为准。

仓库内的协议记录是维护时最重要的参考：

- `docs/protocol/parity/cgyy.md`，其中两节：
  - 「2026-11-25 杭州校区空间预约（hzsm）与杭州统一认证（hzsso）」
  - 「2026-11-25 杭州空间预约提交与取消（写入）」
- `docs/protocol/parity/campus.md`，其中两节：
  - 「杭州校园卡（易通一卡通）」
  - 「杭州网费（深澜认证网关）」

---

## 2. 架构速记（改动落在哪几层）

UBAA 是 Rust 核心加 Flutter 界面。一个功能从下到上要经过这几层：

```
crates/ubaa_core            Rust 业务核心：features/（协议实现）→ facade/（对外入口，路由/缓存/写入框架）
crates/ubaa_flutter_bridge  Rust→Dart 桥（flutter_rust_bridge，简称 FRB）
packages/ubaa_bindings      FRB 自动生成的 Dart 绑定（不要手改，重新生成）
packages/ubaa_domain        Dart 领域模型（FeatureId、写入意图、展示模型）
packages/ubaa_app           Dart 应用层（读取分发、写入准备/提交、校验、读回）
packages/ubaa_host          宿主回调接线
packages/ubaa_ui            Flutter 界面
apps/ubaa_flutter           最终 App（打 APK 的地方）
```

**读取**的路径是 `features → facade/read → bridge read/methods.rs → ubaa_app reader/dispatch → ui`。

**写入**（预约、取消）走 UBAA 现成的写入框架：

1. prepare：做预检，把写入意图存起来，并给用户看确认摘要。
2. commit：按 `dispatch` 发出写请求，再经过 `_if_route_matches` 校验路线。
3. 投影结果，清缓存，读回最新数据。

任何写都**不自动重试**（AGENTS.md 规则 8）。

---

## 3. 各功能实现细节

### 3.1 hzsso 联合登录（`crates/ubaa_core/src/features/hzsso.rs`，新文件）

登录链路共 7 步，全部是 hzsso 公开接口：

1. `GET /api/public/bff/v1.2/frontend/login_data` → `data.clientId`
2. `POST /api/public/bff/v1.2/authenticate/plugin/generate_trace_id`
   - 请求：`{enterpriseAuthId:"idaasplugin_cas", enterpriseId:"idaas", clientId}`
   - 返回：`data.traceId`
3. `POST /public/api/authenticate/plugin_cas/login`
   - 请求：`{enterpriseAuthId, traceId}`
   - 返回：`loginUrl`，即北航 CAS 登录地址
4. 带着北航 SSO 会话跟随 `loginUrl` 跳转，落到 `callback.html?ticket=`
5. `POST /public/api/authenticate/plugin_cas/valid_ticket`，请求 `{enterpriseAuthId, traceId, ticket}`
6. `POST /api/public/bff/v1.2/authenticate/plugin/validate_trace_id`，请求 `{traceId}`，返回 `data.accessToken`
7. `POST /api/bff/v1.2/commons/session/save`，请求 `{access_token}`，请求头带 `Authorization: Bearer`

对外的入口函数：

- `enter_application(runtime, 启动地址, …)`：先访问应用的 hzsso 启动地址。被要求登录时，先走上面 7 步，再进入应用。
- `needs_login(response)`：判断是否被要求登录。它同时识别两种情况，一是跳到 `/login` 或 `/frontend/login` 页面，二是 hzsso 主机直接返回 401 JSON。后一种是校园卡入口的真实行为，v12 修复的就是它。
- `require_direct_route`：hzsso 只支持直连，WebVPN 路线下直接报"不可用"。用户明确说过先不做 WebVPN。

注意：

- hzsso 全站是 http。
- hzsso 门户里的「深澜认证」应用配置错误，会把 access_token 带到 alibaba.com，**绝对不要用它**。
- `features/http.rs` 里有重定向白名单。允许 cgyy 和校园卡等功能跳到 hzsso 和对应应用主机；新接入应用时也要往这里加。

### 3.2 杭州空间预约（`features/cgyy/` 多站点化）

**核心思路**：杭州 hzsm 和北京 cgyy 是同一厂商（Chingo）的产品，app-key、签名前缀、签名算法、`/api/login`、`cgAuthorization` 头都相同。所以没有另写一个模块，而是把 cgyy 改成了"多站点"。

- `features/cgyy/site.rs`（新）：`CgyySite::{Beijing, Hangzhou}`，集中放各站点的差异：
  - 基址 `https://hzsm.buaa.edu.cn/venue-server`
  - Referer
  - SSO Cookie 名 `sso_buaa_h3i_token`
  - 功能名「杭州空间预约」
  - 各自的状态槽 `hz_cgyy`
- `features/cgyy/auth.rs`：杭州登录流程如下：
  1. 经 hzsso JWT 插件 `idaasplugin_jwt38` 跳到 `/venue-server/loginto?id_token=JWT`，拿到 Cookie。
  2. `POST /api/login`，请求头带 `sso-token`，拿到 `access_token`。
  3. `POST /roleLogin`（表单 `roleid`）。这一步实测必需，北京没有。
- `features/cgyy/read.rs` 与 `parser.rs` 里的杭州差异：
  - 场馆列表要用 `venue_information`。`/api/front/website/venues` 在杭州返回 `data:null`，这是 v5 修复的。
  - 场馆 id 字段是 `siteId`，不是 `id`。v6 时所有 id 都成了 0，日表一直不发请求，v7 修复。
  - `hangzhou_advance_dates`：按 `advanceReservationDays`（官网为 3）生成今天、明天、后天三个日期，v8 修复。
  - `admin_remark`：`adminTake==true` 时显示 `adminRemark`，比如「教学使用」；状态 4 显示「已售」。
  - `hangzhou_apply_capacity`：按人数预约的场地（如健康中心，`reservationTotalNum`=200）显示「已约/总数」，约满后不可选，v10 修复。
- `features/cgyy/hangzhou_write.rs`（新）是预约和取消的写入，协议见下面的表。
- `features/cgyy/crypto.rs`：新增 `build_captcha_solution_at`，用用户拖动的真实距离生成验证码答案。
- `facade/write/hangzhou_cgyy.rs`（新）是写入入口，按架构测试要求成对实现 `op`、`op_if_route_matches` 和 `op_resolved`。新的写入要登记到 `tests/route_matrix/atomic_write.rs`。
- `session/business_cache.rs`：新增 `BusinessScope::HzCgyy`，把杭州 token 缓存 2 小时。

**慢的原因与修法（v9）**：只读 worker 每次重建都会丢掉内存里的 token，于是每次都要重走 hzsso 全链路（约 3 秒），80 秒内能重复 3 次。把 token 放进业务会话缓存后解决。

**预约协议**（2026-11-25 用户在浏览器里真实预约并取消两次后录得）：

| 步 | 请求 | 要点 |
|---|---|---|
| 1 | `GET /api/reservation/day/info?venueSiteId&searchDate` | 时段状态：1=空闲，2=不可用，3=未支付，4=已预约 |
| 2 | `GET /api/captcha/get?captchaType=blockPuzzle` | 返回 `secretKey`、`token`、底图和拼图块 |
| 3 | `POST /api/captcha/check` | `pointJson` = AES-ECB(secretKey, `{"x":X,"y":5}`)。**X 必须是用户亲手拖出来的值** |
| 4 | `POST /api/reservation/order/submit` | 表单字段：`captchaVerification`、`captchaToken`、`reservationOrderJson=[{"spaceId":"70","timeId":"331101"}]`、`reservationDate`、`weekStartDate`、`reservationType=-1`、`orderPrice=0`（唯一推断值）、`orderPin`、`venueSiteId`、`phone` |
| 5 | `GET /api/venue/finances/order/detail?venueTradeNo` | 先确认 `payFee` 为 0；**大于 0 就拒绝，绝不付款** |
| 6 | `POST /api/venue/finances/order/pay`，参数 `{venueTradeNo, isApp:0}` | 0 元确认。不做这步，订单会在 10 分钟后超时 |
| 7 | 取消：`GET /api/orders/cancel_tip` → `POST /api/venue/finances/order/cancel`，参数 `{venueTradeNo, handleReason}` | — |

- `orderPin` = AES-128-CBC 加密的 `"clientX,clientY"`。key `c1h2i5n6g2o2k4a7`，iv `C2H3I4N5G2O3K1E4`，PKCS7 填充，小写 hex。这两个是前端公开常量。坐标用用户点「提交」时的**真实点击位置**。
- 选择规则（来自 hzsm 前端，v9）：
  - 所有时段必须是同一房间，不要求相邻。
  - 最多 48 个。
  - 北京仍然是最多 2 个相邻时段。
- 只做免费场馆：预检发现 `isFee != 0` 就直接拒绝。

**界面**（`packages/ubaa_ui`）：

- `write/cgyy/hangzhou_form.dart`（新）：
  - 手机号输入框。
  - 滑块验证码组件。用户自己拖，x = 拖动距离 × 310 / 显示宽度。
  - 记录提交时的真实点击坐标。
  - 取消原因对话框，默认「行程有变」。
- `features/cgyy/table.dart`、`reservation_flow.dart`、`selection_bar.dart`：
  - 杭州表头叫「场地」，不叫「研讨室」。
  - 格子显示「教学使用」「已售」「75/200」。
  - 多选逻辑。
- `domain/feature/catalog.dart`：`FeatureId.hangzhouCgyy`，描述为「预约和管理杭州校区免费场馆（暂只支持直连）」。
- `ubaa_app/contracts/recovery.dart`：`hangzhouCgyy` 显式映射到 `RecoveryTarget.cgyy`。缺了这个映射，手机上会报 internal_error，v2→v3 修复的就是它。

### 3.3 校区识别（`features/campus/hangzhou_card.rs::is_hangzhou`）

满足下面任一条件就算杭州学生；两条都没有证据时，按北京处理：

- 门户 `info.depart` 含有「杭州」「中法航空」「中法未来」之一。不能只匹配「中法」，因为北京有中法工程师学院。
- 学号去掉字母前缀后，第 3–4 位院系代码属于 {57, 60, 61, 63}。例如 `ZY26 57 …`，57 是专项研究生。

流量那一路只能拿到账号名，所以只用学号代码判断。已知的限制是：只能靠院系名认出来的杭州用户，流量仍按北京显示。

### 3.4 杭州校园卡（`features/campus/hangzhou_card.rs`，新文件）

1. 用 `hzsso::enter_application` 打开启动地址 `http://hzsso.buaa.edu.cn/api/bff/v1.2/enduser/portal/sso/go_a2c70d41711752874339a2f988e506ad2MG8YcfZPmG`。
2. 跳转落到 `221.12.169.12:18080/easytong_webapp/static/getAuthInfo.html?etToken=…&AccNum=…`。`AccNum` 是三层 Base64，用 `decode_account` 解开。
3. `POST /easytong_app/GetAccInfo` 拿到 `epid`，再 `POST /easytong_app/GetWalletMoney`。
   - 请求头：`h5Req: Y`，`Authorization: <etToken>`。
   - 表单补充 `Time`（北京时间，格式 yyyymmddhhmmss）和 `ContentType=application/json`。
   - `Sign` = md5(按参数名排序后的各个值用 `|` 连接，末尾也带 `|`，再接 `ok15we1@oid8x5afd@`)。
4. 余额 = 各钱包 `ewalletMoney` 之和，按分精确相加。

接入点：`features/campus/portal.rs::card`。识别为杭州学生时，只显示杭州余额，不再请求北京余额，也就不会同时显示两个校区的余额。

### 3.5 杭州网费与流量（`features/campus/hangzhou_network.rs`，新文件）

**为什么不用上网自助平台**：`https://221.12.169.17:8800` 需要杭州统一认证密码和图片验证码，证书是自签名的，也不接北航统一认证。

**改用深澜上网认证网关**：`http://10.60.0.100/cgi-bin/rad_user_info?callback=ubaa`。

- 返回当前在线设备的 JSONP，**不需要密码**。只在杭州校园网内可达，超时 4 秒。
- 必须同时满足 `error=="ok"` 和 `user_name == 本人学号`，否则提示「当前设备登录的不是你的杭州校园网账号」。
- 网络不通时提示「连接杭州校园网后可查看网费」。
- 读完后恢复 `runtime.network_failure_domain`，避免把整个 App 判成"断网"。

| 显示项 | 规则 | 依据 |
|---|---|---|
| 网费 | `user_balance`，保留 2 位小数 | 与认证页一致 |
| 已用流量 | `sum_bytes`，按 1000 进制换算 | 认证页配置 `TrafficCarry: 1000` |
| 免费剩余 | max(0, 70 GB − 已用)，不显示负数 | 学校规则：免费 70 GB |
| 计费剩余 | 网费 × 4 GB，余额为负时显示 0 | 学校规则：超出部分 0.25 元/GB |

v16 读的是网关的 `remain_bytes`。在电脑上它正好等于余额 × 4 GiB，但手机上同一账号返回 0，靠不住，所以 v17 改成直接按余额计算。单元测试 `计费剩余按余额乘4且不读remain_bytes` 锁定了这个行为。

为配合这项改动，`NetworkProductUsage.free_remaining` 和 `billable_remaining` 改成了可空（`Option`）。连带修改的文件有：

- `domain/campus/mod.rs`
- Bridge `api/campus/mod.rs`（随后重新生成 FRB）
- Dart `campus_account.dart` 和 `service.dart`
- CLI `ubaa_command/src/io/campus.rs`
- `docs/contracts/cli-json.schema.json`

### 3.6 离线显示上次数据（v17，`packages/ubaa_ui/lib/src/app/account/me.dart`）

- 刷新失败但有上次数据时：照常显示旧值，下方加灰字「流量为 11月26日 16:10 的数据，联网后会自动更新」，不显示红色错误。
- 只有某一项失败时（例如网费），只在这一项上标注时间。
- 从来没有成功读过时，才显示错误提示。
- 测试在 `packages/ubaa_ui/test/account/me_test.dart`。

---

## 4. 浏览器实录全流程（标准操作流程，接新功能时照做）

这是这次所有协议证据的来源。工具是 Claude 桌面版的**内置浏览器**（`mcp__Claude_Browser__*`），它和用户的 Chrome 是隔离的，但会保留用户在里面登录的状态。

### 4.1 安全红线（每次必须遵守）

- **密码和验证码由用户自己输入、自己拖**。agent 不替用户输密码，不自动解验证码。
- 只读取**结构**，不打印真实值：可以看方法、主机、路径、参数名、状态码和 JSON 键名。不能看 Token、Cookie、ticket、姓名、学号、手机号、余额、`orderName`、`phone`、`orderUid`。
- 页面脚本输出前先脱敏，例如把 `eyJ…` 形式的 JWT 替换成 `<JWT>`，把 `?ticket=…` 替换成 `<redacted>`。
- 真实写入（预约）只做免费场馆，而且要由用户本人操作。按 AGENTS.md 规则 7，提交 PR 时还要说明这需要维护者授权。
- 录完后清理录制痕迹，用 `sessionStorage.removeItem('__ubaaShapes')`，并关闭标签页。
- 用户导出的 `UBAA-report-*.json` 含个人信息，用完要提醒用户删除。

### 4.2 具体步骤（以场馆预约为例）

1. **打开站点**：`preview_start({url:"https://hzsm.buaa.edu.cn/venue/portal"})`，再用 `tabs_context` 拿到 tabId。
2. **让用户登录**：在 hzsso 页面点「使用北航统一认证登录」，由用户输入北京账号。用户说"好了"后再继续。
3. **读网络记录**：
   - 先用 `read_network_requests({urlPattern:"venue-server", limit:300})` 列出请求。
   - 再用 `requestId` 读单个请求的详情。
   - 按 `urlPattern` 筛选，例如 `sso`、`cas`、`authenticate`、`hzsso.buaa.edu.cn`。
4. **读前端代码找常量和算法**：在页面里执行 `javascript_tool`：
   ```js
   const t = await fetch('/venue/js/chingo.c5fe1b5a.js').then(r=>r.text());
   // 搜索 'app-key'、'function F('、'roleLogin'、'getVenueListFront' 等关键字，截取前后几百字符
   ```
   找按需加载的 chunk 时：先在主 JS 里用正则 `"chunk-xxxx":"hash"` 列出全部 chunk，再逐个 fetch 搜关键字。
5. **跨整页跳转也要记下请求体**：内置浏览器的网络工具不保留请求体，整页跳转后也会丢失记录。做法是先装一个 **XHR 结构记录钩子**，再让用户操作。钩子只把键名和类型写进 sessionStorage，不记录值：
   ```js
   (() => {
     if (window.__ubaaShapeRec) return 'already installed';
     const KEY = '__ubaaShapes';
     const shape = (v, d = 0) => v === null ? 'null'
       : Array.isArray(v) ? (d > 5 ? 'array' : (v.length ? [shape(v[0], d + 1)] : []))
       : typeof v === 'object' ? (d > 5 ? 'object' : Object.fromEntries(Object.keys(v).map(k => [k, shape(v[k], d + 1)])))
       : typeof v;
     const bodyKeys = (b) => {
       if (b == null) return null;
       if (typeof b === 'string') {
         try { return Object.fromEntries(Object.entries(JSON.parse(b)).map(([k, v]) => [k, v === null ? 'null' : v === '' ? 'empty' : typeof v])); } catch (e) {}
         const o = {}; for (const [k, v] of new URLSearchParams(b)) o[k] = v === '' ? 'empty' : 'str'; return o;
       }
       if (b instanceof FormData) { const o = {}; for (const [k] of b) o[k] = 'str'; return o; }
       return typeof b;
     };
     const save = (e) => { try { const a = JSON.parse(sessionStorage.getItem(KEY) || '[]'); a.push(e); sessionStorage.setItem(KEY, JSON.stringify(a)); } catch (err) {} };
     const want = (u) => /venue-server\/(api\/(reservation|captcha|venue\/finances|orders)|roleLogin)/.test(u);
     const O = XMLHttpRequest.prototype.open, S = XMLHttpRequest.prototype.send, H = XMLHttpRequest.prototype.setRequestHeader;
     XMLHttpRequest.prototype.open = function (m, u) { this.__m = m; this.__u = String(u); this.__h = []; return O.apply(this, arguments); };
     XMLHttpRequest.prototype.setRequestHeader = function (k) { try { this.__h.push(k); } catch (e) {} return H.apply(this, arguments); };
     XMLHttpRequest.prototype.send = function (b) {
       if (want(this.__u || '')) {
         const u = new URL(this.__u, location.href);
         const rec = { t: Date.now(), method: this.__m, path: u.pathname, query: [...u.searchParams.keys()], body: bodyKeys(b), headers: this.__h };
         this.addEventListener('readystatechange', () => { if (this.readyState !== 4) return; let r; try { r = shape(JSON.parse(this.responseText)); } catch (e) { r = 'non-json'; } rec.status = this.status; rec.resp = r; save(rec); });
       }
       return S.apply(this, arguments);
     };
     window.__ubaaShapeRec = true; return 'installed';
   })()
   ```
   - 换一个站点时，只需改 `want` 里的正则。
   - 页面整页刷新后钩子会消失，要重新安装。返回值是 `already installed` 就说明还在。
6. **让用户完整操作一遍**：选场地 → 选时段 → 填手机号 → 拖滑块 → 提交 → 到「个人中心 → 场馆预约 → 校园场馆预约记录」取消。用户中途的误点不要紧，agent 根据时间顺序区分。
7. **取回结构**：
   ```js
   JSON.stringify(JSON.parse(sessionStorage.getItem('__ubaaShapes') || '[]'))
   ```
8. **写协议记录**：按 AGENTS.md 的九项格式填进 `docs/protocol/parity/*.md`。推断出来的值（如 `orderPrice=0`）要明确标注。
9. **清理**：执行 `sessionStorage.removeItem('__ubaaShapes')`，再用 `tabs_close` 关闭标签页。

### 4.3 其他场景的变体

- **hzsso 登录段**：先请用户在 hzsso 门户退出，再执行 `navigate` 到 `http://hzsso.buaa.edu.cn/frontend/enduser/#/enduser/index`，让用户点北航登录。然后：
  - 按 `authenticate`、`cas` 过滤网络记录；
  - fetch `/public/api/authenticate/plugin_cas/static/index.html`、`callback.html` 和 `/frontend/login/js/app.*.js`，读里面的调用顺序。
- **hzsso 应用清单**：登录后在 hzsso 页面执行：
  ```js
  fetch('/api/bff/v1.2/enduser/portal/sso/app_list').then(r=>r.json())
  ```
  返回 `data.authorizationApplications[]`，含 `name`、`startUrl`、`applicationId`。输出前把 URL 参数值替换成 `*`。
- **校园卡**：`navigate` 到应用的 `go_…` 启动地址，等它落到易通页面后：
  - 用 `read_network_requests({urlPattern:"easytong_app"})` 看接口；
  - 从 `performance.getEntriesByType('resource')` 找到 app JS，搜 `Md5Key`、`interceptors.request.use`、`h5Req`；
  - 用 `document.querySelector('#app').__vue__.$http.post(...)` 重放接口，只打印结构。
- **网费网关**：
  - 内置浏览器打不开自签名证书的站点，可以在电脑上 `curl -k` 只读查看登录页。
  - 电脑连着杭州校园网但开着系统代理或 TUN 时，用 `curl --interface <本机校园网 IP>` 绕过代理直连。
  - 网关地址的拿法：设备认证过以后不会再弹认证页，要先让手机在校园网上下线，再用普通浏览器打开 neverssl.com，被重定向后地址栏里就是网关地址。
  - 杭州域名用公共 DoH 解析：`https://223.5.5.5/resolve?name=…`。

---

## 5. 开发、测试、打包（Windows 示例）

### 5.1 环境变量与常用命令（Git Bash）

```bash
# Rust（仓库路径含中文时，target 放到纯英文目录）
export PATH="$HOME/.cargo/bin:$PATH" AWS_LC_SYS_PREBUILT_NASM=1 CARGO_TARGET_DIR="<纯英文路径>/ubaa-target"

# Core 是独立 workspace
cd crates/ubaa_core && cargo test --features test-contract
cargo clippy --all-targets --all-features -- -D warnings

# 仓库根目录
cargo test -p ubaa_flutter_bridge
cargo test -p ubaa-command
cargo clippy -p ubaa_flutter_bridge -p ubaa-command --all-targets -- -D warnings

# Flutter / Dart
export PATH="<Flutter SDK>/bin:$PATH"
cd packages/ubaa_ui && flutter test test/account/ && flutter analyze lib test

# 敏感信息扫描（提交前必跑）
py -3 -I -X utf8 scripts/check/sensitive.py
```

- Python 一律用 `py -3 -I -X utf8`。直接敲 `python` 会卡在微软商店的占位程序上。
- 复杂的 Python 编辑脚本，先写成 scratchpad 里的文件再运行。用 bash heredoc 容易出现引号错误。

### 5.2 改了 Bridge 的 Rust 接口后，重新生成 FRB

```bash
cd packages/ubaa_bindings && flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
cd ../.. && py -3 -I -X utf8 scripts/lib/native_bindings.py "$(pwd -W)/packages/ubaa_bindings/lib/src/rust"
rustfmt --edition 2024 crates/ubaa_flutter_bridge/src/frb_generated.rs
# 去掉生成文件里的 \r；如果某个文件只有空行差异，还原它（尤其 api/client.dart 顶部的 import）
```

### 5.3 打测试 APK

1. **同步到构建副本**（纯英文路径下的仓库拷贝，不是 git 仓库）。
   - 用 cmp/cp 循环，把 `git diff --name-only` 和未跟踪文件逐个复制过去，跳过 `packages/*_ohos/analysis_options.yaml`。
   - 可在副本里把包名加 `.hztest` 后缀、名称改为「UBAA 杭州测试」，以便和正式版同时安装；这类改动不提交。
2. **构建**：
   ```bash
   cd <构建副本>/apps/ubaa_flutter
   source <测试签名配置>/signing.env   # 见 app-signing.md
   export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr" ANDROID_HOME="$LOCALAPPDATA/Android/Sdk" ANDROID_ABI=arm64-v8a
   flutter build apk --release --target-platform=android-arm64
   ```
3. **校验签名**：
   ```bash
   "/c/Program Files/Android/Android Studio/jbr/bin/java" -jar "$LOCALAPPDATA/Android/Sdk/build-tools/37.0.0/lib/apksigner.jar" verify build/app/outputs/flutter-apk/app-release.apk
   ```
4. **交付**：命名为 `UBAA-hz-test-vN.apk`，同时给出字节数，方便测试者核对手机上的文件是否传完整。

### 5.4 Git 与 PR

- 写入 git 时用明确的路径，不要用 `git add .`。提交前先跑 `just check-changed` 和 `just check-sensitive`；没有 just 时，用上面的 py 命令代替。
- PR 以 `BUAASubnet/UBAA` 的 `dev` 为目标。
- 已知与本改动无关的失败：
  - ubaa_ui 有 6 个 golden 测试，基线是在 macOS 上生成的。
  - ubaa_app `shared_process_test` 需要 Unix 进程。
  - `contract-versions.sh` 在 Windows 上会因 CRLF 误报。

---

## 6. 常见维护场景

| 现象 | 先查哪里 |
|---|---|
| 杭州相关功能全部「需要登录」或失败 | hzsso 改版：先用 §4.3 重录登录段，再对照 `hzsso.rs` 的 7 步和 `needs_login` |
| 场馆列表为空或解析失败 | `parser.rs::parse_hangzhou_sites`（`siteId`、`venue_information`）；导出诊断报告，看有没有发出 day/info 请求 |
| 日期不是 3 天 | `hangzhou_advance_dates`，读的是 `advanceReservationDays`，取值限制在 1..=14 |
| 预约提交失败 | 按 §4.2 重录一次预约，逐个对照提交表单的键名；检查 `orderPin` 常量是否变了（搜前端 JS 的 k/v 数组） |
| 加载变慢 | `BusinessScope::HzCgyy` 缓存是否生效 |
| 校园卡读取失败 | 易通的 `Md5Key`、接口名是否变了（搜 `app.*.js`）；启动地址 `go_…` 是否变了（重新读 `app_list`） |
| 网费显示「连接杭州校园网后可查看」 | 是否连着杭州校园网、是否直连模式；网关 IP `10.60.0.100` 是否变了 |
| 北京学生受到影响 | `is_hangzhou` 的院系关键字和代码表；北京路径必须保持不变，`request_tests.rs` 里有北京回归测试 |
| 新增一个杭州院系代码 | `hangzhou_card.rs` 的 `HANGZHOU_DEPARTMENT_CODES`，并补测试 |
| 接入新的 hzsso 应用（缴费大厅、宿舍等） | 先读 `app_list` 拿到 `startUrl`，再用 `hzsso::enter_application` 进入；在 `features/http.rs` 白名单里加主机；按 §4 实录并写协议记录 |

---

## 7. 待办与已知限制

- 下一步计划：把学生用的 hzsso 应用合并成一个「杭州校区」入口，不接教职工和管理类应用。候选如缴费大厅 `hzpay.buaa.edu.cn`（公寓电费、水费、空调费）、学生宿舍等。
- 健康云的身高显示为 15.1 cm：需要用户导出诊断报告，看原始格式。解析代码在 `features/health_cloud/parser.rs`。
- 暂不支持 WebVPN：hzsso、易通和网关都只支持直连。
- 按人数预约的场地（健康中心）只做了显示，**预约提交没有实录验证**。
- hzsso「深澜认证」应用会把令牌带到第三方网站，已私下整理报告；代码中不使用该应用。
