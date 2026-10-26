# 博雅课程详情与选课修复

## 问题与来源

2026-10-26，macOS 实际窗口的课程标题显示“可选”，但“准备选课”被禁用。详情同时显示未选课程的“考勤未知”和多项“未提供”。当前解析器要求 `courseCurrentCount` 存在才能选课，与冻结来源不符。

生产修改前已核对以下来源：

- `examples/ubaa_old @ 1f4b8f8412272b6a423d4ad92b396e3db721e6f3`：`shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/BykcApi.kt`、`api/local/LocalBykcApi.kt`、`LocalBykcCrypto.kt`、`model/dto/Bykc.kt`，以及 `LocalBykcApiBackendTest.kt`。旧版课程人数为可空整数，空值不阻止选课。Compose 的 `BykcTimeFormatters.kt` 结合列表快照判断人数已满，`BykcTimeFormattersTest.kt` 覆盖此行为；`BykcCourseDetailScreen.kt` 按实际字段显示适用范围和签到配置。
- `examples/buaa-api @ a63712fa2ae0a6c8066197063ddee98e3a6b5b81`：`src/api/boya/{core,opt,data}.rs` 和 `src/store/{cookies,cred}.rs`。`Capacity.current` 的注释明确指出单项详情返回空人数，反序列化将其置零。UBAA2 保留空值，避免把未知人数显示为零。该来源不提供旧版完整联系信息、范围和考勤展示规则。

## 逐操作对照

共用认证与传输事实：旧版从 `https://bykc.buaa.edu.cn/sscv/cas/login` 启动业务 CAS，示例 SSO 的 service 为同一地址；从最终 URL 或 Location 提取 `/cas-login?token=`。UBAA2 保持现有有界跳转、主机校验和 WebVPN 路线。旧版业务 token 按用户缓存，示例使用 Boya credential 与 Cookie store；UBAA2 保持账号、路线及运行时代次隔离。

请求均为 POST，加密前为 JSON。旧版使用 JSON Content-Type、Accept、Origin、Referer 和 `auth_token` / `authtoken` 双头；示例仅发 `Authtoken` 并将密文作为 JSON 字符串。UBAA2 沿旧版本地行为保留编码。两来源使用相同 RSA 公钥、PKCS1 v1.5、16 字节 AES ECB 与 SHA1 摘要，并发送 ak/sk/ts；本轮不更改加密、密钥生成或 Cookie 规则。

| 操作 | 方法与精确参数 | 字段与解析 | 缓存与并发 | 错误与退出 |
|---|---|---|---|---|
| 课程分页 | POST `/sscv/queryStudentSemesterCourseByPage`，`pageNumber`、`pageSize` | `content`、分页元数据、可空 `courseCurrentCount`、容量、已选状态、日期、分类、范围与签到配置；保持现有字段类型 | 保持服务端分页、当前列表快照与缓存失效规则 | 保持安全错误映射与 CLI 退出码 |
| 单项详情 | POST `/sscv/queryCourseById`，`id` | 保留空人数，不能仅因人数为空拒绝已证明处于选课时间窗的未选课程；缺失已选状态、容量或关键时间仍为未知，畸形人数不能成为许可依据 | 读取和写前复核共用解析规则；写前继续新读同一课程，显示快照不能代替复核 | ID 错配、畸形写前字段继续拒绝 |
| 已选与签到显示补查 | POST `/sscv/getAllConfig`，`{}`；POST `/sscv/queryChosenCourse`，`startDate`、`endDate` | 按旧版选当前学期，`courseList` 内匹配 `courseInfo.id`；主详情有效签到配置优先，缺少时回退已选记录；考勤值保持可空 | 仍只对已选详情补查；不增加真实签到操作 | 补查失败保持失败语义，不虚构考勤或签到配置 |
| 选课 | POST `/sscv/choseCourse`，`courseId` | 旧版和示例均允许详情人数为空时提交，并由服务器处理满员、重复或不可选结果 | 保留准备、确认、同路线新读复核、单次提交及结果回读 | 确定失败保持安全错误；未知结果禁止自动重试 |

## 实现与验证

Core 保留 `courseCurrentCount=None`，仅放宽这一项已证实可空的字段。畸形、负数人数及无效关键字段仍不给选课许可。最终选课继续新读详情，调用一次 `choseCourse`，并保留服务器满员拒绝与未知结果处理。

Flutter 在从课程列表进入详情时保留同课程、同路线的在线列表快照，补充“已报名（列表）”和满员限制。列表快照只能收紧按钮，不能将未知资格改为允许。刷新详情、账号或缓存边界清除此快照。课程简介、适用范围和签到时间按实际内容显示；未选课程没有个人考勤记录时不显示未知考勤。

只读观察使用临时诊断，仅输出字段类型、数组数量和配置长度，未保存原始响应。截图课程的详情人数为 null、签到配置为空字符串；范围列表均有一项，页面内容来自学校。另一个课程的签到配置含四个有效日期和数值坐标，现有解析规则可读取。临时诊断已移除。

修改前新增 Core 反例得到 `Unknown != Allowed`；写边界反例在提交前被误拒绝；UI 反例缺少列表人数。修复后 Core 博雅聚焦测试和 25 项博雅 UI 测试通过。新增用例覆盖人数 null/缺失、无效/负数人数、已选/满员/截止拒绝、单次提交、学校满员失败、列表满员限制、未知资格、路线隔离与刷新清理。没有删除已有测试。

当前候选 Direct、WebVPN 的 `just verify-live mode=... feature=bykc` 均通过认证、资料、20 项课程分页、单项详情、已选和统计。冻结引用、目录与结构检查、敏感扫描、`just check`（含 CLI 二进制与合同测试）、七包静态分析和 1478 项 Flutter 测试、FRB 零漂移均通过。

macOS Debug 已重建，实际签名权限与产物结构检查通过。使用原有独立配置重启后，截图课程的详情显示列表报名人数，空签到明细已移除；点击“准备选课”成功新读并进入确认页，随后取消。学校最终报名结果仍需用户提交后确认。本轮未执行真实选课、退选或签到。


补充观察：原课程确认页验证通过后，继续读取其他课程时出现一次超时，后续详情显示 `upstream_changed`。随后新建隔离 Direct 客户端复查，资料读取耗时约 35.8 秒，课程列表返回 timeout，已选读取成功。该阶段的其他课程原生验收没有通过，不能据此声明全部真实课程均可读取；满员按钮限制由确定性测试覆盖。
