import 'package:flutter/material.dart';
import '../shared/sync_status.dart' show uiIsTouchPlatform;

/// 一组并列选项：手机横向滑动，桌面直接换行铺开，不让鼠标去拖滚动条。
class UiChipStrip extends StatelessWidget {
  const UiChipStrip({
    super.key,
    required this.children,
    this.spacing = 6,
    this.padding = EdgeInsets.zero,
  });
  final List<Widget> children;
  final double spacing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => uiIsTouchPlatform(context)
      ? SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: padding,
          child: Row(spacing: spacing, children: children),
        )
      : Padding(
          padding: padding,
          child: Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: children,
          ),
        );
}
