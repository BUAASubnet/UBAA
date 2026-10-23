# 决策索引

现行目录与模块规则见 [ADR 0006](../adr/0006-explicit-dart-modules.md)，任务边界见 [goal.md](../../goal.md)。以下条目是历史入口，不重新声明当前完成状态。

## 2026-10-23：SPOC默认仅显示未提交

按用户最新要求，SPOC“仅显示未提交”默认开启，覆盖冻结旧版的默认关闭设置。保留隐藏已截止、截止时间升序及两个过滤条件独立组合；用户关闭未提交条件后可查看其他状态，全程本地筛选。调整既有规则及Widget测试，先验证原默认仍展示已提交的失败反例，再修改默认值；原生合成用例查看已提交目标前显式关闭条件，不删除原有导航覆盖。13项聚焦回归、完整Rust/Shell、七包1332项Flutter测试及FRB零漂移通过，macOS重建后实际确认默认只显示未提交作业。

## 2026-10-23：移除作业卡片悬停文字

按用户要求移除 SPOC/希冀共享 `AssignmentCard` 外层的“查看作业详情”Tooltip，保留 InkWell 背景反馈及原typed点击导航。纯展示修改，复用既有19项展示/导航聚焦测试；测试和原生合成脚本改为定位卡片，不再依赖提示文案，没有增加文案缺席或Widget数量断言。完整Rust/Shell、七包1332项Flutter测试及分析、FRB零漂移通过。macOS Debug已重建并打开，截图不纳入仓库。

## 2026-10-23：SPOC本地筛选与旧版对齐

SPOC与希冀共用日期、搜索、排序及Material控件，显式保留默认状态和开关联动差异。SPOC默认不限制提交状态，未提交与已截止条件独立，不新增网络筛选或历史读取。移除手输编号查询入口并改为按课程连续展示，来源和覆盖替换见[实施记录](spoc-list-filters-2026-10-23.md)。

## 2026-10-23：希冀列表恢复旧版展示筛选

默认仅未完成、隐藏已截止、截止时间升序，按课程连续展示。删除批量选择和手输查询面板；搜索、排序与状态筛选均在本地完成。历史范围通过独立按钮显式加载，避免反复切换筛选触发读取。来源、覆盖替换与当前验证见[实施记录](judge-list-filters-2026-10-23.md)。

## 2026-10-15：按行为价值整理测试与执行范围

按用户授权删除自证和重复断言，合并场景时保留独立安全断言；视觉基准按真实布局选代表。日常检查按改动及本地依赖传播，未知情况全量；CI 完整确定性门禁保留。Core 默认配置维持编译/文档和关闭态边界，共享单元只执行一次。具体删减映射和反例见[整理记录](test-value-cleanup-2026-10-15.md)。

## 2026-10-15：全界面文字与信息密度整理

按用户授权删除重复介绍、操作复述与开发术语，必要状态和操作后果使用短句，诊断改为按需展开。保留控制行为及协议，界面投影只改显示名。详见[本轮记录](ui-copy-cleanup-2026-10-15.md)。

## 2026-10-14：登录界面说明精简

按用户当前 macOS 界面检查反馈，删除“密码仅保存在系统安全存储；自动登录决定是否自动使用已保存密码。”与连接模式菜单顶部“尚未读取；这里设置登录与后续查询的默认策略。”。保留选项、路线选择和安全存储不可用时的状态提示。本次仅修改展示，不涉及认证协议、读取行为或冻结来源裁决。

复用既有登录回归用例，将说明断言改为不显示；修改实现前运行该用例，因密码说明仍存在而按预期失败。实现后同文件 6 项测试通过，同步更新原生合成流程的旧说明断言（本轮未运行原生合成流程）。`just refs`、`just check-sensitive`、`just check` 和 macOS Debug 构建通过；完整门禁首次因本机固定开发工具缺失退出，显式执行 `just quality-tools-bootstrap` 后重跑通过。更新后的应用已沿用本次独立配置目录重新启动，界面由用户继续检查。

## 2026-10-07：独立工程审查后的边界修复

用户已授权按[独立审查](engineering-quality-independent-review-2026-10-07.md)完整修复。先将确定性反例纳入正式测试，再处理原子路线、认证完成/迟到状态、损坏偏好和验证工具；保留公开数据语义、唯一写协调器与原工作树。真实账号验证和发布不属于本轮范围，详见[当前合同](../../goal.md)。来源裁决与最终结果分别在本轮专项矩阵和实施记录中登记。

## 2026-10-07：可持续开发性审查

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-10-07可持续开发性审查)

## 2026-09-17 安全材料和缓存密钥接线

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-17-安全材料和缓存密钥接线)

## 2026-09-17 所需路线恢复边界

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-17-所需路线恢复边界)

## 决策记录

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#决策记录)

## 2026-09-17：围绕用户任务设计本地首页与立即恢复登录

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-17围绕用户任务设计本地首页与立即恢复登录)

