import '../contracts/app_service.dart';
import 'dart:async';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../contracts/backend.dart';
import '../contracts/lifecycle.dart';
import 'package:ubaa_platform/shared_accounts.dart';
import '../contracts/recovery.dart';
import '../contracts/session_recovery.dart';

/// GUI 与无 Engine 消费者共用的恢复编排。不持有页面或业务写入闭包。
final class RequiredSessionRecovery {
  RequiredSessionRecovery({
    required RequiredSessionBackend backend,
    required this.credentials,
    this.rebuildBackend,
    this.beforeSharedRebind,
  }) : _backend = backend;
  RequiredSessionBackend _backend;
  RequiredSessionBackend get backend => _backend;

  /// 工厂须释放旧客户端能力、撤销旧写资格，并返回同资料空间的新客户端。
  final Future<RequiredSessionBackend> Function(RecoveryScope scope)?
  rebuildBackend;
  final CredentialVault credentials;
  final void Function()? beforeSharedRebind;
  final _jobs = <Object, _RecoveryJob>{};
  final _draining = <_RecoveryJob>{};
  final _blockedCredentials = <Object, Set<RecoveryScope>>{};
  final _completedLogins =
      <(Object, ConnectionMode), (int, RecoveredRouteSession)>{};
  int _loginRevision = 0;
  (String, int)? _publishedAccount;
  final _logins = <Object, _SharedLogin>{};
  bool _closed = false;
  int get pendingOperations => _draining.length;

  /// 关闭之后仍由服务持有的实际任务；有界 close 返回后可继续等待排空。
  Future<void> get settlement {
    if (!_closed) throw StateError('须先关闭恢复服务');
    return Future.wait<void>(
      _draining.map((job) => job.settled.future),
    ).then((_) {});
  }

  Future<RecoveryResult> ensureRequiredSession({
    required FeatureId feature,
    required RecoveryScope scope,
    required DateTime deadline,
    RecoveryCancellation? cancellation,
  }) => ensureTargetSession(
    target: RecoveryTarget.fromFeature(feature),
    scope: scope,
    deadline: deadline,
    cancellation: cancellation,
  );

  Future<RecoveryResult> ensureTargetSession({
    required RecoveryTarget target,
    required RecoveryScope scope,
    required DateTime deadline,
    RecoveryCancellation? cancellation,
  }) {
    if (_closed)
      return Future.error(const RecoveryInterrupted(RecoveryStopReason.closed));
    if (!scope.isCurrent)
      return Future.error(
        const RecoveryInterrupted(RecoveryStopReason.superseded),
      );
    if (cancellation?.isCancelled ?? false) {
      return Future.error(
        const RecoveryInterrupted(RecoveryStopReason.cancelled),
      );
    }
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero)
      return Future.error(
        const RecoveryInterrupted(RecoveryStopReason.deadline),
      );
    _blockedCredentials.removeWhere((_, blocked) {
      blocked.removeWhere((scope) => !scope.isCurrent);
      return blocked.isEmpty;
    });
    final key = (target, scope.key);
    final job = _jobs.putIfAbsent(key, () {
      final created = _RecoveryJob(this, key, target, scope);
      _draining.add(created);
      return created;
    });
    final consumer = _Consumer(scope, deadline);
    job.consumers.add(consumer);
    consumer.timer = Timer(
      remaining,
      () => job.stop(consumer, RecoveryStopReason.deadline),
    );
    consumer.unlisten = cancellation?.listen(
      () => job.stop(consumer, RecoveryStopReason.cancelled),
    );
    job.start();
    return consumer.completion.future;
  }

  void _blockCredentials(Iterable<RecoveryScope> scopes) {
    for (final scope in scopes) {
      _blockedCredentials
          .putIfAbsent(scope.credentialKey, () => <RecoveryScope>{})
          .add(scope);
    }
    // 只撤销使用已拒材料的登录控制柄。会话校验和其他材料继续独立执行。
    for (final login in _logins.values.toList()) {
      final affected = login.members
          .expand((job) => job.consumers)
          .map((consumer) => consumer.scope)
          .where(
            (scope) =>
                scope.isCurrent &&
                _blockedCredentials.containsKey(scope.credentialKey),
          )
          .toList();
      if (affected.isEmpty) continue;
      for (final scope in affected) {
        _blockedCredentials[scope.credentialKey]!.add(scope);
      }
      login.operation?.cancel();
    }
  }

  /// 组合根改变账号或路线后可同步撤销；活动任务也会定期核对代次。
  void validateScopes() {
    for (final job in _draining.toList()) {
      job.validate();
    }
  }

  Future<RecoveryCloseResult> close({
    Duration grace = const Duration(seconds: 1),
  }) async {
    _closed = true;
    for (final job in _draining.toList()) {
      for (final consumer in job.consumers.toList()) {
        job.stop(consumer, RecoveryStopReason.closed);
      }
    }
    await Future.wait(
      _draining.map((job) => job.settled.future),
    ).timeout(grace, onTimeout: () => <void>[]);
    return RecoveryCloseResult(pendingOperations);
  }
}

