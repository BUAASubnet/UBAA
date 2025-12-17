## **UBAA 项目 AI 解析文档**

### **1. 项目架构概览**

本项目采用典型的 Kotlin Multiplatform 架构，通过分层和模块化实现代码共享与平台特异性开发。其核心思想是 **“一次编写，多处运行”**。

```mermaid
graph TD
    subgraph " "
        A[Application Layer] --> B{Presentation Layer};
        B --> C{Domain/Business Logic};
        C --> D{Data Layer};
    end

    subgraph "Project Modules"
        subgraph "composeApp - UI & Platform Entry"
            direction LR
            AndroidApp[Android]
            iOSApp[iOS]
            DesktopApp[Desktop/JVM]
            WebApp[Web JS]
            WasmApp[Web Wasm]
        end

        subgraph "server - Backend"
            direction LR
            Ktor[Ktor Server]
        end

        subgraph "shared - Shared Logic"
            direction LR
            commonMain[commonMain - 核心业务逻辑]
            platformMain[Platform-specific - 平台实现]
        end
    end

    composeApp --> shared;
    server --> shared;

    style shared fill:#f9f,stroke:#333,stroke-width:2px
    style composeApp fill:#ccf,stroke:#333,stroke-width:2px
    style server fill:#cfc,stroke:#333,stroke-width:2px
```

**架构解读:**

* **`shared` 模块**: 项目的核心。包含了所有平台（Android, iOS, Web, Desktop, Server）共享的业务逻辑和数据处理代码。
  * `commonMain`: 存放纯 Kotlin 代码，与平台无关，例如数据模型、网络请求、业务逻辑等。
  * `androidMain`, `iosMain`, `jvmMain`, `jsMain`, `wasmJsMain` 等: 存放需要调用特定平台 API 的代码，通过 `expect/actual` 机制实现平台差异化。
* **`composeApp` 模块**: 负责构建用户界面 (UI)。它使用 Jetpack Compose for Multiplatform 技术，将 UI 代码在 Android, iOS, Desktop, Web 之间共享。
* **`server` 模块**: 一个独立的 Ktor 服务器应用，可以为客户端 App 提供 API 服务。它也依赖 `shared` 模块来复用业务逻辑。
* **`iosApp` 目录**: 存放 Xcode 项目，是 iOS 应用的入口和容器，负责加载 `composeApp` 模块编译出的 `ComposeApp.framework`。

### **2. 代码文件依赖关系**

模块间的依赖关系是理解项目结构的关键。

| 模块 (Module)                 | 依赖于 (Depends on) | 描述                                                                                                 |
| ----------------------------- | ------------------- | ---------------------------------------------------------------------------------------------------- |
| **`composeApp`**              | `shared`            | UI 层，依赖 `shared` 模块来获取数据和执行业务逻辑。                                                  |
| **`server`**                  | `shared`            | 后端服务，同样依赖 `shared` 模块来处理业务逻辑，确保前后端逻辑一致性。                               |
| **`shared`**                  | (无内部项目依赖)    | 核心逻辑模块，不依赖任何其他项目模块，保证其独立性和可移植性。                                       |
| **`iosApp (Xcode)`**          | `composeApp`        | iOS 应用的壳，通过 Xcode build phase 脚本编译并嵌入 `composeApp` 模块生成的 `ComposeApp.framework`。 |
| **Root (`build.gradle.kts`)** | -                   | 管理所有子模块的插件版本和应用，但不直接参与代码逻辑。                                               |

**依赖图:**

```mermaid
graph LR
    subgraph " "
        composeApp -- "获取数据和逻辑" --> shared;
        server -- "复用业务逻辑" --> shared;
        iosApp -- "嵌入UI框架" --> composeApp;
    end

```

### **3. 功能模块调用逻辑**

以一个典型的“问候”功能为例，展示其在不同模块间的调用流程。

**流程描述:**

1. **UI 触发 (composeApp)**: 用户在 `App.kt` 中点击按钮。
2. **调用共享逻辑**: `App.kt` 创建 `Greeting` 类的实例（该类位于 `shared/commonMain`）。
3. **平台判断 (shared)**: `Greeting` 类内部通过 `getPlatform()` 函数获取当前运行平台的信息。
4. **`expect/actual` 解析**:
   * `getPlatform()` 在 `shared/commonMain` 中被声明为 `expect fun`。
   * Kotlin 编译器会根据当前编译的目标平台，自动链接到对应的 `actual fun` 实现。例如，在 Android 上会链接到 `shared/androidMain` 中的 `Platform.android.kt`。
