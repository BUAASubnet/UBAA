# 应用图标同步旧版

日期：2026-10-07。分支：`ubaa2`。冻结来源：`ubaa_old @ 1f4b8f8412272b6a423d4ad92b396e3db721e6f3`，仅只读使用。

| 目标 | 冻结旧版来源与处理 |
|---|---|
| macOS AppIcon | `composeApp/icons/app.icns`，iconutil提取32/64/128/256/512/1024px；16px用系统sips从32px缩小 |
| Windows | `composeApp/icons/app.ico`，原样复制 |
| Android | `androidApp/src/main/res` 的五密度普通/圆形/前景PNG、自适应XML、背景XML；Manifest增加roundIcon |
| iOS | `iosApp/iosApp/Assets.xcassets/AppIcon.appiconset` 整套原样复制，含普通/深色/着色三种1024px变体；移除不再引用的Flutter模板图 |
| 应用内与OHOS | `composeApp/src/commonMain/composeResources/drawable/app_icon.png`，原样复制 |

32项复制资源已逐字节核对；macOS和iOS资源目录中每个引用的PNG均存在且像素尺寸符合声明；Android新增XML均可解析。新macOS1024px源图已目视核对为旧版蓝底白字UBAA。

私有构建日志、资源映射与运行材料目录：`~/Library/Application Support/UBAA-private-evidence/icon-sync-20261007/`。后续验证结果在本记录追加；其他平台图标资源同步不代表本轮取得其原生运行验收。

## 验证与打开结果

- `just refs`、`just check-sensitive`、完整 `just check`（包含结构、Rust、Bridge、CLI端到端、构建和文档检查）通过。
- 应用内关于页面4项回归通过。图标变更使现有视觉基线先出现预期差异；更新21张平板/桌面golden后，14项视觉基线测试全部通过。逐像素核对每张变化均限制在原侧栏36×36图标范围内，手机基线未改。失败图片已迁至仓库外。
- `just flutter-build platform=macos mode=release` 通过，生产入口 `lib/main.dart`。产物Info.plist引用AppIcon，已从成品ICNS提取图像核对32/128/256px与源资源像素一致。构建仍有既有Keychain弃用警告，无构建错误。
- 已启动新Release实例，使用容器内独立 `UBAA_CONFIG_DIR`。Computer Use确认生产首页可见、窗口已置前，侧栏显示蓝底白字UBAA。当前页面提示需要登录，部分待办显示加载失败，未登录或执行学校业务；此项仅证明新包启动与图标可见，交由用户检查。

对应日志：`macos-build.log`、`check.log`、`about-test.log`、`golden-before.log`、`golden-update.log`、`golden-green.log`、`golden-diff.log`、`bundle-icon-check.log`。
