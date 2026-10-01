# 分支整合前的冻结来源复核

日期：2026-10-01。先于按钮分支生产代码合并完成本记录。当前两源为 `ubaa_old@1f4b8f8412272b6a423d4ad92b396e3db721e6f3`、`buaa-api@a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。

## 历史来源能否复用

已逐文件比较旧按钮专项固定的 `6e75e120`→当前旧版、`efb7976`→当前示例。旧版变更集中在课表/研究生课表、签到、登录到课表账号关联、Android widget 和发布；博雅/图书馆/研讨室的接口、DTO、local、crypto、store、UI和测试未出现在差异清单。示例变化仅在 class、wifi、context、net；SSO、request.rs、Cookie/credential store 内容未变化。

因此按钮分支 `31a7d750` 中以下逐操作九列来源记录仍适用于相同业务操作：`source-parity-ui-bykc-details.md`、`source-parity-ui-libbook-dates.md`、`source-parity-ui-login-options.md`、`source-parity-ui-macos-credentials.md`、`source-parity-ui-navigation-actions.md`。这些记录随对应已提交代码纳入；其中历史证据、旧 SHA/Bridge v10 等不改写成新证据，当前 Bridge v36 及后续版本独立核对。

## 逐操作整合规则

| 操作 | CAS/bootstrap/service | 重定向与最终URL | Cookie/session | 方法/参数 | Header/编码 | 加密/签名 | DTO/parser | 缓存/并发 | 错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| 博雅课程目录与三维筛选 | 沿已对照旧LocalBykcApi | 不变 | 单客户端当前路线 | 旧分页参数不变；UI当前页本地筛选 | 不变 | 旧LocalBykcCrypto不变 | 纳入目录category/subCategory/campus等typed字段 | 与离线精确范围缓存合并；不缓存联系人或写资格 | 保持旧CLI形状/exit与本地缓存错误独立 |
| 博雅普通/已选完整详情 | 沿已对照入口 | 不变 | 不能跨路线拼接列表/详情 | 主详情→配置→已选补查；严格同ID显示 | 不变 | 不变 | 完整显示与资格分离；主配置优先，仅纯文本简介 | 在线完整详情与既有离线显示分开；迟到/身份栅栏保留 | 补查失败不伪装成功，旧API不增请求 |
| 图书馆逐日日程与座位 | 沿LocalLibBookApi及HTTP client | 不变 | 同账号/路线 | 以响应逐日时段配对；日期/seat参数取真实候选 | 不变 | 旧LocalLibBookCrypto不变 | 新typed日程与旧接口兼容 | 保留精确日期缓存；不把一天时段套用其他日期 | 空日/营业窗口保留，不把上游不可用当空座位 |
| 登录选项与macOS凭据 | 学校协议不变 | 不变 | 延续现有会话 | 仅本机Keychain接线和选项 | 不变 | 系统安全存储，不增加学校加密 | 非交互访问与可用性探测 | 与新的安全材料写入/读回/删除探测并存，退出栅栏不可丢 | 安全存储失败不得误报登录成功或降级明文 |
| 语义按钮、详情返回及筛选偏好 | 不新增请求 | 不变 | 账号隔离 | 本地参数及回调恢复 | 不变 | 不适用 | typed选择不推断上游字段 | 跨启动偏好与账号清理、恢复代次同时保留 | 保存失败保留当次编辑并明确反馈 |

示例未实现同一博雅/图书馆协议的操作继续明确不适用，不借用其字段、URL、加密或错误。context 新增校园网探测只证明示例自身行为，本轮显式 WebVPN 不引入它，也不复制关闭TLS验证的配置。

## 当前冻结旧版新增差异

`AuthViewModel`新增 `ScheduleStore.useAccount/forgetAccount`，登录页新增可选“查看已保存的离线课表”；`MainAppScreen`新增跨日更新、账号变化重置与课表周缓存/更新/整学期导入接线。离线分支已有相应缓存首页/账号隔离/整学期导入，但仍需逐项验收，不能从同名推断完全一致。`LocalScheduleApi`和研究生协议变化留待专项核对；课堂签到继续保留主目录已经按当前冻结源完成的 `acd49c27`，绝不从旧按钮分支回退。

交互验证码和门锁专用显示尚未纳入已提交按钮分支；其方案另行按当前源码、来源冲突和失败测试核实，不能以本次合并关闭该缺口。