5. **返回平台信息**: 对应的 `actual` 实现返回平台特定的字符串 (如 "Android 33")。
6. **生成问候语**: `Greeting` 类将平台信息拼接成最终的问候语 "Hello, Android 33!"。
7. **UI 渲染**: `composeApp` 将问候语渲染到屏幕上。

**调用时序图:**

```mermaid
sequenceDiagram
    participant User
    participant App_kt as composeApp/App.kt
    participant Greeting_kt as shared/Greeting.kt
    participant Platform_kt as shared/.../Platform.kt

    User->>App_kt: 点击按钮
    activate App_kt
    App_kt->>Greeting_kt: new Greeting()
    activate Greeting_kt
    Greeting_kt->>Platform_kt: getPlatform()
    activate Platform_kt
    Note right of Platform_kt: expect/actual机制<br/>自动匹配平台实现
    Platform_kt-->>Greeting_kt: 返回平台名称 (e.g., "Android 33")
    deactivate Platform_kt
    Greeting_kt->>App_kt: 返回问候语 ("Hello, ...")
    deactivate Greeting_kt
    App_kt-->>User: 显示问候语
    deactivate App_kt
```

### **4. 关键代码文件索引**

以下是项目中最重要的文件及其功能描述，便于 AI 快速定位和理解代码。

| 文件路径                                                          | 模块         | 功能描述                                                                                                                          |
| ----------------------------------------------------------------- | ------------ | --------------------------------------------------------------------------------------------------------------------------------- |
| `settings.gradle.kts`                                             | Root         | **项目模块定义**：声明项目中包含 `composeApp`, `server`, `shared` 三个核心模块。                                                  |
| `gradle/libs.versions.toml`                                       | Root         | **依赖库版本管理**：集中管理所有第三方库和插件的版本，实现统一控制。                                                              |
| `shared/src/commonMain/kotlin/cn/edu/ubaa/Platform.kt`            | `shared`     | **平台差异化接口 (expect)**：定义了获取平台信息的 `expect` 接口，由各平台模块实现。                                               |
| `shared/src/androidMain/kotlin/cn/edu/ubaa/Platform.android.kt`   | `shared`     | **平台差异化实现 (actual)**：提供了 `getPlatform()` 在 Android 平台的具体实现。                                                   |
| `shared/src/iosMain/kotlin/cn/edu/ubaa/Platform.ios.kt`           | `shared`     | **iOS 平台实现 (actual)**：提供了 `getPlatform()` 在 iOS 平台的具体实现。                                                         |
| `shared/src/jvmMain/kotlin/cn/edu/ubaa/Platform.jvm.kt`           | `shared`     | **JVM 平台实现 (actual)**：提供了 `getPlatform()` 在 JVM/Desktop 平台的具体实现。                                                 |
| `shared/src/commonMain/kotlin/cn/edu/ubaa/Greeting.kt`            | `shared`     | **核心业务逻辑**：实现了与平台无关的问候功能，是共享逻辑的核心。                                                                  |
| `shared/src/commonMain/kotlin/cn/edu/ubaa/Constants.kt`           | `shared`     | **共享常量定义**：定义了跨平台共享的常量，如服务器端口等配置信息。                                                                |
| `shared/src/commonMain/kotlin/cn/edu/ubaa/model/dto/UserInfo.kt`  | `shared`     | **用户数据模型**：定义了用户信息的 DTO，用于前后端数据传输。                                                                      |
| `composeApp/src/commonMain/kotlin/cn/edu/ubaa/App.kt`             | `composeApp` | **共享 UI 入口**：定义了所有客户端（Android, iOS, Desktop, Web）共享的 Compose UI 界面。                                          |
| `composeApp/build.gradle.kts`                                     | `composeApp` | **多平台编译配置**：配置了 Kotlin Multiplatform 插件，定义了所有需要编译的目标平台。                                              |
| `composeApp/src/androidMain/kotlin/cn/edu/ubaa/MainActivity.kt`   | `composeApp` | **Android 应用入口**：Android App 的 `Activity`，负责加载 `App()` 这个共享 Composable。                                           |
| `composeApp/src/iosMain/kotlin/cn/edu/ubaa/MainViewController.kt` | `composeApp` | **iOS UI 控制器**：为 iOS 平台提供 Compose UI 的 ViewController 包装器。                                                          |
| `composeApp/src/jvmMain/kotlin/cn.edu.ubaa/main.kt`               | `composeApp` | **Desktop 应用入口**：JVM/Desktop 平台的应用程序入口点。                                                                          |
| `iosApp/iosApp/ContentView.swift`                                 | `iosApp`     | **iOS UI 桥接**：通过 `UIViewControllerRepresentable` 将 Kotlin Multiplatform 生成的 `MainViewController` 嵌入到 SwiftUI 视图中。 |
| `server/src/main/kotlin/cn/edu/ubaa/Application.kt`               | `server`     | **服务器应用入口**：配置并启动 Ktor 服务器，定义 API 路由，并调用 `shared` 模块的逻辑，使用 `Constants.kt` 中定义的端口配置。     |

