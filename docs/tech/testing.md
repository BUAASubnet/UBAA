# 测试与质量

UBAA 的测试覆盖 shared、composeApp 和 server。文档只改 docs 时至少需要 VitePress 构建验证；改源码时按影响范围选择 Gradle 测试。

## 常用命令

```bash
npm ci
npm run docs:build
./gradlew.bat :shared:jvmTest
./gradlew.bat :composeApp:jvmTest
./gradlew.bat :server:test
./gradlew.bat spotlessCheck
```

跨平台共享逻辑变更可继续运行：

```bash
./gradlew.bat :shared:compileKotlinJs :shared:compileKotlinWasmJs :shared:compileKotlinIosSimulatorArm64 :shared:compileAndroidMain
```

## 测试分层

- shared tests：API 分发、本地直连/WebVPN、DTO 和存储。
- composeApp tests：ViewModel、首页待办、筛选排序、显示逻辑。
- server tests：Ktor 路由、服务、解析器、指标和健康检查。
- browser verification：Wasm/JS UI 变更需要启动 server 和 web dev server 后用 Playwright 验证。

课表真实账号测试默认跳过。显式设置 `UBAA_REAL_SCHEDULE_TEST=true` 后，运行 `:shared:jvmTest --tests cn.edu.ubaa.api.LocalScheduleRealIntegrationTest --no-configuration-cache`，从本机 `local.properties` 读取 `testuser` / `testpasswd`，验证直连和 WebVPN 的首次在线查询、整学期本地化及离线重读。可用 `UBAA_REAL_SCHEDULE_MODE=direct` 或 `webvpn` 限定模式。测试仅查询学校数据，认证与课表缓存使用内存存储，禁用 HTTP 日志，不输出账号、密码、认证令牌或完整课表。

## 文档验证

CI 的 docs workflow 会运行 `npm ci` 和 `npm run docs:build`。本地如果只改 Markdown 且依赖已安装，可直接运行 `npm run docs:build`；修改 `package.json` 或 `package-lock.json` 时应先运行 `npm ci`。构建失败、死链或未提交 lockfile 都应阻止发布。文档涉及 Gradle 任务、共享契约或服务端路由说明时，再按影响面追加运行 `:shared:jvmTest`、`:server:test`、`:composeApp:jvmTest` 或 `spotlessCheck`。

`verifyBhpanReadOnly` 只用于明确允许的只读 bhpan 认证探测；`uploadLatestReleaseToBhpan` 会真实删除并重新上传发布资产，不能作为常规验证命令。

## 来源文件

- `build.gradle.kts`
- `shared/build.gradle.kts`
- `composeApp/build.gradle.kts`
- `server/build.gradle.kts`
- `.github/workflows/test.yml`
- `.github/workflows/format.yml`
- `composeApp/src/commonTest/kotlin/cn/edu/ubaa/ui/HomeTodoTest.kt`
- `shared/src/commonTest/kotlin/cn/edu/ubaa/api/ApiFactoryDispatchTest.kt`
- `server/src/test/kotlin/cn/edu/ubaa/ApplicationTest.kt`
