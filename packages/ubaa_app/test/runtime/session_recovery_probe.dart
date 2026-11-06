import 'dart:async';
import 'package:ubaa_app/runtime.dart';
import 'package:ubaa_platform/credentials.dart';

const profile = UserSummary(username: 'synthetic-user');
const saved = Credential(
  username: 'synthetic-user',
  password: 'synthetic-only',
  autoLogin: true,
);
const expired = BackendException(
  UbaaErrorCode.authenticationRequired,
  resolvedRoute: ConnectionMode.direct,
);

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<Object> failure(Future<Object?> value) async {
  try {
    await value;
  } on Object catch (error) {
    return error;
  }
  throw StateError('应返回失败');
}

Future<void> tick() => Future<void>.delayed(Duration.zero);
RecoveryScope scope({
  bool Function()? current,
  int account = 1,
  int route = 1,
  int backend = 1,
  int credential = 1,
  bool allowed = true,
  RoutePolicy policy = RoutePolicy.direct,
  String alias = 'synthetic-alias',
}) => RecoveryScope(
  accountAlias: alias,
  expectedUsername: profile.username,
  accountGeneration: account,
  routeGeneration: route,
  backendGeneration: backend,
  credentialGeneration: credential,
  routePolicy: policy,
  allowAutomaticLogin: allowed,
  isCurrent: current ?? () => true,
);
Future<RecoveryResult> ensure(
  RequiredSessionRecovery service,
  RecoveryScope current, {
  FeatureId feature = FeatureId.schedule,
  RecoveryCancellation? cancellation,
  int millis = 1000,
}) => service.ensureRequiredSession(
  feature: feature,
  scope: current,
  deadline: DateTime.now().add(Duration(milliseconds: millis)),
  cancellation: cancellation,
);

final class Operation implements RequiredRecoveryOperation {
  Operation(this.result, this.onCancel);
  @override
  final Future<RecoveredRouteSession> result;
  final void Function() onCancel;
  int disposals = 0;
  @override
  void cancel() => onCancel();
  @override
  void dispose() {
    disposals++;
  }
}

class Backend implements ControlledRequiredSessionBackend {
  Object? error;
  Object? loginError;
  RecoveredRouteSession? loginValue;
  final featureGates = <FeatureId, Completer<RecoveredRouteSession>>{};
  final featureErrors = <FeatureId, BackendException>{};
  final operations = <Operation>[];
  Completer<RecoveredRouteSession>? recoverGate;
  Completer<RecoveredRouteSession>? loginGate;
  bool settleOnCancel = true;
  int checks = 0, logins = 0, cancellations = 0, disposals = 0;
  final routes = <ConnectionMode>[];
  RecoveredRouteSession value = const RecoveredRouteSession(
    route: ConnectionMode.direct,
    profile: profile,
  );
  RequiredRecoveryOperation operation(
    Future<RecoveredRouteSession> Function() action,
    Completer<RecoveredRouteSession>? gate,
  ) {
    final done = Completer<RecoveredRouteSession>();
    action().then(
      (value) {
        if (!done.isCompleted) done.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        if (!done.isCompleted) done.completeError(error, stack);
      },
    );
    final operation = Operation(done.future, () {
      cancellations++;
      if (settleOnCancel && !done.isCompleted) {
        done.completeError(
          const BackendException(UbaaErrorCode.operationConflict),
        );
      }
    });
    operations.add(operation);
    return operation;
  }

  @override
  RequiredRecoveryOperation startRequiredRecovery(
    FeatureId feature,
    Duration limit,
  ) => operation(() => recoverRequiredSession(feature), recoverGate);
  @override
  RequiredRecoveryOperation startRequiredLogin(
    ConnectionMode route,
    LoginInput input,
    Duration limit,
  ) => operation(() => loginRequiredRoute(route, input), loginGate);
  @override
  Future<RecoveredRouteSession> recoverRequiredSession(
    FeatureId feature,
  ) async {
    checks++;
    if (featureGates[feature] case final gate?) return gate.future;
    if (featureErrors[feature] case final error?) throw error;
    if (recoverGate != null) return recoverGate!.future;
    if (error != null) throw error!;
    return value;
  }

