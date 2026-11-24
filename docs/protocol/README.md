# 协议来源对照

修改认证、读取或写入功能前，从本目录查找相关操作的来源证据和既有决定。对照要求与停止条件见[协议门禁](../../AGENTS.md#协议门禁)。

## 使用方法

1. 按下表打开功能所在文件，先读“当前规则”，再读“逐操作基线矩阵”和与本次操作相关的“专项记录”。
2. 逐操作核对已记录的来源提交和文件定位；历史矩阵和旧专项中的旧提交只说明当时取证，不能替代当前证据。
3. 新的对照写入对应功能文件的“专项记录”，标题带日期，放在最前；跨功能的总规则写入[总则](parity/general.md)。
4. 来源冲突、换钉或会影响后续判断的取舍写入[决策记录](decision-log.md)，长期架构决策升级为 [ADR](../adr/)。

## 逐操作对照列

每个认证、读取或写入操作都要分别记录以下九项。某个来源没有相同的上游协议时，明确记录“不适用”，不能类比借用另一个来源的 URL、字段、加密或错误。

1. 业务 CAS/引导 URL 与 service
2. 重定向与最终 URL
3. Cookie、Session、Token 的作用域
4. HTTP 方法与精确参数
5. 请求头与正文编码
6. 加密与签名常量
7. DTO 与解析的字段、类型
8. 缓存、并发、重试
9. 错误、退出与产品语义

## 功能索引

| 功能域 | 文件 | 主要内容 |
|---|---|---|
| 总则与跨领域基线 | [general.md](parity/general.md) | 当前规则与冻结版本、逐操作历史矩阵说明、Flutter bridge 投影 |
| 认证、会话与连接方式 | [auth-session.md](parity/auth-session.md) | SSO/UC、WebVPN 重试、网关探测、退出、验证码、门锁显示、登录选项、路线切换 |
| 校园网限定提示页 | [route-policy.md](../contracts/route-policy.md#校园网限定提示页) | 分时段响应的来源对照、识别条件及读取回退 |
| 本机账号与身份 | [accounts.md](parity/accounts.md) | 账号索引、安全材料、共享恢复与身份撤销、CLI 账号登记、macOS Keychain、同账号资料缓存 |
| 离线恢复与持久缓存 | [offline-cache.md](parity/offline-cache.md) | 所需路线恢复、本地仓库、各业务持久范围与接线 |
| 首页 | [home.md](parity/home.md) | 首页状态与读取编排、待办、日程投影、考试待办、并发与加载性能 |
| 日程 | [agenda.md](parity/agenda.md) | 日程界面、本机日程关闭与导出、跨设备同步 |
| 公共命令与 CLI | [app-commands.md](parity/app-commands.md) | App 命令、共享本机服务、CLI 配置、命令实现抽取 |
| 本科课表、考试、成绩与空教室 | [academic.md](parity/academic.md) | 教务课表与考试、成绩、空教室、整学期下载、Android 桌面课表 |
| 研究生系统 | [gsmis.md](parity/gsmis.md) | GSMIS 课表、当前学期、作息方案、门户身份分流 |
| SPOC 与希冀作业 | [coursework.md](parity/coursework.md) | SPOC 认证/列表/详情、希冀列表/详情/批量缓存、正文预算、读取去重 |
| 博雅课程 | [bykc.md](parity/bykc.md) | 列表与详情、按需分页、退选截止、统计默认值、完整详情与筛选 |
| 每日课程 | [signin.md](parity/signin.md) | 今日查询、上课端口与时间戳、2026-09-17 修复 |
| 阳光打卡 | [ygdk.md](parity/ygdk.md) | OAuth 与 SSO 中间跳转、概览与记录、旧版界面依据 |
| 图书馆座位 | [libbook.md](parity/libbook.md) | 座位查询、日期与时段、自动加载 |
| 图书馆当前借阅与续借 | [campus.md](parity/campus.md#当前借阅与续借) | 图书馆会话、借阅列表、续借条件、单本提交与结果核对 |
| 图书馆云打印 | [cloud-print.md](parity/cloud-print.md) | 登录、上传、待打印队列、扫描文档、打印点与使用记录 |
| 研讨室预约 | [cgyy.md](parity/cgyy.md) | 场馆查询、订单详情身份、收据与写入边界 |
| 直接写操作与评教 | [write-actions.md](parity/write-actions.md) | 各写入九列、typed 操作资格、评教提交信封及多业务 DTO 原语补充 |
| 门户、账户指标与财务 | [campus.md](parity/campus.md) | 门户资料、账户指标、网费流量、财务收入 |
| iHome | [ihome.md](parity/ihome.md) | 补充旧版来源、逐操作协议、界面调整 |
| 健康云 | [health-cloud.md](parity/health-cloud.md) | 认证跳转、体测年份和成绩 |
| 北航云盘 | [bhpan.md](parity/bhpan.md) | 认证、读取、写入、分享、传输、日程固定文件版本条件 |
| 应用服务 | [app-service.md](parity/app-service.md) | 遥测、更新、公告与统计开关（非学校协议） |
| 宿主界面与平台能力 | [host-platform.md](parity/host-platform.md) | 列表连续滚动、系统选图与拍照、功能卡片按钮 |
| Core 与工程整理 | [core-engineering.md](parity/core-engineering.md) | Core 精简、模块目录化、传输诊断、依赖收敛、分支整合、工程审查整改、OHOS 安全存储密钥 |

## 来源记录与决策记录

- 各功能逐操作记录保留来源提交、文件定位和结论。
- [决策记录](decision-log.md)：来源冲突、换钉和其他会影响后续判断的取舍。

已被取代的合同、阶段计划和历史功能矩阵见 Git 历史。
