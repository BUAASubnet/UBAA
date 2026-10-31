# 当前实现与验证状态

更新：2026-10-31。本文只维护当前快照，不记录单轮验证流水。整改阶段 1–7、Rust Core 精简、审查修复与签名配置的逐轮记录见[状态流水](history/2026-10-30-status-log-through-signing.md)，更早的时间线见[阶段 4 整理前状态](history/2026-10-30-status-before-quality-phase4.md)，历史决定见[决策索引](decision-log.md)。[阶段目标](../../goal.md)定义本轮范围，门禁清单只在[开发命令](../development/commands.md#检查选择与完成条件)维护。

## 当前实现

Rust Core 统一拥有认证、Direct/WebVPN/Auto 路线、会话、校园领域读写和加密缓存。CLI 与 Bridge 通过 facade 使用 Core，Flutter/OHOS 宿主通过 Bridge 与共享 Dart/UI 接线。当前公开合同为 CLI JSON schema v12 与 Flutter bridge contract v43，独立于 Session v2、配置 v1、业务缓存 v7。产品展示版本与合同版本分别治理，取值与发布规则见[版本约定](../development/conventions.md#版本号与依赖)。

Core 与 CLI 已增加门户身份/学院、五项账户指标和网络流量在线查询，云盘指标明确为剩余空间。此前三个 facade 方法和 `portal profile`、`portal metrics`、`network usage` 命令已在 Direct/WebVPN 两条路线实测成功，并验证网络业务会话在 CLI 进程重开后复用。单项指标失败保留其他结果，金额采用十进制字符串，免费与计费剩余流量分别保留“不含套餐”的含义。精确范围见[门户与网费接入](source-parity-campus.md)。Bridge v43 已提供这三项类型化读取，移动端底栏新增“我的”页展示身份、账户指标与流量，先显示本机快照再后台在线刷新，并支持下拉刷新；三组数据按账号与路线保存快照，指标逐项保留最近成功值，App 内真实账号读取尚未单独验收。iOS 最低版本已按 Xcode 27.2 统一为 15.0。

macOS 应用最低版本已按用户要求统一为 12.0，以匹配 Xcode 27.2 的构建范围。Runner、Podfile 和自有 bindings Podspec 保持一致，依赖 Pod 的较低目标由安装后处理提升，较高要求继续保留。依据见[部署目标决定](decision-log.md#2026-10-31macos-最低版本统一为-120)。

主题保存为设备偏好，重启恢复，不随退出或清除账号删除；业务缓存仍由 Core 持有。[界面规格](../design/flutter-ui-spec.md)描述现行展示规则，[来源对照](source-parity.md)保留逐操作协议依据。

Rust Core 已完成精简：缓存刷新、路线安全检查、凭据槽位与协议解析收敛，业务缓存提升为 schema v7 并删除历史开发格式迁移；旧库普通打开会明确拒绝且不改文件，可显式重建。过程见[Core 精简记录](2026-10-30-core-simplification.md)。

各平台产品标识统一为 `cn.edu.ubaa`，签名材料默认放在被忽略的根 `.sign/`，配置方法见[应用签名配置](../runbooks/app-signing.md)。Android 已用本机 keystore 构建并校验 Release APK，尚未安装运行或与旧正式包对照。

OHOS 已修复 Rust 动态库被改名导致的启动白屏，并更正 HUKS 密钥存在性查询，使首次写入能够创建密钥。API 26 的 DevEco 模拟器已验证正常入口显示登录页，以及合成安全材料的写入、读回、进程重启后读取和删除。模拟器配置关闭 Impeller，构建后保留该配置；OHOS 分析、测试、插件合同和无签名 Debug HAP 构建通过。实体设备、签名发布和当前 OHOS 真实账号验收仍未验证。密钥接口依据与来源边界见[首次创建安全存储密钥](source-parity.md#2026-10-30ohos-首次创建安全存储密钥)。

阳光打卡 OAuth 已补齐 HTTPS 默认端口 SSO `/login` 中间跳转，保留目标地址、路线和授权码来源校验。2026-10-31 的此前独立验证中，`just verify-live feature=ygdk route=direct` 与 `route=webvpn` 均通过认证准备、登录、状态、概览和记录读取，两条路线分别返回 11 个项目与 20 条记录，退出码均为 0。此次真实验证不包含打卡写入或原生 UI。

首页分批读取在首批可用结果后进入后台补全，Dart 与 Bridge 最多八组并发，仍保留同组串行和写方优先。主动刷新先推进主读取代次，再读取博雅已选与研讨室订单，避免重复请求。下拉等待可显示结果，标题栏统一显示刷新状态。“我的”按五分钟过期刷新，并在账号、路线或业务缓存代次变化时清除旧结果；金额与流量只在展示层做十进制舍入。

本地会话恢复中及暂时失败时均保留原位登录入口，登录面板保留当前页面位置。合成测试覆盖入口、验证码流程及恢复期间导航，真实账号长时间后台恢复仍需设备验证。

## 当前未解决与未验证事项

- 远端 CI 尚未运行。阶段 3 已修改 workflow，本地静态检查与监督复核通过；本轮未 push。
- iOS simulator 构建仍在 Flutter 3.41.9 / Xcode 27.2 的 `debug_unpack_ios` 阶段失败：架构检查报告缺少 `arm64 x86_64`，但同一 Flutter.framework 二进制经 `lipo` 核对含这两种架构。未修改 SDK 或绕过检查，工具链问题解决后需重跑构建。
- 保留原生集合的 Linux Secret Service 和 iOS/iPad 方向握手专项尚未在本轮运行。最新平台构建与 Android 签名测试结果见[状态流水](history/2026-10-30-status-log-through-signing.md)，正式发布与真实账号验收仍未运行。
- [原生删减登记](history/2026-10-30-decisions-through-quality-phase3.md#2026-10-29原生集成只保留真实原生能力)中的以下项目已无自动化覆盖：原生登录到查询完整路径、十二领域连续导航、十项写操作连续流程、原生软键盘专项、真实账号原生 UI 巡检、真实账号原生恢复、真实账号原生启动性能测量、Flutter 到 Android 的真实课表组件通道、常驻原生合成预览及 bindings 默认 driver。登记表逐项列出仍保留的 App/Host/Widget/Core 等分层覆盖。已删除流程的旧失败随入口移除，不计作修复通过。
- OHOS 原生 `AppScope/app.json5` 仍为 `1.0.0`/`1000000`，两个 Flutter 应用仍为 `0.1.0+1`。版本号仍需在发布前与旧正式包核对，平台标识已统一。OHOS fork 与官方 Pub workspace 保持独立，原因和锁文件边界见决策记录。
- Rust 阶段已完成。feature 专属 SSO service URL 未合并，避免改变参数编码、重定向和 Cookie 作用域。监督者决定本轮继续保留历史 `mod.rs` 中的协议实现和 Bridge 离线泛型化，列为后续待办；补充来源或私有观察无法由当前克隆复现的记录仍按[来源对照边界](source-parity.md)保留，不补造证据。
- 最终逐项 UI/设备、异常生命周期、离线性能和发布验收仍有缺口；历史真实只读结果仅属于对应候选，不能继承为当前验收或真实写入授权。

## 最近一次完整验证

2026-10-31 收尾按 `mode=full` 计划执行完整确定性检查。过程中发现的合同版本、测试入口、显示状态和刷新代次问题修复后，逐项复跑通过：`check-strict`（Rust/CLI/Bridge、严格 Clippy、构建、Rustdoc 与脚本合同）、八包格式/静态分析（无 error/warning）、1551 项 Flutter 测试、5 项 macOS 原生集成及 FRB 生成零漂移。原生集成首次启动未建立调试连接，结束同路径旧开发进程后重跑通过；iOS 构建阻塞见上节。

本次收尾没有发送真实学校认证、读取或写入请求。门户与阳光的 Direct/WebVPN 记录保留此前独立验证的范围，不能作为当前 App 的真实账号验收。改动按主题本地提交，未推送，远端 CI、实体设备与发布验收未运行。
