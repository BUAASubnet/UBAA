# 2026-09-07 可维护性治理验收记录

本轮可维护性治理已完成本地验收，独立复审无未解决高、中风险问题。此结论不包含真实学校系统、远端 CI 或正式发布。

## 源码与记录身份

- 起始源码：`95705fdcf1095ad42d1c85b25e208ca302263a0f`。
- 设计与计划：`2f56a453`。
- Rust 传输与 Bridge 安全日志：`160e992d`。
- 严格门禁、权限类型、Bash 3 和版本文档检查：`8e3026a1`。
- 最终实现内容：`541981ea51a79044043b74cec3af0a32b5c35308`。

测试和构建针对本轮工作树中的实现内容执行，随后按阶段提交为上述源码。本文与当前状态的后续文档提交只记录结果，不冒称全部门禁曾在文档提交的 SHA 上重新执行。历史 `0bd866c9` 的 CI/live 结果不继承到本轮。

## 问题关闭

| 原问题 | 已实现行为 | 主要验证 |
|---|---|---|
| 错误跨层丢字段 | Bridge → BackendException → UiError 保留 code、kind、retryable、实际失败路线；登录 SafeError 和 JSON 兼容入口也保留。 | 真实 BridgeBackend 适配、登录失败路线、写流程三个兼容入口、错误模型往返测试。 |
| 两套错误策略分歧 | app 委托 platform 唯一映射；parse_error 不改写，结果未知强制禁止通用重试。 | 全错误码一致性与显式错误标志回归。 |
| 原始错误详情不安全 | 旧详情参数保留供兼容，但外部 message 不再作为脱敏文本保存；诊断仅允许枚举、编号、时间、耗时和筛选源码位置。 | 短个人资料、短正文、URL、异常 toString 禁止调用测试。 |
| App 排障不可达 | 有界内存记录；登录失败页与个人页可查看/主动复制，错误卡显示编号及机器码。 | host/UI widget 验证真实接线、复制字段及账号信息缺席。 |
| 可选副作用污染业务 | 遥测异步且有两秒截止预算；错误被隔离；旧代次读取、discard、flush 不污染当前诊断。 | Completer 控制竞态、故障遥测、成功读取/登录终态测试。 |
| 传输失败无安全原因 | Core 发送/收包事件采用有限 I/O 链与 Reqwest 分类；Bridge 默认接收精确 DEBUG 四字段事件。 | 真实回环 GET/POST、断开端口、截断响应、子进程日志过滤与宿主 subscriber 保留。 |
| 默认 CLI 输出回归 | 安全传输事件使用 DEBUG；默认 info 仍保持 JSON stderr 安静，显式日志过滤才输出。 | 原三项 CLI 断言不变，完整 binary E2E 16 项通过。 |
| 工程门禁误判 | 严格 ShellCheck 固定 0.11.0；实际权限必须是 bool true；生产系统工具固定；APK 空数组清理兼容 Bash 3。 | 16 项 Shell 合同，真实 macOS/iOS/APK 检查。 |
| 文档交接困难 | 原状态与 macOS 合同逐字归档，当前入口只列当前事实；历史验收有仓库内安全摘要。 | 版本合同及链接检查；状态页不再依赖历史表格排版。 |

## 本轮最终验证

