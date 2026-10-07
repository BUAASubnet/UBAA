# 独立工程审查整改实施记录

日期：2026-10-07（Asia/Shanghai）。基线 `06e4dfdb`，实施分支 `ubaa2`。用户已授权按[独立审查](engineering-quality-independent-review-2026-10-07.md)完整整理修复；活动合同见 [goal.md](../../goal.md)，新的状态与验证决定见 [ADR 0007](../adr/0007-operation-scopes-and-verification.md)。

## 范围与行为边界

I01—I09 已实现且相关确定性/原生/构建门禁已完成；阶段提交和干净候选材料预检收尾。保留唯一 WriteCoordinator、单个 ChangeNotifier、在线资格/离线数据分离、固定来源、现有独有测试和 golden。没有升级产品依赖、改变 CLI v11/Bridge v40/Session v2/配置v1/缓存v6；网络插件只是把现有6.1.5加入官方宿主dev依赖，锁文件版本/摘要不变。

冻结引用均通过纯 `just refs`。三个独立工作树的起始 HEAD、status、diff 和未跟踪文件内容摘要已保存在仓库外，收尾逐项比较。无真实账号读取、Direct/WebVPN 请求、学校写入、推送、签名或发布；原 B2/C2/C3/D 欠验继续保留。

来源对照均先于生产实现建立：

- [Rust 路线、Session错误和日期](source-parity-engineering-rust-2026-10-07.md)
- [Dart 认证、恢复、学期与缓存](source-parity-engineering-dart-2026-10-07.md)
- [本地普通偏好及平台验证](source-parity-engineering-platform-2026-10-07.md)

## 审查项闭环

| 项 | 已落地实现 | RED 与保护 |
|---|---|---|
| I01 写入路线 | 七类旧写入补 Core expected-route 原子入口；十类提交统一一次解析，再固定runtime完成fresh authority及final。移除Bridge重复博雅详情复核 | 正式RED复现Direct确认/WebVPN提交、矩阵列出七类重复解析；106项写入回归GREEN。Session修订检查、资格、请求正文、一次性意图和unknown不可重放保留 |
| I02 敏感扫描 | Python标准库分别扫描index blob和工作区；Git/读取错误失败关闭，拒绝符号链接，不打印正文 | index被工作区清理/删除遮盖、读失败、输出泄漏先RED；正式6项合同保护，无rg依赖 |
| I03 认证终态 | completion模块独占认证完成token，不依赖已释放的验证码engaged；当前失败解除loading并关闭写资格，身份拒绝回login | 普通/交互错配、旧账号索引失败、迟到本地错误、拒绝后残留路线共8项正式反例；销毁立即清密码，35项相关回归通过 |
| I04 迟到快照 | SessionScope集中backend/生命周期核对；路线成功和失败写回前校验，退出/换代不再被旧结果污染 | 登录与RequiredSessionBackend第二次routeSettings两种交错先RED；包含在认证边界回归 |
| I05 偏好恢复 | 普通保存仍先严格解析；明确清除仅按账号键remove，保留串行队列、账号隔离及插件错误 | 6类博雅坏值+提醒坏JSON共7项RED；Platform16、Host12聚焦GREEN，Host通过实际“恢复默认”与公开清除回调验证 |
| I06 状态边界 | SessionScope/ReadScope；AcademicTermsOwner私有持有结果/在途/demand/serial，成绩只消费CurrentTermsReader；ControllerReadCaches统一invalidate | 新增3项owner行为测试，学期/成绩/cache/rebuild聚焦120项通过；不创建第二通知实例或写状态机 |
| I07 依赖闭包 | 自有workspace/package/跨根helper/条件import-export/part统一解析；完整图判环，按scope限规模；未知语法、编码URI、query/fragment失败关闭 | 首批跨scope/条件/同行导入/外部helper负例RED；交叉复核新增shebang与百分号URI双文件反例，修复后module13+catalog13通过 |
| I08 发布材料 | 固定标准schema实际离线校验；SPDX ID/表达式/非标准声明区分；收集Dart/OHOS许可正文、摘要、来源及缺口；原始metadata只作临时输入并清理，报告目录必须为空 | 两个旧SBOM转换反例先RED，9项材料合同GREEN；当前411 Cargo组件schema通过。材料缺口不再伪装“许可审计通过” |
| I09 文案控制流 | Core私有typed SessionConflict原因；Bridge不再以英文message判定机器语义；serde跳过该内部原因 | 同文案普通错误误分类先RED；真冲突改文案仍识别，JSON仍四字段、外部输入不能伪造原因 |