  @override
  Future<RecoveredRouteSession> loginRequiredRoute(
    ConnectionMode route,
    LoginInput input,
  ) async {
    logins++;
    routes.add(route);
    if (loginGate != null) return loginGate!.future;
    if (loginError != null) throw loginError!;
    return loginValue ??
        RecoveredRouteSession(route: route, profile: value.profile);
  }
}

final class Vault extends MemoryCredentialVault {
  Vault() : super(initial: saved);
  int reads = 0;
  Completer<Credential?>? gate;
  final readGates = <Completer<Credential?>>[];
  @override
  Future<Credential?> load() async {
    reads++;
    if (readGates.length >= reads) return readGates[reads - 1].future;
    return gate != null ? gate!.future : super.load();
  }
}

// 将控制柄创建和密码发送分开，模拟 Core 锁队列中的未发送登录。
final class QueuedBackend extends Backend {
  final sendGate = Completer<void>();
  int queued = 0;
  @override
  RequiredRecoveryOperation startRequiredLogin(
    ConnectionMode route,
    LoginInput input,
    Duration limit,
  ) {
    if (route != ConnectionMode.webvpn) {
      return super.startRequiredLogin(route, input, limit);
    }
    queued++;
    var cancelled = false;
    final done = Completer<RecoveredRouteSession>();
    final current = Operation(done.future, () {
      cancelled = true;
      cancellations++;
      if (!done.isCompleted) {
        done.completeError(
          const BackendException(UbaaErrorCode.operationConflict),
        );
      }
    });
    operations.add(current);
    unawaited(() async {
      await sendGate.future;
      if (cancelled) return;
      try {
        final value = await loginRequiredRoute(route, input);
        if (!done.isCompleted) done.complete(value);
      } on Object catch (error, stack) {
        if (!done.isCompleted) done.completeError(error, stack);
      }
    }());
    return current;
  }
}

