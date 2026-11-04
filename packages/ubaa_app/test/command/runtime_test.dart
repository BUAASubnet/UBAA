import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/command.dart';
import 'package:ubaa_app/src/contracts/session_recovery.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_bindings/src/rust/frb_generated.dart' show RustLibApi;
import 'package:ubaa_platform/shared_accounts.dart';
import '../../../ubaa_platform/test/support/shared_account_worker.dart'
    show syntheticWindowsMaterials;

class _Opaque {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Scope extends _Opaque implements BridgeSharedAccount {}

class _Cache extends _Opaque implements BridgeOfflineCache {
  @override
  Future<void> close() async {}
}

class _Agenda extends _Opaque implements BridgeAgendaStore {
  @override
  void dispose() {}
}

class _Control extends _Opaque implements BridgeRequiredRecoveryControl {
  @override
  void cancel() {}
  @override
  void dispose() {}
}

class _Api extends _Opaque implements RustLibApi {
  final timeouts = <int>[];
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString();
    if (name.contains('BridgeSharedAccountCapture'))
      return Future<BridgeSharedAccount>.value(_Scope());
    if (name.contains('BridgeAgendaStoreOpenShared'))
      return Future<BridgeAgendaStore>.value(_Agenda());
    if (name.contains('BridgeOfflineCacheOpenShared'))
      return Future<BridgeOfflineCache>.value(_Cache());
    if (name.contains('BridgeRequiredRecoveryControlNew')) {
      timeouts.add(invocation.namedArguments[#timeoutMillis] as int);
      return _Control();
    }
    return super.noSuchMethod(invocation);
  }
}

class _IO implements CommandIO {
  @override
  Future<void> configure({required bool local}) async {}
  final out = <int>[];
  final err = <int>[];
  bool failOutput = false;
  @override
  Future<List<int>?> readLine({required bool secret}) =>
      throw StateError('此命令不得读取 stdin');
  @override
  Future<List<int>> readBody() => throw StateError('此命令不得读取 stdin');
  @override
  Future<void> writeStdout(List<int> bytes) async {
    if (failOutput) throw const FileSystemException('合成断管');
    out.addAll(bytes);
  }

  @override
  Future<void> writeStderr(List<int> bytes) async {
    err.addAll(bytes);
  }
}

class _Delivery extends _Opaque implements BridgeCommandDelivery {
  _Delivery(this.label, this.code);
  final String label;
  final int code;
  int reads = 0;
  bool acknowledged = false;
  bool failed = false;
  @override
  Future<Uint8List?> nextStdout() async => reads++ == 0
      ? Uint8List.fromList(utf8.encode(jsonEncode({'result': label})))
      : null;
  @override
  Future<Uint8List?> nextStderr() async => null;
  @override
  Future<void> acknowledgeStdout() async {
    acknowledged = true;
  }

  @override
  Future<void> acknowledgeStderr() async {}
  @override
  Future<void> fail() async {
    failed = true;
  }

