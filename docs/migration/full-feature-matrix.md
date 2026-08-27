# UBAA 旧版完整功能迁移矩阵

本文记录冻结 `ubaa_old` 中公开业务接口与 UBAA 2 当前迁移边界。所有协议字段、请求地址和错误语义必须先由冻结实现、冻结测试或真实上游响应证明，不能凭经验补全。

## 已迁移并提供 CLI

| 功能 | UBAA 2 CLI | 当前状态 |
|---|---|---|
| 认证与用户信息 | `auth`, `user show` | 已完成，Direct/WebVPN 双路会话 |
| 课堂签到查询 | `signin today` | Core、路线隔离业务会话和 CLI 已接入；Direct/WebVPN 已验证 |
| 课表与考试 | `schedule`, `exam` | 已完成，只读 |
| 成绩 | `grades` | 已完成，只读 |
| 空闲教室 | `classroom search` | 已完成，只读 |
| SPOC 作业 | `spoc` | 已完成，只读 |
| 希冀作业 | `judge` | 已完成，只读 |
| 阳光打卡查询 | `ygdk overview`, `ygdk records` | Core、OAuth 业务会话和 CLI 已接入；Direct/WebVPN 概览已验证，记录分页仍需独立真实验证 |
| 图书馆只读查询 | `libbook libraries`, `libbook areas`, `libbook area-detail`, `libbook seats`, `libbook bookings` | Core、CAS 业务会话和 CLI 已接入；Direct/WebVPN 馆区列表已验证，其余子命令仍需独立真实验证 |
| 博雅课程只读查询 | `bykc profile`, `bykc courses`, `bykc course`, `bykc chosen`, `bykc statistics` | Core、业务会话和 CLI 已接入；Direct/WebVPN 课程分页已验证，其余子命令仍需独立真实验证 |
| 场馆预约只读查询 | `cgyy sites`, `cgyy purposes`, `cgyy day`, `cgyy orders`, `cgyy detail` | Core、业务会话和 CLI 已接入；Direct 站点列表已验证，WebVPN 及其余子命令仍需独立真实验证 |

## 尚未迁移

以下接口存在于冻结旧版，但当前 UBAA 2 合同没有定义稳定 Core DTO、上游证据和 CLI 交互，因此不能声称已完成：

| 旧版接口 | 主要能力 | 迁移前置条件 |
|---|---|---|
| `BykcApi` 写操作 | 选课、退选、签到 | 需新的写操作合同；五项只读查询已迁移 |
| `CgyyApi` 写操作 | 预约、取消、门锁码 | 需新的写操作合同；场地、用途、日期、订单和详情已迁移 |
| `EvaluationService` | 评教查询与提交 | 需要冻结 DTO/测试、真实接口证据，以及批量提交确认策略 |
| `LibBookApi` 写操作 | 预约、取消 | 需新的写操作合同；五项只读查询已迁移 |
| `SigninApi` 写操作 | 执行签到 | 需新的写操作合同；今日查询已迁移并完成双路线验证 |
| `YgdkApi` 写操作 | 照片上传、提交打卡 | 需新的写操作合同；概览与记录查询已迁移 |

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
fixture 与 Mock 回归测试；真实 Direct/WebVPN 路线均已验证。`examples/buaa-api` 没有
等价 iClass 协议，不能借用其 URL、字段或错误语义。签到提交操作仍属于写操作，不在
本轮范围内。
