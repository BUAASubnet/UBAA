# F03/F04/F05/F06 实施前来源对照

日期：2026-10-11。纯 refs 通过，冻结 old 为 1f4b8f8412272b6a423d4ad92b396e3db721e6f3，buaa-api 为 a63712fa2ae0a6c8066197063ddee98e3a6b5b81。本轮不改变校园 HTTP 协议，不发真实请求。

已读取 old 的 shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalConnectionAuth.kt（LocalAuthSessionStore、LocalCookieStore、PersistentLocalCookieStorage）、commonTest 对应 Session/Cookie 测试及 repository/TermRepository.kt；读取 buaa-api 的 src/context.rs、store/cred.rs、store/cookies.rs。old 使用按路线分隔的 Settings 与协程 Mutex；示例从 cred.json/cookies.json 读取并返回 typed io/parse 错误。两者都没有 FRB 启动、UBAA2 双槽修订文件锁或 UI 初始化合同，不能借其同步加载方式证明 Flutter UI 允许无界阻塞。

| 本地操作 | CAS/bootstrap/service | 跳转/最终 URL | Cookie/Session 范围 | HTTP 方法/参数 | Header/正文 | 加密/签名 | DTO/解析 | 缓存/并发 | 错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| 打开后端/读取会话 | 不发网络请求，不涉及 | 不涉及 | 保留双路线、schema v2、CAS 修订 | 不涉及 | 不涉及 | 不改变磁盘材料保护 | 不改变会话字段及解析 | 保留进程 Mutex+内核排他锁；一次获取总预算 2 秒；FRB 异步线程打开 | 超时保留 typed 资源忙原因；不删锁、不清坏会话，失败可重新打开 |
| 后端重建 | 不新增认证请求，既有恢复按原协议 | 原规则不变 | 不复用已关闭 opaque handle；迟到新实例必须释放 | 既有恢复入口不变 | 不变 | 不变 | 后端工厂变为 FutureOr，Bridge 合同升级 | 等待工厂时 UI 可绘制；退出/销毁/换代后禁止安装迟到实例 | 安全分类配置、会话、组件、资源忙、合同不兼容 |
| 成绩基线/缓存生命周期 | 本地加密读取，不新增业务请求 | 不涉及 | 保留账号、后端、会话与缓存代次隔离 | 不涉及 | 不涉及 | 加密缓存合同不变 | 原 GradeScoreBaseline 字段不变 | 生命周期所有者统一 scope，业务所有者独立持有在途与有效性 | 失效返回原 OperationConflict，不写旧账号结果 |
| 提交后异常/核对提示 | 继续使用现有 Core 原子路线绑定 | 原规则不变 | 原路线 Cookie 与 Session 修订检查不变 | 以下十种操作均沿既有请求 | 原编码不变 | 原常量不变 | 原 DTO 不变；本地 Bridge 结果增加核对票据确认 | 一次性意图不重放，发送边界独立观察；成功结果投影前保留持久线索 | 发送前已知失败保持原错误；发送后 panic/未分类跨语言异常保留 OutcomeUnknown 并回读 |

写操作逐项协议沿用 [2026-10-07 九列矩阵](source-parity-engineering-rust-2026-10-07.md)：博雅选课、退选、签到/签退、课堂签到、图书馆预约、图书馆取消、阳光打卡、场馆预约、场馆取消、教学评教。此次只增加本地边界观察与结果确认，不调整任何 URL、service、重定向、字段、头、签名、DTO 或重试次数。old 某些方法的认证重放不用于恢复非幂等重试；buaa-api 没有等价的 FRB 意图/核对票据，不能类推。详细已有来源仍见 source-parity.md。

## 提交后的固定路线读取

F04 进一步核对发现，原通用回读没有接收 intent 路线；场馆取消、阳光打卡、评教已有专用固定路线入口，其余补充 caller-pinned 读取。每次先验证指定路线的 Session 与修订，再复用同一个 feature 请求实现，绝不暂改全局策略或 Auto 回退。

| 操作 | CAS/bootstrap/service | 跳转/最终 URL | Cookie/Session | 方法/精确参数 | Header/编码 | 加密/签名 | DTO/解析 | 缓存/并发 | 错误 |
|---|---|---|---|---|---|---|---|---|---|
| 博雅已选回读 | 原 LocalBykcApi bootstrap/service，沿原 feature 保持 | 原有界跳转保持 | 指定已认证路线 | 原 queryChosenCourse/startDate/endDate | 原 JSON 与 token 头保持 | 原博雅加密签名保持 | 原 courseList DTO 与资格投影 | 绕过新增离线恢复，不并发改策略 | 固定路线不可用即失败，不改另一条路线 |
| 图书馆预约列表回读 | 原 LocalLibBookApi 登录引导保持 | 原最终 URL 规则 | 指定已认证路线 | 原 member/seat，type=1/page/limit | 原 requestJson 编码保持 | 不新增加密字段 | 原 bookings DTO | 同上 | 同上 |
| 课堂今日回读 | 原 currentSession 引导保持 | 原规则 | 指定路线 Session/sessionId | 原 get_stu_course_sched.action，id/dateStr | 原 GET 与 sessionId 头 | 无新增签名 | 原 SigninClass | 同上 | 同上 |
| 场馆预约列表回读 | 复用已有 cgyy_orders_on_route | 原规则 | 原指定路线 | 原 get_orders/page/size | 原实现 | 原签名 | 原 CgyyOrdersPage | 不改已有取消双回读 | 原 typed 错误 |

补充读取 old LocalBykcApi.kt:393、LocalLibBookApi.kt:247、LocalSigninApi.kt:71 与示例 boya/opt.rs:51。示例只存在博雅等价请求；未实现图书馆/课堂等价协议，不借用示例 Class。其余列的具体来源继续引用主 source-parity.md 与此前逐操作矩阵。以上生产入口只复用现有 features，不重新实现请求或解析。
