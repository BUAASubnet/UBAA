import 'dart:io';

import 'package:flutter/services.dart';

/// 把应用内主题告知系统，使 Android 12+ 冷启动的系统启动画面与之一致。
///
/// 其他平台的原生启动图由系统按外观绘制或由原生层直接读取偏好，这里不做事。
final class NativeThemeSync {
  NativeThemeSync({MethodChannel? channel, bool? enabled})
    : _channel = channel ?? const MethodChannel('cn.edu.buaa.ubaa/appearance'),
      _enabled = enabled ?? Platform.isAndroid;
  final MethodChannel _channel;
  final bool _enabled;

  /// [mode] 为 system、light 或 dark；失败时保留当前原生外观，不中断 Flutter 主题操作。
  Future<void> apply(String mode) async {
    if (!_enabled) return;
    try {
      await _channel.invokeMethod<void>('setThemeMode', mode);
    } on Object {
      /* 通道缺失或调用失败时保留原生外观。 */
    }
  }
}
