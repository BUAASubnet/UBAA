# iHome 来源对照与实施记录

日期：2026-10-25。UBAA2 起点为 `2bc8427e45e84e61356ab427b4d877782ae07ca3`。本记录先于生产改动建立。

## 来源裁决

冻结 `examples/ubaa_old` 为 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`，接口、DTO、本地实现和测试目录均没有 iHome。固定 `examples/buaa-api` 为 `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`，`src/api.rs` 无 iHome；核对 `api/sso/auth.rs`、`request.rs`、`store/cookies.rs`、`store/cred.rs`，其 SSO/用户中心实现不能提供 iHome 的业务参数、Bearer 或切换写入协议。不得借用其他模块的字段、加密常量及错误。

用户明确要求参考更新后的旧版。本次补充来源为本机 `/Users/moorefoss/Code/UBAA` 的提交 `d6dd8f2e5c8121e43f22cd1fbf15152ae87100e9`：`shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/IhomeApi.kt`、`IhomeUpstreamClient.kt`、`IhomeProtocol.kt`、`api/local/LocalIhomeApi.kt`、`model/dto/Ihome.kt`，以及 `shared/src/commonTest/kotlin/cn/edu/ubaa/api/Ihome{Protocol,UpstreamClient}Test.kt`、Compose 的 iHome 页面与 ViewModel。该仓库存在无关 Judge 未提交改动，iHome 文件无本地改动。冻结引用保持原提交，新增功能仅依据上述已提交 iHome 实现。历史真实观察见旧仓库 `docs/_audit/2026-09-17-ihome-live-api.md` 与 `2026-09-18-ihome-webvpn-login.md`；当前验证另行记录。

## 逐操作协议

以下每行两份冻结源均无同协议实现。公共规则：复用所属账号和路线的 SSO/Cookie；仅登录跳转用 Cookie，不添加未经来源证明的 X-XSRF-TOKEN；业务请求用 `Authorization: Bearer <内存令牌>`，无额外签名/加密。WebVPN 使用既有地址编码，TLS 校验保留。业务不跟随重定向，要求 2xx 且 `code=20000`、`success=true` 和存在 `data`。只读 HTTP 401 最多清除业务令牌重认证一次；错误正文不暴露给宿主。字段投影只保留内容、部门、时间与状态，不保留原始用户资料、电话或令牌。

| 操作 | CAS/bootstrap、service 和最终地址 | 方法、参数和正文 | DTO/解析 | 缓存、并发与错误 |
| --- | --- | --- | --- | --- |
| 业务认证 | GET `https://sso.buaa.edu.cn/login`，service 精确为 `http://i.buaa.edu.cn/api/authLogin`；最多12跳；只允许 SSO/iHome 主机，HTTP 回调升级 HTTPS；保留 `/web/` 尾斜杠，从 fragment `type=0&token=...` 提取令牌，不发送 fragment | GET，无 Bearer、无正文；每跳独立解析 Location，不残留前跳 service/ticket | 令牌仅在当前账号路线内存中 | 单飞、生命周期失效；未知跳转和服务错误显式失败，不误判为成功空列表 |
| 公共诉求 | 共用业务认证，`https://i.buaa.edu.cn/api/appeal` | GET `page`、`limit`；非空 `keyword`、可选 `sqlb_id`；最新/最早 `publish_time=1/0`，已回复/未回复 `reply=1/0` | `data.data[]`，`current_page/last_page/total`；诉求字段见下文 | 按页读取；重复页或重复编号停止继续加载，筛选改变从首页重读 |
| 我的诉求 | 同上，`/api/appeal/my_appreal` | GET `page/limit`；最新 `publish_time=1`，回复时间 `reply_time=0`，已/未回复 `is_reply=1/0`；保留上游拼写 | 同公共列表 | 不发送公共 keyword/sqlb_id/reply 参数 |
| 我的关注 | 同上，`/api/appeal/my_follow` | GET `page/limit` | 同公共列表 | 无公共筛选参数 |
| 我的评价 | 同上，`/api/appraise/my_appraise` | GET `page/limit` | 每行 `appeal` 为诉求，外层评价含 id、department.name、speed、satisfaction、degree、content、created_at | 同页边界；不把外层评价 id 当诉求 id |
| 诉求详情 | 同上，公共 `/api/appeal/{id}`，本人 `/api/appeal/my_appreal/{id}` | GET，正数 id，无正文 | id/content/publish_status_text/sqlb.type_name/publish_date（回退 created_at）/departments[].name；is_user/is_follow/is_praise；follow_count/praise_count；appeal_reply、appraise；change_history 仅保留 restart 与 is_restart 相同的条目；HTML 转纯文本 | 保留未知关注/支持状态；详情可刷新，不落盘原始响应 |
| 功能配置与分类 | 同上，`/api/general_set_more` 与 `/api/mobile/types` | GET 重复键 `key[]=fabulous&key[]=fabulous_show`；GET `type_mark=SQLB` | fabulous 为1才允许支持，fabulous_show 为显示名称；SQLB 的 id/type_name | 两个有界读取，配置失败不启用支持 |
| 公告与公告详情 | 同上，`/api/notice` | GET；详情附 `id` | 列表为数组，详情为对象；id/title/content/date | 无分页猜测 |
| 关注/支持 | 同上，`/api/appeal_follow/{id}`、`/api/appeal/appeal_praise/{id}` | POST；关注为 JSON `{}`，支持无正文 | 写前读当前状态，支持另检查开关；写后 GET 详情核对目标布尔状态 | 固定确认路线、串行、最多提交一次；已达目标不提交；结果未知不重试，刷新核对 |