final class _Consumer {
  _Consumer(this.scope, this.deadline);
  final RecoveryScope scope;
  final DateTime deadline;
  final completion = Completer<RecoveryResult>();
  Timer? timer;
  void Function()? unlisten;
  void release() {
    timer?.cancel();
    unlisten?.call();
  }
}

final class _RecoveryJob {
  _RecoveryJob(this.owner, this.key, this.feature, this.scope);
  final RequiredSessionRecovery owner;
  final Object key;
  final RecoveryTarget feature;
  final RecoveryScope scope;
  final consumers = <_Consumer>{};
  final settled = Completer<void>();
  RequiredRecoveryOperation? operation;
  _SharedLogin? login;
  Timer? watcher;
  bool started = false;
  bool revoked = false;
  bool inBoundary = false;
  bool checking = false;
  Future<void>? validation;

  void validate() {
    for (final consumer in consumers.toList()) {
      if (!consumer.scope.isCurrent)
        stop(consumer, RecoveryStopReason.superseded);
    }
  }

  void stopAccepting() {
    if (identical(owner._jobs[key], this)) owner._jobs.remove(key);
  }

  void stop(_Consumer consumer, RecoveryStopReason reason) {
    if (!consumers.remove(consumer)) return;
    consumer.release();
    consumer.completion.completeError(RecoveryInterrupted(reason));
    if (consumers.isEmpty) {
      revoked = true;
      watcher?.cancel();
      stopAccepting();
      operation?.cancel();
      login?.leave(this);
    }
  }

  void check() {
    validate();
    if (revoked || owner._closed || consumers.isEmpty) {
      throw const RecoveryInterrupted(RecoveryStopReason.superseded);
    }
  }

  bool acceptsDelivery(_Consumer consumer) {
    if (!consumers.contains(consumer) || consumer.completion.isCompleted)
      return false;
    if (!consumer.scope.isCurrent) {
      stop(consumer, RecoveryStopReason.superseded);
      return false;
    }
    return true;
  }

  Future<void> checkpoint() async {
    check();
    for (final consumer in consumers.toList()) {
      try {
        await consumer.scope.validatePersistent();
      } on Object {
        stop(consumer, RecoveryStopReason.superseded);
      }
    }
    check();
  }

  void start() {
    if (started) return;
    started = true;
    watcher = Timer.periodic(const Duration(milliseconds: 20), (_) {
      validate();
      if (inBoundary && !checking) {
        checking = true;
        validation = checkpoint()
            .catchError((Object _) {})
            .whenComplete(() => checking = false);
        unawaited(validation);
      }
    });
    unawaited(run());
  }

  Future<RecoveredRouteSession> invoke(
    RequiredRecoveryOperation Function(ControlledRequiredSessionBackend)
    controlled,
    Future<RecoveredRouteSession> Function() legacy,
  ) async {
    check();
    final backend = owner.backend;
    if (backend is! ControlledRequiredSessionBackend) return legacy();
    final current = controlled(backend);
    operation = current;
    try {
      return await current.result;
    } finally {
      operation = null;
      current.dispose();
    }
  }

  Future<void> run() async {
    try {
      if (!scope.isShared) {
        await execute();
      } else {
        await scope.coordinateRecovery(() async {
          check();
          final changed = await scope.adoptRecoverySuccessor();
          check();
          await checkpoint();
          final state = scope.sharedSnapshot?.state;
          if (changed &&
              owner._publishedAccount !=
                  (state?.account?.id, state?.generation))
            await rebuild();
          if (owner.backend case final SharedAccountBackend backend
              when owner._publishedAccount !=
                  (state?.account?.id, state?.generation)) {
            final binding = await scope.sharedBinding();
            if (binding != null) {
              owner.beforeSharedRebind?.call();
              await backend.bindSharedAccount(binding);
            }
          }
          inBoundary = true;
          await execute();
        }, () => !revoked && !owner._closed && consumers.isNotEmpty);
      }
    } on Object catch (error, stack) {
      stopAccepting();
      for (final consumer in consumers.toList()) {
        consumer.release();
        consumer.completion.completeError(
          error is LocalAccountConflict ||
                  error is MaterialCoordinationException
              ? const RecoveryInterrupted(RecoveryStopReason.superseded)
              : error,
          stack,
        );
        consumers.remove(consumer);
      }
    } finally {
      login?.leave(this);
      consumers.clear();
      watcher?.cancel();
      stopAccepting();
      owner._draining.remove(this);
      owner._completedLogins.removeWhere(
        (key, _) => !owner._draining.any((job) => job.scope.key == key.$1),
      );
      settled.complete();
    }
  }