## 2026-09-17：首页按展示来源加载

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-17首页按展示来源加载)

## 2026-09-17：冻结 buaa-api 引用更新至最新上游

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-17冻结-buaa-api-引用更新至最新上游)

## 2026-09-17 课堂签到追加修复

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-17-课堂签到追加修复)

## 2026-09-17：整理时校正签到历史描述

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-17整理时校正签到历史描述)

## 2026-09-17：冻结旧版引用更新至最新上游并收纳至 examples/

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-17冻结旧版引用更新至最新上游并收纳至-examples)

## 2026-09-07：贯通安全错误诊断并保持既有业务权威

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-07贯通安全错误诊断并保持既有业务权威)

## 2026-09-07：修复 macOS 沙箱主动联网权限

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-07修复-macos-沙箱主动联网权限)

## 2026-09-05：将既有视觉基线的宿主条件显式纳入 CI

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-05将既有视觉基线的宿主条件显式纳入-ci)

## 2026-09-05：Just dry-run 输出通道的版本兼容性

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-05just-dry-run-输出通道的版本兼容性)

## 2026-09-05：固定 Flutter 冷启动下载进度的输出合同

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-05固定-flutter-冷启动下载进度的输出合同)

## 2026-09-05：最终候选 CI 的工具链输出与 Windows 文件身份问题

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-05最终候选-ci-的工具链输出与-windows-文件身份问题)

## 2026-09-05：Phase 12 UI 机械拆分与 Core 入口归属

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-05phase-12-ui-机械拆分与-core-入口归属)

## 2026-09-05：Phase 11K 单一写入状态与会话生命周期所有权

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-05phase-11k-单一写入状态与会话生命周期所有权)

## 2026-09-05：Phase 11J 评教 fresh typed 批量提交与逐课程结果边界（来源合同已固定）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-05phase-11j-评教-fresh-typed-批量提交与逐课程结果边界来源合同已固定)

## 2026-09-05：Phase 11I 阳光打卡 typed 资格与单次最终提交边界（本地确定性门禁完成）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-05phase-11i-阳光打卡-typed-资格与单次最终提交边界本地确定性门禁完成)

## 2026-09-04：Phase 11H 场馆取消双 fresh authority 与最终单次发送边界（当前有效）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-04phase-11h-场馆取消双-fresh-authority-与最终单次发送边界当前有效)

## 2026-09-04：Phase 11G 场馆预约 typed 资格与最终单次发送边界（当前有效）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-04phase-11g-场馆预约-typed-资格与最终单次发送边界当前有效)

## 2026-09-04：Phase 11F 图书馆取消 typed 资格与单次发送边界（当前有效）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-04phase-11f-图书馆取消-typed-资格与单次发送边界当前有效)

## 2026-09-04：Phase 11E 图书馆预约 typed 资格与发送边界（当前有效）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-04phase-11e-图书馆预约-typed-资格与发送边界当前有效)

## 2026-09-04：Phase 11D 课堂签到 typed 资格与发送边界（当前有效）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-04phase-11d-课堂签到-typed-资格与发送边界当前有效)

## 2026-09-04：CLI JSON envelope 显式升级为 schema v3（Phase 11C 历史决策；已由 v4 取代）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-04cli-json-envelope-显式升级为-schema-v3phase-11c-历史决策已由-v4-取代)

## 2026-09-03：Phase 11 typed 写资格的来源边界（当前有效）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-03phase-11-typed-写资格的来源边界当前有效)

## 2026-09-02：MethodChannel 平台能力合同（当前有效）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-02methodchannel-平台能力合同当前有效)

## 2026-09-02：无签名平台能力边界与宿主全功能 smoke（当前有效）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-02无签名平台能力边界与宿主全功能-smoke当前有效)

## 2026-09-02：无签名执行目标取代正式发布门禁（当前有效）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-02无签名执行目标取代正式发布门禁当前有效)

## 当前有效性说明（2026-08-31）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#当前有效性说明2026-08-31)

## 2026-08-31：Cgyy WebVPN 网关 Cookie 同步证据

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-31cgyy-webvpn-网关-cookie-同步证据)

## 2026-08-31：HAR 修复后的 Cgyy 双路线重跑（历史快照）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-31har-修复后的-cgyy-双路线重跑历史快照)

## 2026-08-31：最新 Core-live 实时复核处于图书馆非营业时间

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-31最新-core-live-实时复核处于图书馆非营业时间)

## 2026-08-31：Cgyy 路线与 Core-live 真实验证边界校正

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-31cgyy-路线与-core-live-真实验证边界校正)

## 2026-08-29：用户授权 Cgyy Rust CLI 读写探针及提交落库时序

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29用户授权-cgyy-rust-cli-读写探针及提交落库时序)

## 2026-08-29：继续对齐 Cgyy 业务会话、信封和 Direct 路由

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29继续对齐-cgyy-业务会话信封和-direct-路由)

