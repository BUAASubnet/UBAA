# iHome

入口为“高级功能 → iHome”。本模块读取北航接诉即办平台，提供诉求广场、我的发起、我的关注、我的评价和公告五个视图，不提供新发起诉求入口。

## 当前能力

- 关键词搜索由上游执行，匹配诉求正文和官方回复；从个人视图搜索会切换到诉求广场。
- 诉求广场支持类别、回复状态和时间排序。切换筛选时清除互斥的旧条件，避免界面标签与请求不一致。
- 详情展示诉求正文、官方回复、当前轮次处理进度和已有评价。我的发起使用独立的本人详情接口。
- 关注和支持使用上游切换接口；UBAA 先读取当前状态，按目标状态至多提交一次，再回查结果。
- 未关注和未支持显示空心图标，选中后显示实心图标及选中色。
- 写操作结果不明时不会自动重发；当前条目的写按钮暂时不可用，打开详情刷新确认后恢复。
- 普通列表和评价记录分别解析，评价列表保留三个评分维度及关联诉求。
- 公告提供列表及详情，HTML 正文目前转换为可选择的纯文本，不执行上游脚本。

## 已知边界

公共列表的 `page=2` 实测仍返回第一页及固定分页元数据。客户端遵循上游的结束标记，并检测重复 ID 和页码不前进，避免重复追加；不声称已绕过上游的分页限制。我的发起、我的评价具有正常分页证据。

评价提交仍缺少成功样本，本版只读取已有评价。当前北航关闭的评论、踩、撤回及继续追问入口不开放。附件的非空结构尚未确认，本版没有附件预览；公告表格和图片不做富文本还原。

接口依据为 [HAR 报告](../_audit/2026-09-17-ihome-api.md) 和 [现场报告](../_audit/2026-09-17-ihome-live-api.md)。浏览器证据、Mock 测试和真实 UBAA 端到端验收是不同层级，不能互相替代。

iOS 真实账号直连的已验收项和未覆盖项见 [iOS 验收记录](../_audit/2026-09-18-ihome-ios-acceptance.md)。该记录使用模拟器，不代表物理真机验收。

## 连接和隐私

直连、WebVPN 与服务器中转共享同一上游协议实现。使用 UBAA 现有 CAS 会话获取 ihome token；token 仅保存在对应会话的内存客户端中，切换模式、重新登录或清理缓存时销毁。模块自身不保存 HAR 凭据，也不向日志输出登录跳转、业务 token 或原始响应。

共享 DTO 不包含发布人的账号、姓名、联系方式或原始用户对象。服务器中转需部署包含新路由的后端；客户端更新本身不会使旧服务端自动具备 ihome 能力。

## 维护位置

| 职责 | 文件 |
| --- | --- |
| 跨层数据结构 | `shared/src/commonMain/kotlin/cn/edu/ubaa/model/dto/Ihome.kt` |
| API 与中转调用 | `shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/IhomeApi.kt` |
| 响应解析与隐私字段裁剪 | `shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/IhomeProtocol.kt` |
| CAS 跳转、上游请求及操作回查 | `shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/IhomeUpstreamClient.kt` |
| 本地会话绑定 | `shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalIhomeApi.kt` |
| 服务端会话缓存与路由 | `server/src/main/kotlin/cn/edu/ubaa/ihome/` |
| 页面与状态管理 | `composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/ihome/` |

中转路由前缀为 `/api/v1/ihome`，全部要求 UBAA 登录：

| 方法 | 路径 | 用途 |
| --- | --- | --- |
| GET | `/appeals` | 传入 `scope/page/limit/keyword/filter/categoryId` 查询 |
| GET | `/appeals/{id}?mine=true或false` | 读取本人或公共详情 |
| GET | `/config` | 支持开关、按钮文案及类别字典 |
| GET | `/notices` | 公告列表 |
| GET | `/notices/{id}` | 公告详情 |
| POST | `/appeals/{id}/reaction` | JSON `reaction=FOLLOW或SUPPORT`、`enabled=true或false`，返回回查状态 |

`reaction` 是 UBAA 的目标状态接口，不直接暴露上游切换接口。它降低重复提交风险，但没有上游版本号/幂等键，不能承诺跨进程或多设备并发下的强幂等性。
