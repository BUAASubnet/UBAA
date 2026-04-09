# UBAA (智慧北航 Remake)

![Kotlin](https://img.shields.io/badge/Kotlin-2.3.20-blue.svg?style=flat&logo=kotlin)
![Compose Multiplatform](https://img.shields.io/badge/Compose_Multiplatform-1.10.3-blueviolet.svg?style=flat&logo=jetpack-compose)
![Ktor](https://img.shields.io/badge/Ktor-3.4.1-orange.svg?style=flat&logo=ktor)
![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Desktop%20%7C%20Web-lightgrey.svg?style=flat)

**UBAA** 是一款基于 **Kotlin Multiplatform** 和 **Compose Multiplatform** 构建的现代化跨平台应用，专为北京航空航天大学（BUAA）学生打造。

### [立刻下载](https://github.com/BUAASubnet/UBAA/releases)
### [网页版](https://app.buaa.team)

它不仅仅是一个客户端，更是一个智能的**服务聚合网关**。通过专用的 Ktor 后端，它将复杂的校内系统（如 CAS 认证、教务系统、博雅系统）的数据进行标准化清洗与聚合，为 Android、iOS、Desktop 和 Web 端用户提供统一、流畅且美观的 Material Design 3 体验。

---

## 📦 安装 (Installation)

### Arch Linux (AUR)

如果你使用的是 Arch Linux，可以直接通过 AUR 安装客户端：

```bash
yay -S ubaa
```

---

## ✨ 核心特性 (Features)

### 🖥️ 多端覆盖
*   **📱 Android / iOS**: 原生级性能的移动体验。
*   **💻 Desktop**: 支持 Windows, macOS, Linux 的桌面客户端。
*   **🌐 Web**: 基于 Wasm/JS 的现代网页应用，无需安装即可使用。

### 🎓 智慧教务
*   **🔐 统一认证**: 无缝集成 BUAA CAS 统一身份认证，支持验证码处理与服务端会话保持。
*   **📅 智能课表**: 实时同步学期课表，支持周次切换与详情查看。
*   **📝 考务助手**: 考试安排一键查询，不再错过重要考试。
*   **🏛️ 空闲教室**: 快速查找全校可用自习教室。
*   **🎓 博雅全能**: 博雅课程查询、选课、退课及**远程自主签到**。
*   **✅ 考勤签到**: 支持特定课程的二维码/位置签到功能。
*   **⚡ 自动评教**: 一键完成学期评教。

### 🎨 卓越体验
*   **Material Design 3**: 遵循最新设计规范，界面现代、整洁。
*   **深色模式**: 完美适配系统亮色/深色主题。
*   **更新提醒**: 内置版本检查，及时获取最新功能与修复。
*   **隐私管理**：服务端不存储任何用户信息，所有内容均由北航官方服务器提供。

---

## 🚀 快速开始 (Getting Started)

### 📋 前置条件
*   **JDK**: 17 或更高版本。
*   **IDE**: IntelliJ IDEA (推荐) 或 Android Studio。
*   **Xcode**: 仅 iOS 开发需要 (macOS)。

### 1️⃣ 克隆与配置
```bash
git clone https://github.com/your-repo/UBAA.git
cd UBAA
cp .env.sample .env
# 根据需要编辑 .env 文件配置端口等信息
```

### 2️⃣ 启动后端服务 (Server)
客户端强依赖后端 API，请**务必先启动服务端**。

```bash
./gradlew :server:run
```
> 服务端默认运行在 `http://0.0.0.0:5432`。

### 3️⃣ 启动客户端 (Client)

| 平台        | 命令                                                | 说明                |
| :---------- | :-------------------------------------------------- | :------------------ |
| **Android** | `./gradlew :androidApp:installDebug`                | 连接真机或模拟器    |
| **Desktop** | `./gradlew :composeApp:run`                         | 运行桌面客户端      |
| **Web**     | `./gradlew :composeApp:wasmJsBrowserDevelopmentRun` | 启动本地 Web 服务器 |
| **iOS**     | 打开 `iosApp/iosApp.xcworkspace`                    | 使用 Xcode 运行     |

---

## ⚙️ 配置与环境 (Configuration)

项目配置通过根目录下的 `.env` 文件管理。关键配置项如下：

| 配置项                     | 默认值                   | 说明                           |
| :------------------------- | :----------------------- | :----------------------------- |
| `API_ENDPOINT`             | `http://localhost:5432`  | 客户端连接的后端地址           |
| `SERVER_PORT`              | `5432`                   | 服务端监听端口                 |
| `SERVER_BIND_HOST`         | `0.0.0.0`                | 服务端绑定地址                 |
| `INSTANCE_ID`              | `HOSTNAME / JVM name`    | 后端节点唯一标识，用于日志与监控 drill-down |
| `JWT_SECRET`               | *(需修改)*               | 用于签名 access token 的密钥   |
| `USE_VPN`                  | `false`                  | 是否通过 WebVPN 代理访问校内网 |
| `ENABLE_FORWARDED_HEADERS` | `true`                   | 是否信任 Nginx 注入的 `X-Forwarded-*` |
| `CORS_ALLOWED_ORIGINS`     | 空                       | 逗号分隔的跨域白名单；同域 Nginx 部署可留空 |
| `ACCESS_TOKEN_TTL_MINUTES` | `30`                     | access token 有效期            |
| `REFRESH_TOKEN_TTL_DAYS`   | `7`                      | refresh token 有效期           |
| `SESSION_TTL_DAYS`         | `7`                      | Redis 会话与 Cookie 有效期     |
| `PRELOGIN_TTL_MINUTES`     | `5`                      | 预登录会话在 Redis 中的有效期  |
| `SESSION_COOKIE_SYNC_INTERVAL_MS` | `5000`           | 已提交会话 Cookie 从 Redis 回源同步的最小间隔（毫秒） |
| `LOGIN_MAX_CONCURRENCY`    | `6`                      | 服务端允许并行 fresh login 的最大数量 |
| `AUTH_DISTRIBUTED_LOCK_TTL_MS` | `20000`             | fresh login / 预登录提升使用的 Redis 锁 TTL（毫秒） |
| `AUTH_DISTRIBUTED_LOCK_WAIT_MS` | `5000`             | fresh login / 预登录提升锁等待上限（毫秒） |
| `AUTH_VALIDATION_TIMEOUT_MS` | `3000`                 | 认证状态校验/会话复用校验的上游超时预算（毫秒） |
| `AUTH_PRELOAD_TIMEOUT_MS`  | `3000`                   | `/api/v1/auth/preload` 探测的上游超时预算（毫秒） |
| `AUTH_LOGIN_TIMEOUT_MS`    | `18000`                  | 单次 fresh login 的总超时预算（毫秒） |
| `REDIS_URI`                | `redis://localhost:6379` | Redis 会话持久化地址           |
| `REDIS_HEALTH_TIMEOUT_MS`  | `1000`                   | `/health/ready` 检查 Redis 的超时预算（毫秒） |

认证调优说明：
*   `AUTH_VALIDATION_TIMEOUT_MS` 命中后，服务端会返回可重试的 `503 auth_upstream_timeout`，不会清理现有会话。
*   `AUTH_PRELOAD_TIMEOUT_MS` 命中后，`/api/v1/auth/preload` 会降级返回最小可用结果，不会阻塞等待上游。
*   `AUTH_LOGIN_TIMEOUT_MS` 控制 fresh login 的整体截止时间，避免上游卡顿导致 50-100 秒长挂。
*   `LOGIN_MAX_CONCURRENCY` 只限制 fresh login，不影响已建立会话的状态查询。
*   服务启动时会校验 `AUTH_DISTRIBUTED_LOCK_TTL_MS` 是否至少比 `AUTH_LOGIN_TIMEOUT_MS` / `AUTH_PRELOAD_TIMEOUT_MS` 大 2 秒，避免锁提前过期导致并发 fresh login 串写。
*   多节点部署时，所有后端节点必须共享同一个 `JWT_SECRET`、`REDIS_URI`，并各自设置不同的 `INSTANCE_ID`。
*   默认推荐“同域 Nginx 统一前端 + 后端无粘性负载均衡”部署，此时 `CORS_ALLOWED_ORIGINS` 可以留空；本地跨域联调时再按需显式配置。

---

## 📊 监控与运维 (Observability)

服务端内置了面向多节点部署的监控、探针与链路日志能力，保障服务稳定运行。

*   **📈 指标监控 (Metrics)**:
    *   Endpoint: `GET /metrics`
    *   格式: Prometheus 文本格式
    *   内容: JVM 内存/GC、HTTP 请求吞吐/延迟、线程池状态，以及登录成功统计、Redis readiness、预登录跨节点恢复、分布式锁等待/超时、清理跳过等多节点运行指标。
    *   常用 PromQL:
        *   接口调用次数:
            `sum by (route, method, status) (increase(ktor_http_server_requests_seconds_count[24h]))`
        *   接口平均耗时:
            `sum by (route, method, status) (increase(ktor_http_server_requests_seconds_sum[24h])) / sum by (route, method, status) (increase(ktor_http_server_requests_seconds_count[24h]))`
        *   登录成功累计次数:
            `sum by (mode) (ubaa_auth_login_success_total)`
        *   固定窗口登录人次:
            `ubaa_auth_login_events_window{window="24h"}`
        *   固定窗口唯一登录用户数:
            `ubaa_auth_login_unique_users_window{window="24h"}`
        *   集群 Redis readiness:
            `sum(ubaa_redis_ready)`
        *   预登录跨节点恢复速率:
            `sum(rate(ubaa_auth_prelogin_resolve_total{result="redis_restored"}[5m]))`
        *   分布式锁超时速率:
            `sum(rate(ubaa_distributed_lock_timeout_total[5m])) by (scope)`
    *   登录统计说明:
        *   `ubaa_auth_login_success_total{mode="manual|preload_auto"}` 统计成功建立会话的登录次数。
        *   `ubaa_auth_login_events_window{window="1h|24h|7d|30d"}` 统计固定窗口内的成功登录人次。
        *   `ubaa_auth_login_unique_users_window{window="1h|24h|7d|30d"}` 使用 Redis HyperLogLog 做近似去重，适合监控看板，不保证绝对精确。
        *   `ubaa_redis_ready` 是单节点 gauge，启动后默认从 `0` 开始，并会由后台每 15 秒刷新一次 Redis readiness；`1` 表示最近一次检查通过。
        *   `ubaa_cleanup_skipped_total{kind="session",reason="redis_fresh"}` 表示本地清理时发现 Redis 里仍有更新会话，因此跳过误删。
        *   多节点下 `logout` 或新登录覆盖旧会话后，其他节点会在下一次访问时通过 Redis 中的会话代际 / revision 对账淘汰本地旧副本。

*   **🩺 健康探针 (Health Checks)**:
    *   `GET /health/live`: 仅表示应用进程仍在运行。
    *   `GET /health/ready`: 以 Redis 连通性为准，Redis 不可用时返回 `503`，适合给外部负载均衡 / 容器平台做摘流判断。
    *   仓库里的 `ops/nginx/ubaa.conf` 只是把 `/health/*` 透传到后端；它本身不做主动健康摘流，真正的主动摘流需要外部 LB、Kubernetes probe 或额外的健康检查组件。
    *   即使没有外部持续访问 `/health/ready`，服务端也会后台周期刷新 readiness 状态，确保 `/metrics` 中的 `ubaa_redis_ready` 可直接用于监控面板。

*   **📝 日志系统 (Logging)**:
    *   **控制台**: 实时输出 Info 级别以上日志。
    *   **文件归档**: 自动写入 `server/logs/server.log`。
        *   策略: 按天滚动，保留 30 天历史。
        *   内容: 包含完整的请求链路追踪 (Trace) 和异常堆栈。
    *   每个请求都会附带 `X-Request-Id`；如果前置 Nginx 已注入，则服务端沿用并回写到响应头，同时写入日志 MDC 中的 `req` / `inst` / `fwd` 字段。

---

## 🏗 技术栈与架构 (Architecture)

本项目采用 **Kotlin Multiplatform (KMP)** 分层架构：

### 📂 模块划分
*   **`composeApp` (UI 层)**
    *   基于 **Compose Multiplatform**。
    *   包含所有界面逻辑、ViewModel 和平台特定的入口代码。
*   **`shared` (领域层)**
    *   **KMP 共享模块**，被客户端和服务端同时引用。
    *   定义了所有 **Data Models (DTOs)** 和 **API Interfaces**，确保前后端契约绝对一致。
    *   包含通用的日期处理、加密算法等逻辑。
*   **`server` (后端层)**
    *   基于 **Ktor Server**。
    *   作为 API Gateway 和 Adapter，负责与复杂的校内旧系统交互（爬虫/模拟请求）。
    *   处理 JWT 鉴权、Session 管理和数据缓存。

### 🛠 关键技术
*   **Language**: Kotlin 2.0+
*   **UI**: Jetpack Compose / Compose Multiplatform
*   **Backend**: Ktor 3.x, Netty
*   **Build**: Gradle (Kotlin DSL), Version Catalog
*   **Libraries**: Koin (DI), Ktor Client, Coroutines, Serialization

---

## 🧪 开发指南 (Development)

### 运行测试
执行全量单元测试（包含 Shared 和 Server 逻辑）：
```bash
./gradlew test
```

### 代码覆盖率
生成 HTML 格式的测试覆盖率报告 (基于 Kover)：
```bash
./gradlew koverHtmlReport
```
*   报告路径: `build/reports/kover/html/index.html`

### 代码规范
执行 Lint 检查以确保代码风格一致：
```bash
./gradlew lint
```

---

## 📂 目录结构概览

```text
UBAA/
├── composeApp/          # 客户端主工程
│   ├── src/commonMain   # 核心 UI 代码 (Screens, Components)
│   ├── src/androidMain  # Android 入口
│   ├── src/iosMain      # iOS 入口
│   ├── src/jvmMain      # Desktop 入口
│   └── src/webMain      # Web 入口
├── server/              # 后端服务主工程
│   └── src/main/kotlin  # 路由、业务逻辑、爬虫实现
├── shared/              # 共享代码库 (KMP)
│   ├── src/commonMain   # DTOs, Enums, Utils
├── iosApp/              # iOS Xcode 工程配置
└── gradle/              # 构建配置与 Version Catalog
```