| 检查 | 结果与证据范围 |
|---|---|
| `just refs` | 通过，两份冻结引用不变。 |
| `just layout-check` | 通过，0 个结构例外；同时包含在严格门禁中。 |
| `just check-sensitive` | 通过；新增验收文档后再次执行，最终计数以输出为准。 |
| `just check-strict` | 退出 0；实际执行 ShellCheck 0.11.0，无 SKIP；格式、Clippy、Core 双配置、CLI、Bridge、Mock、Shell、构建、文档和差异检查通过。 |
| CLI | 128 项通过，其中 binary E2E 16 项。 |
| Core | 默认和 test-contract 各 219 项单元测试通过；另有领域集成、22 项架构合同等，未把双配置计数当成独立覆盖率。 |
| Bridge | 110 项通过；2 个标记忽略的隔离子进程入口由父测试显式调度，并非未验证场景。 |
| Shell | 维护合同 16 项、版本合同 7 项通过；其它既有 Shell 合同继续通过。 |
| `just flutter-check` | 7 个 package/app 的格式、分析和 396 项测试通过。 |
| `just flutter-codegen-check` | 最终重生成零漂移，CLI v10 / Bridge v9 不变。 |
| macOS 脱敏宿主 integration | 7 项通过，覆盖十二领域查询和十项模拟写流程；不访问学校。 |
| macOS Debug | 生产入口重新构建完成；实际签名中的 Sandbox 与 network.client 均为布尔 true。 |
| Android Debug APK | armv7、arm64、x86_64、i686 原生桥构建通过；真实 ZIP 结构门禁及 Bash 3 清理通过。 |
| iOS simulator Debug | 构建及产物结构通过，无设备安装。 |
| OHOS API26 Debug | analyze、2 项宿主测试、工具链、无签名 HAP 和 arm64 Rust ELF 内容检查通过。 |

Flutter 分布：domain 25、platform 48、app 189、UI 96、bindings 15、host 20、官方 App 3，共 396。

macOS integration 输出过 `Failed to foreground app` 警告，但测试引擎完成 7 项并退出 0；该结果不作为窗口置前、真实账号或真实页面视觉验收。测试后已重新构建生产入口，未将测试包留作最终 macOS 产物。

构建工具生成的本机 Pod/OHOS 元数据已恢复，临时生成库和资源移至仓库外；没有提交本机 SDK 路径、二进制或运行会话。

## 本机产物摘要

以下摘要由仓库产物检查器按给定相对路径计算；目录产物摘要与路径有关，不应换路径重新比较。

| 产物 | 字节数 | SHA-256 |
|---|---:|---|
| `apps/ubaa_flutter/build/macos/Build/Products/Debug/ubaa_flutter.app` | 189984768 | `32148fb3f7b7bc1068b680fc9b5b007ed28f08fe8cebe061718cdc2008d15ebc` |
| `apps/ubaa_flutter/build/app/outputs/flutter-apk/app-debug.apk` | 265281725 | `37a67ee093664d722280d80b470cf336867fcfab5129f83503ef2fa659b477c9` |
| `apps/ubaa_flutter/build/ios/iphonesimulator/Runner.app` | 310018048 | `86c1b856a3db5aea880074da614366d72b15e554d441d3ed0943d1d56f01c951` |

OHOS 产物为 `apps/ubaa_ohos/build/ohos/hap/entry-default-unsigned.hap`，只证明无签名包结构和 arm64 内容，不证明设备或签名发布。

## 可复验命令与证据保管

普通开发使用 [开发命令](../../development/commands.md)；故障定位使用[本地诊断手册](../../runbooks/local-diagnostics.md)。完整源码验证使用固定工具链和以下入口：

```bash
just refs
just layout-check
just check-sensitive
just check-strict
just flutter-check
just flutter-codegen-check
```

独立 RED/GREEN 的来源与命令见 [Dart/宿主来源边界](../source-parity-maintainability.md)和 [Rust 传输来源记录](../source-parity-maintainability-transport.md)。原始本机执行日志保存在仓库外，仓库摘要本身不依赖那些个人路径。不存在本轮远端 CI 链接；本轮没有推送或远端执行。

## 仍保持独立的真实验收

真实 App/Core-live 继续暂停；没有使用真实凭据、既有用户 Session 或执行业务写入。Windows/Linux 原生运行器、远端 CI、真实写入、签名发布、设备权限和硬件安全存储未在本轮重验。已有原生能力缺口与真实业务验收仍以活动合同的边界为准。

本轮关闭的是已经识别的维护缺陷和验证中暴露的回归，不宣称软件今后不会出现问题或获得客观意义上的满分。
