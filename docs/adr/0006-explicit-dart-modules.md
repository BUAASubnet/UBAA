# ADR 0006：以显式 Dart 模块替代跨领域 part 聚合

日期：2026-10-07。状态：实施中。依据为[可持续开发性审查](../migration/maintainability-audit-2026-10-07.md)。

## 决定

UI 按业务领域与公共展示责任建立独立 library；跨模块组件通过构造参数传递模型与回调。Bridge 领域函数接收独立客户端上下文，不能反向依赖对外 BridgeBackend。AppController 保留唯一组合入口与写入协调，逐步明确生命周期和领域状态的所有者。

内部类或函数因独立 library 去掉私有下划线时，仅在 `lib/src/` 中导入；公开 package barrel 使用显式 `show` 保持原导出集合。只读纯函数允许共用，不引入通用请求模板、共享账号全局变量或第二套写状态机。文件拆分与测试入口迁移不修改条件、调用顺序、字符串、数据字段、golden 和请求。

## 冻结来源与行为保持

移动前 `just refs` 验证旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`、示例 `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。旧版 API/DTO/local 实现与测试按[主矩阵](../migration/source-parity.md)、[离线恢复逐操作矩阵](../migration/source-parity-offline-recovery-2026-09-17.md)及后续专项记录定位；旧矩阵历史 SHA 不能代替当前 refs，本次不修改 Rust 协议实现。

| 操作 | 旧版与示例核对 | 本次移动约束 |
|---|---|---|
| 登录、验证码、资料与退出 | 旧版 AuthViewModel、LocalAuth 与模式会话；示例 sso/user、context、store 的对应边界；交互验证码与当前缓存恢复无同构 Flutter 实现 | 客户端、账号和交互代次只归上下文；准备/提交/取消次序不变 |
| 课表、考试、成绩、空教室 | 旧版各 API、Local 实现、DTO 与 LocalScheduleApiBackendTest；示例 aas 只有对应教务配置和课表读取，不能替代成绩或空教室协议 | 学期、周次、统计和投影逐表达式保留，不以示例 URL 替换现实现 |
| SPOC 列表、详情、补充提交信息 | 旧版 LocalSpocApi/BackendTest；示例 spoc 模块缺少完整同构角色与补充流程 | 保留当前列表权威、详情身份和可选补充错误语义 |
| Judge 列表、详情、分批读取 | 旧版 LocalJudgeApi/缓存与 worker；示例无同等实现 | 调度、取消、fallback 和账号代次原样移动 |
| Bykc 列表、已选、详情、统计 | 旧版 Bykc 接口/DTO/local/测试；示例 boya 仅部分等价 | 不改变筛选参数、目录身份、资格和缓存来源 |
| Cgyy 站点、时段、订单、锁码 | 旧版 LocalCgyyApi/BackendTest/专属加密；示例无同等协议 | 不修改任何端点或锁码权限，独立领域组件仅展示既有模型 |
| LibBook 列表、预约时段、记录 | 旧版 LibBook 接口/local/DTO/测试；示例无完整同构协议 | 当前逐日时段、分页和取消资格原样消费 |
| Ygdk 概览、记录、学期 | 旧版 Ygdk 接口/local/DTO/测试；示例无同等协议 | 原路线、记录分页和上传输入约束保持 |
| Signin 今日列表与查询 | 以 2026-09-17 签到专项九列为准；示例不替代旧 sessionId/时间戳 | 不触碰协议，保留 typed 动作及查询传递 |
| Evaluation 列表与分批详情 | 旧版接口/local/DTO/测试；示例 tes 为部分参考 | 问卷仍只归 Core；投影、资格与错误不变 |

以下九列逐项适用于上表每个操作：CAS/bootstrap/service、重定向与最终 URL、Cookie/session、HTTP 方法与精确参数、Header/正文编码、加密/签名常量均在未改动的 Core 中，保持现行逐操作矩阵；DTO/解析列只移动 Dart 展示投影，不改 FRB 类型或映射表达式；缓存/并发列保持同一上下文、代次和串行尾链，不重新创建客户端；错误/退出列保留原映射和调用位置，CLI 未改动。

成绩直接核对确认：旧版 LocalGradeApiBackend 先 GET 激活再 POST 同一 buaascore 页面，表单 `year/xq`，保留 XHR/Referer 与主会话失效仲裁；LocalScheduleApiBackendTest 断言这些字段。示例 aas 使用另一教务系统的 GET 配置/POST 课表与 query 参数，没有同等成绩端点，不能借其请求方式替换。原模型、统计与展示函数保持；本轮无需新增上游参数或真实写入。

如实现中需要改变上述任一行为列，停止机械移动并另立有来源支持的失败行为测试。结构迁移使用当前行为套件、独立组件测试、AST 标识符级移动检查及全量门禁验收。

## 测试治理

筛选辅助函数缺少用户入口必须失败。公共 API 通过实际 import 和类型签名验证，不对手写名字列表计数。旧兼容 API 的行为回归保留并标注，不能整组删除。集成入口采用可执行清单，新增/失效入口会使门禁失败，真实账号和人工巡检永不进入默认 CI 集合。