## 2026-08-17 至 2026-08-29：已归档历史决策摘要

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-17-至-2026-08-29已归档历史决策摘要)

## 2026-08-28：场馆预约的 WebVPN 策略必须保留直连业务域（已被 2026-08-31 决策取代）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-28场馆预约的-webvpn-策略必须保留直连业务域已被-2026-08-31-决策取代)

## 2026-08-28 Cgyy 门锁码实时证据

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-28-cgyy-门锁码实时证据)

## 2026-08-28 WebVPN 全量只读证据

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-28-webvpn-全量只读证据)

## 2026-08-29 全量只读复测

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-全量只读复测)

## 2026-08-29 Cgyy 单项复测

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-cgyy-单项复测)

## 2026-08-28 Cgyy WebVPN 路线冲突

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-28-cgyy-webvpn-路线冲突)

## 2026-08-28 Cgyy 直连 URL 复测

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-28-cgyy-直连-url-复测)

## 2026-08-28 只读矩阵复测

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-28-只读矩阵复测)

## 2026-08-28 WebVPN 逐项复测

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-28-webvpn-逐项复测)

## 2026-08-29 逐操作验证器扩展与三路线复测

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-逐操作验证器扩展与三路线复测)

## 2026-08-29 用户独立只读验收

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-用户独立只读验收)

## 2026-08-29 Bykc 已选课程包装修复

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-bykc-已选课程包装修复)

## 2026-08-29 Bykc 修复后全量实时矩阵

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-bykc-修复后全量实时矩阵)

## 2026-08-29 Direct Judge/Cgyy 单项复测

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-direct-judgecgyy-单项复测)

## 2026-08-29 WebVPN Cgyy 直连业务 transport 复测

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-webvpn-cgyy-直连业务-transport-复测)

## 2026-08-29 Judge 路线复测更新

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-judge-路线复测更新)

## 2026-08-29 Direct Judge/Cgyy 复测收敛

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-direct-judgecgyy-复测收敛)

## 2026-08-29 Cgyy 验证器逐操作不中断

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-cgyy-验证器逐操作不中断)

## 2026-08-29 Cgyy 三路线逐操作复测

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-cgyy-三路线逐操作复测)

## 2026-08-29 Cgyy 日期窗口排除复测

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-cgyy-日期窗口排除复测)

## 2026-08-29 锁码 CLI 脱敏边界

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-锁码-cli-脱敏边界)

## 2026-08-29 Cgyy 最新三路线波动

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-cgyy-最新三路线波动)

## 2026-08-29 锁码投影后三路线复测

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-锁码投影后三路线复测)

## 2026-08-29 三路线全量复测更新

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-三路线全量复测更新)

## 2026-08-29 当前轮三路线全量验收

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-当前轮三路线全量验收)

## 2026-08-29 Cgyy 用途类型回退修复

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-cgyy-用途类型回退修复)

## 2026-08-29 Cgyy 回退后 Direct 全量复测

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-cgyy-回退后-direct-全量复测)

## 2026-08-29 Cgyy 回退后 WebVPN/auto 全量复测

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-cgyy-回退后-webvpnauto-全量复测)

## 2026-08-29 用途回退后 WebVPN/auto 全量复测

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-用途回退后-webvpnauto-全量复测)

## 2026-08-29 Cgyy 成功信封代码严格校验

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-cgyy-成功信封代码严格校验)

## 2026-08-29 Cgyy 日期槽位排序

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-cgyy-日期槽位排序)

## 2026-08-29 Cgyy 三路线逐操作复测（二）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-cgyy-三路线逐操作复测二)

## 2026-08-29 三路线全量只读复测

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-三路线全量只读复测)

## 2026-08-29 Cgyy 场馆包装展开

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-cgyy-场馆包装展开)

## 2026-08-29 LibBook 座位排序

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-libbook-座位排序)

## 2026-08-29 LibBook 预约总数回退

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-libbook-预约总数回退)

## 2026-08-29 LibBook 分区编号回退

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-libbook-分区编号回退)

## 2026-08-29 Bykc 签到配置严格解析

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-bykc-签到配置严格解析)

## 2026-08-29 Ygdk 记录时间戳

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-ygdk-记录时间戳)

## 2026-08-29 Ygdk 记录图片字段

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-ygdk-记录图片字段)

## 2026-08-29 Ygdk 数字字符串时间戳

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-ygdk-数字字符串时间戳)

## 2026-08-29 LibBook 原语字段兼容

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-libbook-原语字段兼容)

## 2026-08-29 三路线全量只读复测（二）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-三路线全量只读复测二)

## 2026-08-29 Cgyy 原语字段兼容

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-cgyy-原语字段兼容)

## 2026-08-29 Signin 写响应状态兼容

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-signin-写响应状态兼容)

## 2026-08-29 Evaluation 任务 `yhdm` 身份来源

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-evaluation-任务-yhdm-身份来源)