只加入校园服务中的 iHome：公共查询、筛选、详情、个人列表、公告，以及旧版开放的关注/支持。旧版未实现的新建诉求、评论、反对、撤回和继续回复不加入。

## 验证记录

### 已完成的验证

- RED：初始 iHome 解析测试因缺失模块与 DTO 失败；实现后发现 WebVPN 解码 `/web/` 为 `/web` 的行为反例。修复为只剥离网关前缀，保留完整业务路径与 fragment/query 分离。10 项 Core 聚焦测试通过，包含两路线完整认证请求序列、HTTP 401 最多重认证一次、外部跳转拒绝、迟到令牌拒绝回写、提交响应丢失后的回读及不重复发送、支持开关拒绝和无正文单次 POST。
- RED：同一诉求多条评价的界面反例失败。去重键改用评价 id，普通列表仍用诉求 id；刷新失败保留列表。6 项 Widget 测试与 3 项 Bridge/账号代次测试通过，覆盖搜索、切换视图、迟到响应、重复分页、公告和确认后固定路线写入。没有删除旧测试。
- 七包 `just flutter-check` 通过：领域53、平台87、应用660、UI383、绑定20、宿主101、官方应用73，共1377项。最终详情限宽和卡片间距复用 UI 覆盖另行复验。
- `just verify-live mode=direct feature=ihome` 和 `mode=webvpn` 均通过：公共列表、我的诉求、我的关注、我的评价、存在项的公共/本人详情、分类与支持配置、公告列表和公告详情。只记录成功状态和集合规模，原始载荷、诉求内容和个人资料没有保存到仓库。
- CLI 使用隔离临时会话完成真实认证，`ihome list/config/notices` 均退出0并输出 schema12；CLI和 Core-live 均只读。新 CLI schema12、Bridge42 已同步常量、测试和当前合同声明。
- macOS Debug 构建与实际签名权限检查通过。通过 Computer Use 实际检查「校园服务 → iHome」、公共列表、搜索提交、诉求详情/官方回复/进度、返回列表、公告及公告详情。macOS 沙箱无法读取 CLI 的隔离临时会话，原生检查使用应用已有会话；没有手工改写既有会话文件。运行媒体不纳入 Git。

### 收尾门禁

`just refs`、`just layout-check`、`just check-sensitive`、`just check`、`just flutter-check` 和 `just flutter-codegen-check` 全部通过。最后的详情限宽/卡片间距调整另通过 UI 全包383项测试；最终 macOS Debug 已重建并打开，实际签名保留 Sandbox 与 network.client 权限。