  Future<void> rebuild() async {
    await checkpoint();
    final factory = owner.rebuildBackend;
    if (factory == null)
      throw const RecoveryInterrupted(RecoveryStopReason.superseded);
    owner._backend = await factory(scope);
    await checkpoint();
  }

  Duration get remaining {
    final deadlines = consumers.map((consumer) => consumer.deadline);
    final latest = deadlines.reduce((a, b) => a.isAfter(b) ? a : b);
    final value = latest.difference(DateTime.now());
    return value.isNegative
        ? Duration.zero
        : value > const Duration(minutes: 2)
        ? const Duration(minutes: 2)
        : value;
  }

  Future<RecoveredRouteSession> recover() => invoke(
    (backend) {
      if (backend is ControlledRequiredTargetSessionBackend) {
        return backend.startTargetRecovery(feature, remaining);
      }
      final menuFeature = feature.feature;
      if (menuFeature == null)
        throw const BackendException(UbaaErrorCode.invalidInput);
      return backend.startRequiredRecovery(menuFeature, remaining);
    },
    () {
      final backend = owner.backend;
      if (backend is RequiredTargetSessionBackend)
        return backend.recoverTargetSession(feature);
      final menuFeature = feature.feature;
      if (menuFeature == null)
        throw const BackendException(UbaaErrorCode.invalidInput);
      return backend.recoverRequiredSession(menuFeature);
    },
  );

  Future<void> execute() async {
    final checkedRevision = owner._loginRevision;
    try {
      var disposition = RecoveryDisposition.reused;
      RecoveredRouteSession recovered;
      try {
        recovered = await recover();
      } on BackendException catch (error) {
        await checkpoint();
        final route = error.resolvedRoute;
        if (error.code != UbaaErrorCode.authenticationRequired ||
            route == null ||
            error.accountMismatch ||
            !scope.acceptsRoute(route) ||
            !scope.allowAutomaticLogin ||
            scope.accountAlias.trim().isEmpty ||
            scope.expectedUsername.trim().isEmpty ||
            owner._blockedCredentials.containsKey(scope.credentialKey) ||
            !owner.credentials.isAvailable)
          rethrow;
        final loginKey = (scope.key, route);
        final completed = owner._completedLogins[loginKey];
        if (completed != null && completed.$1 > checkedRevision) {
          // 只采用本次检查在途期间完成的登录，避免迟到的旧失败再次提交密码。
          recovered = completed.$2;
        } else {
          final shared = owner._logins.putIfAbsent(
            loginKey,
            () => _SharedLogin(owner, loginKey, route),
          );
          login = shared;
          recovered = await shared.join(this);
        }
        await checkpoint();
        if (recovered.route != route)
          throw const BackendException(UbaaErrorCode.upstreamChanged);
        disposition = RecoveryDisposition.reauthenticated;
      }
      await checkpoint();
      if (!scope.acceptsRoute(recovered.route))
        throw const BackendException(UbaaErrorCode.upstreamChanged);
      if (!scope.accepts(recovered.profile)) {
        throw const BackendException(
          UbaaErrorCode.authenticationRequired,
          accountMismatch: true,
        );
      }
      inBoundary = false;
      await validation;
      check();
      if (scope.publishReusedSession ||
          disposition == RecoveryDisposition.reauthenticated) {
        await scope.publishRecovery();
        if (owner.backend case final SharedAccountBackend backend) {
          final binding = await scope.sharedBinding();
          if (binding != null) {
            owner.beforeSharedRebind?.call();
            await backend.bindSharedAccount(binding);
          }
        }
      }
      if (owner.backend case final ConfirmedAppServiceAccountBackend backend) {
        backend.confirmAppServiceAccount();
      }
      final published = scope.sharedSnapshot?.state;
      if (published != null)
        owner._publishedAccount = (scope.accountAlias, published.generation);
      check();
      // 首次交付会唤醒调用方；重入请求必须创建独立任务。
      stopAccepting();
      for (final consumer in consumers.toList()) {
        try {
          if (!acceptsDelivery(consumer)) continue;
          if (!identical(consumer.scope, scope))
            await consumer.scope.adoptRecoverySuccessor();
          if (!acceptsDelivery(consumer)) continue;
          await consumer.scope.commitDelivery(() {
            // 材料读取可能等待，取消、期限和局部失效只结束所属消费者。
            if (!acceptsDelivery(consumer)) return;
            check();
            consumer.release();
            consumer.completion.complete(
              RecoveryResult(
                recovered,
                disposition,
                scope: consumer.scope,
                backend: owner.backend,
              ),
            );
            consumers.remove(consumer);
          });
        } on Object catch (error, stack) {
          if (!consumers.remove(consumer)) continue;
          consumer.release();
          consumer.completion.completeError(
            error is LocalAccountConflict
                ? const RecoveryInterrupted(RecoveryStopReason.superseded)
                : error,
            stack,
          );
        }
      }
    } on Object catch (error, stack) {
      stopAccepting();
      validate();
      for (final consumer in consumers.toList()) {
        consumer.release();
        consumer.completion.completeError(
          error is LocalAccountConflict
              ? const RecoveryInterrupted(RecoveryStopReason.superseded)
              : error,
          stack,
        );
        consumers.remove(consumer);
      }
    }
  }
}