  @override
  Future<int> finish() async {
    if (!acknowledged) throw StateError('未经写入确认');
    return code;
  }
}

class _Result extends _Opaque implements BridgeCommandResult {
  _Result(String label, {int code = 0}) : delivery = _Delivery(label, code);
  final _Delivery delivery;
  @override
  Future<BridgeCommandDelivery> deliver() async => delivery;
  @override
  Future<bool> authenticationSucceeded() async => false;
  @override
  Future<BridgeCommandResult> recoveryFailed({
    required BridgeCommandFailure failure,
  }) async => _Result(failure.name, code: 3);
}

class _Attempt extends _Opaque implements BridgeCommandAttempt {
  _Attempt(this.result, {this.recoveryTarget});
  @override
  BridgeCommandResult result;
  @override
  BridgeRecoveryFeature? recoveryTarget;
  @override
  BridgeConnectionMode? route = BridgeConnectionMode.direct;
}

class _Command extends _Opaque implements BridgeCommand {
  _Command(this.kind, {this.early, this.auth});
  final BridgeCommandAuth? auth;
  final BridgeCommandClass kind;
  final _Result? early;
  int cancellations = 0;
  @override
  BridgeCommandRequirements requirements() => BridgeCommandRequirements(
    class_: kind,
    auth: auth,
    schoolCache: false,
    recoveryTarget: kind == BridgeCommandClass.schoolWrite
        ? BridgeRecoveryFeature.signin
        : null,
  );
  @override
  Future<BridgeCommandInput> inputRequest({
    required List<int> input,
    required bool eof,
  }) async =>
      const BridgeCommandInput(kind: BridgeCommandInputKind.ready, prompt: '');
  @override
  Future<void> prepare({required List<int> input}) async {}
  @override
  Future<BridgeCommandResult?> earlyResult() async => early;
  @override
  Future<BridgeCommandResult> fail({required bool authentication}) async =>
      _Result(
        authentication ? 'authentication' : 'material',
        code: authentication ? 3 : 7,
      );
  @override
  Future<BridgeCommandResult> failure({
    required BridgeCommandFailure failure,
  }) async => _Result(
    failure.name,
    code: switch (failure) {
      BridgeCommandFailure.timeout => 5,
      BridgeCommandFailure.authentication => 3,
      _ => 7,
    },
  );
  @override
  void cancel() {
    cancellations++;
  }
}

class _LocalCommand extends _Command {
  _LocalCommand() : super(BridgeCommandClass.local);
  @override
  Future<BridgeCommandResult> executeAgenda({
    required BridgeAgendaStore agenda,
    required BridgeSharedAccount scope,
  }) async => _Result('local');
}

class _BodyCommand extends _Command {
  _BodyCommand() : super(BridgeCommandClass.early, early: _Result('prepared'));
  @override
  Future<BridgeCommandInput> inputRequest({
    required List<int> input,
    required bool eof,
  }) async => BridgeCommandInput(
    kind: eof ? BridgeCommandInputKind.ready : BridgeCommandInputKind.body,
    prompt: '',
  );
}

class _NativeBodyIO extends _IO {
  final bytes = Uint8List.fromList([123, 125]).asUnmodifiableView();
  @override
  Future<List<int>> readBody() async => bytes;
}

class _Client extends _Opaque implements BridgeClient {
  _Client(this.invoke);
  final Future<BridgeCommandAttempt> Function(int attempt) invoke;
  int attempts = 0, recoveries = 0, logins = 0, disposals = 0, logouts = 0;
  @override
  Future<void> bindSharedAccount({required BridgeSharedAccount scope}) async {}
  @override
  Future<BridgeCommandAttempt> executeCommand({
    required BridgeCommand command,
    String? expectedIdentity,
  }) => invoke(++attempts);
  @override
  Future<BridgeCommandAttempt> executeCachedCommand({
    required BridgeCommand command,
    required String expectedIdentity,
    required BridgeOfflineCache cache,
  }) => invoke(++attempts);
  @override
  Future<BridgeCommandAttempt> executeCommandLogout({
    required BridgeCommand command,
    required BridgeSharedAccount scope,
  }) => invoke(++attempts);
  @override
  Future<BridgeRouteSettings> routeSettings() async =>
      const BridgeRouteSettings(
        defaultPolicy: BridgeRoutePolicy.direct,
        activeRoutes: [BridgeConnectionMode.direct],
      );
  @override
  Future<BridgeRequiredSession> recoverRequiredSessionControlled({
    required BridgeRecoveryFeature feature,
    required BridgeRequiredRecoveryControl control,
  }) async {
    recoveries++;
    return const BridgeRequiredSession(
      route: BridgeConnectionMode.direct,
      profile: BridgeUserProfile(username: 'synthetic-a'),
    );
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }

