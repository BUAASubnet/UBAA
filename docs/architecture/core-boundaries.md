# Core 边界

- `domain`：可序列化 DTO 和值对象，不访问 HTTP 或文件系统。
- `error`：稳定机器码、分类、重试标志和安全消息。
- `ports`：原始请求/响应传输；`ReqwestTransport` 保持 TLS 校验、禁止自动跳转并限制正文大小。
- `connection`：Direct/WebVPN 转换、主机白名单、跳转解析、有限网关探测和进程内缓存。
- `session`：持久化端口、Cookie 过滤、禁止跟随链接的文件访问、版本比较交换、原子替换的双槽 `session.json`、旧版迁移和失效策略。
- `upstream`（私有）：冻结 SSO/User Center 地址、HTML 表单解析、交互步骤检测和 JSON 信封解析。
- `runtime`（私有）：路线、传输/存储端口、Cookie jar、时间戳/版本、URL 转换、请求执行、持久化和清理。
- `auth`：逐路线 CAS 登录、交互步骤拒绝、风险/激活/注销流程和待提交 execution 状态。
- `features/user`：User Center 状态/资料及认证响应分类；`features/*` 承载只读服务。
- `facade`：聚合 `UbaaClient`、配置、路线解析、两个私有 runtime、双会话协调器和稳定宿主委托；`RouteClient` 固定路线，仅供诊断、Core-live 和测试入口使用。

宿主不得调用 `upstream` 或直接修改 Cookie jar。新增模块必须遵守同一依赖方向，
通过 facade 暴露稳定 DTO，并让 Core 负责路线和敏感数据边界。
