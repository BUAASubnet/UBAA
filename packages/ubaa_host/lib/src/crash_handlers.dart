import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// 保留 Flutter 框架与 root isolate 各自的错误处理链。
final class DartCrashHandlers {
  DartCrashHandlers._(this._previousFlutter, this._previousPlatform);

  final FlutterExceptionHandler? _previousFlutter;
  final ErrorCallback? _previousPlatform;
  late final FlutterExceptionHandler _flutter;
  late final ErrorCallback _platform;

  static DartCrashHandlers install(
    Future<void> Function(Object, StackTrace?) record,
  ) {
    final dispatcher = PlatformDispatcher.instance;
    final handlers = DartCrashHandlers._(
      FlutterError.onError,
      dispatcher.onError,
    );
    void report(Object error, StackTrace? trace) {
      // 遥测 Future 的异常由此消费，不能再次进入未捕获异常处理链。
      unawaited(
        Future<void>.microtask(
          () => record(error, trace),
        ).catchError((Object _) {}),
      );
    }

    handlers._flutter = (details) {
      report(details.exception, details.stack);
      handlers._previousFlutter?.call(details);
    };
    handlers._platform = (error, trace) {
      report(error, trace);
      return handlers._previousPlatform?.call(error, trace) ?? false;
    };
    FlutterError.onError = handlers._flutter;
    dispatcher.onError = handlers._platform;
    return handlers;
  }

  void dispose() {
    if (identical(FlutterError.onError, _flutter)) {
      FlutterError.onError = _previousFlutter;
    }
    final dispatcher = PlatformDispatcher.instance;
    if (identical(dispatcher.onError, _platform)) {
      dispatcher.onError = _previousPlatform;
    }
  }
}
