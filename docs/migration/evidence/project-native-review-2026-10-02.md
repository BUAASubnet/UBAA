# 原生集成与可见窗口审查

日期：2026-10-02。阶段起点 `1b2dac45`，工作分支 `codex/project-completion-20261001`。所有运行日志、截图和操作轨迹保存在仓库外私有目录 `~/Library/Application Support/UBAA-private-evidence/project-review-20261002-resume`。下列文件名均相对此目录，不提交原始运行材料。

## 发现与修复

- 门锁专用页遗留无效搜索按钮。390/1024两宽度Host断言先失败（`lock-toolbar-red.log`），按页面typed view隐藏无效入口，返回普通查询页恢复，聚焦GREEN见 `lock-toolbar-green.log`。
- 前一条Snackbar遮住研讨室/阳光表单底部继续确认。两个命中测试RED（`form-footer-red.log`），表单操作区移入Scaffold底栏，并让阳光底栏按内容收缩；完整旧选图/取消/迟到回调/确认回读等120项聚焦通过（`form-footer-focused.log`）。不取消结果提示，不修改学校写入权威。
- 真实桌面固定WebVPN课表输入无匹配关键词后，七日网格被通用空列表替代。三宽度RED见 `schedule-filter-red.log`；保留源周时间轴、星期结构，明确“没有匹配的课程”，清空筛选恢复。13项聚焦通过（`schedule-filter-green.log`）。双来源和适用边界见决策记录。
- 本科时间轴部分“--:--”沿冻结旧版：只有实际课程边界可用，不能套用研究生标准方案。这不是本轮猜补时间的理由。

- 空教室正文切校区后高级查询草稿仍停留旧校区。真实WebVPN截图复现，`classroom-draft-red.log`观察到预期3实际2；明确正文查询采用新日期/校区并清除旧楼层/节次，15项相关回归通过（`classroom-draft-green.log`），后台刷新不覆盖草稿。

## 原生测试与真实边界

| 验证 | 结果 | 证据 |
|---|---|---|
| macOS主流程 | 7 PASS；十二领域查询、十类合成写操作及博雅两个分支、单次提交、业务回读 | `native-app-flow-macos7.log` |
| macOS离线/安全材料 | 111 PASS；包含真实FFI缓存与系统安全材料闭环，其余为显式合成异常矩阵 | `native-offline-matrix.log` |
| iPhone17 Pro，402×874，iOS26.5 | 明暗两流程通过；78张截图视觉审查 | `native-iphone-baseline.log`、`iphone-baseline/manifest.json` |
| iPad Pro11，834×1210，iOS26.5 | 明暗两流程通过；78张截图视觉审查 | `native-ipad-baseline2.log`、`ipad-baseline2/manifest.json` |
| iPhone阳光专项 | 42项通过；成功/未知/回读失败/上传失败/取消失败/过期/在途、筛选与异常状态 | `native-iphone-sports.log` |
| 生产FRB macOS，只读 | 12领域完成；实际路线全部WebVPN，考试/签到为空，评教0条。学校写入0 | `native-webvpn-readonly.log` |
| 新私有WebVPN会话 | 登录、资料与专用门锁读取通过；无密码/预约，学校写入0 | `final-private-login.log` |

旧原生脚本按实际三入口、子菜单、动态周标题、按需面板与惰性卡片更新，保留严格点击命中失败和完整查询/写后回读断言；不再用固定超高viewport掩盖真实滚动。每项合成写测试核对Snackbar展示/退出后再开始下一项，避免人为队列积压。iPad空教室允许旧宽屏正文快速搜索，完整查询面板仍须收起。

以上原生结果不替代系统鼠标键盘审查。桌面已通过截图确认解锁；生产入口重新构建、独立配置启动，真实窗口激活成功。可见操作另行逐步记录，只有看见实际结果的控件才可更新按钮清单；不按自动化通过数量换算225项完成数。

## 当前门禁

- 完整Flutter七包静态分析及1324项通过，日志 `native-review-flutter4.log`；此前1323项与1320项亦分别通过。
- `just check`通过（包括Rust/CLI、结构、合同、脚本及文档构建），日志 `native-review-check3.log`。
- FRB生成零漂移通过，日志 `native-review-codegen.log`；本阶段没有Bridge合同变更。
- Android Debug APK、iOS模拟器与macOS生产构建成功，分别见 `final-android-build.log`、`final-ios-build.log`、`review-production-macos-build.log`。表单/课表后续小修的最终macOS构建与桌面复验单独追加，不将较早产物当最新候选。

## 未关闭项

逐按钮桌面清单尚未全部完成；真实验证码挑战、有预约的锁码、GSMIS账号、Win/Linux原生系统选图及其他设备仍无当前证据。Android启动器三种课表widget没有接线，阳光旧自动默认值与当前typed确认合同仍有明确差异，见来源审计，不能据此宣称所有旧版功能完全对齐。本轮不推送、不发布。


## 图书馆最新真实失败

此前十二领域原生测试只覆盖默认列表，不覆盖所有下级接口。可见窗口进入首个真实分区后，`Space/map`失败；`library-webvpn-followup.log`重复复现。仅开启已有 `ubaa::libbook` 安全摘要后，`library-webvpn-shape.log`记录该请求为HTTP200、业务code500、顶层仅code/message、没有data。其他图书馆接口返回code0，楼馆/分区/座位/预约记录读取成功。两次专项均退出5，不能计为通过。

当前请求与冻结旧版 `LocalLibbookApi.kt:211` 的 `Space/map`、JSON id完全一致；示例无同协议模块。没有证据支持换URL、猜时段或吞掉code500，故保留失败，不放宽TLS、解析或预约资格。需上游恢复后再次验证真实逐日时段/地图/选座；已加载列表和合成流程仍可分别审查。


## 关键日志摘要指纹

| 私有文件 | SHA-256 |
|---|---|
| `native-review-flutter4.log` | `b64dbeeacc2eca4be92255a5e417197ab9650f10dc4aac077334173ecf7d6ab5` |
| `native-review-check3.log` | `b6ab0575ce2e63c3a46ee0e6fd4c82fb57e018af77452bfedf16aaad2fb7e4cf` |
| `native-app-flow-macos7.log` | `af9454c32e86723c857d56376cc2e4131cf6851c38ffae7e1b57fe89fff237f4` |
| `native-offline-matrix.log` | `78f0228f78a4590ad8fe58cff0d5b569dfba2ff0ee0732382ce04f463b024dd7` |
| `native-webvpn-readonly.log` | `85d7f86239e9e4b86023aab5d7c577b2d84d88fbedef22024812e0dca3e6e642` |
| `native-iphone-baseline.log` | `6bd456eb990540507a8ee1cf878a649680cae48d3cc93f2cb0553257f2fb9a91` |
| `native-ipad-baseline2.log` | `b10cfbbf0f6ca71adc72dd40a82ed7979afd7e9a55413ae63e61868f056269ef` |
| `native-iphone-sports.log` | `87c91a6e43bfa28dbf2cd819a9ee976eecf75d2e03dda14b848344b454f40d17` |
| `library-webvpn-shape.log` | `5d34fd908d407617d2e4359e3cc111e92d9f7d49059292ff42f1a6c20c243178` |