  @override
  Future<void> logout() async {
    logouts++;
    throw StateError('普通关闭不得退出');
  }
}

Future<
  ({
    Directory root,
    CommandMaterials environment,
    SecureLocalAccountStore accounts,
  })
>
_fixture({bool retain = true}) async {
  var repository = Directory.current.absolute;
  while (!File('${repository.path}/justfile').existsSync()) {
    repository = repository.parent;
  }
  final parent = await Directory(
    '${repository.path}/.ubaa_local/command_delivery/runtime_tests',
  ).create(recursive: true);
  final root = await parent.createTemp('consumer_');
  final materials = SecureMaterialStore(
    transport: syntheticWindowsMaterials(root),
    coordinator: MaterialCoordinator(directory: Directory('${root.path}/lock')),
  );
  await materials.probe();
  final accounts = SecureLocalAccountStore(materials);
  if (retain) await accounts.retain('synthetic-a', retainSession: true);
  return (
    root: root,
    environment: CommandMaterials(directory: root.path, materials: materials),
    accounts: accounts,
  );
}

class _SuccessorClient extends _Client {
  _SuccessorClient(super.invoke, {this.beforeSettings});
  final Future<void> Function()? beforeSettings;
  @override
  Future<BridgeRouteSettings> routeSettings() async {
    await beforeSettings?.call();
    return super.routeSettings();
  }

