# ihome 现场功能与接口报告

## 范围和结论

目标是为 UBAA 整理 ihome 普通学生端“除新发起诉求以外”的功能。本轮执行网页操作、网络读取与少量同会话只读探测，未接入业务代码。

现场确认的功能包括：公共诉求搜索、类别筛选、回复状态筛选、时间排序、完整详情与处理进度、官方回复、我的发起及其详情/排序/筛选、我的关注、我的评价、公告列表与详情。支持/取消支持、关注/取消关注的实际往返证据沿用原 HAR。

评价提交存在于当前网页源码，但本账号没有待评价诉求，未完成提交验证。评论、踩、撤回等通用源码能力受北航当前配置限制，不能直接作为已开放功能接入。管理端操作不属于普通学生端范围；新发起诉求及其上传、选部门、AI 辅助填写流程按用户要求排除。

最重要的修正：

搜索已确认正常，支持匹配诉求正文和官方回复；下面的分页限制不能表述为“搜索失效”。

1. **完整详情是 `GET /api/appeal/{id}`**；`GET /api/appeal?id={id}` 只是分页格式的单条列表回查，不能代替完整详情。
2. **我的发起详情是 `GET /api/appeal/my_appreal/{id}`**，路径中的 `my_appreal` 必须保留上游原始拼写。
3. 公共列表请求第二页仍返回同一批第一页数据；个人列表分页正常。不能对所有列表采用同一种分页假设。
4. 同会话只读探测证实：诉求读取仅带 Bearer、不带 Cookie 和 `X-XSRF-TOKEN` 即可成功。此结论未扩展到写接口。
5. HTTP 200 可能包含 `code=40001`、`success=""`、`error=true`，响应字段类型并非始终固定。

## 证据说明

- 日期：2026-09-17，时区 Asia/Shanghai；稳定会话的现场核对自约 22:56 开始，并包含用户随后手动执行的三次搜索。
- 网站：`https://i.buaa.edu.cn/web/`；业务基址：`https://i.buaa.edu.cn/api`。
- 工具：Playwright MCP。内置连接中途出现 `Transport closed`，随后用本机已安装的同一 `@playwright/mcp` 重建 stdio 连接，继续使用保留登录态的浏览器配置。
- 下文 `L44` 等编号来自重建后最终稳定会话的 `browser_network_requests`，不是原 HAR 条目编号。
- `E18` 等编号指 [原 HAR 报告](./2026-09-17-ihome-api.md) 的来源文件，按 `log.entries` 从 1 开始编号。
- **页面实测**：真实点击、输入、回车引发的请求和响应。
- **只读探测**：通过 Playwright MCP 在当前页面使用已有会话发起 GET，没有伪造页面数据或修改服务器响应。
- **源码证据**：当前站点实际使用的 JavaScript，未执行其中未开放的写操作。
- **未验证**：没有足够样本或没有提交的操作，不计为功能验收通过。

脱敏请求清单、响应结构与核对结果保存在 [现场证据 JSON](./2026-09-17-ihome-live-evidence.json)。

报告和配套证据文件不保留真实身份、凭据、诉求/回复正文、具体诉求 ID 或附件地址。自动生成的浏览器调试快照不纳入仓库。网页自动上报的 `/mobile/accesslog`、详情浏览热度等读取伴随副作用不等于人工提交诉求；本轮未主动执行支持、关注、评论、评价、撤回或重启写操作。

## 功能清单

