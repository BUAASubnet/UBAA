# 首页自动成绩读取让位与精确合并（P2-U）

2026-09-23，基于`7afd433d`。学校HTTP协议、Core会话与Bridge v35/schema v6不变。逐操作冻结来源记录先于生产修改，见[source-parity P2-U](../source-parity-offline-recovery-2026-09-17.md)。

先观察5项行为RED：自动学期/成绩排在今日课表或博雅补充来源前；同学期主动视图与自动检查无论已发送或排队都重复读取。最小修复为共享ReadDemand：自动成绩检查background、首页教学周学期home、主动请求interactive；合并的同代请求只能提高未发送批次优先级，已发送批次仍完整收尾。显式成绩视图与同学期辅助读取共享完整集合，然后按已出/待出本地投影；其它学期独立，同页面明确刷新仍产生新观察。

9项专项GREEN覆盖上述顺序、双向合并、排队提升、完整两门课程的待出投影、不同学期、明确刷新和退出取消；聚焦125项通过。完整Flutter1081项/7包分析、just check（含refs/layout、CLI端到端16、Bridge139）、独立敏感扫描通过。无公开Bridge变化，生成绑定与P2-T复验时一致。

三端原生矩阵由83项扩展到92项，macOS、iPhone17Pro与iPadPro13M5/iOS26.5模拟器最终各92项通过。macOS首轮91项通过、1项图书馆切楼馆弹层在读取DropdownButton时No element；同源码单项复跑与全92项重跑均通过，iPhone/iPad首轮通过。未修改或弱化图书馆断言，保留首次失败日志；当前只能确认为未稳定复现的原生测试时序现象，不能声称已修复其根因。成绩9项在所有轮次均通过。

本轮进一步审查发现生产GradeScoreWatch仍使用旧FileGradeScoreStore保存派生成绩正文；下一独立阶段将该基线接入Core加密仓库。当前阶段不掩盖该产品缺口，也不将性能或全方案标完成。

证据保存在仓库外`p2u-grade-priority-20260923`：

| 文件 | SHA-256 |
|---|---|
| `ubaa-p2u-red.log` | `cbd80b5802672f4132fcac627f7b83818eb672f5f3278164c838de9c9cd131b5` |
| `ubaa-p2u-focused.log` | `097f9a24208f0215adbd90a92e70695de317f60e20742848a949fdd558a0bab9` |
| `ubaa-p2u-grade-final.log` | `98ef37104a965a8fa9b78eb778f939d248a98aeb7a1fe788def1fc6bfe83fc05` |
| `ubaa-p2u-flutter.log` | `995662893d908e49775df711e7d826fb4f5ab8b0744682934a44aeca735f38ea` |
| `ubaa-p2u-check.log` | `156ba06c1024d2d73dbd38788b9773be73f41cf87e13b12597db033f490f3cc4` |
| `ubaa-p2u-native-macos.log` | `67017845a486e153df4b404ceeae4dbc5ff8f68ff4b2b7b6884482e82c024474` |
| `ubaa-p2u-native-macos-libbook.log` | `ad424d59b7bd851aae7e26237532239cc71eaa04e2714c93b62ccda48071db71` |
| `ubaa-p2u-native-macos-final.log` | `fb92a9831fbac4411261f733930752747e36f0357637e6546eb770bfd80814cf` |
| `ubaa-p2u-native-iphone.log` | `51a7a07d4e7c1d378a7a911ab25387f619f674cbf8cafcf7f1214d544b4372e3` |
| `ubaa-p2u-native-ipad.log` | `47aaad405486e34f39163e445d73b6e322ad6f1ea4a58150f26bb90da65991b9` |
| `ubaa-p2u-refs.log` | `534334fd86cb3a1e18d73f92643100e7433d193d4d49b1552ec9d7a1dd5639b3` |
| `ubaa-p2u-sensitive.log` | `d83962db650a6b6f589bbc51a8025aca9f35cc592f43133e68c5f90ecfe3f5e6` |