### **5. 常用设计模式与约定**

* **架构模式**:
  * **分层架构 (Layered Architecture)**: 明确划分 UI (`composeApp`)、业务逻辑 (`shared`) 和后端 (`server`)，实现了高内聚、低耦合。
  * **MVVM (Model-View-ViewModel)**: 虽然在当前简单示例中不明显，但 Compose 的设计鼓励使用 ViewModel 来管理 UI 状态和业务逻辑，`shared` 模块可以作为 ViewModel 的数据来源。

* **编码规范与约定**:
  * **`expect/actual` 机制**: 这是 Kotlin Multiplatform 的核心模式，用于处理平台特定 API 的调用。在 `commonMain` 中声明 `expect`，在平台特定的 sourceSet (如 `androidMain`, `iosMain`) 中提供 `actual` 实现。
  * **依赖注入 (Dependency Injection)**: 项目通过 Gradle 的模块依赖来管理耦合关系，这是一种广义上的依赖注入。在更复杂的场景中，可以引入 Koin 或 Hilt/Dagger 等 DI 框架。
  * **统一命名空间**: 项目使用 `cn.edu.ubaa` 作为统一的包名，便于代码管理和识别。
  * **版本目录 (Version Catalog)**: 使用 `gradle/libs.versions.toml` 文件来管理所有依赖项，这是 Gradle 推荐的最佳实践，可以避免版本冲突和方便升级。

### **6. API 设计 & 接口规则**

为了确保一致性、可扩展性和易用性，由 `server` 模块暴露的所有 API 都必须遵守以下规则。这些规则适用于 `composeApp` 客户端和 `server` 之间的通信。

#### **a. URL 结构与版本控制**

*   **基本路径**: 所有 API 端点都必须以 `/api` 作为前缀。
*   **版本控制**: 所有 API 都必须进行版本控制。版本号应包含在 URL 路径中，紧跟在基本路径之后（例如 `/api/v1`）。这使得未来的 API 演进不会破坏现有的客户端。
*   **资源命名**: URL 应面向资源。

**示例:**
```
POST /api/v1/auth/login
GET /api/v1/auth/status
GET /api/v1/user/info
```

#### **b. HTTP 方法**

使用标准的 HTTP 方法来表示对资源的操作：

*   `GET`: 检索资源或资源集合。（安全且幂等）
*   `POST`: 创建一个新资源。（不安全或非幂等）
*   `PUT`: 完全更新一个现有资源。（幂等）
*   `PATCH`: 部分更新一个现有资源。（不安全或非幂等）
*   `DELETE`: 删除一个资源。（幂等）

#### **c. 请求和响应格式**

*   **Content-Type**: 所有请求和响应体都必须是 JSON 格式。对于有请求体的请求和所有响应，`Content-Type` 头必须设置为 `application/json`。
*   **命名约定**: 为了与 Kotlin 和 JavaScript 的约定保持一致，所有 JSON 属性键都使用 `camelCase`。
*   **数据模型**: API 响应中使用的数据模型都应是在 `shared` 模块中定义的模型，以确保整个应用栈的一致性。避免将服务器内部或学校特定的 API 数据结构直接暴露给客户端。

#### **d. 认证**

*   **登录端点**: 登录端点 `POST /api/v1/auth/login` 是唯一接受用户名和密码的公共端点。
*   **JWT 令牌**: 成功登录后，服务器将生成一个安全的 JWT（JSON Web Token）令牌并在响应中返回，格式为：
    ```json
    {
      "user": {
        "name": "用户姓名",
        "schoolid": "学号",
        "username": "用户名"
      },
      "token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9..."
    }
    ```