/// 功能分别解析路线，明确缺少同一路线认证后共用一次密码提交。
final class _SharedLogin {
  _SharedLogin(this.owner, this.key, this.route);
  final RequiredSessionRecovery owner;
  final Object key;
  final ConnectionMode route;
  final members = <_RecoveryJob>{};
  RequiredRecoveryOperation? operation;
  Future<RecoveredRouteSession>? result;

  Future<RecoveredRouteSession> join(_RecoveryJob job) {
    members.add(job);
    return result ??= run();
  }

  void leave(_RecoveryJob job) {
    members.remove(job);
    if (members.isEmpty) {
      operation?.cancel();
      if (identical(owner._logins[key], this)) owner._logins.remove(key);
    }
  }

  Future<RecoveryScope> check() async {
    for (final job in members.toList()) {
      job.validate();
    }
    if (owner._closed || members.isEmpty) {
      throw const RecoveryInterrupted(RecoveryStopReason.superseded);
    }
    for (final job in members.toList()) {
      await job.checkpoint();
    }
    if (members.isEmpty)
      throw const RecoveryInterrupted(RecoveryStopReason.superseded);
    final scope = members.first.consumers.first.scope;
    if (owner._blockedCredentials.containsKey(scope.credentialKey)) {
      throw BackendException(
        UbaaErrorCode.authenticationRequired,
        resolvedRoute: route,
      );
    }
    return scope;
  }

  Future<RecoveredRouteSession> run() async {
    final scope = await check();
    final saved = await owner.credentials.read();
    await check();
    if (saved == null ||
        !saved.isUsable ||
        !saved.autoLogin ||
        !owner.credentials.isAvailable ||
        saved.username != scope.expectedUsername) {
      throw BackendException(
        UbaaErrorCode.authenticationRequired,
        resolvedRoute: route,
      );
    }
    final input = LoginInput(
      username: saved.username,
      password: saved.password,
      rememberPassword: true,
      autoLogin: true,
      routePolicy: scope.routePolicy,
    );
    await check();
    try {
      for (final job in members.toList()) {
        job.check();
      }
      if (owner._closed || members.isEmpty)
        throw const RecoveryInterrupted(RecoveryStopReason.superseded);
      final backend = owner.backend;
      RecoveredRouteSession recovered;
      if (backend is! ControlledRequiredSessionBackend) {
        recovered = await backend.loginRequiredRoute(route, input);
      } else {
        final current = backend.startRequiredLogin(
          route,
          input,
          members.map((job) => job.remaining).reduce((a, b) => a > b ? a : b),
        );
        operation = current;
        try {
          recovered = await current.result;
        } finally {
          operation = null;
          current.dispose();
        }
      }
      final currentScope = await check();
      if (recovered.route != route)
        throw const BackendException(UbaaErrorCode.upstreamChanged);
      if (!currentScope.accepts(recovered.profile)) {
        throw const BackendException(
          UbaaErrorCode.authenticationRequired,
          accountMismatch: true,
        );
      }
      owner._completedLogins[(currentScope.key, route)] = (
        ++owner._loginRevision,
        recovered,
      );
      return recovered;
    } on BackendException catch (error) {
      await check();
      if (error.captchaRequired) {
        // 人工验证码交接只暂停本次材料的自动尝试，保存的密码与自动登录许可保留。
        owner._blockCredentials(
          members
              .expand((job) => job.consumers)
              .map((consumer) => consumer.scope),
        );
        rethrow;
      }
      if (error.accountMismatch ||
          error.code == UbaaErrorCode.invalidCredentials ||
          error.code == UbaaErrorCode.upstreamChanged ||
          error.code == UbaaErrorCode.passwordRiskConfirmationFailed) {
        // 先排空已开始的核对，再由失败所属快照条件撤销持久许可。
        for (final job in members.toList()) {
          job.inBoundary = false;
          await job.validation;
        }
        final rejectedScope = await check();
        await rejectedScope.revokeRejectedCredentials();
        owner._blockCredentials(
          members
              .expand((job) => job.consumers)
              .map((consumer) => consumer.scope),
        );
      }
      rethrow;
    }
  }
}
