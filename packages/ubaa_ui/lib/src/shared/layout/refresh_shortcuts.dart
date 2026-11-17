import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Widget withRefreshShortcuts(Widget child, Future<void> Function()? onRefresh) {
  // 切页时只调整可用的绑定，保持桌面快捷键的父层级稳定。
  void refresh() => unawaited(onRefresh?.call());
  return CallbackShortcuts(
    bindings: {
      if (onRefresh != null) ...{
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true): refresh,
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): refresh,
      },
    },
    child: Focus(autofocus: true, child: child),
  );
}