## 2026-08-29 Ygdk 文本原语

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-ygdk-文本原语)

## 2026-08-29 Evaluation 文本原语

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-evaluation-文本原语)

## 2026-08-29 三路线逐操作实时证据

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-三路线逐操作实时证据)

## 2026-08-29 认证资料持久化冲突

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-认证资料持久化冲突)

## 2026-08-29 三路线逐操作实时复测（认证领域拆分后）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-三路线逐操作实时复测认证领域拆分后)

## 2026-08-29 认证领域拆分后实时只读矩阵

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-认证领域拆分后实时只读矩阵)

## 2026-08-29 Direct 全量验证的聚合登录边界

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-direct-全量验证的聚合登录边界)

## 2026-08-29 WebVPN/auto 全量实时复测

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-08-29-webvpnauto-全量实时复测)

## 2026-09-03 Ygdk 路线状态失效代数

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-03-ygdk-路线状态失效代数)

## 2026-09-03 Ygdk OAuth 跳转主机约束冲突

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-03-ygdk-oauth-跳转主机约束冲突)

## 2026-09-03 Bykc 认证失效重试差异

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-03-bykc-认证失效重试差异)

## 2026-09-08 全功能 UI/UX 重设计执行合同

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-08-全功能-uiux-重设计执行合同)

## 2026-09-08 UI/UX 执行阶段的设计与证据裁决

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-08-uiux-执行阶段的设计与证据裁决)

## 2026-09-08：P3B 原生方向与系统键盘证据

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-08p3b-原生方向与系统键盘证据)

## 2026-09-08：B1 读取归属与学业信息层级

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-08b1-读取归属与学业信息层级)

## 2026-09-08：B2 查询选项隔离与主要信息同时可见

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-08b2-查询选项隔离与主要信息同时可见)

## 2026-09-08：统一账号资料保真与默认遮罩设计（待P4-A实施）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-08统一账号资料保真与默认遮罩设计待p4-a实施)

## 2026-09-08：P4-A 资料本地状态与清除确认生命周期

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-08p4-a-资料本地状态与清除确认生命周期)

## 2026-09-08：P4-C 课程归属、全局进度与选择状态

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-08p4-c-课程归属全局进度与选择状态)

## 2026-09-08：按用户要求以旧版UI为优化基准

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-08按用户要求以旧版ui为优化基准)

## 2026-09-08 O1/O2 旧版导航与按需查询

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-08-o1o2-旧版导航与按需查询)

## 2026-09-09 O3-E1考试时间线与签到横卡

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-09-o3-e1考试时间线与签到横卡)

## 2026-09-09：O3-E2a成绩继承与缓存边界

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-09o3-e2a成绩继承与缓存边界)

## 2026-09-09 O3-E2b：成绩变化派生基线与旧首页横幅

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-09-o3-e2b成绩变化派生基线与旧首页横幅)

## 2026-09-09 O3-D1c：不将可空父字段当只读导航资格

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-09-o3-d1c不将可空父字段当只读导航资格)

## 2026-09-09 O3-E3a：恢复旧空教室表格和查询能力

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-09-o3-e3a恢复旧空教室表格和查询能力)

## E3b课表布局决定（2026-09-09，实施前）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#e3b课表布局决定2026-09-09实施前)

## O3-E3b局部终态（2026-09-09）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#o3-e3b局部终态2026-09-09)

## E3c自然周次入口决定（2026-09-09，实施前）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#e3c自然周次入口决定2026-09-09实施前)

## E3c 验收裁决（2026-09-09）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#e3c-验收裁决2026-09-09)

## E4 登录与账号复核（2026-09-09）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#e4-登录与账号复核2026-09-09)

## P5-A 统一确认的交互裁决（2026-09-09）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#p5-a-统一确认的交互裁决2026-09-09)

## P5-B 研讨室表单裁决

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#p5-b-研讨室表单裁决)

## P5-D 阳光独立表单实施前核对（2026-09-10）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#p5-d-阳光独立表单实施前核对2026-09-10)

## P4-E5 关于入口实施前核对（2026-09-10）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#p4-e5-关于入口实施前核对2026-09-10)

## P5-F Android旧版拍照恢复前核对（2026-09-12）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#p5-f-android旧版拍照恢复前核对2026-09-12)

## 暂停目标并保存工作区（2026-09-14）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#暂停目标并保存工作区2026-09-14)

## UI验收媒体改为仓库外保存（2026-09-14）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#ui验收媒体改为仓库外保存2026-09-14)

## 2026-09-21：离线首页缓存分阶段接入与 Bridge v10/v11

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-21离线首页缓存分阶段接入与-bridge-v10v11)

## 2026-09-22：持久渐进读取与共享锁调度边界

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22持久渐进读取与共享锁调度边界)

## 2026-09-22：按目标调度恢复与一次性只读计划重建

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22按目标调度恢复与一次性只读计划重建)

