# 离线首页与后台恢复执行合同

日期：2026-09-17。状态：执行中；P0–P5连续实施与验收，P5-A已有双路线真实App功能证据，整体未完成。

依据：[已接受完整设计](docs/design/offline-home-and-background-sync.md)。本合同落实该文档全部 P0–P5；旧完整 UI/UX 暂停合同已原样归档到 [历史合同](docs/migration/history/goal-2026-09-17-before-offline-home.md)，不恢复其无关余项。

## 基线与授权

- 源工作区 `/Users/moorefoss/Code/UBAA2`，分支 `ubaa2`，起点 `d7c37f73`，核对时 tracked/untracked 工作区均干净。
- 设计 `7273283a`、首页按需加载 `db4e198d` 均为起点祖先。引用管理 `f63e6d06`、首页/UI/图标 `8f66ce7e`、查询/预约及 golden `d7c37f73` 已完整继承，均为既有成果，不计本任务新增。
- 实施区 `.worktrees/offline-home-20260917`，分支 `codex/offline-home-20260917`；源工作区不覆盖、不清理。冻结引用通过本地忽略的符号链接只读复用，`just refs` 已通过，不运行不必要的 bootstrap。
- 用户授权所需本地实现、构建、调试、模拟器及独立阶段提交、按既有安全路径进行 Direct/WebVPN 真实只读；禁止真实业务写入。敏感输入只读，验收媒体置于仓库外私有目录。

## 必须保持的行为

有可恢复账号先显示本地首页，首帧后立即创建或合并恢复任务；旧 autoLogin 仅限制旧密码的自动使用，不阻止会话恢复。首页保持三入口、今日课表/待办、单个顶栏路线图标和按需查询。认证、同步、本地展示和写资格独立。十二领域精确隔离账号/路线/查询/日期/分页，成功完整替换、部分失败保留、退出栅栏阻止迟到结果。Core 统一加密缓存，密钥不可用不降级明文。希冀持久索引、选择性详情、渐进批次和历史复查，不假定顺序、增量游标或 ETag。

路线优先恢复通过新 facade/Bridge 合同；旧 CLI/双路线语义保持。大读取只在可证明安全边界让位，不复制 Cookie 或并发改写持久会话。唯一 WriteCoordinator 继续负责实时目标与资格、prepare、用户确认、单次 commit、既定回读；离线不授予资格，恢复不提交，未知结果不自动重发。

## 阶段与证据

- [ ] P0：逐操作双冻结来源对照；身份/覆盖范围/完整度合同；账号授权迁移；六平台存储/密钥可行性；路线恢复与分段边界原型、版本决策。
- [x] P1：最小首页持久缓存，展示/认证分离，首帧后恢复，登录失败原位保留，首次/退出/账号隔离。确定性/原生与P5-A双路线真实App功能证据已闭合；多端性能仍归P5。
- [ ] P2：优先队列、去重、前后台/网络恢复、路线优先、Core/Bridge 安全批次与操作保护。
- [ ] P3：希冀索引/详情持久化、选择性和渐进刷新、完整刷新、历史课程新增/旧项后新项/长周期/未知日期测试。
- [ ] P4：十二领域和既有操作清单逐项接入；精确查询、详情、分页、课表覆盖和缓存清理。
- [ ] P5：15 类异常/生命周期场景；手机/平板/macOS 每设备至少 30 次缓存启动测量，首屏/首批/全部完成分列；最终门禁、双路线只读、审查及证据归档。

行为修改逐项 RED→最小实现→GREEN；来源核对先于生产改动。每阶段更新状态、决策和证据，经适用 refs/layout/sensitive/check、Flutter/Bridge/CLI 检查后独立提交。全部目标未达成不得勾选全部完成。

## 当前候选与未闭合条件（2026-09-24）

接续核对起点为`c7e55171`，29项原未提交变更全部保留并完成，其他相关任务空闲，冻结引用保持原SHA。后续独立提交为P2-P `e09e63f4`、P2-Q `a80bbf33`、P3-B `c729e6b9`、P2-R `950c8192`及iPhone原生证据 `55fe5dad`。主工作区未修改。

