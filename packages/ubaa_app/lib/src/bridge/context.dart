import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

/// 单个后端的客户端与状态所有者；领域适配显式借用，不依赖组合入口。
class BridgeContext {
  BridgeContext(this.client, {this.configDirectory});
  final BridgeClient client;
  final String? configDirectory;
  final cache = BridgeCacheState();
  final authentication = BridgeAuthenticationState();
}

/// 账号句柄、失效代次与串行队列始终属于同一缓存上下文。
class BridgeCacheState {
  BridgeOfflineCache? handle;
  LocalAccount? account;
  Future<void> tail = Future<void>.value();
  final Object scopeKey = Object();
  int generation = 0;
  String? targetAccountId;
}

/// 每条交互挑战只能由创建它的后端实例消费或取消。
class BridgeAuthenticationState {
  int generation = 0;
  BridgeInteractiveLogin? login;
  LoginVerificationState? state;
  final Map<ConnectionMode, BridgeCaptchaChallenge> challenges = {};
}