| 功能 | 当前证据 | 后续接入边界 |
| --- | --- | --- |
| 公共诉求列表、空结果 | 页面实测 | 公共列表分页异常必须单独处理 |
| 关键词搜索 | 页面实测 | 全局搜索；从个人页面输入会跳回首页 |
| 诉求/建议/表扬类别 | 字典与页面筛选实测 | 使用动态字典，不固定全部未来类别 |
| 已回复/未回复 | 页面实测 | 公共列表用 `reply`，我的发起用 `is_reply` |
| 公共时间升序/降序 | 页面实测 | `publish_time=0/1` |
| 完整诉求详情、官方回复 | 页面实测 | 使用独立详情接口 |
| 处理进度、历史数据 | 页面实测与源码 | 详情提供 `change_history`；展开完整历史的入口受站点配置限制 |
| 图片/视频/附件预览 | 源码存在组件 | 当前抽样 `annex` 全为空，非空元素与鉴权未验证 |
| 支持/取消支持 | 原 HAR 已证实 | 切换操作，不得无条件重试 |
| 关注/取消关注、我的关注 | 原 HAR 往返证据，现场空列表实测 | 当前关注列表为空，现场没有重新改变关注状态 |
| 我的发起、个人详情 | 页面实测 | 查看已有记录仍在范围内，不提供新发起入口 |
| 我的发起排序/回复筛选 | 页面实测 | 条件名与公共列表不同 |
| 我的评价及三个评分维度 | 页面实测 | 列表条目为评价，内嵌 `appeal`，不是直接的诉求数组 |
| 给本人诉求评价 | 表单与提交源码，待评价部门 GET 失败样本 | 缺少待评价诉求，未提交；不能宣称实现所需协议已全部验证 |
| 公告列表、公告详情 | 页面实测 | 详情正文可能为 HTML，包含表格、图片 |
| 评论、评论回复、我的评论 | 通用源码存在，当前配置关闭 | 不绕过站点开关强行开放 |
| 踩、由本人“不满意”触发重启 | 通用源码存在，当前踩入口关闭 | 提交语义与权限未实测 |
| 撤回 | 通用源码存在，北航租户开关关闭 | 不是当前北航学生端可用入口 |
| 向官方回复继续追问 | 通用源码存在，北航 `userReply` 关闭 | 不能依据通用代码声称北航已开放 |

## 已实测读取接口

| 方法与路径（省略 `/api`） | 已见查询参数 | 返回 `data` | 证据 |
| --- | --- | --- | --- |
| GET `/appeal` | `limit`、`page`、`keyword`、`sqlb_id`、`reply`、`publish_time` | 分页对象 | L44、64、67、73、78、79、87、88、153、154 |
| GET `/appeal/{id}` | 无 | 直接诉求详情对象 | L103 |
| GET `/appeal/my_appreal` | `limit`、`page`、`publish_time`、`reply_time`、`is_reply` | 分页对象 | L112、114–117、137–138、186–187 |
| GET `/appeal/my_appreal/{id}` | 无 | 直接的本人诉求详情对象 | L118 |
| GET `/appeal/my_follow` | `limit`、`page` | 分页对象 | L129；非空样本见原 HAR E193 |
| GET `/appraise/my_appraise` | `limit`、`page` | 评价分页对象 | L122、139 |
| GET `/appraise/wait_department/{id}` | 无 | 本次失败样本为 `[]` | L167，仅已评价诉求探测 |
| GET `/notice` | 无 | 公告摘要数组 | L50、110、126、133 |
| GET `/notice` | `id={noticeId}` | 直接公告详情对象 | L134 |

公共列表按 ID 回查 `GET /appeal?id={id}`、配置 `/general_set_more`、字典 `/mobile/types?type_mark=SQLB`、用户信息 `/user/user_info`、部门 `/department` 已在原 HAR 中记录。用户资料仅用于当前身份与功能判断，不应原样进入日志或公共缓存。

### 搜索与类别

```http
GET /api/appeal?limit=15&page=1&keyword={keyword}
GET /api/appeal?limit=15&page=1&sqlb_id=4&keyword={keyword}
```

- 页面回车搜索会发送 `keyword`，需要按 URL 查询参数编码。
- 类别字典：本次 `3=我要诉求`、`4=我要建议`、`5=我要表扬`。
- 搜索“校园”后返回的记录集合变化；再选择“我要建议”时同时传 `sqlb_id=4`，返回记录的 `sqlb_id` 均为 4。
- 搜索范围至少包含诉求正文和官方回复。用户随后手动搜索“报名”“搜索”“新北”的三个样本中，全部返回条目均能在 `content` 或 `appeal_reply[].content` 找到关键词；只检查诉求正文会错误地认为部分结果不匹配。其他字段是否也参与匹配尚未确定。
- 使用无匹配测试词时数组为空，界面显示“暂无数据”，但公共列表仍报告 `total=20`，总数不能用于判断是否存在结果。
- 从“我的发起”顶部搜索会导航至 `#/`，请求公共 `/appeal`；这不是对本人记录的局部搜索。

用户手动操作的网络请求如下，均为 HTTP 200、`code=20000`、`success=true`，且结果集合不同于未筛选首页：

```http
GET /api/appeal?limit=15&page=1&reply_time=0&keyword=报名
GET /api/appeal?limit=15&page=1&reply_time=0&keyword=搜索
GET /api/appeal?limit=15&page=1&reply_time=0&keyword=新北
```

上面为便于阅读解码后的查询值，实际请求使用 URL 编码。请求携带了 `reply_time=0`，但这三次操作没有单独验证公共列表中该参数的排序效果。