## 2026-09-22：精确查询缓存不等待认证

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22精确查询缓存不等待认证)

## 2026-09-22：学业持久范围与发布错误优先级

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22学业持久范围与发布错误优先级)

## 2026-09-22：学业缓存展示与出分观察分离

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22学业缓存展示与出分观察分离)

## 2026-09-22：首页待办持久 DTO 与可选读取完成信息

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22首页待办持久-dto-与可选读取完成信息)

## 离线首页 P4-E：展示证据与实时操作分离（2026-09-22）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页-p4-e展示证据与实时操作分离2026-09-22)

## 离线首页 P4-F：博雅安全持久投影（2026-09-22）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页-p4-f博雅安全持久投影2026-09-22)

## 离线首页 P4-G：博雅补充来源与写后回读分流（2026-09-22）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页-p4-g博雅补充来源与写后回读分流2026-09-22)

## 离线首页审查修正：禁止缓存 DTO 绕过 Bridge 白名单（2026-09-22）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页审查修正禁止缓存-dto-绕过-bridge-白名单2026-09-22)

## 离线首页 P4-H：研讨室兼容回退不是完整更新（2026-09-22）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页-p4-h研讨室兼容回退不是完整更新2026-09-22)

## 离线首页 P4-I：研讨室部分结果、缓存页面与回读边界（2026-09-22）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页-p4-i研讨室部分结果缓存页面与回读边界2026-09-22)

## 离线首页 P4-J：图书馆兼容空值不等于完整刷新（2026-09-22）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页-p4-j图书馆兼容空值不等于完整刷新2026-09-22)

## 离线首页 P4-K：图书馆持久展示与实时资格分流（2026-09-22）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页-p4-k图书馆持久展示与实时资格分流2026-09-22)

## 离线首页 P4-L：保存拒绝与展示拒绝必须分别成立（2026-09-22）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页-p4-l保存拒绝与展示拒绝必须分别成立2026-09-22)

## 离线首页 P4-M：评教容错结果与完整快照分开（2026-09-22）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页-p4-m评教容错结果与完整快照分开2026-09-22)

## 离线首页 P4-N：评教进度与提交资格分别恢复（2026-09-22）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页-p4-n评教进度与提交资格分别恢复2026-09-22)

## 离线首页 P4-O：阳光分类与分页必须同时归属（2026-09-22）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页-p4-o阳光分类与分页必须同时归属2026-09-22)

## 离线首页 P4-P：概览统计与记录页分开取证（2026-09-22）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页-p4-p概览统计与记录页分开取证2026-09-22)

## 离线首页 P4-Q：资料展示缓存不等于认证身份（2026-09-22）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页-p4-q资料展示缓存不等于认证身份2026-09-22)

## 离线首页 P4-R：展示副本不替代身份，页面归属不使用遮罩文本（2026-09-22）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页-p4-r展示副本不替代身份页面归属不使用遮罩文本2026-09-22)

## 离线首页 P4-S：清理必须终止旧读取链的重新取票（2026-09-22）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页-p4-s清理必须终止旧读取链的重新取票2026-09-22)

## 2026-09-22 P4-T：管理句柄移交与宿主调用链代际

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22-p4-t管理句柄移交与宿主调用链代际)

## 2026-09-22 P4-U：仅清理缓存不复用退出流程

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22-p4-u仅清理缓存不复用退出流程)

## 2026-09-22 P4-V：压力时动态保留，而非永久发布优先级

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22-p4-v压力时动态保留而非永久发布优先级)

## 2026-09-22 P4-W：显式重建与数据库身份隔离

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22-p4-w显式重建与数据库身份隔离)

## 2026-09-22 P4-X：统计集合先交付本地，更新结果另行完成

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22-p4-x统计集合先交付本地更新结果另行完成)

## 2026-09-22 P2-F：账号库打开不使用页面读取代次

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22-p2-f账号库打开不使用页面读取代次)

## 2026-09-22 P4-Y：完整导入独立保留与schema v4

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22-p4-y完整导入独立保留与schema-v4)

## 2026-09-22 P4-Z：逐学期租约与单周读取修订

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22-p4-z逐学期租约与单周读取修订)

## 2026-09-22 P2-G：辅助读同样承担账号冲突关闭责任

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22-p2-g辅助读同样承担账号冲突关闭责任)

## 2026-09-22：P4-AA 整学期导入接入 Bridge 与课表页

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22p4-aa-整学期导入接入-bridge-与课表页)

## 2026-09-22：P4-AB 本地课表索引与日期导航

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22p4-ab-本地课表索引与日期导航)

## 2026-09-22：P4-AC Core关联范围失效与schema v5

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22p4-ac-core关联范围失效与schema-v5)

## 2026-09-22：P4-AD 写提交结果与本地失效分列

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22p4-ad-写提交结果与本地失效分列)

## 2026-09-22：P4-AE 阳光已观察学期与周期隔离

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22p4-ae-阳光已观察学期与周期隔离)

