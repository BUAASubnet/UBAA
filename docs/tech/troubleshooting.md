# 排障指南

## docs 构建失败

- 先运行 `npm ci`，确认 `package-lock.json` 已提交且未被 `.gitignore` 忽略。
- 再运行 `npm run docs:build`，根据 VitePress 输出修复死链或 Markdown 语法。
- 如果本地构建通过但 CI 失败，检查 Node 版本是否为 22，Secrets 是否存在。

## docs 发布失败

- `DOCS_SSH_HOST`、`DOCS_SSH_USER`、`DOCS_SSH_KEY`、`DOCS_SSH_PORT`、`DOCS_DEPLOY_PATH` 任一为空都会直接失败。
- `ssh-keyscan` 失败通常是 host 或 port 错误，或服务器不允许外部访问 SSH。
- `rsync` 失败通常是目标目录权限、SSH key 权限或服务器缺少 rsync。

## 登录或连接模式异常

- 先确认当前模式是否在平台可用模式中。
- 切换模式后应清理旧 Token、Cookie 和本地上游客户端。
- 服务器中转已弃用；Web/Wasm 不支持本地连接，登录问题应在 Android、iOS 或 Desktop 的直连或 WebVPN 模式下排查。

## 功能数据为空

- 先比较服务端路由返回和 shared/local backend 返回。
- 若上游 raw 数据存在但解析结果为空，优先检查 HTML/JSON parser。
- Judge、SPOC、CGYY、Grade 是高漂移区域，修复时补对应 parser/backend 回归测试。

## 来源文件

- `docs/.vitepress/config.mts`
- `.github/workflows/docs.yml`
- `shared/src/commonMain/kotlin/cn/edu/ubaa/api/ConnectionRuntime.kt`
- `shared/src/commonMain/kotlin/cn/edu/ubaa/api/auth/NetworkUtils.kt`
- `server/src/main/kotlin/cn/edu/ubaa/auth/api/UserFacingErrors.kt`
- `server/src/main/kotlin/cn/edu/ubaa/judge/JudgeSupport.kt`
- `server/src/main/kotlin/cn/edu/ubaa/cgyy/CgyyService.kt`
