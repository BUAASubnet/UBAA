# UBAA 登录界面实现

## 概述

本实现为 UBAA 多平台项目提供了一个简单的登录界面，并支持用户信息展示。该方案遵循模块化架构，支持所有目标平台（Android、iOS、桌面、Web）。

## 架构

### 共享模块（shared）
- **API 层**：带有平台特定实现的 HTTP 客户端
  - `ApiClient.kt`：多平台 HTTP 客户端配置
  - `ApiService.kt`：用于 API 调用的 AuthService 和 UserService
  - 平台实现：Android（OkHttp）、iOS（Darwin）、JVM（CIO）、JS/WASM（JS）

### ComposeApp 模块（composeApp）
- **UI 层**：Compose 多平台 UI 组件
  - `AuthViewModel.kt`：认证流程的状态管理
  - `LoginScreen.kt`：包含用户名/密码输入的登录表单
  - `UserInfoScreen.kt`：用户信息展示与注销
  - `App.kt`：带有登录/用户信息导航的主应用

## 功能

### 登录界面
- 用户名/密码输入框
- 表单校验（字段不能为空）
- 加载状态与进度指示器
- 错误信息展示与自动清除
- 针对不同屏幕尺寸的响应式设计

###用户信息界面
- 基本用户信息（姓名、学号）
- 来自 API 的详细信息（邮箱、电话、身份证号）
- 敏感数据（身份证号）脱敏显示
- 注销按钮，清除会话
- 简洁卡片式布局

### API 集成
- 基于 JWT 的身份认证
- HTTP 客户端自动管理 Token
- 友好的错误处理
- 支持会话状态检查

## 使用方法

### 运行应用

1. **Android**：使用 Android 运行配置或构建 APK
2. **桌面**：通过 `./gradlew :composeApp:run` 运行 JVM 目标
3. **Web**：构建并部署 JS/WASM 目标
4. **iOS**：通过 Xcode 构建生成的框架

### 服务器要求

应用需连接运行中的 UBAA 服务器，需支持以下接口：
- `POST /api/v1/auth/login` —— 用户名/密码登录
- `GET /api/v1/user/info` —— 获取用户信息（需 Bearer Token）

服务器端口配置见 `Constants.kt`：`SERVER_PORT = 8081`

### 登录流程

1. 用户输入用户名（学号）和密码
2. 应用调用登录 API，获取 JWT Token
3. Token 自动存储于 HTTP 客户端，用于后续请求
4. 获取并展示用户信息
5. 注销时清除 Token，返回登录界面

## 测试

本实现包含以下单元测试：
- AuthViewModel 状态管理
- API 数据模型序列化/反序列化
- UI 状态处理

运行测试命令：`./gradlew test`

## 平台兼容性

本实现支持多平台：

- **Android**：采用 Material Design 3，正确处理生命周期
- **iOS**：原生风格，使用 iOS 专用 HTTP 客户端
- **桌面**：窗口应用，适配尺寸
- **Web**：兼容浏览器，支持 JS/WASM 目标

## 安全性考虑

- 登录成功后密码会从内存中清除
- JWT Token 由 HTTP 客户端安全管理
- UI 中敏感数据（身份证号）脱敏显示
- 注销时清理会话，防止 Token 泄漏

## 错误处理

- 网络错误会被捕获并展示给用户
- 无效凭证会显示相应错误信息
- 加载状态防止多次并发请求
- 自动清除错误信息提升用户体验