## 2026-09-22：P2-H 前台恢复退避与网络变化提示

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22p2-h-前台恢复退避与网络变化提示)

## 2026-09-22：P2-I 无持久缓存希冀在线计划

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22p2-i-无持久缓存希冀在线计划)

## 2026-09-22：P2-J 无缓存分段生产接线与Bridge v29

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22p2-j-无缓存分段生产接线与bridge-v29)

## 2026-09-22：P5-A 真实App功能证据与性能口径

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22p5-a-真实app功能证据与性能口径)

## 2026-09-22 P2-N 评教真实只读失败分类

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-22-p2-n-评教真实只读失败分类)

## 2026-09-23：接续离线首页P2-P与当前候选证据

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-23接续离线首页p2-p与当前候选证据)

## 2026-09-23：部分在线计划的内容稳定性

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-23部分在线计划的内容稳定性)

## 2026-09-23：明确批量详情复用独立持久范围

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-23明确批量详情复用独立持久范围)

## 2026-09-23：只在客户端明确失效时原位替换

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-23只在客户端明确失效时原位替换)

## 2026-09-23：未知结果仅保存最小核对提示

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-23未知结果仅保存最小核对提示)

## 离线首页 P5-B1：原生 iOS 空环境目录修复（2026-09-23）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#离线首页-p5-b1原生-ios-空环境目录修复2026-09-23)

## 2026-09-23：P2-S 分段计划复用希冀激活，P5-B 保留失败样本

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-23p2-s-分段计划复用希冀激活p5-b-保留失败样本)

## 2026-09-23：原生日期矩阵的显式时钟装配

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-23原生日期矩阵的显式时钟装配)

## 2026-09-23：P2-T按可见性恢复及严格区分验收范围

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-23p2-t按可见性恢复及严格区分验收范围)

## 2026-09-23：P2-U自动读取按需让位，主动查询共享完整观察

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-23p2-u自动读取按需让位主动查询共享完整观察)

## 2026-09-23：P4-AH将成绩变化基线纳入加密仓库

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-23p4-ah将成绩变化基线纳入加密仓库)

## 2026-09-23：P4-AI 退出保护覆盖本地偏好清理

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-23p4-ai-退出保护覆盖本地偏好清理)

## 2026-09-24：P5-B2完整首页与阶段成本测量边界

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-24p5-b2完整首页与阶段成本测量边界)

## 2026-09-24：P5-B2正式轮次裁决

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-24p5-b2正式轮次裁决)

## 2026-09-24：P2-R显式重建本地首页恢复核对（实施前）

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-24p2-r显式重建本地首页恢复核对实施前)

## 2026-10-01：整合现有成果并恢复旧版功能验收

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-10-01整合现有成果并恢复旧版功能验收)

## 2026-09-15：恢复macOS逐按钮核对与安全凭据接线

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-15恢复macos逐按钮核对与安全凭据接线)

## 2026-09-15：完整旧版功能需要的只读接口补齐

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-15完整旧版功能需要的只读接口补齐)

## 2026-09-15：验证码与门锁信息的独立短期显示

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-15验证码与门锁信息的独立短期显示)

## 2026-09-15：博雅完整详情和筛选生命周期

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-09-15博雅完整详情和筛选生命周期)

## 整合行为裁决与失败回归

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#整合行为裁决与失败回归)

## 2026-10-02：设置真实能力与最新路线选择

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-10-02设置真实能力与最新路线选择)

## 2026-10-02：交互验证码接入当前离线生命周期

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-10-02交互验证码接入当前离线生命周期)

## 2026-10-02：门锁短期页面与独立接口

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-10-02门锁短期页面与独立接口)

## 2026-10-02：GSMIS数据源与时间轴合同

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-10-02gsmis数据源与时间轴合同)

## 2026-10-02：原生按键命中与表单提示避让

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-10-02原生按键命中与表单提示避让)

## 2026-10-02 可见窗口筛选空结果

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-10-02-可见窗口筛选空结果)

## 2026-10-02 空教室正文校区与查询草稿同步

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-10-02-空教室正文校区与查询草稿同步)

## 2026-10-03 空教室已应用条件跨校区复验

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-10-03-空教室已应用条件跨校区复验)

## 2026-10-07：本地分支统一到ubaa2

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-10-07本地分支统一到ubaa2)

## 2026-10-07：应用图标沿用冻结旧版资源

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-10-07应用图标沿用冻结旧版资源)

## 2026-10-07：未确认本机账号时启动必须进入登录页

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-10-07未确认本机账号时启动必须进入登录页)

## 2026-10-07：开发阶段统一安全存储插件

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-10-07开发阶段统一安全存储插件)

## 2026-10-07：通用依赖复用审计

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-10-07通用依赖复用审计)

## 2026-10-07：实施通用依赖收敛