I06完成的是报告指定的实质试点：认证完成、学期读取和统一缓存失效。它不等于整个Controller已变为互不耦合的领域模块；后续按实际变更波及度继续收敛，不能再用mixin数量或单纯文件长度作为完成指标。

## 额外收敛与独立复核

Judge日期改用已锁定Chrono月减法，SPOC用Chrono/chrono-tz承担日期与时区运算，小型wrapper只保留冻结Kotlin Instant语法/回退。正式测试还修复了畸形时间suffix误解析；独立复核补出十位零填充年份 `+0000002026` 的合法边界，再次RED→GREEN。低年/负年使用未补零year符合旧`${date.year}`，没有机械套用ISO展示；SPOC最终22项、Judge9项通过。不扩大Chrono可表示范围，范围外仍走兼容文本回退。

Rust `UbaaError` 新私有cause不进入JSON/FRB/磁盘。`UbaaError::new`和四个公开wire字段保留；外部Rust结构体字面量构造会受私有字段限制，现有合同未保证该形式，此源码兼容取舍已记录，不称作完全零API影响。

新真实插件测试直接调用锁定connectivity_plus的读取、订阅、取消后再订阅；两项原生用例还闭环普通偏好写入/读回/重开/删除。默认macOS集合由3入口增至4入口，未把live/manual放入CI。仅dev直接依赖声明变化，没有升级包版本。

原生完整流程首轮出现Bykc查询矩阵失败。原日志只读取跨领域共享lastQuery，无法区分本次请求、后台请求及原生布局时序。修复fixture为记录(feature,query)序列，每次点击后必须出现目标领域的新请求；输入值、按钮启用/可见/可命中均验证，保留所有typed view断言，不调用内部State、不加sleep。原矩阵在普通widget环境通过，修复后原生聚焦1项及完整组合7项通过；首次日志不足以归因具体OS原因，不宣称修复了未经证明的生产Bykc缺陷。

检查器跨代理复核补齐了百分号URI语义：Dart会将编码路径解析为另一文件，checker不能按字面路径漏扫；当前明确拒绝该形式。依赖图与live标记政策仍各自保留，复用指令闭包而不删除任一保护。

新增固定版本/全平台hash锁的Python开发工具，仅用于标准schema、YAML/JSON5材料解析；不进入App运行依赖。显式quality-tools-bootstrap准备，普通checker/preflight离线；CI显式cargo fetch --locked预取所有目标依赖，并复用七包清单的flutter-dependencies准备Dart源码，防止依赖本机暖缓存。

发布Runbook已分离当前流程与历史候选，最终维护采用check-strict；历史流程归档。源码、生成/依赖、文档证据与平台运行分别记账。审查报告的复跑命令补上已有锁文件的--locked，保留首次审查输出说明；这是全门禁发现的文档命令缺口。

## 当前验证账本

日志统一保存在仓库外私有目录 `/Users/moorefoss/Library/Application Support/UBAA-private-evidence/engineering-repair-20261007`。下表只记本次实际结果；临时RED日志与来源记录一同归档，不纳入Git。

