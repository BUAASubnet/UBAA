import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_platform/shared_accounts.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../contracts/backend.dart';
import '../../contracts/lifecycle.dart';
import '../../contracts/recovery.dart';
import '../../contracts/session_recovery.dart';
import '../../bridge/auth/required_session.dart';
import '../session_recovery.dart';
import '../shared_consumer.dart';

/// 只有实际写入和刷新完成才确认输出块；原生负责停止阻塞的终端操作。
abstract interface class CommandIO {
  Future<void> configure({required bool local});
  Future<List<int>?> readLine({required bool secret});
  Future<List<int>> readBody();
  Future<void> writeStdout(List<int> bytes);
  Future<void> writeStderr(List<int> bytes);
}

final class CommandMaterials {
  CommandMaterials({required this.directory, required this.materials});
  final String directory;
  final SecureMaterialStore materials;
}

/// 命令只调度既有服务。参数、业务执行、错误信封和最终输出都保留在 Rust。
final class CommandRuntime {
  CommandRuntime({
    required this.io,
    required this.openMaterials,
    this.openClient = BridgeClient.open,
    this.parse = BridgeCommand.parse,
  });
  final CommandIO io;
  final Future<CommandMaterials> Function(String? configured) openMaterials;
  final Future<BridgeClient> Function({required String configDir}) openClient;
  final BridgeCommand Function({
    required List<String> argv,
    required int remainingMillis,
  })
  parse;
  BridgeCommand? _command;
  final _cancellation = RecoveryCancellation();
  final _stopped = Completer<void>();
  bool _closed = false;
  bool _deadline = false;
  bool _local = false;
  bool _progressOutputFailed = false;
  Future<void> get stopped => _stopped.future;
  int get stoppedExitCode => _deadline && !_local ? 5 : 7;
  void expire() {
    if (_closed || _stopped.isCompleted) return;
    _deadline = true;
    cancel();
  }

  void cancel() {
    if (_closed) return;
    _command?.cancel();
    _cancellation.cancel();
    if (!_stopped.isCompleted) _stopped.complete();
  }

  Future<T> _wait<T>(Future<T> work) => Future.any([
    work,
    _stopped.future.then<T>(
      (_) => throw RecoveryInterrupted(
        _deadline ? RecoveryStopReason.deadline : RecoveryStopReason.cancelled,
      ),
    ),
  ]);

  BridgeCommandFailure _stopFailure(RecoveryStopReason reason) =>
      switch (reason) {
        RecoveryStopReason.deadline => BridgeCommandFailure.timeout,
        RecoveryStopReason.cancelled =>
          _deadline
              ? BridgeCommandFailure.timeout
              : BridgeCommandFailure.cancelled,
        RecoveryStopReason.closed => BridgeCommandFailure.cancelled,
        RecoveryStopReason.superseded => BridgeCommandFailure.authentication,
      };

