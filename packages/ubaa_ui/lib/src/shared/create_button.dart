import 'package:flutter/material.dart';

/// 创建按钮距页面右下角的统一边距。
const ubaaCreateButtonMargin = 16.0;

/// 全应用统一的创建按钮：右下角圆形加号，含义放在 tooltip 与无障碍标签里。
///
/// [open] 用于展开菜单的场景（0 收起、1 展开），加号随之旋转成关闭。
/// [key] 直接落在 [FloatingActionButton] 上，便于定位与读取状态。
Widget ubaaCreateButton({
  Key? key,
  required String tooltip,
  required VoidCallback? onPressed,
  Animation<double>? open,
}) {
  const icon = Icon(Icons.add);
  return Builder(
    builder: (context) {
      final colors = Theme.of(context).colorScheme;
      final enabled = onPressed != null;
      return FloatingActionButton(
        key: key,
        heroTag: null,
        tooltip: tooltip,
        onPressed: onPressed,
        // Material 的 FAB 不可用时外观不变；降低对比，避免看起来仍可点。
        backgroundColor: enabled ? null : colors.surfaceContainerHighest,
        foregroundColor: enabled
            ? null
            : colors.onSurface.withValues(alpha: .38),
        elevation: enabled ? null : 0,
        child: open == null
            ? icon
            : RotationTransition(
                turns: Tween(begin: 0.0, end: .125).animate(open),
                child: icon,
              ),
      );
    },
  );
}

/// 在页面 [Stack] 中按统一位置放置创建按钮。
Widget ubaaPositionedCreateButton({
  Key? key,
  required String tooltip,
  required VoidCallback? onPressed,
}) => Positioned(
  right: ubaaCreateButtonMargin,
  bottom: ubaaCreateButtonMargin,
  child: ubaaCreateButton(key: key, tooltip: tooltip, onPressed: onPressed),
);
