# 离线首页启动与后台成本测量接线证据

日期：2026-09-24。实施区：`codex/offline-home-20260917`。本文件记录测量工具和校验边界，不把工具通过写成设备性能或学校可达性通过。原始启动日志、账号材料和加密快照均保存在仓库外的私有目录，不进入 Git。

## 本批完成

- 独立只读入口继续使用生产 `UbaaAppHost`、`AppController`、Core/Bridge 分段读取和安全材料；启动器拒绝真实 commit，并为每轮建立独立配置目录、材料命名空间和缓存快照。
- 事件分别记录内核进程出生、Dart 入口、首页逻辑帧结束、引擎 raster 首帧、缓存可见、恢复任务开始、首批在线数据和完整首页刷新结束。
- 完整首页范围为五个主要领域（课表、签到、SPOC、评教、希冀）加四个补充来源（已选博雅、研讨室订单、当前周、成绩检查）。成绩检查另记录加密基线检查是否收尾以及是否实际持久化。
- `ReadScheduler` 的可选诊断记录 queued/started/completed/cancelled、排队等待和运行耗时；分段后台操作记录认证、上游、缓存命中、来源和重复操作。
- Python 统计固定计划样本分母，保留未启动和无效样本，P95 使用 nearest-rank；完整首页校验区分主领域 `complete`、补充来源 `finished` 和成绩 `check_complete`。

## RED→GREEN 与门禁

1. 修改分析测试使四个补充来源使用实际输出字段 `finished`，先观察到完整首页样本被错误标记 `incomplete_home_coverage`（RED，日志 `/tmp/ubaa-p5b2-analysis-red.log`）。
2. 按最小范围拆分主领域与补充来源校验，并要求成绩检查收尾信号；7 项 Python 合同测试通过（GREEN，日志 `/tmp/ubaa-p5b2-analysis-green.log`）。
3. Flutter 全量检查在接入调度诊断、成绩收尾回调和独立入口后通过：domain 57、platform 75、app 562、UI 287、bindings 23、host 53、Flutter 应用 55，共 1112 项；7 个包分析器均无问题。日志 SHA-256：`dea8524f9fa80f5c105a36da6f584aba57bbd4585cfe8e3f25b44c750412d9fe`。
4. `just refs`、`just layout-check`、`just check-sensitive`、`just flutter-codegen-check` 已通过；Rust/Bridge 生成目录无漂移。本批没有改变学校协议或 FRB schema。

## 正式测量结果

三轮均使用当前提交 `436f4a86`、独立加密业务快照、每次新建内核进程、WebVPN 只读路线和计划 30 个样本；每轮 `valid=30`、`fully_refreshed=30`、`invalid=[]`，业务写入计数均为 0。`dart_main` 是进程出生到 Dart 入口，后续时间均从同一进程出生基线计算；P95 使用 nearest-rank。数据和原始日志在仓库外私有目录，下面只记录摘要与 SHA-256。

| 设备/构建 | Dart 入口中位数/P95 (ms) | 首页首帧中位数/P95 (ms) | 缓存可见中位数/P95 (ms) | 恢复启动中位数/P95 (ms) | 首批数据中位数/P95 (ms) | 全部刷新中位数/P95 (ms) | 首帧后启动中位数/P95 (ms) |
|---|---:|---:|---:|---:|---:|---:|---:|
| macOS Release | 240.791 / 290.150 | 323.951 / 384.314 | **342.145 / 410.584** | 321.333 / 381.732 | 736.371 / 857.182 | 12121.350 / 16171.182 | 0.384 / 0.733 |
| iPhone 17 Pro iOS 模拟器 Debug | 916.630 / 1587.282 | 1737.776 / 2380.090 | 1989.248 / 2601.328 | 1763.663 / 2411.308 | 2345.004 / 2942.376 | 25032.629 / 27132.956 | 12.820 / 16.993 |
| iPad Pro 13 M5 iOS 模拟器 Debug | 949.324 / 1613.723 | 1816.618 / 2481.854 | 2112.204 / 2765.966 | 1847.698 / 2523.216 | 2441.866 / 3133.358 | 25645.802 / 27582.737 | 20.451 / 39.855 |

macOS Release 的缓存可见目标（中位数 500 ms、P95 1 s）通过；两个 iOS Debug 模拟器未达到该目标，首帧和 Dart 调试宿主开销分别约 1.7–1.8 s 和 0.9–1.0 s。三端首帧后恢复启动均低于 200 ms，说明恢复调度没有阻塞首页；iOS 模拟器结果不能替代实体设备或发布模式结果。Flutter 工具链明确拒绝 iOS Simulator Release/Profile 构建（分别返回 `Release mode is not supported for simulators`、`Profile mode is not supported for simulators`），因此没有伪造发布模式数据。