*   **认证请求**: 对于所有后续对受保护端点的请求，客户端必须在 `Authorization` HTTP 头中使用 `Bearer` 方案包含 JWT 令牌。
*   **令牌验证**: 客户端可通过 `GET /api/v1/auth/status` 端点验证令牌有效性并获取会话状态。

**示例:**
```
Authorization: Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9...
```

**JWT 令牌特性:**
- 令牌有效期与会话 TTL 一致（默认 30 分钟）
- 包含用户身份信息和签发时间
- 支持自动续期机制（活跃会话延长有效期）
- 使用 HMAC256 算法签名确保安全性

#### **e. 标准化响应与错误处理**

为了给客户端提供一致的体验，所有 API 响应都应遵循通用的结构。

**成功响应 (`200 OK`, `201 Created`):**

响应体应直接包含请求的数据（对于单个资源）或数据数组（对于集合）。

```json
// GET /api/v1/user/info
{
  "idCardType": "身份证",
  "idCardTypeName": "居民身份证",
  "phone": "13800138000",
  "schoolid": "20201234",
  "name": "张三",
  "idCardNumber": "11010119900307XXXX",
  "email": "zhangsan@example.com",
  "username": "zhangsan"
}
```

**错误响应 (`4xx`, `5xx`):**

所有错误响应必须返回一个具有一致结构的 JSON 对象，其中包含一个机器可读的 `errorCode` 和一个人类可读的 `message`。

```json
{
  "error": {
    "code": "invalid_credentials",
    "message": "学号或密码错误。"
  }
}
```

常见的 `errorCode` 值:
*   `unauthenticated`: 会话令牌缺失或无效。
*   `invalid_request`: 请求体或参数格式错误。
*   `not_found`: 请求的资源不存在。
*   `permission_denied`: 用户无权执行此操作。
*   `internal_server_error`: 服务器上发生意外问题的通用错误。

### **7. 服务端 SessionManager 指南**

`SessionManager` 位于 `server` 模块，负责为每位登录用户维护独立的 BUAA SSO 会话。其设计要点如下：

* **目标**
  * 每个用户拥有独立的 `HttpClient` 与 cookie 存储，避免不同用户之间的状态串扰。
  * 默认 30 分钟的 TTL 失效机制，失效后自动踢出缓存，防止长期占用资源。
  * 通过 `GlobalSessionManager.instance` 提供单例访问，方便在路由或业务服务中复用。

* **核心类型**
  * `SessionManager.SessionCandidate`：登录前准备阶段生成的临时客户端。
  * `SessionManager.UserSession`：缓存的会话实体，包含用户资料、`HttpClient`、cookie 存储和认证时间。
  * `GlobalSessionManager`：全局懒加载单例，保证服务器端仅维护一份会话表。

* **使用流程**
  1. 通过 `sessionManager.getSession(username)` 复用缓存会话；该调用会自动触发 `markActive()`，将最近活动时间滑动到当前，避免活跃连接被误清理，必要时可调用 `verifySession` 再次校验状态。
  2. 当缓存不可用时执行 `prepareSession(username)`，使用返回的 `client` 完成登录步骤。
  3. 登录成功后调用 `commitSession(candidate, userData)` 写入缓存，旧会话会被自动关闭。
  4. 如需主动登出或密码变更，调用 `invalidateSession(username)`；可定期调用 `cleanupExpiredSessions()` 清除过期记录。

* **最佳实践**
  * 登录失败或异常退出时务必关闭 `SessionCandidate.client`，避免连接泄露。
  * 对复用的会话再次访问受保护接口前，应在业务逻辑中处理 401/302，必要时触发重新登录。
  * 如果未来需要跨平台共享，会话接口可在 `shared` 模块定义 expect/actual 形式的抽象，由各平台提供实现。
  * 若需要定期清理长时间未使用的会话，可结合 `cleanupExpiredSessions()` 与调度任务统一执行，保持缓存轻量。

### **8. JWT 认证与会话管理**

项目现已集成 JWT（JSON Web Token）认证机制，每个 JWT 令牌对应一个用户会话，提供更安全的无状态认证方案。

