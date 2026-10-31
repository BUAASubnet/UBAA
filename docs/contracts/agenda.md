# 日程 Core 合同

日程一期 1a、1b 提供本机自建事项、标准重复展开、学校事项投影与本地覆盖层，以及本地合并查询。所有生产入口从 `ubaa_core::facade` 导出，不调用学校网络。1c-a 通过独立 typed Bridge 和 Dart 服务接入账号生命周期，1c-b 已将首页七类学校待办接入统一纯投影，1d 增加 Core 范围快照导出。CLI 独立安全材料方案 A 已由主聊天选定，执行通道留给后续会话，命令执行与同步仍未接入。[设计稿](../design/agenda.md)描述完整产品目标，[明文存储决定](../migration/decision-log.md#2026-10-31日程改为逐记录明文-sqlite)记录本期取舍。

## 时间与事项

`AgendaTime` 保存带偏移量的时间和 IANA 时区标识。`new` 将输入时刻转换成 `Asia/Shanghai`，写入时核对时区、偏移量和秒精度。`AgendaItem` 使用 UUID，包含 `AgendaContent`、标准 RRULE 正文、EXDATE、单次覆盖、完成记录、创建/修改/删除时间及 `locally_modified`。

事件必须有开始和结束，结束严格晚于开始。全天规则的 DATE 形式 UNTIL 按校园零点展开，不依赖宿主时区。全天事件使用零点边界，结束日期不包含在事件内。待办可有截止时间或无日期。重复事项必须有开始或截止时间。覆盖与完成的键使用原始发生时间的规范 RFC 3339 字符串，无日期待办的完成键为 `undated`。单次覆盖移动到其他日期后，完成和删除仍使用原始发生时间。

`expand_agenda(item, from, to)` 与 `AgendaStore.query(from, to)` 返回 `[from, to)` 内相交的事件、范围内到期的待办及无日期待办。结果包含 `item_id`、`recurrence_id`、实际内容、`completed_at` 和 `overridden`。查询上限为 3,660 天，单系列展开使用 rrule 的有限迭代，达到 65,535 次发生或库内部限制返回 `CacheError::Capacity`。查询不会把截断结果当作完整结果。

`teaching_week_rule` 接收学期第一周周一、起止周、每周/单周/双周、星期、时间与跳过日期，输出开始时间、标准 RRULE 和 EXDATE。单双周以学期第一周为基准，存储不包含教学周专用语法。

## 持久化与修改

`AgendaStore.open(root, account)` 只接收私有根目录与已核实账号的随机 32 位十六进制别名，不需要 `CacheKey` 或钥匙串。账号身份核实仍由宿主负责。日程保存于独立的 `agenda/<随机账号别名>.sqlite` 明文库，没有路线维度，Direct/WebVPN 共用同一账号的日程。只读缓存继续按账号和路线加密，缓存密钥、容量淘汰、清理或重建不作用于日程。普通打开保留退出状态，宿主必须在退出时调用 `deactivate`，在同账号重新登录后调用 `activate`。持久退出栅栏作用于所有连接；切换账号必须更换句柄并隐藏旧投影。`active` 只描述当前持久状态，同账号重新激活后不能依靠该布尔值识别此前排队的调用，宿主必须先收束旧写入再重新激活。

日程目录在 Unix 上以 0700 创建，数据库以 0600 创建。打开时拒绝 root/日程目录、数据库和 journal/WAL/SHM 路径中的符号链接，日程目录或文件开放组/其他用户权限时也拒绝打开。沿用宿主随机别名和私有目录规则。明文记录不提供密码学保密或完整性保证，能够读取该账号私有文件的本机进程可以查看或修改内容。

`create/get` 创建与读取原始事项。创建会把本地修改标记设为 true，已有 UUID（包括删除标记）不能覆盖。`edit/delete` 接收 `AgendaEditScope`：仅此次、此次及以后、全部。针对发生的操作必须提供原始时间，无日期事项传入 None。编辑传入完整新内容及规则，仅此次编辑重复事项时保持系列规则。后半段编辑返回新 UUID，系列拆分在一个事务内完成。相同规则的平移保留剩余 COUNT、例外和完成记录；新规则无法产生的例外随整体规则替换移除。`complete` 记录或取消某次完成，取消后保存明确的空完成时间。单次删除后的发生不能再完成。

`SchoolAgendaKey` 以来源和上游稳定标识组成键。`set_overlay/overlay/clear_overlay` 设置、读取和清除完整覆盖。覆盖记录存在、未删除且 `completion_override = true` 时，`completed_at` 是否为空直接决定列表完成状态，`effective_completed(upstream)` 实现这一规则。只设置隐藏或备注时传入 `completion_override = false`，继续沿用上游完成状态。隐藏和备注保留在覆盖层，学校来源状态由公开缓存投影传入。清除覆盖写删除标记并恢复上游完成状态。

所有本地修改写入 `updated_at` 和未同步标记，发生错误时事务回滚。调用方传入当前校园时间，早于原记录修改时间的写入会被拒绝。`unsynced_count` 包含事项、覆盖和删除标记。`clear_local_data` 显式删除当前账号全部日程并返回清除前未同步记录数，宿主可先查询数量再展示确认。`purge_tombstones` 仅移除已同步且严格超过 180 天的删除标记；所有未同步删除标记均保留。同步确认和跨设备合并属于后续任务，本期没有清除未同步标记的公开入口。

日程磁盘 schema 为 2：`agenda_meta` 单行保存 schema、账号别名与持久 `active`，`agenda_items` 按 UUID 每项一行，`agenda_overlays` 按来源/上游标识的 JSON 元组每项一行。两类记录的 `body` 是可直接读取的 UTF-8 JSON，重复例外及完成记录仍属于对应事项。`PRAGMA user_version` 与元数据版本均须匹配。只读缓存磁盘版本仍为 7，CLI schema v12 保持不变，独立日程通道当前使用 Bridge v45。

写操作在 SQLite IMMEDIATE 事务内读取最新记录、执行既有领域操作、比较前后状态，只 INSERT/UPDATE/DELETE 实际变化的行。系列拆分、完成、覆盖、删除和清理均在同一事务内提交，任一步失败整体回滚，跨连接写入不会覆盖另一连接已提交的记录。读取使用同一快照事务。当前操作仍会在内存加载账号全部记录，这次没有改成按操作选择记录。

账号总量不再受原 16 MiB 密文行限制。每条 JSON 上限 16 MiB，并保留原有标题、备注、规则长度、每系列 10,000 项例外及完成记录、日期跨度和展开数量限制。超过限制返回 `CacheError::Capacity`，保留原记录，不能截断或淘汰日程。

新文件通过排他创建标记与已有文件区分，只有本次新建文件才能初始化。已有文件先用只读连接核对版本、账号元数据、全部记录和 SQLite 完整性，成功后才打开可写连接。旧密文 v1、未知版本、已有版本 0 文件、损坏数据及账号元数据不匹配均明确拒绝，保留文件，不自动清空、迁移、重建，也不改变其 journal/schema。已有有效库的 journal_mode 同样保留。当前尚无生产宿主日程数据，因此不实现旧格式迁移。错误类别复用 facade 的 `CacheError`，不携带路径、SQL 或业务正文。

## 学校投影与合并查询

`project_school_agenda(records, context)` 是纯投影函数，接收 Core 公开 `CacheRecord` 及 `SchoolAgendaContext`，不访问文件或网络。输入只使用明确查询范围的公开读载荷，不接收学校写入资格。`SchoolAgendaContext` 包含校园当前时间、当前教学周和 `YgdkAgendaSettings`。阳光提醒开关、周达标记忆和学期达标记忆由调用方显式传入，三项参数只影响本地提醒。

`SchoolAgendaItem` 包含 `SchoolAgendaKey`、`AgendaTiming`、独立的 `sort_time`、标题、副标题、地点、`SchoolAgendaStatus`、状态文案和 `AgendaNavigation`。导航包含 feature 及定位原功能详情的公开标识。投影类型没有学校写操作或资格，持久签到的状态文案统一为“状态待更新”。原始学校状态供详情读取，不能从进行时间、提交数量或本地完成状态恢复学校写入资格。

下表的组合键均使用 JSON 元组编码，避免分隔符碰撞。课程额外包含学期，防止同一课程在不同学期的覆盖互相影响。

| 来源 | 上游键 | 形态与时间 | 导航 |
|---|---|---|---|
| 课表 | 学期、课程代码、序号（可空）、周次、星期、该节节次 | 每个节次一条时段，教学周真实日期加该节起止时间；缺时刻时保留已知端点或全天占位 | 学期、周次、课程代码、序号、星期、起始节 |
| 考试 | 学期、task_id（后备 course_no、标题）、日期、开始时间 | 已安排考试的日期与起止时刻；时刻均未知时为当天全天占位 | 学期、task_id、course_no、标题、日期、开始时间 |
| 博雅 | course_id | 课程开始与结束，允许单端点缺失 | course_id |
| SPOC | assignment_id | 截止时间 | assignment_id |
| 希冀 | course_id、assignment_id | 截止时间 | course_id、assignment_id |
| 研讨室 | 订单 id | 预约开始与结束，允许单端点缺失 | 订单 id |
| 签到 | course_id（已有领域类型中的课程安排标识） | 今日快照中的课程起止时刻 | 课程安排标识、当天日期 |
| 阳光提醒 | 学期、教学周 | 本周日 23:59:59 截止 | 阳光概览 |

现有考试字段不能证明 task_id 唯一标识一次考试，考试组合键沿现有首页字段区分不同日期或时刻的发生。缺 task_id 时依次后备 course_no、标题，日期、标题或开始时间变化可能断开旧覆盖。阳光提醒没有独立上游记录，学期与教学周表示一条合成提醒。缺课程代码、起始节或必需业务标识时不生成临时键，无法投影的数量由查询返回。课程序号缺失时键保留 null。完全相同的重复项只保留一条。相同键的内容、时间或状态相互冲突时，该键的全部条目均跳过，避免套用到错误的覆盖记录。丢弃的重复和冲突条目计入无法投影数量。

连堂排课按已知起止节次逐节展开，每节使用独立键，单节完成或隐藏只影响该节。结束节次缺失时只保留已知开始节次，结束时刻保持未知。节次范围展开超过 65,535 条返回 Capacity。缺字段或元数据错误的课程按原排课记录计数，重复和冲突按投影条目计数，避免逐节展开后的条目数掩盖其他课程缺字段的问题。

普通周元数据先复用 `CachedSemesterSchedule.normalized_weeks` 规范化带时间尾部和非补零日期。课程日期沿 `CachedSemesterSchedule.today` 与 Dart `homeWeekOn/homeProjectScheduleDay` 的规则：只在真实教学周日期覆盖内匹配实际星期，跨年按日期运算，周元数据重叠或重复时不任意选周。某周任一排课缺少合法星期时整周不投影，并报告无法投影数量。节次时间等价移植 Dart `scheduleSectionTimes`：前十四节固定采用 2026—2027 校历时间，第十五节起使用唯一接口边界，再后备唯一课程边界，冲突或结束不晚于开始时保留未知，并使用全天占位。`SchoolAgendaStatus::Schedule` 保留课程原始起止时间，包括研究生原始时间，详情可同时展示。

完整日程保留日期范围内已结束、已提交和已取消的公开记录，便于查看历史和本地重新挂起。`home_todo` 单独标记既有 Dart `buildHomeTodos` 的筛选结果：博雅仅排除严格早于现在的结束时间，研讨室排除结束时刻、取消和拒绝状态，SPOC 只保留已开始且未提交、未到期的摘要，希冀保留未提交或部分提交且未到期的摘要。签到仅使用当天快照，在开始前十分钟至结束前、上游明确未签到时标记。考试只处理已安排记录，严格晚于结束时间才排除，结束时间非法时沿既有规则按当天 23:59 判断。阳光沿现有第 11—14 周、每周少于 4 次、学期少于 16 次及三项本地设置筛选。部分阳光缓存不能把默认零当成完整统计；既有缓存保留的旧完整结果仍可使用。

学校条目按来源定义的 `sort_time` 稳定排序。普通来源使用开始时间或截止时间，博雅与研讨室仅有结束时刻时沿首页使用结束时刻。考试始终使用开始时间，开始未知时使用考试日期零点，即使结束时间已知也保持这一顺序。排序回退不写入 `AgendaTiming.start`，未知开始时间仍为 None。相同时刻依次沿博雅、SPOC、希冀、研讨室、签到、考试、阳光的来源顺序及响应顺序，课程放在这些来源之后。`AgendaTiming.is_soon_at(now)` 沿首页规则，只在截止或开始时间严格晚于现在且不超过 48 小时时返回 true；全天占位和仅有结束时间的时段不判定紧迫。缺失时刻的全天占位仅供日期展示，不表示学校声明全天事件。

`OfflineCache.query_agenda(&AgendaStore, &AgendaQuery)` 返回 `AgendaQueryResult { entries, sources }`。参数显式提供路线、课表/考试学期、日期范围、校园当前时间、阳光设置和 `include_hidden`（构造器默认为 false）。两个句柄的随机账号别名必须相同，已退出的任一仓库均拒绝查询。查询没有 `UbaaClient`，不会请求学校、刷新缓存或写入日程。既有只读缓存读取仍会维护访问时间。各来源独立读取，结果通过逐范围时间戳说明观察时刻，不承诺跨来源的同一事务快照。

`entries` 以 `AgendaEntryItem::Local(AgendaOccurrence)` 或 `School(SchoolAgendaItem)` 保存原始详情，共用 `completed/hidden/note` 及 `title()/timing()/sort_time()`。自建事项按原规则展开，学校条目按相同左闭右开日期范围筛选。时段按相交关系返回，只有一个端点时按该端点日期筛选，全天占位结束日期不包含在条目内。无日期自建待办每次返回。学校完成状态先读取上游：SPOC/希冀已提交、签到状态 1、博雅考勤通过 1 为完成，其余状态保守为未完成并保留原值。研讨室订单状态没有“完成”的现有映射，不从预约结束时间推断完成。随后叠加未删除的本地覆盖，`completion_override` 优先，隐藏默认过滤，清除覆盖恢复上游状态。自建条目与覆盖层在一次日程读取事务内合并。总条目及日期跨度沿用原查询上限。

`sources` 固定返回八个来源，每项包含已读取范围的 `observations`、缺失的 `missing_scopes`、无法投影数量，课表另有 `semester_imported`。每条观察保留实际取得时间、最近校验/尝试时间、尝试结果和完整性，`is_fresh(now, ttl_seconds)` 复用原缓存新鲜度条件，由宿主选择提示阈值。空列表与无缓存通过这些字段区分。未导入整学期时只投影有教学周元数据和周缓存的课程，并返回 `semester_imported = false`；完整导入后备用原有 `read_imported_schedule`，保留原学期、周的取得时间。零散周不会变成整学期导入证明。

SPOC 与阳光沿现有“当前选择”缓存指针读取。签到只读调用时的上海当天。希冀沿首页 `include_expired = false` 范围，因此历史日程无法补出此范围已过滤的作业。研讨室沿首页每页 20 条的零基分页，从第 0 页读取已知页，缺页逐项返回，超过 1,000 页返回 Capacity；其他分页尺寸的缓存不冒充该范围。完整日程只能显示已缓存的公开结果，缺失来源需要宿主在独立刷新流程中补齐。

## 无学校缓存查询与宿主生命周期

`AgendaStore.query_local_agenda(&AgendaQuery)` 返回仅自建事项的统一列表，允许学期为空。查询仍校验校园时间、日期范围、退出状态和展开限制。八个学校来源都返回空 `observations` 和空 `missing_scopes`，课表的 `semester_imported` 为 false，表示没有取得可用缓存观察，不代表上游没有事项。`OfflineCache.matches_agenda_account` 只比较本机别名，供 Bridge 在缓存降级前排除串号。

Bridge v44 的输入与输出、日程独立错误和 Dart 服务见 [Bridge 合同](flutter-bridge.md#v44独立本机日程通道)。宿主只依据安全索引中的已核实账号打开日程，不扫描目录、计算账号哈希、认领旧库或创建新别名绕过异常索引。日程不依赖业务缓存密钥。退出或换号关闭服务并拒绝迟到结果，同账号重新登录重新激活，Direct/WebVPN 共用日程。清理登录材料及学校缓存保留账号别名和原缓存密钥，不调用日程清除。

`AgendaService` 的所有持久写操作与打开、关闭共用串行尾链。关闭请求立即推进账号代次并撤销新访问，尚未交给后端的旧代次写操作在执行前返回 `superseded`。已经交给后端的写操作，包括尚在 Bridge 队列或预处理阶段的调用，可以在关闭等待期间提交或失败；服务等待后端返回，再停用持久库。后续打开必须等待上述收尾，因此关闭完成后旧写入不能借同账号重登继续修改数据。已进入 SQLite 事务的操作按原事务提交或回滚。写入失败不阻断关闭和后续打开，也不自动重试。调用方收到 `superseded` 时不能据此推断该写入没有在关闭完成前提交。

读取不加入写入尾链，挂起查询不会阻塞关闭，迟到结果继续按代次拒绝。退出时日程关闭与安全索引禁止自动恢复独立启动，索引关闭不等待写入收尾。后端重建先等待旧日程关闭，再建立继任服务；销毁永久拒绝再次打开。以上顺序只约束由同一生产服务管理的操作，直接使用 Core/Bridge 的调用方仍须自行保证停用与重新激活之间没有未收尾写入。

## 首页学校待办

`HomeAgendaRead` 按来源接收已经取得的公开读字段，`project_home_agenda(reads, context, agenda)` 复用学校投影规则。参数不包含缓存取得时间，因此无法把内存结果伪装成新的持久缓存观察。在线、缓存和部分来源均可独立投影，来源缺失与读取错误继续由原首页快照报告。

没有覆盖时保留原七来源的首页行为。有明确完成覆盖时移除条目，有隐藏覆盖时隐藏条目。显式重新挂起 SPOC/希冀已提交记录时，保留学校原状态并显示本地待办，同时继续检查开始/截止条件。清除覆盖恢复学校规则。首页查询不展开自建事项，也不混入课表条目。

生产接线、打开等待与签到资格规则见 [Bridge v45](flutter-bridge.md#v45首页统一本地投影)。日程关闭和持久写入尾链沿用上一节顺序。

## RFC 5545 范围快照导出

`AgendaStore.export_local_ics(&AgendaExportOptions)` 仅导出已打开账号的本机日程，不需要缓存密钥。参数包含校园日期范围 `from/to`、生成时间 `generated_at`、`include_hidden` 和 `include_completed`，两个筛选均须由宿主明确指定。`OfflineCache.export_agenda_ics(&AgendaStore, &AgendaQuery, include_completed)` 只读取同随机账号别名、指定路线的既有缓存，返回 `AgendaCachedExportResult { snapshot, sources }`。账号不符直接拒绝。`sources` 与同参数 `query_agenda` 的逐来源缺口、完整性和时间语义相同，过期数据保留其观察时间，由宿主使用 `is_fresh` 明示。导出不会验证会话、刷新来源或在缓存错误后静默交付仅本机内容。

`AgendaExportResult` 返回 `ics`、`exported_count` 与 `skipped_unknown_time_count`。展开、覆盖、完成和自建记录修改时间来自同一次日程只读事务。学校缓存仍沿既有逐范围读取方式，不声明跨所有缓存范围的数据库原子快照。文件内容是 `[from,to)` 相交查询结果的快照：保留相交事件的完整起止时间，无日期自建待办始终包含。重复事项先经 Core 展开，每次发生形成独立组件，不输出 RRULE、EXDATE 或标准 RECURRENCE-ID，也不承诺导入后恢复可编辑重复系列。

| 数据 | RFC 5545 表达 |
|---|---|
| 起止明确的时段事件 | VEVENT，DTSTART 与 DTEND 使用等价 UTC 时刻。 |
| 自建全天事件 | VEVENT，DTSTART/DTEND 均为 DATE，结束日期排他。 |
| 有截止时间的待办 | VTODO，仅 DUE，不补造 DTSTART。 |
| 无日期自建待办 | VTODO，省略 DTSTART 与 DUE。 |
| 学校时段缺任一端点、日期占位或无日期未知项 | 跳过并计入 `skipped_unknown_time_count`，不把排序回退或日期占位导出为真实时间。 |
| 待办完成状态 | STATUS 为 COMPLETED 或 NEEDS-ACTION。已完成时写 PERCENT-COMPLETE=100，仅在确有生效本地完成时刻时写 UTC COMPLETED。 |
| 事件本地完成与隐藏 | 使用 X-UBAA-COMPLETED/X-UBAA-HIDDEN，不为 VEVENT 写非法的 COMPLETED 状态。 |

UID 使用编码元组的 SHA-256 摘要。自建来源编码 UUID 和原始发生键，单次移动后 UID 保持不变；学校来源编码随机账号别名、来源和上游稳定键。同一账号库重复导出和改变范围保持 UID，不同来源或发生互相区分。导出器不额外写入学号、会话、缓存密钥或原始上游标识。用户标题、地点和备注仍按选择的事项导出。随机别名不同的宿主不承诺相同学校 UID。

每个组件显式写生成时刻 DTSTAMP。自建组件写入真实 CREATED/LAST-MODIFIED，学校组件不补造上游修改或完成时刻。X-UBAA-UPSTREAM-COMPLETED 保留学校完成事实，本地重新挂起只影响导出状态。X-UBAA-OVERLAY-MODIFIED 表示本地覆盖时间，X-UBAA-RECURRENCE-ID 保留自建原始发生键；这些扩展字段仅提供快照信息，不构成导入或双向同步协议。VCALENDAR 的 X-UBAA-EXPORT-MODE=RANGE-SNAPSHOT、X-UBAA-RANGE-FROM/TO 和 X-UBAA-TIMEZONE=Asia/Shanghai 明示范围与校园时区。实际 DATE-TIME 使用 UTC，因此不需要猜造 VTIMEZONE 的历史转换规则。

序列化使用精确锁定的 `icalendar 0.17.17`。生产关闭默认 parser/recurrence，测试启用 parser 并断言解析后的实际时刻、类型、状态、UID 与文本。TEXT 转义反斜杠、逗号、分号、换行，CRLF 输入规范化为换行，其他控制字符拒绝。物理行使用 CRLF，并按最多 75 个 UTF-8 字节折行。输出大小上限为 32 MiB，逐组件写入内存缓冲，超限返回 Capacity，整个调用不返回半份正文。Core 不创建导出文件，路径校验、覆盖确认与原子文件交付由后续宿主实现。

已观察到的性能限制：icalendar 0.17.17 的折行实现对很长的 UTF-8 属性反复按字符查找位置，批量接近字段上限的中文备注导出耗时较高。合成的 600 次重复、每次约 63 KiB 备注压力用例使本机未优化日程聚焦测试耗时 937 秒、完整 Core 测试耗时 931 秒，其余普通断言很快完成。此结果没有优化构建的对照，不能据此估算正式产物耗时。32 MiB 预算只限制输出大小，不提供 CPU 时间上限；本期未增加超时或更换上游折行实现。普通中文长行、内容完整性和超限错误分别由回归验证。

## CLI 命令与输入模型（方案 A 已选定，待实施）

主聊天已选定 CLI 独立安全材料方案 A，由后续新会话实施。当前 `ubaa` 尚无 agenda 命令，下表是待实现接口设计。生产 CLI 只有 `--config-dir` 与会话入口，没有可离线恢复的已核实账号登记。现有会话文件不持久化账号身份，普通 `auth_status` 会请求学校。不能从用户名参数或裸别名打开日程，也不能通过读取 Flutter 安全索引或扫描库寻找账号。证据、备选和停止位置见[账号接线决定](../migration/decision-log.md#2026-11-01日程-cli-独立安全材料方案-a-已选定)。

| 拟定命令 | 参数与行为 |
|---|---|
| `agenda list` | 必填 `--from YYYY-MM-DD --to YYYY-MM-DD`；默认仅本机。显式 `--school-cache --route direct/webvpn --term TERM` 才合并同账号缓存，输出逐来源缺失/过期信息。 |
| `agenda show --id UUID` | 返回本机原始事项与删除标记，不能通过学校键读取其他账号。 |
| `agenda create --input FILE`、`agenda edit --id UUID --scope this/this-and-future/all --input FILE` | `--input -` 读取 stdin，typed 输入只含可编辑内容与 rrule，创建额外允许 exdates，拒绝未知字段。修改完整替换可编辑内容；仅此次/此次及以后必填原始 `--at RFC3339`。 |
| `agenda delete --id UUID --scope this/this-and-future/all` | 重复删除范围必填，发生操作使用原始 `--at`。 |
| `agenda complete --id UUID --at RFC3339`、`agenda reopen` | 按原发生完成/取消完成，无日期待办显式 `--undated`，与 `--at` 互斥。 |
| `agenda overlay set --source SOURCE --upstream-id ID` | `--completion complete/reopen/inherit`、`--hidden true/false`、`--note-file FILE` 修改本机覆盖，不调用学校写入。 |
| `agenda overlay clear --source SOURCE --upstream-id ID` | 清除覆盖并保留 Core 删除标记。 |
| `agenda unsynced`、`agenda clear` | 前者返回未同步记录数；后者默认先显示数量并拒绝，显式确认和 `--expected-unsynced N` 与当前数量匹配才清除。需要新增 Core 原子比较并清除能力，不能只在 CLI 查询后无条件清空。 |
| `agenda export` | 同 list 的范围与缓存参数，必选 `--output FILE` 或 `--stdout`。文件默认拒绝覆盖，显式 `--overwrite` 才原子替换普通文件；JSON 与 `--stdout` 互斥。成功 JSON 只返回计数、范围、交付类型与缓存观察，不混入正文或日志。 |

所有本机修改要求明确的 `--confirm-local-write`，其确认文案写明“本机日程”，不使用 Direct 学校写入的路由元数据。输入模型应为独立 `deny_unknown_fields` DTO：`kind/title/location/notes/color/start/end/all_day/due/rrule`，创建输入额外允许 exdates。编辑沿 Core 的范围操作保留或重映射例外，不接收内部 exdates/overrides/completions 映射。两个输入均不接受 id、locally_modified、会话或存储配置。日期时间通过明确偏移量转换为校园时刻。接口落地时新增 local envelope，`meta.feature=agenda`、本机操作标识及账号状态，无伪造 resolvedRoute；版本随最终公开字段兼容性决策。本次 CLI schema v12、Bridge v45、日程 v2 和缓存 v7 均保持。

暂不提供 sync。二进制 CRUD/退出/切号/坏缓存/确认/原子文件输出验收随账号方案实施，当前没有可用 CLI 示例；上述命令不能作为已实现功能调用。

后续账号接线按 `--config-dir` 的独立安全材料作用域登记，只能由显式成功登录的核实 profile/Core 身份能力建立映射，账号/路线/会话冲突均拒绝。旧会话未登记时要求显式登录，不自动校验学校状态。同账号跨路线复用随机别名，退出撤销活动选择且保留日程与映射。新材料丢失或不可用时失败关闭并保留原文件，不另造别名，不访问 Flutter 安全材料。日程操作、登记、退出和切号关键段必须有跨进程共享作用域锁或等价原子关联，以阻止旧操作借后续激活重新生效。安全材料只管理身份与必要密钥，日程正文仍为明文。这些条件尚未实现，平台覆盖须按后续实际提供者分别验收。
