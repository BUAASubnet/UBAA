# UBAA 旧版完整功能迁移矩阵

本文记录冻结 `ubaa_old` 中公开业务接口与 UBAA 2 当前迁移边界。所有协议字段、请求地址和错误语义必须先由冻结实现、冻结测试或真实上游响应证明，不能凭经验补全。

实时验收只使用 `core-live` 的 Direct/WebVPN 只读矩阵；历史上经用户单独授权的写探针不属于本周期证据，任何写操作仍只做 Fixture、Mock、向量和默认拒绝路径测试。

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
| 阳光打卡查询 | `ygdk overview`, `ygdk records` | Core、OAuth 业务会话和 CLI 已接入；Direct/WebVPN 概览与记录均有实时成功证据 |
| 图书馆只读查询 | `libbook libraries`, `libbook areas`, `libbook area-detail`, `libbook seats`, `libbook bookings` | Core、CAS 业务会话和 CLI 已接入；Direct/WebVPN 已有实时证据，分区详情须在每日 08:30–23:00（`Asia/Shanghai`）开放窗口内验收 |
| 博雅课程只读查询 | `bykc profile`, `bykc courses`, `bykc course`, `bykc chosen`, `bykc statistics` | Core、业务会话和 CLI 已接入；Direct/WebVPN 已有课程业务成功证据，其他子命令由确定性测试覆盖 |
| 场馆预约只读查询 | `cgyy sites`, `cgyy purposes`, `cgyy day`, `cgyy orders`, `cgyy detail`, `cgyy lock-code` | Core、业务会话和 CLI 已接入；Direct/WebVPN 由 Core-live 逐操作验证，站点/用途及日期、订单、详情、锁码的实时结果分别记录，不以单项成功推断其它操作 |

## 已实现但默认禁止真实执行的写操作

以下写接口已具备 Core/CLI 协议实现和确定性安全证据，依据本合同默认不得在真实验收中调用；只有独立记录的明确授权例外才可执行：

| 旧版接口 | 主要能力 | 迁移前置条件 |
|---|---|---|
| `BykcApi` 写操作 | 选课、退选、签到 | Core/CLI 已实现；具备加密向量与默认阻止测试，禁止真实调用 |
| `CgyyApi` 写操作 | 预约、取消 | Core/CLI 已实现；预约验证码图像求解、加密向量、重试和 Mock 链已有确定性证据；2026-08-29 经用户独立授权完成一次 Direct 预约、等待旧版要求的 5 秒后取消，并由订单列表确认状态 2；后续仍默认禁止 |
| `EvaluationService` | 评教查询与提交 | Core/CLI 已实现自动问卷链、提交信封和确认门禁；仅允许 Mock/向量验证 |
| `LibBookApi` 写操作 | 预约、取消 | Core/CLI 已实现；具备 AES 请求向量与确认门禁，禁止真实调用 |
| `SigninApi` 写操作 | 执行签到 | Core/CLI 已实现冻结表单与确认门禁，禁止真实调用 |
| `YgdkApi` 写操作 | 照片上传、提交打卡 | Core/CLI 已实现 multipart/表单链与请求向量，禁止真实调用 |

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