* **JWT 组件架构**
  * `JwtUtil`：JWT 令牌生成、验证和解析工具类，使用 HMAC256 签名算法
  * `SessionManager.SessionWithToken`：包含会话与 JWT 令牌的数据结构
  * `JwtAuth`：JWT 认证中间件和工具函数集合
  * `AuthService.loginWithToken()`：支持 JWT 的登录方法
  * JWT 令牌到用户名的映射表，支持快速会话检索

* **JWT 令牌特性**
  * 使用 HMAC256 算法签名，密钥可通过环境变量 `JWT_SECRET` 配置
  * 令牌过期时间与会话 TTL 保持一致（默认 30 分钟）
  * 包含用户名、签发时间、过期时间等标准声明
  * 支持令牌有效性验证和过期检测

* **认证流程**
  1. **登录**: 调用 `POST /api/v1/auth/login`，成功后返回 `LoginResponse` 包含用户信息和 JWT 令牌
  2. **验证码处理**: 如果需要验证码，服务器返回 422 状态码和 `CaptchaRequiredResponse`，包含验证码图片信息
  3. **验证码输入**: 客户端显示验证码图片，用户输入验证码后重新提交登录请求
  4. **令牌使用**: 客户端在后续请求中携带 `Authorization: Bearer <jwt-token>` 头
  5. **会话验证**: 调用 `GET /api/v1/auth/status` 验证令牌有效性并获取会话状态
  6. **自动续期**: 活跃会话在访问时自动更新最后活动时间，延长有效期

* **开发使用指南**
  * 使用 `sessionManager.getSessionByToken(jwt)` 通过令牌获取会话
  * 使用 `sessionManager.requireSessionByToken(jwt)` 强制获取会话（失败时抛异常）
  * 受保护路由可使用 `authenticatedRoute { }` 包装，自动验证 JWT
  * 通过 `call.getUserSession()` 在路由中获取当前用户会话
  * 调用 `sessionManager.invalidateSessionByToken(jwt)` 使特定令牌失效

* **安全考虑**
  * JWT 密钥应在生产环境中设置为强随机字符串
  * 令牌在传输过程中应使用 HTTPS 保护
  * 客户端应安全存储令牌（移动端使用 Keychain/Keystore，Web 使用 HttpOnly Cookie）
  * 支持令牌撤销机制，通过 `invalidateSessionByToken` 主动失效令牌
  * 定期清理过期令牌和会话，防止内存泄漏

### **9. CAPTCHA 验证码支持**

项目支持 BUAA SSO 的验证码验证机制，当登录需要验证码时，系统会自动检测并提供相应的用户交互流程。

* **CAPTCHA 检测机制**
  * `AuthService.detectCaptcha()` 方法解析 SSO 登录页面 HTML
  * 使用正则表达式提取 JavaScript 配置：`config.captcha = { type: 'image', id: '...' }`
  * 自动构建验证码图片 URL：`https://sso.buaa.edu.cn/captcha?captchaId=<id>`

* **后端 CAPTCHA 处理**
  * 登录时检测验证码需求，若需要验证码且未提供，抛出 `CaptchaRequiredException`
  * API 返回 422 状态码和 `CaptchaRequiredResponse`，包含验证码信息
  * 提供 `/api/v1/auth/captcha/{captchaId}` 端点获取验证码图片
  * 登录请求支持可选的 `captcha` 字段

* **前端 CAPTCHA 流程**
  * `AuthViewModel` 管理验证码状态和对话框显示
  * `CaptchaDialog` 组件展示验证码图片和输入框
  * `AuthService` 处理 422 状态码，触发验证码输入流程
  * 用户输入验证码后自动重新提交登录请求

### **10. 博雅课程 (BYKC) 模块**

完整实现 BYKC（博雅课程）系统集成，支持课程查询、选课、退选、签到等功能。

#### **a. 架构设计**

```
server/src/main/kotlin/cn/edu/ubaa/bykc/
├── BykcCrypto.kt      # RSA+AES 加密工具
├── BykcClient.kt      # BYKC API 客户端
├── BykcService.kt     # 业务逻辑层
├── BykcRoutes.kt      # REST API 路由
├── BykcModels.kt      # 服务端数据模型
└── BykcExceptions.kt  # 自定义异常

shared/src/commonMain/kotlin/cn/edu/ubaa/model/dto/
└── Bykc.kt            # 共享 DTO 定义
```

#### **b. 加密机制 (`BykcCrypto.kt`)**

BYKC 系统使用 RSA+AES 混合加密：