完整门禁中发现的内部层反向依赖已通过把 iHome 凭据状态移入 `internal/route_state` 修复；旧 CLI schema11 测试辅助值已随公开 schema12 同步。没有放宽门禁、扩大结构基线或禁用测试。图书馆独立提交 `747cb353` 已保留，本次提交仅包含 iHome 实现及必需的合同/生成文件和验证记录。

### 验收边界

没有执行真实关注或支持 POST；写入证据来自 Mock 请求序列和界面确认测试。当前原生验收为 macOS；Android、iOS、Windows、Linux、OHOS 真机与发布流程未在本次执行。仅新增校园服务入口，不加入首页自动刷新，不添加新建诉求、评论、撤回或其它旧版未开放操作。

## 2026-10-25：列表内详情与操作调整

用户要求详情在当前页面呈现，移除固定路线小字，并将支持/关注放到列表卡片。本轮只调整 UI 展示与交互，继续复用上述 typed 读取、确认路线、单次提交和回读协议。详情与公告改为原位展开/收起，保留搜索、筛选和滚动；读取不增加新的请求参数。先复现原位展开与列表支持/关注用例失败，再实现。原详情写入用例迁移到列表，保留确认、固定路线与未知结果禁止重复提交覆盖。


本轮结果：原位详情与列表支持/关注反例先失败后通过；补充复现了刷新已展开卡片后详情消失的问题，修复为仅补取当前已展开项。8项聚焦用例及 `just check-changed` 全部通过，包含冻结引用、敏感/结构/模块检查，以及 UI385、宿主101、官方应用73 项测试和静态分析。macOS Debug 重建与实际签名权限检查通过，Computer Use 已实际检查列表操作按钮、原位详情展开/收起、公告原位展开与页签保留；没有执行真实关注/支持提交。


## 2026-10-25：关注与支持的紧凑样式

对照旧版主仓库 `d6dd8f2e` 的 `composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/ihome/IhomeScreen.kt` 中 `ReactionRow`：采用无边框图标切换、星标关注、点赞支持与独立 labelMedium 数量。UBAA2 图标视觉尺寸设为20，保留标准点击区域、悬停提示、已选颜色、禁用状态和原确认/单次提交/回读链。纯样式调整复用现有8项 iHome 行为覆盖，仅把定位方式改为图标语义，不新增文案缺席或控件数量断言。

本轮验收：8项 iHome 现有行为测试通过；`just check-changed` 通过，包含引用、敏感、结构、模块检查和 UI385/宿主101/官方应用73 项测试及静态分析，共559项。macOS Debug 构建与签名权限检查通过，已打开实际列表核对无边框星标/点赞、数量字号及间距；未操作真实关注或支持。


## 2026-10-25：全文显示与选择复制

用户明确要求列表完整显示诉求和全部回复，正文支持选中复制且不承担展开操作；查看详情只增加处理进度，保持回复位置。本轮仅修改共享 UI：列表文案始终来自当前分页条目，关注/支持的状态仍可消费详情回读；展开内容只使用详情中的当前轮次 history，不添加新协议或请求参数。先建立正文点击/长文本选择复制、全部回复布局，以及详情响应与列表文案不一致时回复位置不变的反例，再修改展示。既有展开测试切换到显式按钮，查询/刷新/复用和未知结果核对覆盖保留。

本轮验证：正文点击会误读详情、展开改变回复布局的反例先失败后通过。10项聚焦用例验证长文本末尾完整布局、全部回复复制内容、正文点击零详情请求、回复坐标/尺寸稳定和原确认核对行为。`just refs`、结构/模块检查以及 UI388、宿主101、官方应用73项测试与静态分析通过，共562项。当前工作区有并行首页考试任务，`just check-plan` 的全工作区规划包含该任务；本次执行上述与共享UI改动相关的门禁，未改动其代码。

macOS Debug 构建与实际签名权限检查通过；Computer Use 已检查完整正文/回复、拖选文字后仍保持收起、仅点击查看详情追加进度，展开后回复位置和已有选中状态均保持。没有执行真实关注/支持写入；运行媒体未纳入Git。