P4-AG已提交`3ca371fc`，补齐未知结果的重启核对提示，业务缓存schema v6、Flutter bridge contract v35及生成绑定已接通；Core加密最小线索、单次提交收尾、控制器迟到读取保护、首页查看/本地移除及清理确认均已实现，该阶段完整just check、CLI端到端16项、Flutter1066项/7包静态分析、FRB零漂移与macOS/iPad模拟器原生合成通过；历史1057项Flutter不代替本轮检查。当前核对索引见[最终验收索引](docs/migration/evidence/offline-home-acceptance-2026-09-23.md)。

十二领域已具备所列范围缓存、完整学期导入、关联写后失效与管理；P3-B补齐明确批量详情，P2-R按明确clientDisposed原位替换并接管查询。剩余精确范围、长读取、生命周期仍按实际代码审查，不能用阶段数量代替覆盖。

P1有历史双路线真实App功能证据；本轮新App macOS/iPhone/iPad WebVPN分段只读准备及30次启动测量均完成，Direct在SPOC真实上游`unexpected_eof`处停止，旧CLI Direct同轮也因SPOC `network_error`退出5，不能以空集合回退宣称成功。macOS Release缓存可见中位数/P95为342.145/410.584ms，iPhone Debug模拟器为1989.248/2601.328ms，iPad Debug模拟器为2112.204/2765.966ms；首帧后恢复启动三端均低于200ms。完整数据和阶段成本见[测量证据](docs/migration/evidence/offline-startup-measurement-2026-09-24.md)。

六平台安全材料原生运行未全覆盖；macOS和iPhone模拟器已有合成FFI，iPhone模拟器安全材料单项通过，iPad模拟器FFI及安全材料两项通过。三端30次轮次均为模拟器或macOS宿主，其中macOS Release达到缓存可见500ms中位数/1s P95目标，iOS Simulator无法构建Release/Profile且Debug未达目标；这些数据不证明实体设备或发布性能。确定性、原生合成、Core-live、真实App、设备性能和发布证据分列。未经要求不推送、不发布；整体执行中。

当前P5-B1已修复iOS空环境导致私有目录不可用，3项行为测试RED→GREEN、完整Flutter1069项/7包分析、just check/refs/layout/sensitive及iPhone原生目录/安全材料2项通过。P5-B首次macOS基线的停滞记录继续保留作历史诊断，不能与本轮独立30次样本混合。P5-B1已提交1a8f7ded、P2-S已提交94ff3a5c，后者Core29项、Bridge4项及完整just check/CLI16通过，FRB零漂移。macOS/iPhone/iPad各80项原生合成通过，P4-AI后当前三端各111项原生矩阵也通过；Debug新App可见窗口恢复已按双来源完成P2-T修复，当前WebVPN真实App可见恢复和三端30次测量已记录，Direct上游阻碍与实体/发布设备边界仍保持未闭合。

P2-T已提交`7afd433d`；P2-U自动成绩让位及同学期主动合并已通过完整Flutter1081项/7包分析、just check和三端各92项原生矩阵。自审发现的成绩提醒旧JSON明文基线已由P4-AH迁入Core加密仓库；P5-B2正式计时已纳入四个补充来源和成绩检查收尾信号，成本按认证、上游、缓存、来源和重复操作分开保存。

P4-AH已将成绩变化基线接入统一加密库，补齐旧文件迁移、精确学期隔离、本机失败提示和清理后提醒撤销。当前Bridge v36/schema v6，完整Flutter1099项/7包分析、just check、CLI16、FRB零漂移及三端各100项原生矩阵通过，见[证据](docs/migration/evidence/offline-grade-baseline-2026-09-23.md)。提醒偏好清理审查缺口已由P4-AI修复；P5-B2已补充真实App测量和成本证据，仍不把合成矩阵替代 Direct 上游、实体设备或发布模式。

P4-AI已修复退出清理偏好遗漏、迟到回调与清理期间登录竞态，11项行为RED→GREEN，见[证据](docs/migration/evidence/offline-local-clear-2026-09-23.md)。P5-B2已补齐五个主领域、四个补充来源和成绩检查收尾的完整首页测量，并接入调度等待/运行和认证、上游、缓存、重复操作成本分类；分析器先按实际输出取得RED后GREEN。当前全量Flutter1112项/7包分析、refs/layout/sensitive/FRB零漂移及`just check`通过，三端各30次正式测量和新App WebVPN分段只读已完成；新App Direct的SPOC网络错误、iOS模拟器发布模式不可用、实体设备及其他平台证据仍未闭合，整体未完成。