* **RSA 公钥**: 1024-bit，用于加密 AES 密钥和签名
* **AES 加密**: AES-128-ECB 模式，PKCS5Padding
* **签名算法**: SHA1 摘要

**加密流程:**
1. 生成随机 16 字节 AES 密钥
2. 使用 RSA 公钥加密 AES 密钥 → `ak`
3. 对请求数据计算 SHA1 签名，RSA 加密 → `sk`
4. 使用 AES 加密请求体 → `encryptedData`
5. 生成时间戳 → `ts`

#### **c. API 端点**

| 方法     | 路径                               | 描述             |
| -------- | ---------------------------------- | ---------------- |
| `GET`    | `/api/v1/bykc/profile`             | 获取博雅用户信息 |
| `GET`    | `/api/v1/bykc/courses`             | 获取课程列表     |
| `GET`    | `/api/v1/bykc/courses/{id}`        | 获取课程详情     |
| `GET`    | `/api/v1/bykc/courses/chosen`      | 获取已选课程     |
| `POST`   | `/api/v1/bykc/courses/{id}/select` | 选课             |
| `DELETE` | `/api/v1/bykc/courses/{id}/select` | 退选             |
| `POST`   | `/api/v1/bykc/courses/{id}/sign`   | 签到/签退        |

**课程列表查询参数 (`GET /courses`):**
* `page`: 页码 (默认 1)
* `size`: 每页数量 (默认 200, 最大 500)
* `all`: 是否包含已过期课程 (默认 false)

**签到请求体 (`POST /courses/{id}/sign`):**
```json
{
  "courseId": 12345,
  "lat": 39.9876,
  "lng": 116.1234,
  "signType": 1
}
```
* `signType`: 1=签到, 2=签退

#### **d. 课程状态计算**

`BykcService.calculateCourseStatus()` 根据时间和选课情况计算状态：

| 状态   | 条件                 |
| ------ | -------------------- |
| `过期` | 课程已开始           |
| `已选` | 用户已选择该课程     |
| `预告` | 选课尚未开始         |
| `结束` | 选课已结束           |
| `满员` | 当前人数 >= 最大人数 |
| `可选` | 其他情况             |

#### **e. 共享 DTO (`shared/model/dto/Bykc.kt`)**

| DTO                   | 描述                   |
| --------------------- | ---------------------- |
| `BykcCourseDto`       | 课程列表项             |
| `BykcCourseDetailDto` | 课程详情               |
| `BykcChosenCourseDto` | 已选课程（含签到状态） |
| `BykcUserProfileDto`  | 用户信息               |
| `BykcSignRequest`     | 签到请求               |
| `BykcSignConfigDto`   | 签到配置               |
| `BykcCoursesResponse` | 课程列表响应           |

#### **f. 错误处理**

| 异常类                             | 描述          |
| ---------------------------------- | ------------- |
| `BykcException`                    | 基础异常      |
| `BykcLoginException`               | 登录失败      |
| `BykcSelectException`              | 选课/退选失败 |
| `BykcAlreadySelectedException`     | 重复选课      |
| `BykcCourseFullException`          | 课程已满      |
| `BykcCourseNotSelectableException` | 课程不可选    |

#### **g. 使用示例**

```kotlin
// 在路由中使用
authenticatedRoute {
    get("/courses") {
        val username = call.jwtUsername ?: return@get unauthorized()
        val courses = bykcService.getCourses(username, page = 1, pageSize = 200)
        call.respond(HttpStatusCode.OK, BykcCoursesResponse(courses, courses.size))
    }
}
```

### **11. 新增 UI 组件架构**

本次更新新增了完整的多层次UI架构，实现了现代化的移动应用界面设计。

#### **a. 组件层级结构**

```mermaid
graph TD
    A[App.kt - 根组件] --> B{认证状态判断}
    B -->|已登录| C[MainAppScreen - 主应用容器]
    B -->|未登录| D[LoginScreen - 登录界面]
    
    C --> E[Sidebar - 悬浮侧边栏]
    C --> F[主内容区域]
    C --> G[BottomNavigation - 底部导航]
    
    F --> H[HomeScreen - 主页]
    F --> I[RegularFeaturesScreen - 普通功能]
    F --> J[AdvancedFeaturesScreen - 高级功能]
    F --> K[ScheduleScreen - 课表页面]
    F --> L[CourseDetailScreen - 课程详情]
    F --> M[MyScreen - 我的页面]
    F --> N[AboutScreen - 关于页面]
```