final cases = <String, Future<void> Function()>{
  '验证码耗尽交接人工，保留凭据且后续功能不重复自动提交': () async {
    final backend = Backend()
      ..error = expired
      ..loginError = const BackendException(
        UbaaErrorCode.authenticationRequired,
        captchaRequired: true,
        resolvedRoute: ConnectionMode.direct,
      );
    final vault = Vault();
    final service = RequiredSessionRecovery(
      backend: backend,
      credentials: vault,
    );
    final error = await failure(ensure(service, scope()));
    check(error is BackendException && error.captchaRequired, '未交付人工验证码状态');
    check(await vault.read() == saved, '验证码失败撤销了保存凭据');
    await failure(ensure(service, scope(), feature: FeatureId.signin));
    check(backend.logins == 1, '其它功能重新启动了自动验证码尝试');
    await service.close();
  },
  '跨路线材料读取挂起后被拒，另一条路线不提交密码': () async {
    for (final code in [
      UbaaErrorCode.invalidCredentials,
      UbaaErrorCode.upstreamChanged,
      UbaaErrorCode.passwordRiskConfirmationFailed,
    ]) {
      final backend = Backend()
        ..error = expired
        ..loginError = BackendException(code);
      backend.featureErrors[FeatureId.signin] = const BackendException(
        UbaaErrorCode.authenticationRequired,
        resolvedRoute: ConnectionMode.webvpn,
      );
      final direct = Completer<Credential?>(), vpn = Completer<Credential?>();
      final vault = Vault()..readGates.addAll([direct, vpn]);
      final service = RequiredSessionRecovery(
        backend: backend,
        credentials: vault,
      );
      final first = failure(ensure(service, scope(policy: RoutePolicy.auto)));
      final second = failure(
        ensure(
          service,
          scope(policy: RoutePolicy.auto),
          feature: FeatureId.signin,
        ),
      );
      await tick();
      check(vault.reads == 2, '未分别进入两次材料读取');
      direct.complete(saved);
      await first;
      vpn.complete(saved);
      await second;
      check(
        backend.logins == 1 && !backend.routes.contains(ConnectionMode.webvpn),
        '另一条路线提交已拒密码',
      );
      check((await service.close()).settled, '读取阻断未收尾');
    }
  },
  '跨路线材料阻断撤销排队登录，保留其他材料与有效会话': () async {
    final backend = QueuedBackend()
      ..error = expired
      ..loginGate = Completer();
    for (final feature in [FeatureId.signin, FeatureId.grades]) {
      backend.featureErrors[feature] = const BackendException(
        UbaaErrorCode.authenticationRequired,
        resolvedRoute: ConnectionMode.webvpn,
      );
    }
    final reusedGate = Completer<RecoveredRouteSession>();
    backend.featureGates[FeatureId.spoc] = reusedGate;
    final service = RequiredSessionRecovery(
      backend: backend,
      credentials: Vault(),
    );
    final first = failure(ensure(service, scope(policy: RoutePolicy.auto)));
    final blocked = failure(
      ensure(
        service,
        scope(policy: RoutePolicy.auto),
        feature: FeatureId.signin,
      ),
    );
    final other = ensure(
      service,
      scope(policy: RoutePolicy.auto, credential: 2),
      feature: FeatureId.grades,
    );
    final reused = ensure(
      service,
      scope(policy: RoutePolicy.auto),
      feature: FeatureId.spoc,
    );
    await tick();
    check(backend.queued == 2 && backend.logins == 1, '未进入发送前队列');
    backend.loginGate!.completeError(
      const BackendException(UbaaErrorCode.invalidCredentials),
    );
    await first;
    await tick();
    final revoked = backend.cancellations == 1;
    backend.loginGate = null;
    backend.sendGate.complete();
    reusedGate.complete(backend.value);
    final blockedResult = await blocked;
    final otherResult = await other;
    final reusedResult = await reused;
    check(revoked, '已拒材料的排队登录未撤销或影响其他材料');
    check(
      backend.logins == 2 &&
          backend.routes.where((r) => r == ConnectionMode.webvpn).length == 1,
      '已拒密码发送或其他材料被取消',
    );
    check(
      blockedResult is BackendException &&
          otherResult.disposition == RecoveryDisposition.reauthenticated &&
          reusedResult.disposition == RecoveryDisposition.reused,
      '阻断影响其他材料或有效会话',
    );
    check((await service.close()).settled, '排队取消未收尾');
    check(backend.operations.every((op) => op.disposals == 1), '控制柄未恰好释放一次');
  },
  '无 Controller 复用有效会话后继续原读取且零密码读取': () async {
    final backend = Backend(), vault = Vault();
    final service = RequiredSessionRecovery(
      backend: backend,
      credentials: vault,
    );
    var reads = 0;
    final result = await ensure(service, scope());
    if (result.session.profile.username == profile.username) reads++;
    check(
      result.disposition == RecoveryDisposition.reused &&
          reads == 1 &&
          vault.reads == 0 &&
          backend.logins == 0,
      '有效会话被重登',
    );
    check((await service.close()).settled, '未收尾');
  },
  '明确过期仅登录目标路线并继续读取': () async {
    final backend = Backend()..error = expired;
    final service = RequiredSessionRecovery(
      backend: backend,
      credentials: Vault(),
    );
    final result = await ensure(service, scope());
    check(
      result.disposition == RecoveryDisposition.reauthenticated &&
          backend.routes.single == ConnectionMode.direct,
      '目标路线错误',
    );
    check((await service.close()).settled, '未收尾');
  },
  '临时故障与无目标错误不读取密码': () async {
    for (final error in [
      const BackendException(
        UbaaErrorCode.timeout,
        resolvedRoute: ConnectionMode.direct,
      ),
      const BackendException(UbaaErrorCode.networkError),
      const BackendException(UbaaErrorCode.authenticationRequired),
    ]) {
      final backend = Backend()..error = error;
      final vault = Vault();
      final service = RequiredSessionRecovery(
        backend: backend,
        credentials: vault,
      );
      check(identical(await failure(ensure(service, scope())), error), '错误被替换');
      check(backend.logins == 0 && vault.reads == 0, '误读密码');
      await service.close();
    }
  },
  '禁用恢复、禁用 autoLogin、无材料和错误账号均不登录': () async {
    for (var variant = 0; variant < 5; variant++) {
      final backend = Backend()..error = expired;
      final vault = Vault();
      if (variant == 1) await vault.save(saved.copyWith(autoLogin: false));
      if (variant == 2) await vault.clear();
      if (variant == 3)
        await vault.save(saved.copyWith(username: 'other-user'));
      final service = RequiredSessionRecovery(
        backend: backend,
        credentials: variant == 4 ? const NoopCredentialVault() : vault,
      );
      await failure(ensure(service, scope(allowed: variant != 0)));
      check(backend.logins == 0, '未许可材料提交');
      await service.close();
    }
  },
  '无效密码和交互要求跨功能阻断同代材料，更新代次后允许': () async {
    for (final code in [
      UbaaErrorCode.invalidCredentials,
      UbaaErrorCode.upstreamChanged,
      UbaaErrorCode.passwordRiskConfirmationFailed,
    ]) {
      final backend = Backend()
        ..error = expired
        ..loginError = BackendException(code);
      final service = RequiredSessionRecovery(
        backend: backend,
        credentials: Vault(),
      );
      await failure(ensure(service, scope()));
      await failure(ensure(service, scope(), feature: FeatureId.signin));
      check(backend.logins == 1, '重复提交已拒材料');
      backend.loginError = null;
      await ensure(service, scope(credential: 2));
      check(backend.logins == 2, '新材料代次仍被阻断');
      await service.close();
    }
  },
  '异身份和异路线不得交付': () async {
    for (final value in [
      const RecoveredRouteSession(
        route: ConnectionMode.direct,
        profile: UserSummary(username: 'other-user'),
      ),
      const RecoveredRouteSession(
        route: ConnectionMode.webvpn,
        profile: profile,
      ),
    ]) {
      final backend = Backend()..value = value;
      final service = RequiredSessionRecovery(
        backend: backend,
        credentials: Vault(),
      );
      check(await failure(ensure(service, scope())) is BackendException, '误交付');
      check(backend.logins == 0, '错误身份触发密码提交');
      await service.close();
    }
  },
  '同 scope 合并，一个取消不撤销另一消费者': () async {
    final backend = Backend()..recoverGate = Completer();
    final service = RequiredSessionRecovery(
      backend: backend,
      credentials: Vault(),
    );
    final cancel = RecoveryCancellation();
    final first = failure(ensure(service, scope(), cancellation: cancel));
    final second = ensure(service, scope());
    cancel.cancel();
    check(
      await first is RecoveryInterrupted && backend.cancellations == 0,
      '取消影响其他消费者',
    );
    backend.recoverGate!.complete(backend.value);
    await second;
    check(backend.checks == 1, '未合并');
    await service.close();
  },
  '一个消费者到期后另一消费者继续': () async {
    final backend = Backend()..recoverGate = Completer();
    final service = RequiredSessionRecovery(
      backend: backend,
      credentials: Vault(),
    );
    final first = failure(ensure(service, scope(), millis: 20));
    final second = ensure(service, scope());
    check(
      (await first as RecoveryInterrupted).reason ==
              RecoveryStopReason.deadline &&
          backend.cancellations == 0,
      '期限影响其他消费者',
    );
    backend.recoverGate!.complete(backend.value);
    await second;
    await service.close();
  },
  '账号路线后端或材料代次不同不能合并': () async {
    final backend = Backend()..recoverGate = Completer();
    final service = RequiredSessionRecovery(
      backend: backend,
      credentials: Vault(),
    );
    final pending = [
      for (final current in [
        scope(),
        scope(account: 2),
        scope(route: 2),
        scope(backend: 2),
        scope(credential: 2),
      ])
        ensure(service, current),
    ];
    check(backend.checks == 5, '不同代次合并');
    backend.recoverGate!.complete(backend.value);
    await Future.wait(pending);
    await service.close();
  },
  '凭据挂起期间换号退出取消或到期，迟到凭据不登录': () async {
    for (var variant = 0; variant < 4; variant++) {
      var current = true;
      final backend = Backend()..error = expired;
      final vault = Vault()..gate = Completer();
      final service = RequiredSessionRecovery(
        backend: backend,
        credentials: vault,
      );
      final cancel = RecoveryCancellation();
      final pending = failure(
        ensure(
          service,
          scope(current: () => current),
          cancellation: cancel,
          millis: variant == 3 ? 20 : 1000,
        ),
      );
      await tick();
      if (variant == 0 || variant == 1) {
        current = false;
        service.validateScopes();
      }
      if (variant == 2) cancel.cancel();
      check(await pending is RecoveryInterrupted, '消费者未退出');
      check(
        !(await service.close(
              grace: const Duration(milliseconds: 20),
            )).settled &&
            service.pendingOperations == 1,
        '丢失材料收尾',
      );
      vault.gate!.complete(saved);
      await tick();
      check(backend.logins == 0 && service.pendingOperations == 0, '迟到材料导致登录');
    }
  },
  '登录挂起时最后消费者退出，取消底层且不交付迟到结果': () async {
    final backend = Backend()
      ..error = expired
      ..loginGate = Completer();
    final service = RequiredSessionRecovery(
      backend: backend,
      credentials: Vault(),
    );
    final cancel = RecoveryCancellation();
    var delivered = false;
    final pending = failure(
      ensure(service, scope(), cancellation: cancel).then((value) {
        delivered = true;
        return value;
      }),
    );
    await tick();
    check(backend.logins == 1, '未进入登录');
    cancel.cancel();
    await pending;
    check(
      (await service.close()).settled && backend.cancellations == 1,
      '底层未取消收尾',
    );
    backend.loginGate!.complete(backend.value);
    await tick();
    check(!delivered, '迟到登录交付');
  },
  '空 alias 不得提交密码但可复用有效会话': () async {
    final backend = Backend()..error = expired;
    final vault = Vault();
    final service = RequiredSessionRecovery(
      backend: backend,
      credentials: vault,
    );
    await failure(ensure(service, scope(alias: '')));
    check(vault.reads == 0 && backend.logins == 0, '空 alias 提交密码');
    backend.error = null;
    await ensure(service, scope(alias: ''));
    await service.close();
  },
  '不同功能明确同一路线后合并登录，取消一个不影响另一消费者': () async {
    final backend = Backend()
      ..error = expired
      ..loginGate = Completer();
    final vault = Vault();
    final service = RequiredSessionRecovery(
      backend: backend,
      credentials: vault,
    );
    final cancel = RecoveryCancellation();
    final first = failure(ensure(service, scope(), cancellation: cancel));
    final second = ensure(service, scope(), feature: FeatureId.signin);
    await tick();
    check(backend.logins == 1 && vault.reads == 1, '并发重复密码提交');
    cancel.cancel();
    await first;
    check(backend.cancellations == 0, '取消影响共享登录');
    backend.loginGate!.complete(backend.value);
    await second;
    await service.close();
  },
  '共享失败后单成员失效不解除剩余成员的材料阻断': () async {
    var firstCurrent = true;
    final backend = Backend()
      ..error = expired
      ..loginGate = Completer();
    final service = RequiredSessionRecovery(
      backend: backend,
      credentials: Vault(),
    );
    final first = failure(ensure(service, scope(current: () => firstCurrent)));
    final second = failure(ensure(service, scope(), feature: FeatureId.signin));
    await tick();
    backend.loginGate!.completeError(
      const BackendException(UbaaErrorCode.invalidCredentials),
    );
    await Future.wait([first, second]);
    firstCurrent = false;
    backend.loginGate = null;
    backend.loginError = const BackendException(
      UbaaErrorCode.invalidCredentials,
    );
    await failure(ensure(service, scope(), feature: FeatureId.grades));
    check(backend.logins == 1, '单成员失效解除已拒密码阻断');
    check((await service.close()).settled, '共享失败未收尾');
    check(backend.operations.every((op) => op.disposals == 1), '控制柄未恰好释放一次');
  },
  '异身份和异路线登录结果拒绝交付且阻断同代密码': () async {
    for (final value in [
      const RecoveredRouteSession(
        route: ConnectionMode.webvpn,
        profile: profile,
      ),
      const RecoveredRouteSession(
        route: ConnectionMode.direct,
        profile: UserSummary(username: 'other'),
      ),
    ]) {
      final backend = Backend()
        ..error = expired
        ..loginValue = value;
      final service = RequiredSessionRecovery(
        backend: backend,
        credentials: Vault(),
      );
      await failure(ensure(service, scope()));
      await failure(ensure(service, scope(), feature: FeatureId.signin));
      check(backend.logins == 1, '异常登录结果反复提交密码');
      await service.close();
    }
  },
  '重叠检查迟到的认证失败复用期间完成的同路线登录': () async {
    final backend = Backend()..error = expired;
    final gate = Completer<RecoveredRouteSession>();
    backend.featureGates[FeatureId.signin] = gate;
    final service = RequiredSessionRecovery(
      backend: backend,
      credentials: Vault(),
    );
    final later = ensure(service, scope(), feature: FeatureId.signin);
    await ensure(service, scope());
    gate.completeError(expired);
    await later;
    check(backend.logins == 1, '旧认证失败重复提交密码');
    await service.close();
  },
  '自动路线按实际目标隔离登录，服务关闭取消各控制柄': () async {
    final backend = Backend()
      ..error = expired
      ..loginGate = Completer();
    backend.featureErrors[FeatureId.signin] = const BackendException(
      UbaaErrorCode.authenticationRequired,
      resolvedRoute: ConnectionMode.webvpn,
    );
    final vault = Vault();
    final service = RequiredSessionRecovery(
      backend: backend,
      credentials: vault,
    );
    final first = failure(ensure(service, scope(policy: RoutePolicy.auto)));
    final second = failure(
      ensure(
        service,
        scope(policy: RoutePolicy.auto),
        feature: FeatureId.signin,
      ),
    );
    await tick();
    check(backend.routes.toSet().length == 2 && vault.reads == 2, '不同路线错误合并');
    check((await service.close()).settled, '关闭未收尾');
    await Future.wait([first, second]);
    check(backend.cancellations == 2, '关闭未取消两条路线');
    check(backend.operations.every((op) => op.disposals == 1), '控制柄未恰好释放一次');
    backend.loginGate!.complete(backend.value);
  },
  '登录挂起期间切号退出期限和关闭均撤销消费者并保管迟到结果': () async {
    for (var variant = 0; variant < 4; variant++) {
      var current = true, delivered = false;
      final backend = Backend()
        ..error = expired
        ..loginGate = Completer()
        ..settleOnCancel = false;
      final service = RequiredSessionRecovery(
        backend: backend,
        credentials: Vault(),
      );
      final pending = failure(
        ensure(
          service,
          scope(current: () => current),
          millis: variant == 2 ? 20 : 1000,
        ).then((value) {
          delivered = true;
          return value;
        }),
      );
      await tick();
      check(backend.logins == 1, '未进入登录门');
      if (variant < 2) {
        current = false;
        service.validateScopes();
      }
      if (variant == 3)
        await service.close(grace: const Duration(milliseconds: 20));
      final error = await pending as RecoveryInterrupted;
      check(
        error.reason ==
            (variant == 2
                ? RecoveryStopReason.deadline
                : variant == 3
                ? RecoveryStopReason.closed
                : RecoveryStopReason.superseded),
        '撤销原因错误',
      );
      check(
        backend.cancellations == 1 && service.pendingOperations == 1,
        '丢弃登录收尾',
      );
      backend.loginGate!.complete(backend.value);
      await tick();
      check(!delivered && (await service.close()).settled, '迟到登录交付');
    }
  },
  '服务关闭及时返回并保管未收尾操作': () async {
    final backend = Backend()
      ..recoverGate = Completer()
      ..settleOnCancel = false;
    final service = RequiredSessionRecovery(
      backend: backend,
      credentials: Vault(),
    );
    final pending = failure(ensure(service, scope()));
    final report = await service.close(grace: const Duration(milliseconds: 20));
    check(!report.settled && report.pendingOperations == 1, '虚报底层已结束');
    check(
      (await pending as RecoveryInterrupted).reason ==
          RecoveryStopReason.closed,
      '关闭未撤销消费者',
    );
    backend.recoverGate!.complete(backend.value);
    await tick();
    check(service.pendingOperations == 0, '迟到调用失去管理');
  },
};

Future<void> main(List<String> args) async {
  for (final entry in cases.entries.where(
    (entry) => args.isEmpty || entry.key.contains(args.single),
  )) {
    await entry.value();
    print('通过：${entry.key}');
  }
  print('纯 Dart 恢复行为：${cases.length} 项通过');
}
