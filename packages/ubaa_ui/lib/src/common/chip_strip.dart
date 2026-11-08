import 'package:flutter/material.dart';
import '../shared/sync_status.dart' show uiIsTouchPlatform;
import '../theme.dart' show UbaaTheme;

/// 一组并列选项：手机横向滑动，桌面直接换行铺开，不让鼠标去拖滚动条。
class UiChipStrip extends StatelessWidget {
  const UiChipStrip({
    super.key,
    required this.children,
    this.spacing = 6,
    this.padding = EdgeInsets.zero,
    this.bleed = false,
  });
  final List<Widget> children;
  final double spacing;
  final EdgeInsetsGeometry padding;

  /// 位于页面左右边距内时设为 true：手机上滑动区延伸到屏幕边缘，
  /// 选项不会在页边距处被截断，起止仍与页面内容对齐。
  final bool bleed;

  @override
  Widget build(BuildContext context) => uiIsTouchPlatform(context)
      ? _touch(context)
      : Padding(
          padding: padding,
          child: Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: children,
          ),
        );

  Widget _touch(BuildContext context) {
    Widget strip(EdgeInsetsGeometry padding) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(spacing: spacing, children: children),
    );
    if (!bleed) return strip(padding);
    final gutter = UbaaTheme.pagePadding(MediaQuery.sizeOf(context).width);
    // 高度取选项的固有高度；宽度左右各多出一个页边距，居中后正好贴到屏幕边缘。
    return LayoutBuilder(
      builder: (context, constraints) => IntrinsicHeight(
        child: OverflowBox(
          maxWidth: constraints.maxWidth + gutter * 2,
          minWidth: constraints.maxWidth + gutter * 2,
          child: strip(padding.add(EdgeInsets.symmetric(horizontal: gutter))),
        ),
      ),
    );
  }
}