#### **b. UI 组件功能详解**

**主应用容器 (`MainAppScreen.kt`)**
* 统一管理应用内导航状态
* 响应式布局：根据屏幕类型显示相应导航元素
* 集成侧边栏切换、底部导航和页面导航逻辑
* 状态管理：维护当前屏幕、选中标签页等状态
* **悬浮式侧边栏**：使用Box布局实现overlay效果，避免内容挤压

**侧边栏组件 (`Sidebar.kt`)**
* 用户信息展示：头像、姓名、学号
* 功能菜单："我的"、"关于"页面入口
* 登出按钮：支持 SSO 端点调用
* **悬浮式设计**：使用Card包装，添加阴影效果，悬浮在主内容之上
* 半透明背景：点击背景可关闭侧边栏

**底部导航栏 (`BottomNavigation.kt`)**
* 三个主要标签：主页、普通功能、高级功能
* Material Design 3 风格设计
* 状态指示：高亮当前选中标签

**主页组件 (`HomeScreen.kt`)**
* 今日课表展示：支持空状态、加载状态、错误状态
* 课程卡片：显示课程名称、时间、地点信息
* 下拉刷新功能
* 日期显示：自动获取当前日期

**课表功能页面 (`ScheduleScreen.kt`)**
* 学期选择器：下拉菜单形式，支持多学期切换
* **改进的周次选择器**：
  - 左右箭头按钮：支持快速切换上下周
  - 下拉菜单选择：支持快速跳转到具体周次
  - 当前周标识：在下拉菜单中高亮显示当前周
  - 状态控制：防止越界操作，自动禁用不可用的箭头按钮
* 课表网格视图：7列（周一到周日）× 12行（节次）
* 课程点击：跳转到详情页面
* 颜色编码：根据课程设置显示不同背景色

**课程详情页面 (`CourseDetailScreen.kt`)**
* 详细信息展示：课程代码、名称、学分、时间、地点
* 卡片式布局：信息分组显示
* 返回导航：支持从课表页面返回

**"我的"和"关于"页面 (`MyScreen`, `AboutScreen`)**
* **独立屏幕设计**：拥有独立的TopAppBar和返回按钮
* **智能返回逻辑**：返回时自动显示侧边栏，保持用户操作连贯性
* 页面内容：卡片式布局展示相关信息

#### **c. 数据管理架构**

**ScheduleViewModel (`ScheduleViewModel.kt`)**
* 课表数据状态管理：学期列表、周列表、课表数据
* API 调用封装：自动处理加载状态和错误状态
* 响应式数据流：使用 StateFlow 提供数据订阅

**ScheduleService (`ApiService.kt` 扩展)**
* 新增课表相关 API 服务方法：
  * `getTerms()` - 获取学期列表
  * `getWeeks(termCode)` - 获取指定学期的周列表
  * `getWeeklySchedule(termCode, week)` - 获取周课表
  * `getTodaySchedule()` - 获取今日课表

**登出功能增强**
* SSO 登出支持：调用 `https://sso.buaa.edu.cn/logout`
* 双重登出机制：同时调用应用服务器和 SSO 端点
* 容错处理：即使 SSO 登出失败也清理本地状态

#### **d. 导航系统设计**

**多层级导航**
* 底部导航：主要功能区域切换
* **悬浮侧边栏导航**：用户功能和设置入口，overlay显示避免内容挤压
* 页面内导航：详情页面和返回导航

**导航状态管理**
* 枚举定义：`AppScreen` 和 `BottomNavTab`
* 状态同步：导航状态与 UI 状态保持一致
* **智能路由逻辑**：`navigateTo()` 和 `navigateBack()` 函数统一管理导航跳转
  - MY和ABOUT页面导航时保持侧边栏状态
  - 返回时智能恢复到合适的页面和侧边栏状态

**响应式导航**
* 条件显示：根据当前页面决定导航元素的显示
* 状态保持：页面切换时保持用户操作状态
* **多级返回处理**：支持复杂的页面返回路径和状态恢复

#### **e. 交互体验优化**

**侧边栏交互**
* 悬浮式设计：点击外部区域关闭侧边栏
* 阴影效果：使用Card组件提供Material Design阴影
* 动画过渡：平滑的显示/隐藏过渡效果

