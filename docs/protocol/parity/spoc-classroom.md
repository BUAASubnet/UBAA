# SPOC 课堂直录播

## 当前规则

- 按 `kcid` 进入课堂。同名课程可能有不同 `kcid`，并签出不同的 `bind_id` 和 `course_id`。App 去除 `kcid` 首尾空白，拒绝空值、控制字符或超过 128 个字符的标识。`course_id` 和 `sub_id` 只接受 1–20 位 ASCII 数字。
- `queryYhSflx` 的学生样本只有字符串 `"2"`。前端源码将非 `1`、`3` 的身份按学生模式处理；App 只允许 `"2"` 继续请求签名。`"1"`、`"3"`、`"6"` 提示“暂不支持教师身份”，其余值提示“暂不支持当前身份”。
- 只读课程映射、目录、节次、转写、摘要、PPT 和媒体。不加载上游网页，不实现 `courseapi/v2/sign/sign`（维护者确认已废弃）、观看进度上报、点击计数或弹幕。
- 智学北航（msa）的 JWT 和 casapi Cookie 只在内存中持有，按账号、路线和认证代次隔离，不并入主 Cookie Jar。登出或认证代次变化时清空，不调用远端 casapi 登出。业务 `5002` 或 HTTP `401` 时，在当前路线重新认证一次，只重试原只读请求一次；再次失败交给既有 UC 会话仲裁。
- 目录与附加数据只在页面生命周期内持有，不写离线仓库。签名、`bind_id`、账号字段、Cookie 和 JWT 不传给宿主；日志和诊断也不保留这些值及媒体 `auth_key`。
- 维护者确认校外可直连媒体。即使业务走 WebVPN，也优先使用原始媒体地址。WebVPN 媒体仅作备选，不做本机流代理。播放器不按 `is_allow_video_drag`、`is_allow_speed_up` 限制拖动或倍速。

## 逐操作基线矩阵

Direct 使用表中的上游主机；WebVPN 使用 `d.buaa.edu.cn`，上游地址由 Core `to_webvpn_url` 包装，校验重定向目标前还原其上游地址。WebVPN 已验证可达的业务及媒体主机：`spoc.buaa.edu.cn`、`yjapi.msa.buaa.edu.cn`、`classroom.msa.buaa.edu.cn`、`resource.msa.buaa.edu.cn`、`lmt9.buaa.edu.cn`。不复制网页的 `vpn-12-o2-<host>` 查询标记。显式 Direct 与 WebVPN 不自动互换。

