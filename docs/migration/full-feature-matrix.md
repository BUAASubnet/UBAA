# UBAA 旧版完整功能迁移矩阵

本文记录冻结 `ubaa_old` 中公开业务接口与 UBAA 2 当前迁移边界。所有协议字段、请求地址和错误语义必须先由冻结实现、冻结测试或真实上游响应证明，不能凭经验补全。

## 已迁移并提供 CLI

| 功能 | UBAA 2 CLI | 当前状态 |
|---|---|---|
| 认证与用户信息 | `auth`, `user show` | 已完成，Direct/WebVPN 双路会话 |
| 课堂签到查询 | `signin today` | Core、路线隔离业务会话和 CLI 已接入；真实路线待验证 |
| 课表与考试 | `schedule`, `exam` | 已完成，只读 |
| 成绩 | `grades` | 已完成，只读 |
| 空闲教室 | `classroom search` | 已完成，只读 |
| SPOC 作业 | `spoc` | 已完成，只读 |
| 希冀作业 | `judge` | 已完成，只读 |
| 阳光打卡查询 | `ygdk overview`, `ygdk records` | Core、OAuth 业务会话和 CLI 已接入；真实路线待验证 |
| 图书馆只读查询 | `libbook libraries`, `libbook areas`, `libbook area-detail`, `libbook seats`, `libbook bookings` | Core、CAS 业务会话和 CLI 已接入；真实路线待验证 |

## 尚未迁移

以下接口存在于冻结旧版，但当前 UBAA 2 合同没有定义稳定 Core DTO、上游证据和 CLI 交互，因此不能声称已完成：

| 旧版接口 | 主要能力 | 迁移前置条件 |
|---|---|---|
| `BykcApi` | 博雅课程查询、选课、退选、签到、统计 | 领域 DTO 与响应解析已完成；业务会话、HTTP、Facade 和 CLI 待接入；写操作仍需独立合同 |
| `CgyyApi` | 研讨室查询、预约、订单、取消、门锁码 | 需要冻结 DTO/测试、真实接口证据，以及预约/取消确认策略 |
| `EvaluationService` | 评教查询与提交 | 需要冻结 DTO/测试、真实接口证据，以及批量提交确认策略 |
| `LibBookApi` | 图书馆区域、座位、预约、取消 | 只读查询已接入；预约、取消仍需新的写操作合同 |
| `SigninApi` | 今日签到查询与签到 | 需要冻结 DTO/测试、真实接口证据，以及签到确认策略 |
| `YgdkApi` | 阳光打卡查询、记录、照片打卡 | 需要冻结 DTO/测试、真实接口证据，以及照片和提交确认策略 |

## 实施顺序

先迁移上述接口中的纯查询操作，再迁移有副作用的操作。每个操作独立完成以下闭环：

1. 记录 `ubaa_old` 接口、DTO、实现和测试的逐操作对照。
2. 添加脱敏 fixture/Mock 的失败测试并确认失败原因。
3. 在 Core facade 增加稳定 DTO 和方法，CLI 只调用 facade。
4. 增加 CLI 人类输出、JSON schema 和参数验证。
5. 运行聚焦测试、`just check`，更新迁移状态并独立提交。

没有完成真实上游验证的操作只能标记为“确定性测试通过”，不能标记为完整迁移。

## 课堂签到查询 parity

冻结 `SigninApi` 的查询不是普通教务接口复用：先访问
`https://iclass.buaa.edu.cn:8346/?type=jumpMyCenter`，在最终 URL 或重定向
`Location` 中提取 `loginName`；随后向 8347 的 `app/user/login.action` 发送固定
查询参数，取得业务 `id` 与 `sessionId`；最后请求
`app/course/get_stu_course_sched.action`，携带 `sessionId`、`id` 和
`yyyyMMdd` 格式的 `dateStr`。业务会话按学生标识缓存，并在失效后重试一次。

UBAA 2 已完成响应 DTO/解析器、独立业务会话、路线转换和 facade/CLI 接入，并有脱敏
fixture 与 Mock 回归测试；真实 Direct/WebVPN 路线仍待验证。`examples/buaa-api` 没有
等价 iClass 协议，不能借用其 URL、字段或错误语义。签到提交操作仍属于写操作，不在
本轮范围内。