**周次选择器优化**
* **双重选择方式**：
  - 箭头按钮：适合连续浏览相邻周次
  - 下拉菜单：适合跳转到特定周次
* **智能状态控制**：
  - 自动禁用超出范围的箭头按钮
  - 当前周在下拉菜单中特殊标识
* **用户友好性**：减少横向滚动，提升单手操作体验

**返回逻辑优化**
* **上下文感知返回**：根据当前页面类型选择合适的返回目标
* **状态保持**：从"我的"和"关于"页面返回时显示侧边栏
* **导航一致性**：统一的返回按钮样式和行为

#### **f. 开发最佳实践**

**组件化设计**
* 单一职责：每个组件专注特定功能
* 可复用性：组件支持参数化配置
* 状态提升：状态管理在合适的层级进行
* **悬浮式UI**：使用Box + overlay模式实现悬浮效果

**数据流管理**
* 单向数据流：从 ViewModel 到 UI 组件
* 响应式更新：使用 StateFlow 自动更新 UI
* 错误处理：统一的错误状态处理机制

**用户体验优化**
* **Material Design 3**：严格遵循MD3设计规范
* **多种交互方式**：为复杂操作提供多种交互选择（如周次选择的箭头+下拉组合）
* **智能导航**：基于用户操作上下文的智能页面跳转
* **状态保持**：关键操作状态在页面切换时保持

**多平台兼容**
* 共享 UI 代码：所有 UI 组件在 commonMain 中定义
* 平台适配：颜色解析等平台特定功能的处理
* 依赖管理：正确配置 kotlinx-datetime 等依赖
* **响应式布局**：适配不同屏幕尺寸和设备类型

### **10. API 服务扩展**

#### **a. 课表相关接口**

基于现有 API 文档，新增了完整的课表功能支持：

**学期管理**
```kotlin
suspend fun getTerms(): Result<List<Term>>
```
- 调用 `GET /api/v1/schedule/terms`
- 返回可用学期列表，包含选中状态

**周次管理**
```kotlin
suspend fun getWeeks(termCode: String): Result<List<Week>>
```
- 调用 `GET /api/v1/schedule/weeks?termCode={termCode}`
- 返回指定学期的周列表，标识当前周

**课表数据**
```kotlin
suspend fun getWeeklySchedule(termCode: String, week: Int): Result<WeeklySchedule>
suspend fun getTodaySchedule(): Result<List<TodayClass>>
```
- 支持周课表和今日课表查询
- 处理课程时间、地点、教师等详细信息

#### **b. 登出功能增强**

```kotlin
suspend fun logout(): Result<Unit> {
    // 1. 调用应用服务器登出接口
    val serverResponse = apiClient.getClient().post("api/v1/auth/logout")
    
    // 2. 调用 SSO 登出接口
    try {
        val ssoResponse = apiClient.getClient().get("https://sso.buaa.edu.cn/logout")
    } catch (ssoException: Exception) {
        // SSO 登出失败处理
    }
    
    // 3. 清理本地状态
    apiClient.close()
}
```

### **11. 构建和部署指导**

#### **a. 依赖更新**

项目新增依赖项：
- `kotlinx-datetime`: 用于日期时间处理
- 版本配置在 `gradle/libs.versions.toml` 中统一管理

#### **b. 模块结构**

```
composeApp/src/commonMain/kotlin/cn/edu/ubaa/
├── App.kt                    # 应用根组件
├── ui/
│   ├── MainAppScreen.kt      # 主应用容器
│   ├── ScheduleViewModel.kt  # 课表数据管理
│   ├── components/           # 可复用组件
│   │   ├── Sidebar.kt        # 侧边栏
│   │   └── BottomNavigation.kt # 底部导航
│   └── screens/              # 页面组件
│       ├── HomeScreen.kt     # 主页
│       ├── ScheduleScreen.kt # 课表页面
│       ├── CourseDetailScreen.kt # 课程详情
│       ├── RegularFeaturesScreen.kt # 普通功能
│       └── OtherScreens.kt   # 其他页面
```

#### **c. 多平台构建**

项目支持以下平台：
- Android (minSdk 24)
- iOS (iOS 12+)
- Desktop (JVM)
- Web (JS/Wasm)

构建命令示例：
```bash
./gradlew :composeApp:assembleDebug          # Android APK
./gradlew :composeApp:createDistributable    # Desktop 应用
./gradlew :composeApp:jsBrowserDistribution  # Web 应用
```