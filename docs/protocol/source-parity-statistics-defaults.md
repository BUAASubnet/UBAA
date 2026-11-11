# 博雅统计与阳光留空默认值核对（2026-10-24）

参考提交沿用 references.md：ubaa_old 1f4b8f84、buaa-api a63712fa。当前修复基线 d79a05b1。

## 博雅统计

| 项目 | 冻结证据与处理 |
|---|---|
| API、DTO、测试 | 旧 shared 的 BykcApi.getStatistics、LocalBykcApi.getStatistics/LocalBykcStatisticsData 和 LocalBykcApiBackendTest；返回 validCount，statistical 为大类到小类的映射。当前错误地按对外 DTO 的 totalValidCount/categories 解析。 |
| CAS、service | 旧 LocalBykcApi.loginUrl 为 https://bykc.buaa.edu.cn/sscv/cas/login；buaa-api boya/core.rs 使用 SSO login、noAutoRedirect=true、service 指向上述业务地址。继续使用现有业务 bootstrap。 |
| 跳转与最终 URL | 旧实现从最终 URL/Location 提取 token，回退 cas-login；buaa-api 从最终 URL 提取 token。Core 继续限定 SSO/博雅主机与当前路线，详见 source-parity.md。 |
| Cookie 与会话 | 旧共享上游客户端 Cookie 与内存 bykcToken/loginMutex；buaa-api 共享 client/cred。继续使用当前会话、路线及业务单飞。 |
| 请求 | POST https://bykc.buaa.edu.cn/sscv/queryStatisticByUserId，明文参数 {}。两份参考 opt/LocalBykcApi 一致。 |
| 头、编码与加密 | 旧实现 JSON Content-Type、Accept、Referer/Origin、双 token、ak/sk/ts；AES-128 ECB padding 后 Base64，16 字节随机密钥，固定 RSA 公钥 PKCS1、SHA1 十六进制签名再 RSA。buaa-api 使用同公钥/算法、单 Authtoken、JSON 字符串包装。沿用旧实现及现有 crypto 向量，不改变请求。 |
| 解析 | validCount 必填整数；statistical 可缺省为空映射；分类键取第一个竖线之后文字，无竖线保留；assessmentCount/completeAssessmentCount 必填整数，后者大于等于前者即达标。buaa-api data.rs 同样读取 statistical 与上述计数，但硬编码分类编号且未投影总次数；采用旧版动态遍历。 |
| 缓存、并发 | 不新增缓存；沿用现有业务会话与读请求串行规则。 |
| 错误 | 信封继续经现有检查；结构或必填字段无效报解析错误，避免静默显示缺失统计。公开 DTO 不变。 |

## 阳光留空表单

旧 YgdkViewModel 将空白时间/地点转 null；LocalYgdkApi.submitClockin 为缺省项目选择名称含“跑”的首项，否则 sort 最小项；时间同时留空时按 Asia/Shanghai 生成：09:00 前使用前一天 20:00–21:00，其余使用当前小时减一并限制开始小时在 8–21，分钟归零，时长一小时。仅一个时间留空时报错。地点缺省为操场，图片缺省为旧版 ygdk_auto.png，分享缺省 false。用户确认本次“随机”指上述留空补齐。

本次在 UI 形成明确输入后进入既有准备/确认流程，沿用 Core 提供的可提交目标；过期或无效选择不替换为其他目标。输入字段、上传协议、OAuth bootstrap/service、重定向、Cookie/token、请求头、签名、缓存、并发和错误语义均不修改，沿用 source-parity.md 的阳光打卡逐操作核对。buaa-api 的 api 模块无阳光打卡等价实现，不能提供默认规则。旧 LocalYgdkApiBackendTest 和 YgdkViewModelTest 为默认值与半填时间行为的参考；本次补充实际表单输出的回归覆盖。

## 验证记录

- 修复前 博雅统计 lib 聚焦测试 两项失败：总次数返回 None；损坏数据被静默接受。修复后博雅聚焦测试通过。
- 修复前全部留空表单用例返回 null；修复后阳光 UI 31 项通过，包括北京时间 08:30、09:00、23:30 与半填时间反例。
- `just verify-live mode=direct feature=bykc` 与 `mode=webvpn` 均通过认证、资料、课程、详情、已选、统计六阶段；CLI Core-live 统计调用实际完成。仅记录阶段结果，不保存个人资料或原响应。
- macOS Debug 构建通过；没有提交真实打卡记录。默认图片沿用冻结字节和文件名，仅在用户继续后形成输入，仍由既有确认流程执行最终提交。

- 完整 `just flutter-check` 通过，共 1380 项测试；`just refs`、`just layout-check`、`just check-sensitive` 与 `just flutter-codegen-check` 通过。`just check` 复核时 Core 全部测试通过，但工作区并行评教修改导致 Bridge 的 3 项 judge_scan 测试出现 unexpected request method/url mismatch，故整仓 Rust 门禁未通过。涉及 online.rs、details.rs 和 tests.rs；本次未修改这些实现或夹具。
