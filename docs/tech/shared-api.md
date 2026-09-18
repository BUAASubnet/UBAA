# 共享 API 与契约

shared API 是客户端和服务端之间的稳定层。UI 不直接拼接服务器路由，而是通过业务 API 和 backend 接口获取数据。

## 设计规则

- DTO 放在 `shared/src/commonMain/kotlin/cn/edu/ubaa/model`，使用 kotlinx.serialization。
- 每个业务模块在 `api/feature` 中定义 backend 接口，relay backend 使用 `ApiClientProvider.shared` 访问 server。
- 本地连接模式在 `api/local` 中实现同一 backend 接口。
- 错误响应通过 `ApiErrorResponse` 和错误码映射到用户可读文案。
- 新增业务能力时优先先扩展 shared 接口，再分别实现 relay、本地和服务端路由。

## API 分类

- 认证与用户：`AuthApi.kt`、`AnnouncementService.kt`、`UpdateService.kt`。
- 课程与学习：`ScheduleApi.kt`、`GradeApi.kt`、`SpocApi.kt`、`JudgeApi.kt`。
- 校园服务：`BykcApi.kt`、`ClassroomApi.kt`、`SigninApi.kt`、`CgyyApi.kt`、`LibBookApi.kt`、`YgdkApi.kt`、`EvaluationService.kt`。
- 校园诉求：`IhomeApi.kt`，协议解析和上游调用由本地与中转共用，详见 [iHome](/features/ihome)。
- 存储：Token、凭据、公告已读、博雅筛选、研讨室表单。

## 兼容性

服务端返回字段要兼容已发布客户端。尤其是版本检查、错误响应、成绩和作业 DTO，服务端能兼容时优先在服务端做向后兼容。

版本检查响应当前同时返回 `latestVersion`、`status`、`updateAvailable`、`downloadUrl`、`releaseNotes`，并保留旧客户端兼容字段 `serverVersion` 和 `aligned`。

## 来源文件

- `shared/src/commonMain/kotlin/cn/edu/ubaa/api/core/ApiClient.kt`
- `shared/src/commonMain/kotlin/cn/edu/ubaa/api/core/ApiFactory.kt`
- `shared/src/commonMain/kotlin/cn/edu/ubaa/api/auth/NetworkUtils.kt`
- `shared/src/commonMain/kotlin/cn/edu/ubaa/api/auth/UpdateService.kt`
- `shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/GradeApi.kt`
- `shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/JudgeApi.kt`
- `shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/LibBookApi.kt`
- `shared/src/commonMain/kotlin/cn/edu/ubaa/model/dto/Auth.kt`
- `shared/src/commonMain/kotlin/cn/edu/ubaa/model/dto/Judge.kt`
- `shared/src/commonMain/kotlin/cn/edu/ubaa/model/dto/LibBook.kt`
- `shared/src/commonTest/kotlin/cn/edu/ubaa/api/ApiFactoryDispatchTest.kt`