| 证据 | 搜索词 | 返回条数 | 正文包含 | 回复包含 | 正文或回复包含 |
| --- | --- | --- | --- | --- | --- |
| L197 | 报名 | 20 | 18 | 5 | 20 |
| L211 | 搜索 | 20 | 13 | 8 | 20 |
| L219 | 新北 | 20 | 20 | 2 | 20 |

“正文包含”和“回复包含”可能同时命中同一条诉求，不能将两列相加。三个样本均报告 `current_page=1`、`per_page=20`、`total=20`、`last_page=1`；这些分页元数据不影响已经验证的关键词匹配结论。

### 筛选与排序

| 页面操作 | 实际参数 | 已证实行为 |
| --- | --- | --- |
| 公共已回复 | `reply=1` | 返回记录 `reply=1` |
| 公共未回复 | `reply=0` | 本次空数组，但 `total` 仍为 20 |
| 公共时间从新到旧 | `publish_time=1` | 返回 `publish_time` 非递增 |
| 公共时间从旧到新 | `publish_time=0` | 返回 `publish_time` 非递减 |
| 我的发起按最近发起 | `publish_time=1` | 页面默认选项 |
| 我的发起按回复时间 | `reply_time=0` | 本次按回复时间升序；再次点击仍发送 0，没有切换为 1 |
| 我的发起已回复 | `is_reply=1` | 本次非空 |
| 我的发起未回复 | `is_reply=0` | 本次为空，`total=0` |

网页的筛选实现会替换筛选对象：选择类别后再点“未回复”，请求只有 `reply=0`，不再带 `sqlb_id`，但类别按钮可能仍显示旧标签；点时间排序也会覆盖回复条件。关键词可以与当前筛选一起发送。上游是否支持任意多条件交叉组合未完整验证，不能把网页标签当成当前请求条件。

### 分页实测

网页采用滚动追加的代码路径，没有常规页码按钮。本次公共列表及个人默认页均显示“数据加载完毕”。实际执行滚动到底后没有触发公共第二页请求。

随后执行如下**只读探测**，与页面点击证据分开记录：

| 请求 | 结果 | 结论 |
| --- | --- | --- |
| `/appeal?limit=15&page=2`（L136） | 20 条，`current_page=1`、`per_page=20`、`last_page=1`；ID 顺序与第一页完全相同 | 当前公共列表未按这些参数翻页 |
| `/appeal/my_appreal?limit=2&page=1`（L137） | 2 条，`current_page=1`、`per_page="2"`、`last_page=4` | 小页长有效 |
| `/appeal/my_appreal?limit=2&page=2`（L138） | 2 条，`current_page=2`；与上一页没有重复 ID | 我的发起分页有效 |
| `/appraise/my_appraise?limit=2&page=2`（L139） | 2 条，`current_page=2`、`per_page="2"`、`last_page=4` | 我的评价第二页请求有效 |

后续公共列表实现必须检测页码不前进、重复 ID 或服务端终止标记，避免无限请求和重复追加。这里没有证明公共列表“只能获取全站 20 条”，仅证明当前账号和接口行为下，该分页请求未得到下一批数据。不能通过伪造游标、时间字段或其他未观察到的参数声称解决了此限制。

## 完整详情与进度

### 接口差异

```http
GET /api/appeal/{appealId}
GET /api/appeal/my_appreal/{appealId}
```

普通详情通过点击列表正文打开弹窗；我的发起中的正文使用第二条接口。两者 `data` 都是直接对象。原 HAR 的 `GET /appeal?id=...` 返回 `data.data[]`，只用于列表条目更新，不能共用同一个响应解析模型。

在列表字段之外，详情还出现：

| 字段 | 类型与用途 |
| --- | --- |
| `appraise_count` | number，已评价部门数量相关字段 |
| `appraise` | array，已存在的评价；空和非空样本均已见 |
| `change_history` | array，处理历史 |
| `comment` | 本人详情中为 array，本次为空；公共详情样本未包含 |
| `publish_user` | 本人详情中为 string；不向日志输出实际值 |

`change_history[]`：`id:number`、`appeal_id:number`、`contents:string`、`restart:number`、`create_time:number`、`created_at:string`、`updated_at:string`。

界面实测显示“学生中心已分办”“完成回复”等进度和对应时间。源码按 `history.restart == detail.is_restart` 选择当前轮次历史；不能把所有重启轮次简单混为一条当前进度。全历史展开、重启理由等组件存在，但本次没有重启样本，且北航 `history`/`historyAdmin` 租户开关为 false。

