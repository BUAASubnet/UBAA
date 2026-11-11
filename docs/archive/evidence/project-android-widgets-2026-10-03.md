# Android桌面课表、原生启动与最终候选验证

日期：2026-10-03。基础提交 `02d68d19`，当前分支 `codex/project-completion-20261001`。双来源、字段与宿主裁决见[来源对照](../source-parity-android-widgets-2026-10-03.md)。整体合同仍执行中，不将Android结果代替macOS真实按钮验收。

## 实现

- 共享层只读取当前随机账号别名下、覆盖完整学期的既有加密课表缓存；保留空周、学期名称、课程时间地点和周次教师，不导出会话、原始fields或写资格。
- 原生周课表、今日课程、未来三天三种组件沿旧版绘制；默认紧凑排列、拉高显示时间网格，上一周/下一周/本周、跨周三天、相同周离线跳转保留。
- 点击打开只读原生页面，无需等待在线认证；有今日摘要、学期/教学周选择、左右切周、课程详情/关闭、返回，账号错配拒绝显示。
- Android Keystore AES-256-GCM、随机IV、原子私有文件和读回验证保护组件副本；退出/清缓存先撤销发布代次，迟到结果不能恢复旧内容，安全材料错误不降级。
- 正式入口实际冷启动发现三项仅构建无法发现的问题：Android无HOME导致目录失败、Rust1.95标准库Android文件锁不支持、Rustls平台验证器缺少JVM初始化和Kotlin组件。分别补原生私有目录、Android内核文件锁封装、TLS宿主初始化。正式主Manifest补联网权限；未关闭TLS或改变学校协议。
- 移植的旧版渲染及资源补MIT版权和许可证全文。原有worktree、冻结来源和真实账号材料保持不变。

## 分层证据

媒体、日志均位于仓库外私有 `project-review-20261002-resume` 目录；Git只存本记录、来源说明和测试源码。

| 层 | 结果及证据 |
|---|---|
| 投影行为 | `android-widget-projection-red.log` 缺失行为RED；完整/空周、部分学期拒绝、错账号、迟到取消、原名称与教师字段GREEN；详情字段另有 `android-widget-detail-red.log` → `android-widget-detail-green.log` |
| 发布竞态/宿主 | 代次撤销、旧读取拒绝、原生存储失败上抛、线上恢复未完成时本地发布、退出撤销；完整宿主92项通过 |
| 原生加密/解析 | Android 36 arm64专用模拟器，原生2项Keystore测试与1项Provider/渲染/同周/按钮/错账号页面测试通过：`android-widget-instrumentation-final.log`；JVM周选择和跨周议程2项通过 |
| Flutter→原生 | `android-widget-channel2.log` 真实通道发布、清理、迟到拒绝通过；后续 `android-core-startup-green.log` 2项通过，含实际FRB/Core初始化 |
| 启动RED→GREEN | `android-private-path-red.log`→`android-private-path-green.log`；`android-core-startup-red2.log` 稳定错误could not lock session→原生Core成功；`android-webvpn-bootstrap.log` 网络准备失败→`android-webvpn-tls-green.log` 2项通过且WebVPN准备槽无错误 |
| Launcher实操 | A02今日课程、A03同周打开；A22紧凑周、A23翻下周、A25同周离线、A26—27课程详情/关闭、A28—31周次/学期选择、A32滑动下一周、A33返回、A34本周、A35—37拉高网格；A46三天紧凑溢出提示、A48拉高后实际显示周六/周日/下周一、A49点击打开 |
| 全量确定性 | 最终7包分析与1337项Flutter测试通过（57+99+633+350+31+92+75）：`project-final-flutter-check.log`。早期格式失败已修正，不把失败运行当PASS |
| 工程 | `project-final-android-build.log`：Debug APK、AndroidTest APK、JVM测试、Release主Manifest处理通过；`project-final-codegen.log`：FRB零漂移。Rust/CLI首次总门禁发现独立编译夹具锁文件未同步fs2，随后修正文档命令的锁定参数描述，最终重跑结果见 `project-final-core-check3.log` |

首次安装期间Launcher保留旧APK资源路径导致“Can't load widget”，重启测试Launcher后恢复，原日志保留；首次原生页面系统栏遮挡已补安全边距并重建复验。截图A24处于切换动画中，以稳定A25作为视觉结论。A50记录原目录错误，A53记录原文件锁导致的初始化不可用，A55最终正式入口已正常显示完整登录页，无启动错误卡。A01—55是操作记录序号，不是55个独立PASS。

## 真实验收边界

Android模拟器只使用明确合成课程，未放入真实账号。网络专项不传账号密码、不提交登录或学校业务；现有登录准备API内部准备双槽，仅判断WebVPN槽，不将Direct尝试记为Direct通过。APK本地Debug签名不等于发布签名，未发布。

macOS正式 `lib/main.dart` 已恢复构建和独立配置启动，系统仍锁屏。此前生产WebVPN的D01—275及研讨室真实详情复验有效；最新教室父条件/隐藏Tooltip真实鼠标复验，以及按钮清单中待验项仍需解锁后继续。图书馆Space/map上游code500、博雅统计缺字段、真实空记录、未触发验证码与GSMIS账号，以及Windows/Linux/OHOS原生运行，不被本阶段通过覆盖。