表中 **SPOC 会话**沿用[既有认证与会话规则](coursework.md#当前规则)：Direct 使用当前路线的 SPOC Token 与 RoleCode，WebVPN 另保留网关会话。**msa 读取**在 Direct 只提交当前路线的 msa Bearer JWT，在 WebVPN 经网关会话向上游提交同一路线的 Bearer JWT，业务接口不使用 casapi Cookie 鉴权。两条路线的业务 GET 均无正文。**msa 读取恢复**指上文规定的一次重认证与一次原请求重试；HTTP 或业务失败不能当作空数据。

| 操作 | CAS / 引导与 service | 重定向与最终地址 | Cookie / 会话范围 | 方法与精确参数 | 请求头与正文编码 | 加密与签名 | DTO 与解析 | 缓存、并发、重试 | 错误、退出与产品语义 |
|---|---|---|---|---|---|---|---|---|---|
| `queryYhSflx` | Direct：复用 `spoc.buaa.edu.cn` 的 SPOC 引导；WebVPN：同一业务经网关引导。两条路线均无新增 service。 | Direct：最终为该 SPOC 接口；WebVPN：为包装后的接口。登录跳转交既有 SPOC 认证处理。 | 两条路线均用 SPOC 会话。 | 两条路线均 GET `/spocnewht/kc/queryYhSflx?kcid=<课程标识>`。 | 两条路线均用 `Token: Inco-<token>`、`RoleCode`、`X-Requested-With: XMLHttpRequest`，无正文。 | 两条路线均无新增签名。 | 两条路线均读取 `code`、`msg`、`content`；学生样本为字符串 `"2"`。 | 两条路线均随映射读取，不持久化，认证错误沿用 SPOC 恢复。 | 两条路线均只开放学生身份；教师身份提示“暂不支持教师身份”。失败不推断身份。 |
| `getHxyTimestampAndSignature2` | Direct：在 SPOC 引导完成且确认学生身份后调用；WebVPN：同接口经网关。无新增 service。 | Direct：最终为 SPOC 签名接口；WebVPN：为包装后的接口。登录跳转交既有 SPOC 认证处理。 | 两条路线均用 SPOC 会话；签名材料只用于本次课程映射。 | 两条路线均 GET `/spocnewht/yun/getHxyTimestampAndSignature2?kcid=<课程标识>&type=&isxs=1`；不传 `rwh`。 | 两条路线均用 `Token: Inco-<token>`、`RoleCode`、`X-Requested-With: XMLHttpRequest`，无正文。 | 两条路线均使用 SPOC 下发的签名，Core 不生成签名。 | 两条路线均读取 `code=200` 与 `content.{ktsl_url,bind_id,username,realname,tenant_code,timestamp,signature,allow_live}`。`tenant_code`、`timestamp` 接受字符串或数字，`allow_live` 接受字符串或布尔，拼接时字符串化；两条路线均已通过解析，未单独记录原始类型。 | 两条路线均按 `kcid` 单次映射，不按课程名合并，不持久化签名；认证错误沿用 SPOC 恢复。 | 两条路线均在 `bind_id` 为空时停止，前端提示“任务号为空”。不猜测任务号或其他身份的参数。 |
| `get-bh-course-url` | Direct：使用签名响应给出的 `ktsl_url`，已观察到 `yjapi.msa.buaa.edu.cn`；WebVPN：包装该地址。无 CAS service。 | Direct：只读 302 的 `Location`；WebVPN：只读网关改写后的 302 `Location`，还原上游后校验。两条路线均只接受 HTTPS、精确主机 `classroom.msa.buaa.edu.cn` 与路径 `/coursedetail`，不跟随。 | Direct：以签名参数授权，不转发 SPOC Token、msa JWT 或 casapi Cookie；WebVPN：保留网关会话，不附加上述凭据。 | 两条路线均 GET `/coursescheduleapi/v2/bh-university/get-bh-course-url`，将 `bind_id`、`username`、`realname`、`tenant_code`、`timestamp`、`signature`、`allow_live` 依次拼接到以 `?` 结尾的 `ktsl_url`。 | 两条路线均无正文；`realname` 按前端 `encodeURIComponent` 进行查询值编码。 | 两条路线均原样使用下发的签名材料，不自行签名。 | 两条路线均只解析 `Location` 的 `course_id`（实测为数字形态）；同一 Location 的其他参数不参与 App 读取。 | 两条路线均不缓存签名 URL，不通过重放签名或打开落地页恢复。 | 两条路线均将 HTTP 200 且媒体类型为 `text/html` 判为课程未开通（`BusinessUnavailable`，`mapping_unbound_page`），不解析正文。其他非 302 响应返回 `UpstreamChanged`（`mapping_status`）。302 缺失 Location、无有效 ID 或目标不符也判为协议异常；不调用网页的 `check-bh-page-sign`。 |
| casapi 认证 | Direct：`yjapi.msa.buaa.edu.cn/casapi/index.php`，SSO `service` 为同一个不带 `auType` 的 casapi 起点；WebVPN：casapi、SSO、forward 经网关包装。 | Direct：入口 → SSO → 带 ticket 的 casapi → 去 ticket 的 casapi → classroom，均为 302；已有 casapi 会话可直接进入 forward。WebVPN：同一跳转链经网关，另读 Cookie 快照。两条路线均拒绝任何指向 HTTP 的跳转。 | Direct：复用当前路线 SSO 会话，在独立容器接收 `.msa.buaa.edu.cn` 的 `_token`。WebVPN：复用网关会话，在内存中从快照只提取 `_token`。两条路线均不写回主 Cookie Jar。 | 两条路线均 GET `/casapi/index.php?r=auth/login&tenant_code=21&forward=https://classroom.msa.buaa.edu.cn/`；SSO 回跳携带 `ticket`。WebVPN 另 GET `/wengine-vpn/cookie?method=get&host=classroom.msa.buaa.edu.cn&scheme=https&path=/coursedetail&vpn_timestamp=<毫秒>`。 | 两条路线均无正文，不带 SPOC Token 或 msa Bearer；Direct 按当前跳的 Cookie 域处理，WebVPN 网关请求只用当前路线会话。 | 两条路线均不计算 JWT 签名或构造 ticket；WebVPN 沿用 Core 包装。 | Direct：从 `Set-Cookie` 取得 `_token`；WebVPN：从分号分隔的 `name=value` 快照取同名字段。两条路线均先百分号解码，再从 PHP 序列化片段提取 JWT，不依赖前缀，不回退页面 URL 的 `token`。 | 两条路线均仅在当前账号、路线及认证代次内复用。msa 读取恢复只重认证一次。 | 两条路线均将 HTTP 跳转视为上游协议变化；无可解析 JWT 视为认证失败。登出及认证代次变化仅清本机状态。 |
| `get-course-detail` | Direct：完成 msa 认证后访问 `yjapi.msa.buaa.edu.cn`；WebVPN：同主机经网关。无新增 service。 | Direct：最终为 `yjapi` 接口；WebVPN：为包装后的接口。两条路线均不跟随到网页。 | 两条路线均用 msa 读取的凭据规则。 | 两条路线均 GET `/courseapi/v3/multi-search/get-course-detail?course_id=<课程标识>&student=<学号>`。 | 两条路线均用 msa 读取的请求头，无正文。 | 两条路线均不重用签名 URL，无业务签名参数。 | 两条路线均读取 `code=0` 与 `data`，包括 `id`、`title`、`realname`、`teachers`、`term_name` 与 `sub_list[年][月][日][]`。节次 `id`、`sub_status`、`playback_status` 和 Unix 秒时间字段为字符串；`play_time` 样本有字符串与整数。 | 两条路线均为页面内存读取，使用 msa 读取恢复。 | 两条路线根据节目状态与回放标志区分未开始、直播和回放；无回放数据时展示无回放，不解析 SPOC 故障公告。 |
| `get-sub-info` | Direct：完成 msa 认证后访问 `classroom.msa.buaa.edu.cn`；WebVPN：同主机经网关。无新增 service。 | Direct：最终为 `classroom` 接口；WebVPN：为包装后的接口。两条路线均不打开 `livingroom` 或回放页。 | 两条路线均用 msa 读取的凭据规则。 | 两条路线均 GET `/courseapi/v3/portal-home-setting/get-sub-info?course_id=<课程标识>&sub_id=<节次标识>`。 | 两条路线均用 msa 读取的请求头，无正文。 | 两条路线均无业务签名参数。 | 两条路线均读取 `code=0` 和 `data`。直播样本 `sub_status="1"`，用 `live_url.output.m3u8` 与 `live_url.output_student.m3u8`；回放样本 `sub_status="6"`，用 `video_list` 对象。每路用 `resource_guid`、`preview_url`、`duration`（秒字符串）、`type`（`"2"` PPT，`"3"` 教师）、`thumb`、`time_offset`（秒字符串）；`playurl` 样本也是对象。 | 两条路线均只在播放页持有，使用 msa 读取恢复，不持久化流地址。 | 两条路线均按实际媒体数据判断可播；空回放列表不构造媒体地址。拖动、倍速不受上游标志限制。 |
| `search-trans-result` | Direct：完成 msa 认证后访问 `yjapi.msa.buaa.edu.cn`；WebVPN：同主机经网关。无新增 service。 | Direct：最终为 `yjapi` 接口；WebVPN：为包装后的接口。两条路线均不跟随到网页。 | 两条路线均用 msa 读取的凭据规则。 | 两条路线均 GET `/courseapi/v3/web-socket/search-trans-result?sub_id=<节次标识>&format=json&resource_guid=<教师路标识>`。 | 两条路线均用 msa 读取的请求头，无正文。 | 两条路线均无业务签名参数。 | 两条路线均读取 `code=0` 与 `list[].all_content[]`；`BeginSec`、`EndSec` 为数字，`Text`、`TransText` 为字符串；`trans_content` 样本为同结构的 JSON 字符串。 | 两条路线均只在播放页持有，使用 msa 读取恢复。 | 两条路线均显示学校转写，空列表可独立显示无转写；转写故障不代替播放结果。 |
| `intelligent-summary/detail` | Direct：完成 msa 认证后访问 `classroom.msa.buaa.edu.cn`；WebVPN：同主机经网关。无新增 service。 | Direct：最终为 `classroom` 接口；WebVPN：为包装后的接口。两条路线均不跟随到网页。 | 两条路线均用 msa 读取的凭据规则。 | 两条路线均 GET `/courseapi/v2/intelligent-summary/detail?sub_id=<节次标识>&resource_guid=<媒体标识>`。 | 两条路线均用 msa 读取的请求头，无正文。 | 两条路线均无业务签名参数。 | 两条路线均读取 `success` 和 `result`，样本 `result.code=200`。`result.data[]` 按 `type` 解释 `content`：总结是字符串，关键词是字符串数组，问答和章节是对象数组，`start`、`end` 为毫秒。`QA` 与 `Q&A` 可重复；其余已见类型见专项记录。 | 两条路线均只在播放页持有，使用 msa 读取恢复。 | 两条路线均独立展示摘要与章节；没有摘要不影响回放，重复问答不显示两次。 |
| `search-ppt` | Direct：完成 msa 认证后访问 `classroom.msa.buaa.edu.cn`；WebVPN：同主机经网关。无新增 service。 | Direct：最终为 `classroom` 接口；WebVPN：为包装后的接口。图片读取按媒体规则。 | 两条路线均用 msa 读取的凭据规则，图片无需业务凭据。 | 两条路线均 GET `/pptnote/v1/schedule/search-ppt?course_id=<课程标识>&sub_id=<节次标识>&page=1&per_page=100&resource_guid=<媒体标识>`。 | 两条路线均用 msa 读取的请求头，无正文。 | 两条路线均无业务签名参数。 | 两条路线均读取 `code=0` 与 `list[]`，再解析 `content` 中的 JSON；取 `pptimgurl`、`pptthumb`、`detecttype`、`is_key`、`status`。文件名给出毫秒偏移。 | 两条路线均只在播放页持有，使用 msa 读取恢复。取第一页；实测页码 2 返回同一完整列表。 | 两条路线均将空结果显示为无幻灯片；PPT 错误不代替播放结果。 |
| 媒体 URL（HLS、MP4、PPT 图片） | Direct：使用 msa 已返回的 `lmt9.buaa.edu.cn`、`resource.msa.buaa.edu.cn` HTTPS 地址；WebVPN：相关主机已验证可包装访问，仅作备选。无 CAS 或 service。 | Direct：仅交付精确媒体主机上的 HTTPS URL，不拼接流 ID；WebVPN：备选地址使用 Core 包装，HLS 相对分片沿播放列表解析。 | 两条路线均不向播放器传 Cookie、JWT 或 SPOC Token；网关探测结果不作为复制网关 Cookie 给播放器的依据。 | 两条路线均 GET URL；HLS 按播放列表读取 TS；MP4 支持 Range；PPT 图片使用返回地址。 | 两条路线均无正文；播放器可发送 `Range`，无业务鉴权头；Direct 探测无 Cookie 或 Referer。 | 不计算或篡改 `auth_key`。Direct 样本未强制其值，但不得依赖免校验；WebVPN 备选也保留原查询。 | 已观察到 Direct HLS 为 200、MP4 Range 为 206；WebVPN 验证了 HLS、分片、MP4 Range 和 PPT 图片。 | 两条路线均只在播放器生命周期内使用地址，退出释放播放器，不做离线缓存或本机流代理。 | 两条路线均不把媒体故障视作业务认证失效；播放失败提供外部播放器入口，未验证的清晰度变体不作为可用来源。 |

## 专项记录

### 课堂映射、认证与播放读取（2026-11-26）

**证据来源：**2026-11-26 维护者授权的浏览器只读抓取（Direct + WebVPN）；前端源码 `getToken`（2026-11-26 抓取的 app/0 chunk）；既有 WebVPN Cookie 同步规则（[cgyy.md](cgyy.md) / [auth-session.md L-B](auth-session.md#研讨室门锁逐操作九列)）。[脱敏夹具清单](../../../fixtures/readonly/spoc_classroom/README.md)区分抓包裁剪和按记录构造的样本。

- SPOC 课程标识取自 `queryKclb` 的 `content[].kcid`；`kcmc` 仅用于显示。学生签名请求固定空 `type`、`isxs=1`，不调用教师的任务号选择接口。
- 映射请求保留签名响应中的 `ktsl_url`，只接受表中以 `?` 结尾的固定入口。按表中顺序拼接参数，只有 `realname` 按 `encodeURIComponent` 编码（空格为 `%20`）。其余参数保留原值，只接受 ASCII 字母、数字及 `._-`，否则返回 `UpstreamChanged`。
- App 拒绝含反斜杠、空白、ASCII 控制字符、用户信息或非默认端口的媒体和 PPT 地址。直播允许显式 HTTPS 443 端口。Direct 拒绝网关包装；WebVPN 解包后复核 HTTPS 和媒体主机。交付给宿主的是规范化地址，调试输出不包含地址。
- Direct 的含 `auType=cmc` 入口曾返回 `http://yjapi.msa.buaa.edu.cn/…`，再由上游升回 HTTPS。App 从不带 `auType` 的 HTTPS 入口起步，也不接受先降级后升级。
- 前端对 `_token` 做百分号解码，从 `{i:<序号>;s:<长度>:"_token";i:<序号>;s:<长度>:"<JWT>";}` 片段取 JWT。Direct 从 casapi 下发的 Cookie 取 `_token`，WebVPN 从课堂 Cookie 快照取 `_token`。两条路线的解析和后续 Bearer 读取均已通过真实验证。
- 未带 Bearer 的样本是 HTTP 200、`{"code":5002,"msg":"未传入token"}`，无 `data`。回放样本的 PPT 路 `time_offset` 为 `"-120"`，教师路为 `"0"`；偏移方向待核对。直播只采用已验证的 `output.m3u8` 和 `output_student.m3u8`。
- 回放两路及转写响应的 `resource_guid` 均为含字母的 32 位小写十六进制字符串。夹具使用相同形态的假值。Core 接受 1–64 个 ASCII 字母或数字，并逐项编码查询参数。目录的 `student` 取当前课程签名响应的 `username`。
- 课堂读取共用既有 SPOC 角色激活的 `POST /spocnewht/sys/casLogin`；课程映射、msa 认证和业务读取均为 GET。首次 `5002` 或 HTTP 401 只重试原 GET 一次，再次失败后核验主会话。主会话有效或无法确认时返回 `UpstreamUnavailable`，确认失效时返回 `AuthenticationRequired`。单独缺少可解析的课堂令牌时保留主会话。
- 摘要样本另有 `MindMapSummary`（嵌套 `topic`，时间为秒字符串），以及空的 `Asr`、`PptExtraction`。本期用学校自带转写，不接外部语音识别。PPT 缩略图与原图均按返回地址读取。

### 2026-11-26 真实只读验证（Direct / WebVPN）

维护者使用同一账号验证，两条路线的认证均为 PASS，读取结果一致：

- SPOC 课程列表返回 15 门课，尝试映射 12 门，成功映射 9 门。目录共 107 节：`replay` 81、`upcoming` 23、`tencent_meeting` 2、`other` 1、`live` 0。`other` 节次的 `sub_status=3`、`playback_status=0`，上游未说明这组状态的含义，App 显示为不可播放。
- 最近一节回放有教师与 PPT 两路，偏移非零。逐字稿 1087 段；摘要含总结、关键词 15 个、问答 9 条、章节 12 个；PPT 95 张。回放 MP4 的 `Range` 探测返回 HTTP 206（本机设有代理环境变量）。
- Direct 由 casapi 下发的 `_token` 可以按前端 `getToken` 规则解析。WebVPN 的 `/wengine-vpn/cookie` 快照也含可解析的 `_token`。两条路线的认证与后续 Bearer 读取均通过。
- 签名响应中的 `tenant_code` 和 `timestamp` 接受字符串或数字，`allow_live` 接受字符串或布尔值。两条路线均解析成功。诊断隐藏完整签名响应正文，未单独记录字段的原始类型。
- `get-bh-course-url` 对 9 门课返回 HTTP 302，目标为 `classroom.msa.buaa.edu.cn/coursedetail`；另 3 门课返回 HTTP 200，`Content-Type: text/html; charset=utf-8`，且正文完全相同，均为 1337 字节。脱敏诊断未保留正文。同批签名可用于成功映射的 9 门课，维护者据此将该响应判为课程级未开通。App 对 HTTP 200 且媒体类型为 `text/html` 的映射响应提示“该课程暂未在智学北航开通课堂”，返回 `BusinessUnavailable`，诊断原因为 `mapping_unbound_page`。其他非 302 响应仍返回 `UpstreamChanged`，诊断原因为 `mapping_status`。
- 当时没有直播节次，直播仅通过夹具验证。有直播课时，按授权分别运行 `just verify-live feature=spoc_classroom route=<direct|webvpn>`。

### 未验证项

| 项目 | 当前边界与重跑条件 |
|---|---|
| 离开回放页是否上报进度 | 已观察的加载及播放窗口内未见进度 POST。离页行为未验证。App 不加载上游页面，不受影响。 |
| `livepgc.msa.buaa.edu.cn` 清晰度及音频变体 | 此前观察到 HTTP 503。有活动直播且原响应仍提供 `m3u8_lhd`、`m3u8_lsd` 或 `m3u8_audio` 时，按授权只读复测。 |
| 两路 `time_offset` 的方向 | B5 使用两路齐全且偏移非零的真实回放，用两个画面都可辨认的事件校准播放时间。 |
| 两路音频是否一致 | 取得同一节次的两路音轨并按可确认的时间对齐，比较声音内容；轨道参数不能证明音源相同。 |
