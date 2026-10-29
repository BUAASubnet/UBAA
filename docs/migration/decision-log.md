# 决策记录

本页维护现行决策入口与新增记录。阶段 3 及以前的 282 个记录标题已建立[完整索引](history/2026-10-30-decision-index.md)，正文[原样归档](history/2026-10-30-decisions-through-quality-phase3.md)，顺序、文字和既有链接均未改写。更早的历史汇总仍见原记录中的归档入口。历史授权与测试结果只适用于记录时的范围，不能提供当前操作授权。

## 近期决定索引

| 时间与主题 | 记录 |
|---|---|
| 阶段 1：工具链、脱敏、许可证与证据保留 | [2026-10-29 阶段 1](history/2026-10-30-decisions-through-quality-phase3.md#2026-10-29阶段-1-去除个人机器依赖) |
| 阶段 2：权威入口与冻结引用换钉 | [2026-10-29 阶段 2](history/2026-10-30-decisions-through-quality-phase3.md#2026-10-29阶段-2-统一权威来源与规范) |
| 原生集成删减、每项覆盖缺口与保留理由 | [原生能力范围决定](history/2026-10-30-decisions-through-quality-phase3.md#2026-10-29原生集成只保留真实原生能力) |
| 工具版本、配置解析、CI 与文档链接范围 | [门禁与 CI](history/2026-10-30-decisions-through-quality-phase3.md#2026-10-29门禁基础逻辑与-ci-统一) |
| 阶段 3 最终本机验证与未运行事项 | [2026-10-30 验收](history/2026-10-30-decisions-through-quality-phase3.md#2026-10-30阶段-3-验收结果) |
| 主题等设备偏好与文档站 | [2026-10-29 文档站迁移](history/2026-10-30-decisions-through-quality-phase3.md#2026-10-29将-ubaa-v20-文档站迁入开发分支) |

## 2026-10-30：阶段 4 文档分工与历史保留

状态页改为当前快照，旧时间线完整迁入 history。decision-log 原文件通过 git mv 原样归档，以完整标题索引和近期决定表保留每条入口。既有记录不删改，也不把历史成功改写成当前候选结果。

已完成的 superpowers 计划、9 月 UI 设计/审计/执行记录和 macOS 逐按钮记录归入 history，按日期前缀命名。现行 design 只保留维护中的界面、配色与首页规格；migration 保存来源对照、当前结果与历史入口；两类 evidence 保存各自的验证文字和采集元数据，分工见[文档索引](../index.md#文档分工与归档)。

沿用阶段 3 的链接检查范围：history 内部保留原始相对链接和旧路径，便于按原提交与原位置追溯，豁免原因是历史语义与记录完整性。归档内部链接不承诺按当前目录可点击；[历史目录说明](history/README.md)提供当前入口与原位置映射。现行文档指向归档的文件与标题仍必须通过断链检查。不增加逐链接 allow、基线或脚本豁免。现行规格和来源对照中的源码链接已按当前目录修正；补充来源中无法共享的原材料继续明确为不可复现的历史证据。

约 4000 个 UI 证据 JSON 继续保留在 docs/design/evidence，实际受跟踪 JSON 为 3967 个。本阶段不删除、不移动、不改写 JSON，也不重算历史采集摘要。两类 evidence 不合并，以免丢失原批次和提交映射。

主题已由 ThemePreferenceStore 通过 PreferenceValues 保存为设备偏好，键为 `flutter.ubaa.preferences.theme`；Host 在启动时恢复并防止迟到读取覆盖用户新选择。无效值或读取失败回退到 system，普通偏好写失败不打断本次选择。现行规格、配置与隐私说明同步；旧设计中的“仅本次运行”保留为当时方案。

产品代际名 UBAA 2 / UBAA v2.0、SemVer、平台 build number、CLI/Bridge 合同与磁盘格式分别表达不同含义。当前 OHOS 原生版本与 pubspec 不一致，登记到状态页，配置修复留待阶段 6；本阶段不更改生产版本。离线合同的 CLI schema 旧值改为 v12，Bridge 历史版本节保持当时语义。CLI JSON Schema 使用版本化 URN `urn:ubaa:cli:json:schema:12` 标识文档，局部 $ref 与验证规则不变；消费者从受跟踪 Schema 文件加载，URN 不提供下载服务。

GitHub 仓库已启用私有漏洞报告，本轮通过只读 API 确认；SECURITY 写明实际报告入口与脱敏要求，没有修改远端设置或发送报告。README 收敛为概览与合同链接，协议细节集中到现有 Bridge 合同。
