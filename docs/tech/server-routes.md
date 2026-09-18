# 服务端路由

server 使用 Ktor 注册公开路由、认证路由和业务路由。除健康检查、指标、公告、版本和认证外，业务路由都在 JWT 认证保护下。

## 公开路由

- `GET /`：基础响应。
- `GET /metrics`：Prometheus 指标。
- `GET /health/live`：进程存活检查。
- `GET /health/ready`：Redis 等依赖就绪检查。
- `GET /api/v1/app/version`：客户端版本检查。
- `GET /api/v1/app/announcement`：当前公告。
- `/api/v1/auth/*`：登录、刷新、退出、验证码和状态。

## 认证业务路由

- `/api/v1/user/info`
- `/api/v1/schedule/*`
- `/api/v1/exam/list`
- `/api/v1/grade/list`
- `/api/v1/bykc/*`
- `/api/v1/classroom/query`
- `/api/v1/signin/*`
- `/api/v1/cgyy/*`
- `/api/v1/evaluation/*`
- `/api/v1/spoc/*`
- `/api/v1/judge/*`
- `/api/v1/libbook/*`
- `/api/v1/ygdk/*`
- `/api/v1/ihome/*`：诉求、个人列表、公告及目标状态操作，具体契约见 [iHome](/features/ihome)。

图书馆座位当前注册的具体路由为：

- `GET /api/v1/libbook/libraries`
- `GET /api/v1/libbook/areas`
- `GET /api/v1/libbook/areas/{areaId}`
- `GET /api/v1/libbook/areas/{areaId}/seats`
- `POST /api/v1/libbook/bookings`
- `GET /api/v1/libbook/reservations`
- `POST /api/v1/libbook/bookings/{bookingId}/cancel`

## 维护规则

- 新路由要有 server route test。
- 对 shared DTO 的字段变更需要确认旧客户端兼容。
- 上游错误应转换为稳定错误码，而不是把内部异常文本透出给客户端。

## 来源文件

- `server/src/main/kotlin/cn/edu/ubaa/Application.kt`
- `server/src/main/kotlin/cn/edu/ubaa/health/HealthSupport.kt`
- `server/src/main/kotlin/cn/edu/ubaa/auth/api/AuthRoutes.kt`
- `server/src/main/kotlin/cn/edu/ubaa/version/AppVersionRoutes.kt`
- `server/src/main/kotlin/cn/edu/ubaa/announcement/AnnouncementRoutes.kt`
- `server/src/main/kotlin/cn/edu/ubaa/judge/JudgeRoutes.kt`
- `server/src/main/kotlin/cn/edu/ubaa/libbook/LibBookRoutes.kt`
- `server/src/main/kotlin/cn/edu/ubaa/cgyy/CgyyRoutes.kt`
- `server/src/test/kotlin/cn/edu/ubaa/ApplicationTest.kt`
- `server/src/test/kotlin/cn/edu/ubaa/health/HealthSupportTest.kt`