官方回复位于 `appeal_reply[]`，字段与原报告一致。本次公共与个人记录、关键词“照片”的额外检索均未获得非空 `annex`，因此图片/视频/文件预览仍缺少真实结构证据。不能根据正文包含外部图片地址，就将其当成 `annex` 的正式附件协议。

## 我的评价与评价提交

### 读取已评价记录

`GET /appraise/my_appraise` 返回的每个条目是评价对象：

| 字段 | 已见类型 | 说明 |
| --- | --- | --- |
| `id`、`appeal_id` | number | 评价 ID 与诉求 ID，不能混用 |
| `speed` | number | 页面标签“响应时间” |
| `satisfaction` | number | 页面标签“回复满意度” |
| `degree` | number | 页面标签“问题解决程度” |
| `avg_grade` | string | 平均评分，不能只接受 JSON number |
| `content` | string | 评价文本，本文不保留原值 |
| `user_id`、`user` | null | 系统自动评价样本；不是所有评价必然都有评价人对象 |
| `department` | object | 被评价部门；响应是对象，提交时使用 code |
| `appeal` | object | 关联诉求 |
| `created_at`、`updated_at` | string | 评价时间 |

当前账号的历史诉求均已关闭、已评价，界面存在“系统自动默认五星好评”的记录。因此“我的评价”不能狭义解释成用户亲手提交的评价。

评价列表内嵌 `appeal` 并不保证包含普通列表的所有个人状态字段，例如本次缺少 `is_praise`、`praise_count` 等。后续不能把缺失字段直接当作“未支持”；需要完整状态时应读取详情。

### 待评价部门

源码接口为 `GET /appraise/wait_department/{appealId}`。本次仅对当前账号已评价的诉求做只读探测，L167 返回 HTTP 200：

```json
{
  "code": 40001,
  "data": [],
  "message": "",
  "success": "",
  "error": true
}
```

这是失败样本，不是“正常空列表”成功协议。未抓到真实待评价部门的成功响应。源码期望成功时拿到含 `code`、`name` 的部门数据，但对结束条件又检查 `data.length`，存在形状变化线索；需要实际待评价样本才能定型。

### 提交接口（仅源码证据）

```http
POST /api/appeal/{appealId}/appraise
Content-Type: application/json
```

已观察到的源码请求体字段：

```json
{
  "speed": 5,
  "satisfaction": 5,
  "degree": 5,
  "content_text": "示例评价，仅说明结构，未提交",
  "department": "{departmentCode}"
}
```

上例仅是合成结构，不是抓包请求，也不是实际评价。前端要求三个评分均非 0，使用星级控件；完整服务端范围、文本限制与必填规则未验证。

源码中的入口条件为：当前在我的发起、存在部门、部门数量不等于 `appraise_count`、`reply===1`，且评价隐藏开关关闭。提交后再次查询待评价部门，多部门情况下继续评价；全部完成时前端更新 `publish_status=3`。这表明评价可能结束诉求处理，不能为了接口探索提交测试评价，也不能将其描述为普通点赞操作。

## 公告

- 列表：`GET /notice`，`data` 为 `{id,title}` 数组。
- 详情：`GET /notice?id={id}`，`data` 为直接对象。
- 详情字段：`id:number`、`title:string`、`content:string`、`is_show:number`、`hits:number`、`sort:string`、`created_at:string`、`update_at:string`、`deleted_at:null`、`date:string`、`notice_files:array`。
- 字段名是 `update_at`，不是其他对象常见的 `updated_at`。
- 本次公告正文有富文本表格与图片；正文渲染和链接处理不能套用纯文本诉求展示。`notice_files` 本次为空，文件元素未验证。

## 鉴权和响应兼容

L166 通过当前页面会话中的 ihome token 发起 GET，设置 `credentials: "omit"`，仅显式提供 `Authorization: Bearer ...` 和 Accept。网络请求头复核：存在 Bearer，不存在 Cookie 和 `X-XSRF-TOKEN`；响应 HTTP 200、`code=20000`、`success=true`。

这补足了原 HAR 没有保存 Authorization 的证据缺口。只读列表可以采用这一组合；不能据此断言 CAS 登录链或写操作完全不需要 Cookie/CSRF。未验证 token 过期、刷新、注销以及 WebVPN/中转模式。