| 入口 | 当前结果 | 证据 |
|---|---|---|
| just refs / layout-check / contract-version-check / check-sensitive | 通过；当前合同版本未变；敏感扫描同时检查index与工作区 | 最终门禁日志 |
| just script-test | 48项：catalog13、module13、sensitive6、release9、启动统计7，通过 | 最终门禁日志 |
| just flutter-check | 七包分析/格式与1340项全部通过，187.96秒 | flutter-check.log |
| 七包分项 | Domain57、Platform83、App647、UI353、Bindings31、Host94、官方宿主75 | 同上 |
| just flutter-codegen-check | 首次生成仅1行“已忽略私有函数”工具注释变化，已保留正确机械产物；再次生成零漂移，14.18秒 | codegen.log、codegen-final.log |
| Rust聚焦/Clippy | 写106、SPOC22、Judge9、公开合同7、路线矩阵9通过；Core/Bridge全目标-D warnings通过 | Rust阶段日志 |
| just check-strict | 首轮因审查复跑命令未写--locked，在CLI E2E 15过/1失败处停止；文档修正后该用例GREEN，最终全门禁通过，309.11秒 | check-strict.log、check-strict-final.log |
| 原生network/plugins | network1、真实plugin2通过 | integration.log |
| 原生flow | 首轮6过/1失败；查询聚焦修复后1通过；完整组合7项通过，193.44秒 | integration-query-focused.log、integration-flow-final.log |
| 原生FFI cache | 1项通过，46.58秒；四入口合计11项通过 | integration-cache-final.log |
| OHOS无签名debug | 分析、2项宿主测试、HUKS/网络源码合成合同、HAP及arm64动态库检查通过，86.32秒 | ohos-check.log |
| Android APK / iOS simulator | 构建与产物结构检查通过；分别212.00秒/90.59秒 | build-android-apk.log、build-ios-simulator.log |
| release-preflight | 等待干净阶段提交后执行；直接离线材料生成已通过schema | 待补最终日志 |

原生runner报告无法前置macOS窗口，因此鼠标逐按钮/真实App交互仍未验收；这不影响已实际调用的原生插件通道证据，但不能用其关闭原B2/C2/C3/D。OHOS无签名HAP不等于实体HUKS成功。Windows/Linux运行、实体设备、真实学校读取/写入及正式发布未执行。

许可材料目前848条按锁文件/原生manifest分别计数（同包可多次出现），821条已收集，27条明确发布材料缺口：20条Dart自有包正文缺失、3条OHOS正文缺失、4条原生依赖需按HAR/.so核验。收集不等于法律批准；本轮不编造版权归属或擅自给项目补授权声明。这些材料缺口继续阻止正式交付批准，不是schema生成器失败。

## 提交与收尾

三个独立工作树 HEAD、status、diff、未跟踪文件内容摘要均与开工一致；golden字节无变化。OHOS构建仅产生的buildinfo删除与本地HAR锁文件路径差异已核对并恢复，未提交构建副作用。阶段提交与干净候选预检收尾后补齐下方记录；不推送或发布。


### 已完成阶段提交

| 提交 | 范围 |
|---|---|
| d1e04888 | 独立审查、当前整改合同与双冻结来源矩阵 |
| a8d111fc | Core确认路线原子化、typed Session冲突、共同写回归及1行机械生成同步 |
| 5c5d9704 | Chrono复用与冻结日期/年份兼容 |
| b7d01506 | 认证完成/迟到结果、学期owner及统一缓存失效 |
| 075f10ed | 损坏普通偏好的明确恢复与Host接线回归 |
| 7a5c863c | index敏感扫描、完整源码闭包、离线标准SBOM与许可材料工具 |
| cac32010 | 真实原生插件通道、查询矩阵证据和默认CI入口 |

全部源码/测试/生成改动的候选为 `cac32010`；后续提交仅收敛文档及记录证据，不将先前日志改称后续文档HEAD的全套运行。当前模块检查为UI63/Bridge45/Controller50个受管library，完整自有闭包无导入环；这仍不代表动态状态依赖已经消失。
