# 应用配色：中性表面与蓝色强调

更新：2026-10-25。适用于共享 Flutter UI 的浅色和深色主题。

## 依据与取舍

用户反馈首页蓝紫色背景、标签、图标和日期同时强调，画面突兀。本轮采用 Microsoft Fluent 2 的中性色层次、克制使用品牌色、按用途区分状态色的原则；通过现有 Material 3 ColorScheme 统一实现，控件和交互结构保持。

官方资料（2026-10-25 查阅）：

- [Fluent 2 Color](https://fluent2.microsoft.design/color)：表面、文字和布局以中性色为基础；品牌色用于操作和选中状态，避免铺满大面积背景；语义色用于反馈并配合其他提示。
- [Fluent 2 Color Tokens](https://fluent2.microsoft.design/color-tokens/)：按背景、前景、品牌和状态定义角色，浅深主题分别映射。
- [Android 官方配色指南](https://developer.android.com/design/ui/mobile/guides/styles/color)：使用颜色角色，成对设置容器与前景，提供明暗方案，避免装饰颜色过多。
- [W3C 文字对比度说明](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)：普通文字至少 4.5:1。

具体色值是本项目的选择，不表示复刻某一产品或取得设计系统认证。

## 当前颜色角色：图标蓝

首轮方案偏灰，用户要求更多体现应用图标的主题色。直接统计 `packages/ubaa_ui/assets/icons/app_icon.png` 的不透明蓝色像素，主色为 `#1976D2`，因此将品牌种子与浅色 primary 统一为该色。深色主题提高同色系蓝色亮度，正文与状态标签保留不同强调级别。

实现入口：`packages/ubaa_ui/lib/src/theme.dart`。页面继续使用 ColorScheme 角色。

| 用途 | 浅色 | 深色 |
|---|---|---|
| 页面底色 | `#FCFDFF` | `#111C29` |
| 卡片 | `#FFFFFF` | `#1C2B3D` |
| 导航底色 | `#EAF3FC` | `#14283D` |
| 主要文字 | `#242424` | `#EAF3FC` |
| 次要文字 | `#596B7E` | `#B8C7D9` |
| 品牌蓝／主操作 | `#1976D2` | `#83BEF7` |
| 来源标签底色／前景 | `#E3F0FC`／`#125EA7` | `#183F64`／`#B8DAFC` |
| 普通状态底色 | `#F1F4F7` | `#27374A` |
| 装饰边界 | `#DBE5EF` | `#364B62` |

待办图标采用品牌蓝，来源与课程简称采用浅蓝标签，时间使用同色系深蓝；普通状态标签使用低强调底色，课程说明保持次要文字。常用功能恢复蓝色图标底座。文本按钮与描边按钮文字采用 onPrimaryContainer，保证浅蓝背景上的可读性。错误、课程区别色和空教室空闲绿色保留原有语义。

## 验证边界

[2026-10-25 实施与验证](../migration/history/2026-10-25-color-system-validation.md)保留当时测试、原生运行和私有材料标识。当前门禁及自动化缺口以[状态页](../migration/status.md)为准，现行原生范围见[测试策略](../development/testing.md)。