  Future<int> run(
    List<String> argv, {
    Duration budget = const Duration(minutes: 2),
  }) async {
    final elapsed = Stopwatch()..start();
    final command = parse(
      argv: argv,
      remainingMillis: budget.inMilliseconds.clamp(0, 120000),
    );
    _command = command;
    final timer = Timer(budget, expire);
    if (budget <= Duration.zero) expire();
    _CommandBackend? backend;
    SharedAccountConsumer? consumer;
    try {
      final requirements = command.requirements();
      _local = requirements.class_ == BridgeCommandClass.local;
      await _wait(io.configure(local: _local));
      var input = <int>[];
      var eof = false;
      while (true) {
        final request = await _wait(
          command.inputRequest(input: input, eof: eof),
        );
        if (request.kind == BridgeCommandInputKind.ready) break;
        if (request.prompt.isNotEmpty)
          await _wait(io.writeStderr(utf8.encode(request.prompt)));
        if (request.kind == BridgeCommandInputKind.body) {
          input = List<int>.of(await _wait(io.readBody()));
          eof = true;
        } else {
          final line = await _wait(
            io.readLine(secret: request.kind == BridgeCommandInputKind.secret),
          );
          if (line == null) {
            eof = true;
          } else {
            input.addAll(line);
          }
        }
      }
      await _wait(command.prepare(input: input));
      input.fillRange(0, input.length, 0);
      final early = await command.earlyResult();
      if (early != null) return await _deliver(early);
      final environment = await _wait(
        openMaterials(requirements.configDirectory),
      );
      final accounts = SecureLocalAccountStore(environment.materials);
      if (!environment.materials.isAvailable)
        return await _deliver(await command.fail(authentication: false));
      var snapshot = await _wait(accounts.capture());
      backend = _CommandBackend(environment.directory, openClient);
      final recovery = RequiredSessionRecovery(
        backend: backend,
        credentials: PlatformCredentialVault(
          store: MaterialCredentialStore(environment.materials),
        ),
        rebuildBackend: (scope) => backend!.rebuild(scope),
      );
      consumer = SharedAccountConsumer(
        backend: backend,
        accounts: backend,
        recovery: recovery,
      );
      if (requirements.auth == BridgeCommandAuth.login) {
        snapshot = await _wait(
          environment.materials.coordinate(() async {
            await accounts.signOut();
            return accounts.capture();
          }),
        );
        final client = await _wait(backend.ensureClient());
        await _wait(client.releaseSharedAccountForLogin());
        final attempt = await _wait(client.executeCommand(command: command));
        try {
          final identity = await _wait(client.takeCommandLoginIdentity());
          await _wait(
            environment.materials.coordinate(() async {
              if (snapshot == null ||
                  !await accounts.validate(snapshot!, requireRestore: false))
                throw const LocalAccountConflict();
              final username = await client.commandLoginUsername(
                identity: identity,
              );
              await accounts.retain(username, retainSession: true);
              final retained = (await accounts.capture())!;
              try {
                await client.consumeCommandLoginIdentity(identity: identity);
              } on Object {
                await accounts.revokeIfCurrent(retained);
                rethrow;
              }
              snapshot = retained;
            }),
          );
        } on BridgeError {
          // 学校认证结果由原聚合信封交付；缺少登记身份时不能建立本机映射。
          final succeeded = await attempt.result.authenticationSucceeded();
          return await _deliver(
            succeeded
                ? await attempt.result.registrationFailed()
                : attempt.result,
          );
        }
        if (snapshot != null)
          await _wait(
            consumer.bind(accounts, snapshot!, requireRestore: false),
          );
        return await _deliver(await attempt.result.registrationSucceeded());
      }
      if (requirements.auth == BridgeCommandAuth.status &&
          snapshot?.state.account == null) {
        final attempt = await _wait(
          (await backend.ensureClient()).executeCommand(command: command),
        );
        return await _deliver(attempt.result);
      }
      if (requirements.auth == BridgeCommandAuth.logout) {
        if (snapshot == null) {
          snapshot = await _wait(
            environment.materials.coordinate(() async {
              if (await accounts.capture() != null)
                throw const LocalAccountConflict();
              await accounts.signOut();
              return accounts.capture();
            }),
          );
        }
        final client = await _wait(backend.ensureClient());
        final revoked = await _wait(accounts.revokeBinding(snapshot!));
        final ticket = await _wait(
          BridgeSharedAccount.capture(
            directory: revoked.directory,
            generation: BigInt.from(revoked.generation),
          ),
        );
        final attempt = await _wait(
          client.executeCommandLogout(command: command, scope: ticket),
        );
        return await _deliver(attempt.result);
      }
      final activeSnapshot = snapshot;
      if (activeSnapshot == null || activeSnapshot.state.account == null)
        return await _deliver(await command.fail(authentication: true));
      if (!activeSnapshot.state.canRestore &&
          requirements.class_ != BridgeCommandClass.local &&
          requirements.auth != BridgeCommandAuth.status)
        return await _deliver(await command.fail(authentication: true));
      await _wait(
        consumer.bind(accounts, activeSnapshot, requireRestore: false),
      );
      if (requirements.class_ == BridgeCommandClass.local) {
        final agenda = await _wait(backend.openAgenda());
        BridgeOfflineCache? cache;
        if (requirements.schoolCache)
          cache = await _wait(backend.openCache(accounts));
        final result = await _wait(
          cache == null
              ? command.executeAgenda(agenda: agenda, scope: backend.native!)
              : command.executeCachedAgenda(
                  agenda: agenda,
                  cache: cache,
                  scope: backend.native!,
                ),
        );
        return await _deliver(result);
      }
      final client = await _wait(backend.ensureClient());

      if (requirements.agendaSync) {
        final agenda = await _wait(backend.openAgenda());
        final result = await _wait(
          command.executeAgendaSync(
            client: client,
            agenda: agenda,
            scope: backend.native!,
            configDir: environment.directory,
          ),
        );
        return await _deliver(result);
      }

      Future<void> restore(BridgeRecoveryFeature target) async {
        final settings = await _wait(client.routeSettings());
        final scope = await _wait(
          RecoveryScope.capture(
            accounts: accounts,
            snapshot: activeSnapshot,
            routeGeneration: 1,
            backendGeneration: 1,
            credentialGeneration: 1,
            routePolicy: switch (settings.defaultPolicy) {
              BridgeRoutePolicy.auto => RoutePolicy.auto,
              BridgeRoutePolicy.direct => RoutePolicy.direct,
              BridgeRoutePolicy.webVpn => RoutePolicy.webvpn,
            },
            allowAutomaticLogin: true,
            isCurrent: () => !_closed && !_stopped.isCompleted,
          ),
        );
        final recovered = await _wait(
          recovery.ensureTargetSession(
            target: _target(target),
            scope: scope,
            deadline: DateTime.now().add(budget - elapsed.elapsed),
            cancellation: _cancellation,
          ),
        );
        await _wait((recovered.scope ?? scope).validatePersistent());
      }

      if (requirements.class_ == BridgeCommandClass.schoolWrite) {
        try {
          await restore(requirements.recoveryTarget!);
          await _wait(consumer.bind(accounts, backend.binding!.snapshot));
        } on RecoveryInterrupted catch (error) {
          return await _deliver(
            await command.failure(failure: _stopFailure(error.reason)),
          );
        } on BackendException catch (error) {
          return await _deliver(
            await command.failure(failure: _recoveryFailure(error)),
          );
        }
      }

      BridgeOfflineCache? onlineCache;
      try {
        onlineCache = await _wait(
          backend.openCache(accounts, requireExisting: false),
        );
      } on _LocalFailure {
        if (requirements.class_ == BridgeCommandClass.schoolWrite) rethrow;
      } on BridgeError {
        if (requirements.class_ == BridgeCommandClass.schoolWrite) rethrow;
      }
      Future<BridgeCommandAttempt> execute(BridgeClient current) {
        final work = onlineCache == null
            ? current.executeCommand(
                command: command,
                expectedIdentity: backend!.binding!.account.username,
              )
            : current.executeCachedCommand(
                command: command,
                expectedIdentity: backend!.binding!.account.username,
                cache: onlineCache,
              );
        return requirements.hasTransfer
            ? _withTransferProgress(command, work)
            : work;
      }

      BridgeCommandAttempt attempt;
      if (requirements.class_ == BridgeCommandClass.schoolWrite) {
        attempt = await _wait(
          consumer.schoolWrite(
            () async => execute(await backend!.ensureClient()),
          ),
        );
      } else {
        attempt = await _wait(execute(client));
      }
      if (requirements.class_ == BridgeCommandClass.readonly &&
          attempt.recoveryTarget != null) {
        try {
          await restore(attempt.recoveryTarget!);
          onlineCache = null;
          try {
            onlineCache = await _wait(
              backend.openCache(accounts, requireExisting: false),
            );
          } on _LocalFailure {
          } on BridgeError {}
          attempt = await _wait(execute(await backend.ensureClient()));
        } on RecoveryInterrupted catch (error) {
          return await _deliver(
            await command.failure(failure: _stopFailure(error.reason)),
          );
        } on LocalAccountConflict {
          return await _deliver(await command.fail(authentication: true));
        } on BackendException catch (error) {
          return await _deliver(
            await attempt.result.recoveryFailed(
              failure: _recoveryFailure(error),
            ),
          );
        }
      }
      await _wait(backend.binding!.validate());
      return await _deliver(attempt.result);
    } on RecoveryInterrupted catch (error) {
      return await _deliver(
        await command.failure(failure: _stopFailure(error.reason)),
      );
    } on LocalAccountConflict {
      return await _deliver(await command.fail(authentication: true));
    } on _LocalFailure catch (error) {
      return await _deliver(await command.failure(failure: error.failure));
    } on BridgeAgendaError catch (error) {
      return await _deliver(
        await command.failure(
          failure: switch (error.failure) {
            BridgeAgendaFailure.inactive || BridgeAgendaFailure.superseded =>
              BridgeCommandFailure.authentication,
            BridgeAgendaFailure.corrupt ||
            BridgeAgendaFailure.unsupportedVersion =>
              BridgeCommandFailure.agendaCorrupt,
            _ => BridgeCommandFailure.storage,
          },
        ),
      );
    } on Object {
      return await _deliver(await command.fail(authentication: false));
    } finally {
      _closed = true;
      timer.cancel();
      if (consumer != null) {
        await consumer.close(grace: const Duration(seconds: 1));
      } else if (backend != null) {
        await backend.dispose().timeout(
          const Duration(seconds: 1),
          onTimeout: () {},
        );
      }
      _command = null;
    }
  }

