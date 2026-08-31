# 真实只读验证运行手册

真实验证的唯一网络入口是 Core-live。`verify-live` 只做参数白名单、凭据安全读取、临时会话目录、`cargo build --locked --bin core-live` 和一次 stdin 转发；`scripts/core-live.sh` 只负责启动已构建的二进制。二进制在一个固定路线 `RouteClient` 内登录一次并串行执行只读 facade，stdout 每行都是安全摘要，不包含 DTO、URL、Cookie、Token、验证码或个人资料。

前置条件：`just refs`、`just check-sensitive` 和 `just check` 已通过；`.env.local` 仅包含非空 `UBAA_TEST_USERNAME`、`UBAA_TEST_PASSWORD`（兼容无前缀名称）。该文件被忽略，凭据不会复制、打印或写入参数。

## Direct/WebVPN 矩阵

只执行两条真实路线，禁止用 `auto` 代替真实证据：

```bash
just verify-live mode=direct
just verify-live mode=webvpn
```

也可以缩小功能范围以重跑单项：

```bash
just verify-live feature=cgyy route=direct
just verify-live feature=cgyy route=webvpn
```

`feature=all` 会在一个客户端内依次检查认证、用户、课表/考试/成绩、教室、SPOC、Judge、签到、阳光打卡、图书馆、博雅、场馆和评教读取。依赖数据缺失必须输出 `NOT_APPLICABLE`，依赖请求失败必须输出 `BLOCKED`，独立操作继续执行；任何 `FAIL` 或 `BLOCKED` 都使该路线退出非零。真实写操作（选课、签到、预约、取消、评教、上传）不在 Core-live 白名单中。

摘要格式为 `route=<direct|webvpn> feature=<name> operation=<name> status=<PASS|FAIL|BLOCKED|NOT_APPLICABLE> [error=<stable-code>] [count=<n>] [reason=<code>] [mapping=embedded_login_state] [source=<upstream|static_fallback>] [global_page_count=<n>] [course_count=<n>] [raw_anchor_count=<n>] [filtered_unique_count=<n>]`。只把这些字段及日期、固定引用提交、退出码记录到 `docs/migration/status.md`，不要保存 stderr 或上游正文。

每条路线只创建并复用一个 `RouteClient`；登录前的 `auth/prepare` 必须与
`auth/login` 成对出现。认证失败时，当前功能所需的全部操作都要输出
`BLOCKED(reason=authentication_failed)`，使矩阵完整且可审计。

## auto 确定性验证

`auto` 只在 Core/Mock 路由测试中验证网络探测、解析和 WebVPN-only 会话；`verify-live` 与 `core-live` 均拒绝 `auto`，不执行真实登录矩阵。

## Cgyy 诊断

需要排查 Cgyy 时可临时设置窄范围日志并让其写入 stderr：

```bash
RUST_LOG='ubaa::cgyy=debug' just verify-live feature=cgyy route=direct
RUST_LOG='ubaa::cgyy=debug' just verify-live feature=cgyy route=webvpn
```

日志只允许操作名、方法/路径、脱敏参数键与长度、状态码、最终主机/路径、响应长度/哈希和稳定错误码；不得使用全局 `trace`，不得记录用户名、密码、Cookie、业务令牌、签名、验证码、查询值或正文。WebVPN 的每个 Cgyy 操作都必须使用 facade 解析出的 WebVPN runtime，不能回退 Direct。

## 记录失败

```text
date=<YYYY-MM-DD> commit=<client-commit> refs=<old-commit>,<example-commit>
command=just verify-live mode=<direct|webvpn>
route=<direct|webvpn> feature=<name> operation=<name>
status=<PASS|FAIL|BLOCKED|NOT_APPLICABLE> error=<stable-code-or-none>
count=<safe-count-or-none> reason=<dependency-code-or-none> exit_code=<n>
```

`upstream_changed`、`upstream_unavailable`、交互式认证页面、账号不适用和网络阻塞都必须逐操作记录，并说明可重复的日期/路线重跑条件。不要以认证成功、站点数量或 Mock 通过推断其它操作成功，也不要为真实账号调用任何写入口。