三轮摘要文件 SHA-256 依次为：macOS `9d156f1f1be7c8600dbb64762656551225fbb8a6fc2836d4e7cfaa5bc0570116`，iPhone `a24b4aa9967d837b6b4b7f738d340f8c78c7b618788d7675f44385df66a9b1cf`，iPad `e535c9fe3f383ea3ed3161c4b29dda08c705fc40570f49328989df608dd14c93`。对应私有轮次分别为 `p5b2-macos-webvpn-20260924`、`p5b2-iphone-webvpn-20260924`、`p5b2-ipad-webvpn-20260924`；准备摘要和运行清单仍在同目录，未复制进仓库。

当前提交的 15 类异常/生命周期原生矩阵也在 macOS、iPhone 17 Pro 模拟器、iPad Pro 13 M5 模拟器各通过 111 项；日志仍在私有目录 `p5b2-native-current-20260924`，SHA-256 依次为 macOS `0515b246bcc2b556dc3379ebd5b6fa23722d2e8e1aaaa25db97c4bba27ffddac`、iPhone `0b4e2a16c5316890cbb7262e8033d104a9190e849169bf40b5948e709b4be4e2`、iPad `c1d3741216216de65f3caca8f7600699ad228ab278ee6ee63ba50f1f29e6f958`。矩阵使用脱敏后端、独立合成缓存和系统材料，业务写入仍为 0。

### 后台成本拆分

| 设备 | 阶段（次数）认证中位数/P95 (ms) | 缓存中位数/P95 (ms) | 上游中位数/P95 (ms) | 调度等待中位数/P95 (ms) | 调度运行中位数/P95 (ms) | 取消数 | 重复操作数 |
|---|---:|---:|---:|---:|---:|---:|---:|
| macOS Release | 0.227 / 82.428 (726) | 2.871 / 21.409 (74) | 231.175 / 816.144 (442) | 0.002 / 1810.138 | 46.971 / 260.982 | 91 | 3465 |
| iPhone Debug | 0.583 / 108.441 (720) | 58.844 / 262.458 (62) | 241.965 / 859.847 (420) | 0.011 / 1949.713 | 186.185 / 480.649 | 90 | 3422 |
| iPad Debug | 0.666 / 108.400 (720) | 74.698 / 318.974 (63) | 233.787 / 790.383 (420) | 0.011 / 1877.857 | 185.732 / 498.394 | 90 | 3423 |

网络读取、必要的分段认证和 Core 安全批次保持完整；没有通过删除领域、详情或历史覆盖来换取刷新时间。macOS WebVPN 的在线来源计数 255、未知来源 4080；iPhone 为 240/4052，iPad 为 240/4053。未知来源来自合成观测中无法映射来源的桥接事件，不能当作持久命中；持久来源三轮均为 0。`batch.judge`/`batch.spoc` 等操作仍在安全批次边界让位，调度取消数是生命周期收尾结果。

## 双路线只读验证

- 新 App macOS WebVPN 预备和三轮测量均完成，五个主要领域的准备结果完整，SPOC 6、评教 71、希冀 11 条等摘要只记录计数，不保存正文；准备摘要 SHA-256 为 `4cededcaad76febe89d16bc941a01b8e5336b2b3e4a6190b72ea9ab7ad2985a8`。
- 新 App iPhone/iPad WebVPN 预备和三轮测量均完成，准备摘要 SHA-256 分别为 `9fe594d08014322d173928b516912778f809c63467a99ac6747715a48ec0e2c8`、`3f59f41c05323c2580e1f0578843a6fd5bf009bdd980d7c1ce843a4ebccb6327`。
- 新 App macOS Direct 在两次独立准备中均完成课表、签到后，于 SPOC `batch.spoc` 因真实上游 `unexpected_eof`（约 5 s）返回 `BackendException(network_error)`，均未开始统计；两次 `business_writes=0`，准备摘要 SHA-256 为 `aab0a72a3b75d3d042bf36328cfcc0bc00d26247684c13e13323bb04103dd9c8`、`6c22f777e31db1395d2782ef6bbdac36e94b0e1194f01235f9ad8bb3ad7447b6`。该失败与旧 CLI Direct 同轮的 SPOC `network_error` 一致，仍属于外部可达性阻碍，不能用空集合或聚合回退宣称成功。
- 旧 CLI `verify-live mode=direct`：认证、用户、课表、考试、成绩、课堂、评教、签到、希冀、图书馆、博雅和充电等只读步骤通过，SPOC assignments/diagnostics 为 `network_error`，命令退出 5；日志 SHA-256 `2ad617f87af0e115f1c861db130df06309a6666a828d588ddc7380a8efbddb2f`。
- 旧 CLI `verify-live mode=webvpn`：认证至评教的只读步骤全部 PASS（评教计数 0 是当前账号状态，不是错误容错），命令退出 0；日志 SHA-256 `0ae847fb6178d2b870f0d4168dec129a8cd02f586efcec41a52cd6b889cddd11`。旧 CLI 证据与新 App 分段证据分开保存。

正式轮次没有实体手机/平板、Windows/Linux/OHOS 或 iOS Simulator 发布模式运行证据；这些外部边界保持未闭合。后续优化必须先定位实际阶段成本，不能以减少必要读取覆盖或提高批次风险来满足数字目标。
