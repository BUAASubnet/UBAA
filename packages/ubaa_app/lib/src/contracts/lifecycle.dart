import 'dart:async';
import 'backend.dart';
import 'package:ubaa_platform/shared_accounts.dart';

/// 可由应用生命周期关闭的后端资源。
abstract interface class BackendLifecycle {
  Future<void> dispose();
}

/// 在宿主 isolate 或原生生命周期重建后重新打开业务 backend。
///
/// 工厂必须创建全新的 backend；它不能复用已 dispose 的 opaque handle，也不能
/// 在 Dart 层复制 Core 的 Session 或路线状态。生产宿主通常把
/// [createProductionBackend] 作为工厂，测试则注入脱敏 fake。
typedef BackendFactory = FutureOr<UbaaBackend> Function();

/// GUI 与命令消费者共用；绑定只能来自安全索引捕获的固定快照。
abstract interface class SharedAccountBackend {
  Future<void> bindSharedAccount(SharedAccountBinding binding);
}

/// 显式退出的受限清理；票据只能来自条件撤销，不绑定为新的普通能力。
abstract interface class SharedAccountLogoutBackend {
  Future<void> logoutSharedAccount(
    SharedAccountBinding revoked, {
    required bool clearCache,
  });
}