| 字段 | 成功样本 | 已见失败样本 | 解析约束 |
| --- | --- | --- | --- |
| `code` | `20000` | `40001` | 与 HTTP 状态分开判断 |
| `success` | `true` | `""` | 不应无条件按 Boolean 反序列化失败响应 |
| `error` | `""` | `true` | 不应无条件按 String 反序列化 |
| `message` | `"success"` | `""` | 可能为空，不保证可直接向用户展示 |
| `data` | 对象、数组、写操作字符串 | `[]` | 依据接口和业务结果解析 |
| `per_page` | 公共为 number；个人为 string | 不适用 | 兼容数字字符串 |

## 通用源码中的其他接口

下列是已定位的接口线索，不是全部已验证或北航已开放的能力。不得为了补证据更改租户开关、进入管理端或给真实诉求发送测试内容。

| 功能 | 接口和源码参数 | 当前北航边界 |
| --- | --- | --- |
| 评论列表 | GET `/comment/{appealId}?page=1&limit=10000` | 配置 `comment="0"`，页面无评论入口，未请求 |
| 我的评论 | GET `/comment/my_comment?limit=15&page=1` | 同一开关隐藏导航，未请求 |
| 发布评论 | POST `/comment`，`appeal_id`、`content_text` | 未提交 |
| 回复评论 | POST `/comment_reply/{commentId}`，`appeal_id`、`content_text` | 未提交 |
| 回复评论的回复 | POST `/comment_reply_reply/{replyId}`，`appeal_id`、`content_text` | 未提交 |
| 踩 | POST `/appeal_tread/{appealId}`，源码无 data | `step_on="0"`，未提交；切换语义不能直接从支持接口类推 |
| 重启诉求 | POST `/appeal/appeal_restart/{appealId}`，按租户可带 `reason` | 本人踩操作关联的弹层有入口线索；当前入口关闭，未提交 |
| 撤回诉求 | POST `/appeal/withdraw`，`appeal_id` | 北航 `withdraw=false`；通用代码还要求未回复且无官方回复 |
| 继续回复官方处理 | POST `/appeal/appeal_reply/{appealId}` | 北航 `userReply=false`；源码含正文、原回复及部门信息，完整请求未验证 |

当前 `general_set_more` 中 `fabulous="1"`、`fabulous_show="支持"`、`comment="0"`、`step_on="0"`；支持开启，评论和踩关闭。租户模块 `bfc7` 将北航标记为 `bjhkht`，其 `withdraw`、`userReply`、`history`、`historyAdmin` 均为 false。评价相关函数返回 false 在对应页面中表示“不隐藏评价”，不能仅凭变量名将其误判成评价关闭。

## 源码版本核对

通过浏览器读取当前资源并计算 SHA-256，与原 HAR 对应脚本逐一相同：

| 当前脚本 | HAR 条目 | SHA-256 |
| --- | --- | --- |
| `chunk-02bdb9d0.bf2b52b9.js` | E18 | `622db67518e59660dc401d7e7df8da15517c373555fbd3318ab65b377dd414d6` |
| `chunk-440a3eba.621036ad.js` | E22 | `2f40c38c1e3d6962812c79bc60910f0f05a9952963327db61a2c82761332be11` |
| `chunk-5cf0878b.ec70c3ee.js` | E25 | `ceef84493490b4b542dafa34f83b7b5a6b55943305b7e85c4743da6ef617ce6d` |

关键定位：E18 模块 `0315` 定义我的发起、待评价部门和评价提交；详情组件区分普通/本人详情；评价组件定义三个评分字段及逐部门流程。E22 的 `24a3` 定义详情读取，`58d9` 包含关注和撤回，`b775` 定义 Bearer 头，`bfc7` 定义租户差异。E25 定义我的评价列表。

## 尚未闭合的证据

1. 公共列表返回固定分页元数据的上游原因，以及官方支持的下一批数据读取方式。
2. 真实待评价部门的成功结构、多个待评价部门的切换和评价提交结果。
3. 非空附件、多个回复、匿名、重启诉求的真实样本与显示规则。
4. 我的关注非空多页、取消后刷新；目前非空与取消证据仍来自原 HAR。
5. 写接口最小鉴权、失败/限流/超时与并发语义。
6. token 过期、重新登录、账号切换与 UBAA 各连接模式。网页登录成功不代表这些能力已经验证。

后续接入应先覆盖已开放且有证据的能力；评价保留为明确范围内的待补证项，关闭的通用能力按站点开关处理。上述“待补证”不是已完成实现或验收。
