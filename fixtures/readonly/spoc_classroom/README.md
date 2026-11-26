# SPOC 课堂直录播脱敏夹具

同名课程的两条 `kcid` 按清单顺序分别使用 `signature-a`、`signature-b` 和 `course-url-a`、`course-url-b`。这组假 ID 用于串联测试：第一门课的目录与回放、转写、摘要、PPT 对应，第二门课的单节样本用于直播分支，不对应实际选课关系。账号、教师、学期和时间、课程与节次标识、媒体 GUID、签名、ticket、JWT、Cookie 及媒体 URL 中的标识和查询值均使用假值。媒体保留来源主机和路径形态。

业务正文 JSON 可直接作为响应字节。带头响应使用 `{status, headers, body}`，`headers` 的键为小写，值为字符串数组，`body` 为原始文本。认证链文件是按顺序排列的响应数组，每条按请求地址填入 `HttpResponse.final_url`，再交给 `ExpectedRequest`。第一跳的请求地址见[协议矩阵](../../../docs/protocol/parity/spoc-classroom.md#逐操作基线矩阵)，后续地址按上一跳的 `location`；WebVPN 链的最后一项由 Cookie 快照 GET 返回。加载方式见[确定性传输](../../../crates/ubaa_test_support/src/http.rs)。

回放的教师路假 GUID 为 `fedcba9876543210fedcba9876543210`，PPT 路为 `abcdef0123456789abcdef0123456789`。转写及摘要请求样本使用教师路，PPT 请求样本使用 PPT 路。只有转写响应包含 GUID，摘要和 PPT 响应不添加该字段。图片路径中的目录名保留原有格式。

| 文件 | 来源与覆盖 |
|---|---|
| `course-list.json` | 按已记录字段构造：`evidence.md` 第 1 节，保留同名课程条目的 `kcid`、`kcmc`。 |
| `identity.json` | 按已记录字段构造：`evidence.md` 第 2 节；`req1.txt` 仅记录请求。 |
| `signature-a.json` | 按已记录字段构造：`evidence.md` 第 2 节；`req2.txt` 仅记录请求。本样本覆盖字符串标量。B2 两条路线均解析成功，未单独记录原始类型。 |
| `signature-b.json` | 按已记录字段构造：`evidence.md` 第 2 节。本样本覆盖 `tenant_code`、`timestamp` 为数字以及 `allow_live` 为布尔值的解析。 |
| `course-url-a.json` | 按已记录字段构造：`findings.md`“总链路”与 `evidence.md` 第 1、2 节；302 头形态取自 `req_tab1_1.txt`。 |
| `course-url-b.json` | 按已记录字段构造：`findings.md`“总链路”与 `evidence.md` 第 1、2 节；沿用 `req_tab1_1.txt` 的 302 头形态，使用另一假 `course_id`。 |
| `course-url-unbound.json` | 按真实观察的状态码 / 类型 / 长度构造：HTTP 200、`text/html; charset=utf-8`、1337 字节。正文未取证。 |
| `casapi-direct.json` | 按已记录字段构造：`findings.md`“智学北航（msa）鉴权”与 `evidence.md` 第 4 节。按前端解析构造 `Set-Cookie`。B2 确认 Direct 由 casapi 下发的 `_token` 可解析，后续 Bearer 读取通过。 |
| `casapi-webvpn.json` | 按已记录字段构造：`findings.md`“智学北航（msa）鉴权”“WebVPN”与 `evidence.md` 第 4、5 节。按既有网关格式和前端解析构造快照。B2 确认 `/wengine-vpn/cookie` 快照含可解析的 `_token`，后续 Bearer 读取通过。 |
| `casapi-http-redirect.json` | 裁剪自原始抓包：`fresh229.txt`，含 `auType` 入口的明文 HTTP 跳转。 |
| `course-detail.json` | 裁剪自原始抓包：`resp45.json`，覆盖有回放和未开始；`vpn_detail.json` 中目录字段形态一致。 |
| `sub-recording.json` | 裁剪自原始抓包：`rec_subinfo.json`，教师与 PPT 两路回放。 |
| `sub-live.json` | 裁剪自原始抓包：`live45.json`，两路直播 HLS，回放对象为空。 |
| `transcript.json` | 裁剪自原始抓包：`rec_trans.json`，保留结构化分段及对应的 JSON 字符串。 |
| `summary.json` | 裁剪自原始抓包：`rec_summary.json`，保留总结、关键词、重复问答、章节、思维导图和空结果类型。 |
| `ppt.json` | 裁剪自原始抓包：`rec_ppt.json`，保留两张不同偏移的图片及字符串嵌套。 |
| `missing-token.json` | 按已记录字段构造：`evidence.md` 第 3 节，HTTP 200 业务 `5002`，无 `data`。 |