  @override
  Future<BridgeCommandAttempt> executeCachedCommand({
    required BridgeCommand command,
    required String expectedIdentity,
    required BridgeOfflineCache cache,
  }) async {
    if (disposals != 0) throw StateError('已关闭的旧客户端不能执行学校写入');
    return super.executeCachedCommand(
      command: command,
      expectedIdentity: expectedIdentity,
      cache: cache,
    );
  }
}

class _WaitingRecoveryClient extends _Client {
  _WaitingRecoveryClient()
    : super(
        (_) async => _Attempt(
          _Result('expired', code: 3),
          recoveryTarget: BridgeRecoveryFeature.user,
        ),
      );
  final entered = Completer<void>();
  final release = Completer<BridgeRequiredSession>();
  final finished = Completer<void>();
  @override
  Future<BridgeRequiredSession> recoverRequiredSessionControlled({
    required BridgeRecoveryFeature feature,
    required BridgeRequiredRecoveryControl control,
  }) async {
    recoveries++;
    entered.complete();
    try {
      return await release.future;
    } finally {
      finished.complete();
    }
  }
}

void main() {
  final api = _Api();
  setUpAll(() => RustLib.initMock(api: api));
  setUp(() => api.timeouts.clear());
  test('同账号外部恢复继任后学校操作只使用当前客户端一次', () async {
    final fixture = await _fixture();
    final previous = (await fixture.accounts.capture())!;
    final old = _SuccessorClient(
      (_) async => _Attempt(_Result('old')),
      beforeSettings: () async {
        await fixture.accounts.refreshIfCurrent(previous);
      },
    );
    final fresh = _SuccessorClient((_) async => _Attempt(_Result('fresh')));
    final io = _IO();
    var opens = 0;
    try {
      final runtime = CommandRuntime(
        io: io,
        parse: ({required argv, required remainingMillis}) =>
            _Command(BridgeCommandClass.schoolWrite),
        openMaterials: (_) async => fixture.environment,
        openClient: ({required configDir}) async => ++opens == 1 ? old : fresh,
      );
      expect(await runtime.run(['ubaa', 'signin', 'perform']), 0);
      expect(opens, 2);
      expect(old.disposals, 1);
      expect(old.attempts, 0);
      expect(fresh.recoveries, 1);
      expect(fresh.attempts, 1);
      expect(fresh.disposals, 1);
      expect(utf8.decode(io.out), contains('fresh'));
    } finally {
      await fixture.root.delete(recursive: true);
    }
  });
  for (final reason in [
    RecoveryStopReason.cancelled,
    RecoveryStopReason.deadline,
    RecoveryStopReason.superseded,
  ]) {
    test('只读恢复按停止原因返回 ${reason.name} 且不重跑业务', () async {
      final fixture = await _fixture();
      final client = _WaitingRecoveryClient();
      final io = _IO();
      final runtime = CommandRuntime(
        io: io,
        parse: ({required argv, required remainingMillis}) =>
            _Command(BridgeCommandClass.readonly),
        openMaterials: (_) async => fixture.environment,
        openClient: ({required configDir}) async => client,
      );
      try {
        final done = runtime.run([
          'ubaa',
          'user',
          'show',
        ], budget: const Duration(seconds: 5));
        await client.entered.future;
        if (reason == RecoveryStopReason.cancelled) {
          runtime.cancel();
        } else {
          client.release.completeError(RecoveryInterrupted(reason));
        }
        expect(
          await done,
          reason == RecoveryStopReason.cancelled
              ? 7
              : reason == RecoveryStopReason.deadline
              ? 5
              : 3,
        );
        expect(client.attempts, 1);
        expect(client.recoveries, 1);
        expect(utf8.decode(io.out), isNot(contains('expired')));
      } finally {
        if (!client.release.isCompleted)
          client.release.complete(
            const BridgeRequiredSession(
              route: BridgeConnectionMode.direct,
              profile: BridgeUserProfile(username: 'synthetic-a'),
            ),
          );
        await client.finished.future;
        await fixture.root.delete(recursive: true);
      }
    });
  }
  test('help 直接交付且不初始化材料或网络客户端', () async {
    final command = _Command(BridgeCommandClass.early, early: _Result('help'));
    final io = _IO();
    final runtime = CommandRuntime(
      io: io,
      parse: ({required argv, required remainingMillis}) => command,
      openMaterials: (_) => throw StateError('不得初始化材料'),
      openClient: ({required configDir}) => throw StateError('不得创建网络客户端'),
    );
    expect(await runtime.run(['ubaa', '--help']), 0);
    expect(utf8.decode(io.out), contains('help'));
  });
  test('语义无效命令的早期结果不会访问注入的材料 factory', () async {
    final command = _Command(
      BridgeCommandClass.local,
      early: _Result('invalid_input', code: 2),
    );
    final runtime = CommandRuntime(
      io: _IO(),
      parse: ({required argv, required remainingMillis}) => command,
      openMaterials: (_) => throw StateError('材料 factory 被调用'),
    );
    expect(
      await runtime.run(['ubaa', '--json', 'agenda', 'export', '--stdout']),
      2,
    );
  });
  test('原生通道的只读字节视图可准备并清理本进程输入副本', () async {
    final command = _BodyCommand();
    final io = _NativeBodyIO();
    final runtime = CommandRuntime(
      io: io,
      parse: ({required argv, required remainingMillis}) => command,
      openMaterials: (_) => throw StateError('无效输入不得初始化材料'),
    );
    expect(await runtime.run(['ubaa', 'agenda', 'create']), 0);
    expect(io.bytes, [123, 125]);
  });
  test('只读过期恢复后只重跑一次完整命令且只交付最终结果', () async {
    final fixture = await _fixture();
    final io = _IO();
    final command = _Command(BridgeCommandClass.readonly);
    final old = _Result('old', code: 3);
    final fresh = _Result('fresh');
    final client = _Client(
      (attempt) async => attempt == 1
          ? _Attempt(old, recoveryTarget: BridgeRecoveryFeature.user)
          : _Attempt(fresh),
    );
    try {
      final runtime = CommandRuntime(
        io: io,
        parse: ({required argv, required remainingMillis}) => command,
        openMaterials: (_) async => fixture.environment,
        openClient: ({required configDir}) async => client,
      );
      expect(
        await runtime.run([
          'ubaa',
          'user',
          'show',
        ], budget: const Duration(seconds: 5)),
        0,
      );
      expect(api.timeouts, isNotEmpty);
      expect(api.timeouts.every((v) => v > 0 && v <= 5000), true);
      expect(client.attempts, 2);
      expect(client.recoveries, 1);
      expect(old.delivery.reads, 0);
      expect(utf8.decode(io.out), contains('fresh'));
      expect(client.logouts, 0);
      expect(client.disposals, 1);
    } finally {
      await fixture.root.delete(recursive: true);
    }
  });
  test('学校写入仅在准备资格前恢复，失败后不恢复或重放', () async {
    final fixture = await _fixture();
    final io = _IO();
    final command = _Command(BridgeCommandClass.schoolWrite);
    late _Client client;
    client = _Client((_) async {
      expect(client.recoveries, 1, reason: '学校写资格准备前需要同账号会话恢复');
      return _Attempt(
        _Result('outcome_unknown', code: 5),
        recoveryTarget: BridgeRecoveryFeature.signin,
      );
    });
    try {
      final runtime = CommandRuntime(
        io: io,
        parse: ({required argv, required remainingMillis}) => command,
        openMaterials: (_) async => fixture.environment,
        openClient: ({required configDir}) async => client,
      );
      expect(await runtime.run(['ubaa', 'signin', 'perform']), 5);
      expect(client.attempts, 1);
      expect(client.recoveries, 1);
      expect(client.logouts, 0);
    } finally {
      await fixture.root.delete(recursive: true);
    }
  });
  test('另一消费者切号后拒绝迟到正文且不把旧任务续到新账号', () async {
    final fixture = await _fixture();
    final io = _IO();
    final command = _Command(BridgeCommandClass.readonly);
    final old = _Result('private-a');
    final client = _Client((_) async {
      await fixture.accounts.retain('synthetic-b', retainSession: true);
      return _Attempt(old);
    });
    try {
      final runtime = CommandRuntime(
        io: io,
        parse: ({required argv, required remainingMillis}) => command,
        openMaterials: (_) async => fixture.environment,
        openClient: ({required configDir}) async => client,
      );
      expect(await runtime.run(['ubaa', 'user', 'show']), 3);
      expect(old.delivery.reads, 0);
      expect(utf8.decode(io.out), isNot(contains('private-a')));
      expect(client.attempts, 1);
      expect(client.recoveries, 0);
    } finally {
      await fixture.root.delete(recursive: true);
    }
  });
  test('恢复许可关闭后新消费者仍可离线使用同账号本机日程', () async {
    final fixture = await _fixture();
    await fixture.accounts.revokeIfCurrent((await fixture.accounts.capture())!);
    final command = _LocalCommand();
    try {
      final runtime = CommandRuntime(
        io: _IO(),
        parse: ({required argv, required remainingMillis}) => command,
        openMaterials: (_) async => fixture.environment,
        openClient: ({required configDir}) => throw StateError('本机命令不得创建学校客户端'),
      );
      expect(await runtime.run(['ubaa', 'agenda', 'unsynced']), 0);
    } finally {
      await fixture.root.delete(recursive: true);
    }
  });
  test('未登记账号的显式退出创建受限撤销版本并保留成功退出码', () async {
    final fixture = await _fixture(retain: false);
    final io = _IO();
    final command = _Command(
      BridgeCommandClass.explicitAuth,
      auth: BridgeCommandAuth.logout,
    );
    final client = _Client((_) async => _Attempt(_Result('logged_out')));
    try {
      final runtime = CommandRuntime(
        io: io,
        parse: ({required argv, required remainingMillis}) => command,
        openMaterials: (_) async => fixture.environment,
        openClient: ({required configDir}) async => client,
      );
      expect(await runtime.run(['ubaa', 'auth', 'logout']), 0);
      expect(client.attempts, 1);
      expect(client.logouts, 0);
      final state = (await fixture.accounts.capture())!.state;
      expect(state.account, null);
      expect(state.canRestore, false);
    } finally {
      await fixture.root.delete(recursive: true);
    }
  });
  test('断管使交付失败且不追加错误正文或重跑业务', () async {
    final fixture = await _fixture();
    final io = _IO()..failOutput = true;
    final command = _Command(BridgeCommandClass.readonly);
    final result = _Result('single-result');
    final client = _Client((_) async => _Attempt(result));
    try {
      final runtime = CommandRuntime(
        io: io,
        parse: ({required argv, required remainingMillis}) => command,
        openMaterials: (_) async => fixture.environment,
        openClient: ({required configDir}) async => client,
      );
      expect(await runtime.run(['ubaa', 'user', 'show']), 7);
      expect(client.attempts, 1);
      expect(result.delivery.failed, true);
      expect(result.delivery.acknowledged, false);
      expect(command.cancellations, greaterThan(0));
    } finally {
      await fixture.root.delete(recursive: true);
    }
  });
}