  Future<T> _withTransferProgress<T>(
    BridgeCommand command,
    Future<T> work,
  ) async {
    final finished = Completer<void>();
    Future<void> report() async {
      String? previous;
      try {
        while (!finished.isCompleted && !_stopped.isCompleted) {
          await Future.any([
            Future<void>.delayed(const Duration(milliseconds: 500)),
            finished.future,
          ]);
          if (finished.isCompleted || _stopped.isCompleted) return;
          final line = command.transferProgressLine();
          if (line != null && line != previous) {
            previous = line;
            await _wait(io.writeStderr(utf8.encode(line)));
          }
        }
      } on RecoveryInterrupted {
        // 原命令保留首次取消或期限原因。
      } on Object {
        _progressOutputFailed = true;
        cancel();
      }
    }

    final reporting = report();
    try {
      return await work;
    } finally {
      finished.complete();
      await reporting;
    }
  }

  Future<int> _deliver(BridgeCommandResult result) async {
    final delivery = await result.deliver();
    Future<void> copy(bool output) async {
      try {
        while (true) {
          final bytes = await (output
              ? delivery.nextStdout()
              : delivery.nextStderr());
          if (bytes == null) break;
          await (output ? io.writeStdout(bytes) : io.writeStderr(bytes));
          await (output
              ? delivery.acknowledgeStdout()
              : delivery.acknowledgeStderr());
        }
      } on Object {
        cancel();
        await delivery.fail();
        rethrow;
      }
    }

    try {
      await Future.wait([copy(true), copy(false)]);
      final code = await delivery.finish();
      return _progressOutputFailed ? 7 : code;
    } on Object {
      return stoppedExitCode;
    }
  }
}

