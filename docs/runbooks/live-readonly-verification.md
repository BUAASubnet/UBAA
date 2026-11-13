# 真实只读验证运行手册

本手册供需要用真实学校账号验证认证与只读协议的开发者使用，说明如何在 Direct/WebVPN 两条路线上运行 `just verify-live`、如何读懂输出，以及失败时如何记录。何时必须做真实验证见[来源对照与真实验证](../development/commands.md#来源对照与真实验证)。

## 何时使用

- 认证、读取或写入协议变更完成确定性验收后，需要两条路线的真实只读证据。
- 排查某个功能在真实上游上的失败，例如 Cgyy 或图书馆。

真实写操作（选课、签到、预约、取消、评教、上传）不在验证白名单中，本手册不能验证写入。

## 前提

- 已按[检查选择与完成条件](../development/commands.md#检查选择与完成条件)完成对应检查。
- 具有 [AGENTS 规定的当前会话授权](../../AGENTS.md#真实账号与验收范围)，覆盖要运行的功能和路线。
- 在被忽略的根目录 `.env` 中设置非空的 `UBAA_TEST_USERNAME`、`UBAA_TEST_PASSWORD`（兼容旧名 `UBAA_USERNAME`、`UBAA_PASSWORD`）。凭据经 stdin 传递，不打印，也不出现在命令参数中。

运行时的分工：

- `verify-live` 校验参数白名单，安全读取凭据，经 stdin 转发给 Core-live 启动器。
- `scripts/live/core-live.sh` 管理隔离会话目录，运行 `cargo build --locked --bin core-live` 并启动二进制。
- Core-live 在一个固定 Direct 或 WebVPN 策略的 `UbaaClient` 内登录一次，串行执行客户端共用的只读 facade。stdout 每行都是安全摘要，不含 DTO、URL、Cookie、Token、验证码或个人资料。
- 显式指定 `config-dir` 时使用专用验证目录。登录准备会重建该目录内的会话和固定路线配置，不能复用日常 App 的材料目录。
- Core-live 是脚本化只读验证的联网程序；真实 App 的验收另行记录。

## 步骤

### 完整矩阵

两条真实路线分别执行，不能用 `auto` 代替：

```bash
just verify-live mode=direct
just verify-live mode=webvpn
```

`feature=all`（默认矩阵）在一个客户端内依次检查认证、用户、课表/考试/成绩、教室、SPOC、Judge、签到、阳光打卡、图书馆、博雅、研讨室和评教读取。

### 单项重跑

```bash
just verify-live feature=auth route=direct
just verify-live feature=auth route=webvpn
just verify-live feature=cgyy route=direct
just verify-live feature=cgyy route=webvpn
```

缩小范围的运行不等于完整验收。

### 财务

`feature=finance` 使用固定为 Direct 或 WebVPN 的 `UbaaClient`：

- 与其他功能共用客户端登录按钮的 `prepare_quiet_login_for → submit_quiet_login → continue_interactive_login`，随后调用 `finance_incomes`。
- 输出 `auth/prepare`、`auth/login`、`auth/status` 和 `finance/incomes` 的安全摘要；认证失败时把依赖读取标记为 `BLOCKED`。
- 财务账号需要查询系统权限。使用其他获授权账号时，通过本机密钥管理工具只向这次验证进程注入对应账号和密码；进程环境优先于 `.env`。

### Cgyy 窄范围日志

需要排查 Cgyy 时，可以临时打开窄范围日志写入 stderr：

```bash
RUST_LOG='ubaa::cgyy=debug' just verify-live feature=cgyy route=direct
RUST_LOG='ubaa::cgyy=debug' just verify-live feature=cgyy route=webvpn
```

诊断字段按[日志与诊断脱敏](../development/conventions.md#日志与诊断脱敏)处理，不直接共享原始 stderr。WebVPN 的每个 Cgyy 操作都必须使用 facade 解析出的 WebVPN runtime，不能回退 Direct。

## 验证

### 读懂摘要

每行摘要的格式：

```text
route=<direct|webvpn> feature=<name> operation=<name> status=<PASS|FAIL|BLOCKED|NOT_APPLICABLE> [error=<stable-code>] [count=<n>] [reason=<code>] [mapping=embedded_login_state] [source=<upstream|static_fallback>] [global_page_count=<n>] [course_count=<n>] [raw_anchor_count=<n>] [filtered_unique_count=<n>]
```

状态规则：

- 依赖数据缺失输出 `NOT_APPLICABLE`，依赖请求失败输出 `BLOCKED`，独立操作继续执行。
- 任何 `FAIL` 或 `BLOCKED` 都使该路线以非零退出。
- 每条路线只创建并复用一个固定策略的 `UbaaClient`；登录前的 `auth/prepare` 必须与 `auth/login` 成对出现。
- 认证失败时，当前功能所需的全部操作都输出 `BLOCKED(reason=authentication_failed)`，使矩阵完整、可审计。
- 图片验证码复用客户端 Core 的本地识别和最多三轮自动处理。耗尽时输出 `auth/login FAIL error=captcha_required`，依赖读取标记为 `BLOCKED`，进程非零退出。工具不等待人工输入，也不输出或保存验证码。
- 未支持的验证类型仍按 Core 错误失败，服务异常不在验证器中额外重试。固定路线不进行 Auto 探测，也不登录另一条路线。
- 希冀等功能的聚合只读接口用于协议验收；Flutter 的渐进调度、缓存保存及首屏耗时需要在应用端另行验证。

### 记录结果

只把摘要字段及日期、固定引用提交和退出码记入[状态页](../project/status.md)，不保存 stderr 或上游正文，也不把原始输出、会话文件、Cookie、验证材料或完整资料字段附到 issue 或提交中。

## 故障处理

失败按以下格式逐操作记录：

```text
date=<YYYY-MM-DD> commit=<client-commit> refs=<old-commit>,<example-commit>
command=just verify-live mode=<direct|webvpn>
route=<direct|webvpn> feature=<name> operation=<name>
status=<PASS|FAIL|BLOCKED|NOT_APPLICABLE> error=<stable-code-or-none>
count=<safe-count-or-none> reason=<dependency-code-or-none> exit_code=<n>
```

- `upstream_changed`、`upstream_unavailable`、交互式认证页面、账号不适用和网络阻塞都逐操作记录，并写明可重复的日期与路线重跑条件。
- 不以认证成功、站点数量或 Mock 通过推断其他操作成功，也不为真实账号调用任何写入口。
- 授权或网络条件不足时，如实登记未运行或失败及重跑条件，双路线要求保持。

### 图书馆营业时间

图书馆分区详情依赖上游营业窗口：每日 08:30–23:00（`Asia/Shanghai`）。

- `libbook/area_detail` 的实时验收在该窗口内执行。
- 窗口外出现 HTTP 200、业务 `code=500` 且缺少 `data` 时，保留安全摘要，只记录为“非营业时间待复测”，不据此判定协议变化或放宽解析器。
- 非营业时间样本还要记录开放时间和时区，并在窗口内用同一条 Direct/WebVPN 命令重跑；重跑前不修改 `Space/map` 的 URL、参数或错误映射。

## auto 的确定性验证

`auto` 只在 Core/Mock 路由测试中验证网络探测、解析和 WebVPN-only 会话。`verify-live` 与 `core-live` 都拒绝 `auto`，不执行真实登录矩阵。早期基于 CLI 的认证验证器说明见[归档](../archive/history/live-auth-verification-2026-08-26.md)。
