
# UBAA（智慧北航remake）

**UBAA** 是一款现代化、跨平台的应用，旨在简化北京航空航天大学（BUAA）学生的学业生活。基于 **Kotlin Multiplatform** 和 **Compose Multiplatform** 构建，支持 Android、iOS 和桌面端，提供统一且美观的界面访问多种校内服务。

本系统作为校内各系统的智能桥梁，复杂的认证与数据解析均在专用后端完成，为用户带来简洁流畅的体验。


## 🏗 项目架构

本项目采用标准的 Kotlin Multiplatform 结构：

*   **`composeApp`（前端）**：基于 Compose Multiplatform 的客户端应用，支持：
    *   **Android**
    *   **iOS**
    *   **桌面端**（JVM）
    *   **Web**（Wasm/JS）
*   **`server`（后端）**：基于 **Ktor** 的服务端应用，作为 API 网关，负责：
    *   **认证**：对接学校 CAS（统一认证服务）
    *   **数据聚合**：抓取并解析各类校内遗留系统（如博雅、教务等）数据
    *   **会话管理**：安全管理用户会话
*   **`shared`**：客户端与服务端共享的通用代码，包括：
    *   数据模型（DTO）
    *   API 接口
    *   共享业务逻辑


## ✨ 功能特性 (Features)

* **多端支持**：
    * 📱 **Android / iOS**：原生体验的移动端应用。
    * 🖥️ **Desktop (JVM)**：Windows/macOS/Linux 桌面客户端。
    * 🌐 **Web**：基于 Wasm/JS 的网页端应用。
* **教务服务**：
    * 🔐 **统一认证 (Signin/Auth)**：集成学校统一身份认证 (CAS/Login)。
    * 📅 **课程表 (Schedule)**：学期课表查询与展示。
    * 📝 **考试查询 (Exam)**：考试时间与安排查询。
    * 🏛️ **空教室查询 (Classroom)**：查询特定时间段的空闲教室。
    * 🎓 **博雅课程 (BYKC)**：博雅选课、管理和远程自主签到。
    * ✅ **签到功能 (Signin)**：课程考勤与签到支持。
* **用户体验**：
    * 🌙 **暗黑模式支持**：系统主题自动适配。
    * 🔔 **通知提醒**：重要事项及时通知
    *   **自动更新检查**：内置版本检查与更新提醒
    *   **更多功能**：持续迭代中，敬请期待！


## 🛠 技术栈

*   **语言**：[Kotlin](https://kotlinlang.org/)
*   **UI 框架**：[Compose Multiplatform](https://www.jetbrains.com/lp/compose-multiplatform/)
*   **后端框架**：[Ktor](https://ktor.io/)
*   **构建系统**：[Gradle（Kotlin DSL）](https://gradle.org/)
*   **网络**：Ktor Client
*   **设计体系**：Material Design 3


## 🚀 快速开始

### 前置条件
*   JDK 17 或更高版本
*   Android Studio（用于 Android 开发）/ IntelliJ IDEA（通用/后端开发）
*   Xcode（iOS 开发，仅限 macOS）

### 启动后端服务
客户端依赖后端提供数据，建议先启动服务端：

```bash
./gradlew :server:run
```
*注意：服务端默认端口为 5432，可在 `.env` 文件中配置。*

### 启动客户端

**Android：**
```bash
./gradlew :composeApp:installDebug
```

**桌面端：**
```bash
./gradlew :composeApp:run
```

**Web 应用 (Wasm)：**
```bash
./gradlew :composeApp:wasmJsBrowserDevelopmentRun
```

**iOS：**
用 Xcode 打开 `iosApp/iosApp.xcworkspace` 并运行。

## 📂 目录结构

```text
├── composeApp/          # 共享 UI 代码 (Compose Multiplatform)
│   ├── src/androidMain  # Android 特定实现
│   ├── src/commonMain   # 跨平台通用 UI 逻辑 (页面、组件、ViewModel)
│   │   ├── cn/edu/ubaa/ui/screens/  # 各功能页面 (bykc, schedule, exam, etc.)
│   │   └── cn/edu/ubaa/ui/common/   # 通用组件
│   ├── src/iosMain      # iOS 特定实现
│   ├── src/jvmMain      # Desktop 特定实现
│   └── src/webMain      # Web 特定实现
│
├── server/              # 后端服务应用 (Ktor)
│   ├── src/main/kotlin/cn/edu/ubaa/
│   │   ├── auth/        # 认证逻辑
│   │   ├── bykc/        # 博雅逻辑
│   │   ├── classroom/   # 教室逻辑
│   │   └── utils/       # 工具类 (VpnCipher, JwtUtil)
│
├── shared/              # 共享业务逻辑 (KMP)
│   ├── src/commonMain
│   │   ├── api/         # 网络 API 定义
│   │   └── model/       # 数据模型 (DTOs)
│
└── iosApp/              # iOS 原生工程入口 (Xcode Project)