[查看原始记录](history/decisions-before-maintainability-2026-10-07.md#2026-10-07实施通用依赖收敛)


## 2026-10-11：F01—F07 的边界修复

依据当前 a0a1736 的实际 CI 失败与故障注入，保留技术栈、严格 lint、CAS 修订及排他锁。Bridge 合同 v41 将生产 open 改为异步，Session 两级锁共用 2 秒预算；初始化错误保留白名单原因。提交发送观察独立于普通收尾，panic 展开不抹去可能发送事实；持久核对提示在 Dart 投影完成后确认。固定路线回读不改全局策略。会话/缓存生命周期分别拥有状态，成绩基线消费统一 scope。

来源与逐操作边界见 [实施前对照](source-parity-quality-2026-10-11.md)，RED/GREEN 与平台记录见 [整改账本](quality-repair-2026-10-11.md)。App Sandbox 保持；原生持锁夹具由外部测试宿主建立，不给产品增加启动子进程权限。源码清单覆盖全部跟踪输入，并将实际产物与作业关联；外部 SDK/系统依赖不伪称源码摘要或可复现证明。


## 2026-10-20：统一加载反馈并保持刷新布局

用户要求将普通加载反馈放回内容区。移除改变内容高度的全局连接条，首次读取用静态骨架，同查询刷新保留已有内容、空状态及滚动位置，进度留在按钮或局部标题；异步出现的成绩学期栏预留原位。旧写入按钮原位禁用，缓存和错误的必要信息继续可见。仅改展示，不改上游协议与业务缓存。失败反例、各页面清单及验证边界见[实施记录](loading-feedback-2026-10-20.md)。


## 2026-10-20：本机 macOS 使用固定开发签名

按用户授权使用本机已有开发证书，解决临时签名随重建改变应用身份的问题。通过被 Git 忽略的本机 Xcode 配置选择身份，原 bundle identifier 与沙盒权限保持；无本机配置的共享默认行为不变。旧钥匙串与容器授权由用户在系统界面确认，不删除数据、不放宽访问控制。两次构建与再次启动的事实见[实施记录](macos-local-signing-2026-10-20.md)。


## 2026-10-21：以成功 HAR 核对 SSO HTTP 跳转

UBAA2 已有有界手动UC激活和最终status校验，但重定向仍原样保留HTTP SSO。用户成功HAR中UC激活经历HTTP Location后使用HTTPS SSO取得ticket；两份冻结源缺少这项显式协议升级。采用实时证据优先规则，计划仅升级精确SSO默认HTTP端口、保留service编码并维持固定路线；实现前完整对照见[来源记录](source-parity-auth-2026-10-21.md)。用户明确不处理中转，不改其配置。

本轮随后确认教务currentUser原校验只依据HTTP200，已用HAR中的字符串code=0、datas.userId及正确最终地址补足成功条件，保留原GSMIS回退；完整反例和两路线真实验证均通过，见[实施记录](auth-repair-2026-10-21.md)。

## 2026-10-23：登录选项悬停样式

用户截图显示登录选项的外层直角矩形与复选框圆形悬停背景叠加。按用户确认的方向，保留整组选项的悬停反馈，使用 12 像素圆角与主题主色 4% 不透明度，文字末端增加 12 像素留白；复选框自身的状态背景始终透明、圆形反馈半径为零，并由外层整行统一接收鼠标和键盘输入，避免复选框与文字之间切换时出现圆形闪烁。整行保留键盘焦点、按压反馈和禁用逻辑。仅改展示样式，复用账号领域已有的点击单次派发、禁用、窄窗大字等 12 项测试，复选框点击测试改为点击其中心坐标，继续验证实际命中外层后的单次派发与禁用行为，未删除覆盖。未新增样式自证断言，也未发起真实学校请求。

首版重启后用户曾观察到背景残留，随后自行恢复，未确定原因；不将该现象记作已修复。

验证：`just check-changed` 因既有未跟踪 `.serena/` 输入而保守选择完整门禁，Rust/Shell、七包 1326 项测试和 FRB 零漂移通过。最终反馈调整后另跑账号领域 12 项测试及 UI 分析/格式检查通过；macOS Debug 已重建并打开，最终鼠标视觉效果交由用户继续预览。`.serena/` 未纳入本轮提交。

## 2026-10-23：共享 Material 交互反馈统一

按用户要求全面排查后，选择共享主题统一悬停/焦点色、选项控件背景、列表行圆角及卡片裁剪，仅特殊点击区域局部调整。不引入第三方 UI 库、不重写官方选项控件，不将独立图标按钮的圆形反馈视为缺陷。已复现卡片越界反例；官方选项行的基线实验未普遍复现双层背景，作为样式统一处理。完整清单、验证与后续独立控件维护规则见[交互审计](interaction-feedback-2026-10-23.md)。

## 2026-10-23：希冀业务获取按当前官网与真实观察修复

实施前核对发现冻结旧版和 UBAA2 均沿用 HTTP Judge service，而当前公开登录页实际链接 HTTPS service；用户引用聊天的真实调查还确认整课历史排除和 WebVPN 共享课程状态会丢失或串课。本轮按来源优先级采用官网 HTTPS service，原生登录页拒绝为空列表，取消批量整课排除并对 WebVPN 课程任务串行；重新认证后恢复选课。另一冻结源不实现 Judge 协议，明确不借用 SPOC 参数。逐操作矩阵及具体文件/提交见[实施前对照](source-parity-judge-2026-10-23.md)。

## 2026-10-23：作业详情保留列表父层并沿旧版分区

用户反馈首页进入作业后直接返回功能列表，重进功能又恢复详情。当前 `openFromHome` 清空父栈，功能入口也未恢复根列表；已用两功能4项反例复现。按用户要求保留/补足列表父层，并依冻结旧版的独立列表、分区详情移除通用“更多信息”；希冀不展示整页文本。实施前来源和协议边界见[导航与展示记录](assignment-navigation-2026-10-23.md)。

## 2026-10-23：共享界面布局重构

按用户确认的预览执行五项展示导航与设置式分组，复用 Flutter Material 3 控件和领域页面。改动限制在 UI 和宿主展示接线；预览与方案继续仅本地保留。阶段记录、覆盖迁移和平台证据见[实施记录](ui-layout-2026-10-23.md)。

## 2026-10-23：课表默认下载整学期

按用户要求，将整学期保存入口改为确定学期后的自动下载，右上角刷新固定重跑当前已应用学期的导入。沿用原逐周读取、任务合并、完整保存与取消机制；失败或取消不因重建再次自动请求。保存后从账号与实际路线匹配的本地精确查询更新当前周，保留查询修订与周次，拒绝迟到、错归属或不完整投影；旧 summary 周查询兼容相同行为。实施前双来源核对、差异与验证见[课表下载记录](source-parity-schedule-default-2026-10-23.md)。

## 2026-10-23：课表同步静默化

用户要求后台下载和保存时间对用户隐藏。移除课表常规同步进度、成功和取消状态栏，右上角提示改为“刷新”；失败保留简短错误和重试，空间不足保留可执行的清理提示。课表正文、首页今日课表、学期及教学周选择移除保存时间。底层整学期任务、数据来源、取得时间、完整度与归属校验保持。详情见[课表实施记录](source-parity-schedule-default-2026-10-23.md)。

## 2026-10-24：课表六项布局与交互调整

根据用户校历和应用截图，统一课表与功能列表宽度，去掉突兀周次背景与顶栏重复周次，补齐标准 14 节时间，按课程稳定分配可区分的颜色，并以直接选择学期替换搜索筛选。明确返回的时间优先，原下载、完整保存与归属校验保持。来源、测试调整映射和原生验证见[实施记录](schedule-layout-2026-10-23.md)。

## 2026-10-24：统一转圈加载动画

用户确认以转圈替代各页静态加载占位。采用共享组件统一首次与局部读取，刷新保留已有内容；首页未发起请求的状态和隐藏页面不持续播放动画。具体范围、旧测试适配与验证见[加载动画记录](loading-indicators-2026-10-24.md)。

## 2026-10-24：课表索引只作为选择数据

根据首页入口闪跳反馈，修复自动链提前交付索引页面的问题；按用户补充要求，学期和教学周仅通过选择控件展示，正文直接交付周课表。自动阶段延续到周结果就绪，失败可重试，取消选择继续原自动链。原因、双来源依据及验证见[实施记录](schedule-entry-2026-10-24.md)。

## 2026-10-24：待办独立滚动与常用功能按访问排序

待办改为约两行高度的独立纵向滚动窗口，保留宽屏两列和窄屏单列；常用功能按最近访问去重置顶，最多四项。访问记录通过已有平台偏好能力按账号保存，支持重启恢复、迟到读取隔离与退出清除。回归及原生截图范围见[实施记录](home-window-2026-10-24.md)。

## 2026-10-24：课表低饱和度配色

用户反馈深色课表色块过于鲜艳。共享课表配色的 HSL 饱和度由 0.62 降为 0.24，深色明度由 0.32 降为 0.28，浅色明度由 0.82 提至 0.87。保留按课程分配色相、学期内颜色保持和文字对比度选择。仅调整样式，不改变读取协议、课程数据或交互。

复用现有课程颜色区分、切周保持和文字对比度至少 4.5:1 的回归覆盖，更新两张课表 golden；不新增样式数值自证测试。Golden 用于颜色和布局核对，默认测试字体不能证明中文原生字体显示效果。

验证完成：26 项聚焦回归、`just check-changed`（完整 Rust/Shell、七包 Flutter 分析与测试、FRB 生成零漂移）、敏感扫描通过。macOS Debug 构建与实际签名权限检查通过，沿用当前检查配置重启，实际进入第 7 周课表核对低饱和度色块和中文文字。此次应用显示检查未执行真实协议专项验收。