RecoveryTarget _target(BridgeRecoveryFeature value) => switch (value) {
  BridgeRecoveryFeature.libBook => RecoveryTarget.libbook,
  _ => RecoveryTarget.values.byName(value.name),
};
BridgeCommandFailure _recoveryFailure(
  BackendException error,
) => switch (error.code) {
  UbaaErrorCode.authenticationRequired => BridgeCommandFailure.authentication,
  UbaaErrorCode.invalidCredentials => BridgeCommandFailure.invalidCredentials,
  UbaaErrorCode.permissionDenied => BridgeCommandFailure.permissionDenied,
  UbaaErrorCode.networkError ||
  UbaaErrorCode.upstreamUnavailable => BridgeCommandFailure.network,
  UbaaErrorCode.timeout => BridgeCommandFailure.timeout,
  UbaaErrorCode.upstreamChanged ||
  UbaaErrorCode.parseError => BridgeCommandFailure.upstreamChanged,
  _ => BridgeCommandFailure.storage,
};

final class _LocalFailure implements Exception {
  const _LocalFailure(this.failure);
  final BridgeCommandFailure failure;
}

final class _CommandBackend
    implements
        ControlledRequiredTargetSessionBackend,
        SharedAccountBackend,
        BackendLifecycle {
  _CommandBackend(this.directory, this.open);
  final String directory;
  final Future<BridgeClient> Function({required String configDir}) open;
  BridgeClient? _client;
  BridgeSharedAccount? native;
  SharedAccountBinding? binding;
  BridgeAgendaStore? _agenda;
  BridgeOfflineCache? _cache;
  bool closed = false;
  Future<BridgeClient> ensureClient() async {
    if (closed) throw const RecoveryInterrupted(RecoveryStopReason.closed);
    if (_client == null) {
      final client = await open(configDir: directory);
      if (closed) {
        await client.dispose();
        throw const RecoveryInterrupted(RecoveryStopReason.closed);
      }
      if (native != null) await client.bindSharedAccount(scope: native!);
      _client = client;
    }
    return _client!;
  }

  @override
  Future<void> bindSharedAccount(SharedAccountBinding value) async {
    await value.validate();
    final captured = await BridgeSharedAccount.capture(
      directory: value.directory,
      generation: BigInt.from(value.generation),
    );
    if (closed) throw const RecoveryInterrupted(RecoveryStopReason.closed);
    if (_client != null) await _client!.bindSharedAccount(scope: captured);
    await value.validate();
    native = captured;
    binding = value;
  }

  Future<BridgeAgendaStore> openAgenda() async {
    final account = binding!.account;
    return _agenda ??= await BridgeAgendaStore.openShared(
      configDir: directory,
      accountId: account.id,
      scope: native!,
    );
  }

  Future<BridgeOfflineCache> openCache(
    SecureLocalAccountStore accounts, {
    bool requireExisting = true,
  }) async {
    final account = binding!.account;
    if (requireExisting &&
        !await File('$directory/business-cache/${account.id}.sqlite').exists())
      throw const _LocalFailure(BridgeCommandFailure.cacheMissing);
    final List<int> key;
    try {
      key = await accounts.cacheKey(account);
    } on SecureMaterialException {
      throw const _LocalFailure(BridgeCommandFailure.cacheKeyMissing);
    }
    try {
      return _cache ??= await BridgeOfflineCache.openShared(
        configDir: directory,
        accountId: account.id,
        expectedIdentity: account.username,
        key: key,
        scope: native!,
      );
    } on BridgeError catch (error) {
      throw _LocalFailure(switch (error.cacheFailure) {
        BridgeCacheFailure.corrupt || BridgeCacheFailure.unsupportedVersion =>
          BridgeCommandFailure.cacheCorrupt,
        BridgeCacheFailure.inactive ||
        BridgeCacheFailure.superseded => BridgeCommandFailure.authentication,
        _ => BridgeCommandFailure.storage,
      });
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  Future<RequiredSessionBackend> rebuild(RecoveryScope scope) async {
    await scope.validatePersistent();
    final old = _client;
    _client = null;
    if (_cache != null) {
      await _cache!.close();
      _cache = null;
    }
    if (old != null) await old.dispose();
    final value = await scope.sharedBinding();
    if (value == null)
      throw const RecoveryInterrupted(RecoveryStopReason.superseded);
    await bindSharedAccount(value);
    await ensureClient();
    await scope.validatePersistent();
    return this;
  }

  BridgeRequiredSessionBackend get _recovery =>
      BridgeRequiredSessionBackend(_client!);
  @override
  RequiredRecoveryOperation startTargetRecovery(
    RecoveryTarget target,
    Duration limit,
  ) => _recovery.startTargetRecovery(target, limit);
  @override
  RequiredRecoveryOperation startRequiredRecovery(
    FeatureId feature,
    Duration limit,
  ) => _recovery.startRequiredRecovery(feature, limit);
  @override
  RequiredRecoveryOperation startRequiredLogin(
    ConnectionMode route,
    LoginInput input,
    Duration limit,
  ) => _recovery.startRequiredLogin(route, input, limit);
  @override
  Future<RecoveredRouteSession> recoverTargetSession(RecoveryTarget target) =>
      _recovery.recoverTargetSession(target);
  @override
  Future<RecoveredRouteSession> recoverRequiredSession(FeatureId feature) =>
      _recovery.recoverRequiredSession(feature);
  @override
  Future<RecoveredRouteSession> loginRequiredRoute(
    ConnectionMode route,
    LoginInput input,
  ) => _recovery.loginRequiredRoute(route, input);
  @override
  Future<void> dispose() async {
    if (closed) return;
    closed = true;
    if (_cache != null) await _cache!.close();
    _agenda?.dispose();
    if (_client != null) await _client!.dispose();
  }
}
