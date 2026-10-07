# 当前实现与验证状态

更新日期：2026-10-07（Asia/Shanghai）。[独立工程审查整改](../../goal.md)的I01—I09已完成，实现、阶段提交及干净候选材料预检均已落地。实施分支为ubaa2，仅本地提交，不推送发布。

## 当前事实

- CLI JSON schema v11、Flutter bridge contract v40、Session v2、配置v1、缓存v6保持；当前Rust错误构造兼容取舍见[ADR0007](../adr/0007-operation-scopes-and-verification.md)。
- 冻结old为1f4b8f8412272b6a423d4ad92b396e3db721e6f3、示例为a63712fa2ae0a6c8066197063ddee98e3a6b5b81，普通refs纯校验。
- 写入统一Core原子确认路线；认证完成token与验证码状态分离；SessionScope/ReadScope保护回写，学期缓存有明确owner，清理/重建统一失效。普通偏好可显式清除坏值。
- 敏感扫描分别读取index/工作区并失败关闭；Dart指令检查完整自有源码闭包；SBOM实际离线schema校验、Dart/OHOS许可材料及缺口单列。
- 原生清单仍73入口，默认macOS改为4入口，新增真实插件通道；live/manual不进入CI。生成与历史材料的边界继续保留。

## 当前候选验证

严格Rust/CLI/Shell门禁通过；七包Flutter分析/格式与1340项通过；FRB同步1行机械注释后生成零漂移。macOS默认四入口分层累计11项通过（网络1、插件2、应用流程7、FFI缓存1）。Android Debug APK、iOS simulator App、OHOS无签名Debug HAP及对应结构检查通过。

验证日志、RED/GREEN、修复中被回归检出的分支、阶段提交和预检结果见[完整实施记录](engineering-quality-implementation-2026-10-07.md)。历史F1—F7的1327项与WebVPN记录只适用于[上一轮候选](maintainability-implementation-2026-10-07.md)，不用于本轮宣称真实验收通过。

## 继续保留的证据缺口

本轮未发起Direct/WebVPN、真实App账号读取或学校写入。原生runner无法前置macOS窗口，合成流程和真实插件handler通过不代表逐按钮Computer Use。OHOS实体HUKS、Windows/Linux运行、移动实体设备、签名及正式发布未验收。

原B2/C2/C3/D沿[旧收尾合同](history/goal-2026-10-07-before-maintainability.md)与[按钮记录](../design/macos-ui-button-results.md)继续跟踪。干净候选bbbbca52的preflight成功生成材料，411个Cargo组件通过schema；Dart/OHOS材料仍有27/848条自有包正文/原生分发缺口，不能凭schema通过声称正式交付批准。
