# UBAA 旧版完整功能迁移矩阵

本文记录冻结 `ubaa_old` 的公开业务能力与 UBAA 2 当前 Core/CLI/Flutter 交付边界。所有协议字段、请求地址、
加密常量和错误语义必须来自安全实时证据或固定冻结来源，不能凭经验补全。

当前“无签名执行目标已完成”表示生产 Core/bridge/app/UI、确定性测试、无签名构建和发布准备已闭合；它不表示
真实写入、签名、实体设备、原生安全存储或正式发布完成。实时验收默认只运行 Core-live Direct/WebVPN 只读
矩阵；任何真实写入仍需逐操作、逐目标、逐路线、逐时间单独授权。

## 读取与用户功能

| 功能 | Core/CLI | Flutter/FRB | 当前证据边界 |
|---|---|---|---|
| 认证、用户与路线设置 | `auth`、`user show`、双路线 Session、Auto/Direct/WebVPN | Splash、登录、会话恢复、我的、设置、路线切换与注销 | Core Direct/WebVPN 实时只读已验证；真实 App 账号链路/设备未验证 |
| 课表与考试 | `schedule`、`exam` | 学期/周次 typed 查询与详情页面 | 两路线 Core-live 与确定性 UI/宿主测试 |
| 成绩 | `grades` | 学期与已出成绩 typed 查询 | 两路线 Core-live 与确定性 UI 测试 |
| 空闲教室 | `classroom search` | 日期、校区、楼层、节次 typed 查询 | 两路线 Core-live 与确定性 UI 测试 |
| SPOC 作业 | `spoc` 列表、详情与安全诊断 | 列表/详情 typed 页面 | 两路线 Core-live；详情仅在父列表有 ID 时必需 |
| 希冀作业 | `judge` 列表、详情、批量与安全诊断 | 当前/过期/单项/批量 typed 查询 | 两路线 Core-live 与并发/缓存确定性测试 |
| 课堂签到查询 | `signin today` | 今日课程与签到状态 | 两路线 Core-live、业务会话 Mock 和 UI 状态测试 |
| 阳光打卡查询 | `ygdk overview`、`ygdk records` | 概览、记录分页、图片数量白名单 | 两路线 Core-live；图片 URL 不跨 FFI |
| 图书馆查询 | `libbook` 楼馆、分区、详情、座位、预约记录 | 分区/时段/座位/记录 typed 查询 | 两路线 Core-live；分区详情只在每日 08:30–23:00 营业窗口判定 |
| 博雅课程查询 | `bykc` 资料、课程、详情、已选、统计 | 课程/详情/已选/统计 typed 页面 | 两路线 Core-live；空父列表详情可带依据 N/A |
| 场馆预约查询 | `cgyy` 站点、用途、日期、订单、详情、锁码 | 场地/时段/订单 typed 页面 | 两路线逐操作 Core-live；用途 `static_fallback` 不冒充上游成功 |
| 教学评教查询 | `evaluation all/pending` | 全部/待评本地派生视图 | 两路线 Core-live 与 schema/UI 测试 |

## 写入能力

以下十项用户可见写入已具备 Core/CLI 协议、typed bridge、一次性确认、防重复、未知结果保护和确定性读取
核对流程。CLI 默认拒绝并要求 `--confirm-write`；Flutter 必须由用户主动进入 prepare→确认→单次 commit。

| 领域 | 用户操作 | 确定性实现 | 真实边界 |
|---|---|---|---|
| 博雅 | 选课、退选、签到/签退 | Core/CLI、加密/请求向量、typed intent、页面确认与读取刷新 | 当前周期未真实执行；UI 仍按展示字段收紧部分入口，状态缺失时保留 prepare 入口并由 Core 最终校验；typed eligibility 与默认拒绝将在阶段 11 完成 |
| 场馆 | 预约、取消 | 业务认证、签名、验证码挑战、Mock 重试、typed 表单、收据与订单列表核对 | 2026-08-29 有一次独立授权的历史 Direct 预约/取消证据；不自动证明当前提交或后续授权 |
| 教学评教 | 提交待评课程 | 问卷链、提交信封、typed 课程选择、确认与状态刷新 | 当前周期仅 Fixture/Mock/宿主 fake |
| 图书馆 | 预约、取消 | AES 请求向量、typed 座位/时段、确认、记录刷新 | 当前周期仅 Fixture/Mock/宿主 fake |
| 课堂签到 | 执行签到 | 冻结表单、重复签到门禁、确认与课程状态刷新 | 当前周期仅 Fixture/Mock/宿主 fake |
| 阳光打卡 | 上传照片并提交 | multipart/表单向量、照片 typed 边界、确认与记录刷新 | 当前周期仅 Fixture/Mock/宿主 fake；无真实照片上传 |

任何写请求一旦可能到达上游都不得自动重试。`outcome_unknown`、transport 异常、收据缺失或读取刷新失败
必须提示先核对，不得把 UI 成功文案当作上游最终状态。

## 能力变更闭环

后续新增或修改每个操作时独立完成：

1. 记录 `ubaa_old` 与 `examples/buaa-api` 的接口、DTO、实现、测试及“不适用”项；
2. 固定 URL/service、重定向、Cookie/Token、方法/参数/Header/Body、加密、DTO、缓存/重试和错误语义；
3. 添加脱敏 Fixture/Mock 的失败测试并确认失败原因；
4. 在 Core facade 提供稳定能力，CLI/FRB/Flutter 只消费 facade/bridge typed 合同；
5. 运行 focused、敏感扫描、Rust、Flutter/codegen 与适用平台门禁；
6. 认证或只读行为变化最终串行运行 Direct/WebVPN；真实写入另行申请具体授权。

只有 Fixture/Mock 的操作标记为“确定性验证”，不能标记“真实上游已验证”；只有无签名构建的宿主不能标记
“实体设备/正式发布”。

## 课堂签到协议 parity

冻结 `SigninApi` 的查询不是普通教务接口复用：先访问 iClass 8346 的跳转入口，从最终 URL 或重定向取得
`loginName`；再调用 8347 的业务登录取得 `id` 与 `sessionId`；最后按 `yyyyMMdd` 日期读取课程。业务会话按
学生标识缓存，失效后最多重试一次。

UBAA 2 已完成响应 DTO/解析器、独立业务会话、路线转换、facade/CLI/FRB/Flutter 接入，并有脱敏 Fixture、
Mock 与 Direct/WebVPN 只读证据。`examples/buaa-api` 没有等价 iClass 协议，不得借用其字段或错误语义。
签到提交属于已实现的写操作，当前只有确定性安全证据；没有单次真实授权时保持不执行。
