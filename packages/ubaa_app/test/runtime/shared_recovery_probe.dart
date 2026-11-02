import 'dart:async';
import 'dart:io';
import 'package:ubaa_app/runtime.dart';
import 'package:ubaa_platform/shared_accounts.dart';
import '../../../ubaa_platform/test/support/shared_account_worker.dart'
    show syntheticWindowsMaterials;
import 'session_recovery_probe.dart'
    show check, failure, saved, profile, expired;

Future<SecureLocalAccountStore> openAccounts(Directory root) async {
  final materials = SecureMaterialStore(
    transport: syntheticWindowsMaterials(root),
    coordinator: MaterialCoordinator(directory: Directory('${root.path}/lock')),
  );
  await materials.probe();
  check(materials.isAvailable, '合成材料应可用');
  return SecureLocalAccountStore(materials);
}

Future<RecoveryScope> capture(SecureLocalAccountStore accounts) async {
  return RecoveryScope.capture(
    accounts: accounts,
    routeGeneration: 1,
    backendGeneration: 1,
    credentialGeneration: 1,
    routePolicy: RoutePolicy.direct,
    allowAutomaticLogin: true,
    isCurrent: () => true,
  );
}

class FileBackend implements RequiredSessionBackend {
  FileBackend(
    this.root, {
    this.loginGate,
    this.loginEntered,
    this.recoveryError,
    this.loginError,
  }) {
    revision = session.existsSync() ? session.readAsStringSync() : '';
  }
  final Directory root;
  final BackendException? recoveryError;
  final BackendException? loginError;
  final Future<void>? loginGate;
  final void Function()? loginEntered;
  late String revision;
  File get session => File('${root.path}/session');
  void owned() {
    if ((session.existsSync() ? session.readAsStringSync() : '') != revision) {
      throw const BackendException(UbaaErrorCode.operationConflict);
    }
  }

  @override
  Future<RecoveredRouteSession> recoverRequiredSession(
    FeatureId feature,
  ) async {
    if (recoveryError case final error?) throw error;
    owned();
    if (revision.isEmpty) throw expired;
    return const RecoveredRouteSession(
      route: ConnectionMode.direct,
      profile: profile,
    );
  }

  @override
  Future<RecoveredRouteSession> loginRequiredRoute(
    ConnectionMode route,
    LoginInput input,
  ) async {
    owned();
    await File(
      '${root.path}/submission-$pid-$hashCode',
    ).writeAsString('合成提交', flush: true);
    loginEntered?.call();
    if (loginGate != null) await loginGate;
    owned();
    if (loginError case final error?) throw error;
    revision = '会话-$pid';
    await session.writeAsString(revision, flush: true);
    return const RecoveredRouteSession(
      route: ConnectionMode.direct,
      profile: profile,
    );
  }
}

RequiredSessionRecovery service(Directory root, {FileBackend? backend}) =>
    RequiredSessionRecovery(
      backend: backend ?? FileBackend(root),
      credentials: MemoryCredentialVault(initial: saved),
      rebuildBackend: (_) async => FileBackend(root),
    );
Future<RecoveryResult> ensure(
  RequiredSessionRecovery recovery,
  RecoveryScope scope,
) => recovery.ensureRequiredSession(
  feature: FeatureId.schedule,
  scope: scope,
  deadline: DateTime.now().add(const Duration(seconds: 15)),
);
Future<Directory> fixture() async {
  var repo = Directory.current.absolute;
  while (!File('${repo.path}/justfile').existsSync()) {
    repo = repo.parent;
  }
  final base = Directory('${repo.path}/.ubaa_local/command_mode_h1b3');
  await base.create(recursive: true);
  final root = await base.createTemp('synthetic_');
  await (await openAccounts(
    root,
  )).retain(profile.username, retainSession: true);
  return root.absolute;
}

final cases = <String, Future<void> Function()>{
  '两个独立消费者使用被拒密码只提交一次，持久许可撤销': () async {
    final root = await fixture();
    final a = await openAccounts(root), b = await openAccounts(root);
    const rejected = BackendException(UbaaErrorCode.invalidCredentials);
    final one = service(root, backend: FileBackend(root, loginError: rejected));
    final two = service(root, backend: FileBackend(root, loginError: rejected));
    try {
      final scopes = await Future.wait([capture(a), capture(b)]);
      final results = await Future.wait([
        failure(ensure(one, scopes[0])),
        failure(ensure(two, scopes[1])),
      ]);
      check(results.every((error) => error is BackendException), '消费者必须结束');
      check(
        root
                .listSync()
                .whereType<File>()
                .where(
                  (file) =>
                      file.uri.pathSegments.last.startsWith('submission-'),
                )
                .length ==
            1,
        '被拒密码只能提交一次',
      );
      check(!(await a.read())!.canRestore, '被拒密码必须撤销持久恢复许可');
    } finally {
      await one.close();
      await two.close();
      await root.delete(recursive: true);
    }
  },
  '旧密码拒绝晚到不能撤销同 alias 重新登录的许可': () async {
    final root = await fixture();
    final a = await openAccounts(root), b = await openAccounts(root);
    final entered = Completer<void>(), release = Completer<void>();
    final recovery = service(
      root,
      backend: FileBackend(
        root,
        loginGate: release.future,
        loginEntered: entered.complete,
        loginError: const BackendException(UbaaErrorCode.invalidCredentials),
      ),
    );
    try {
      final pending = failure(ensure(recovery, await capture(a)));
      await entered.future;
      await b.signOut();
      final freshCredentials = MaterialCredentialStore(b.materials);
      const namespace = 'com.buaa.ubaa.credentials.v1';
      await freshCredentials.write(
        namespace,
        saved.copyWith(password: 'synthetic-new-only'),
      );
      await b.retain(profile.username, retainSession: true);
      release.complete();
      check(await pending is RecoveryInterrupted, '旧失败必须停止');
      check((await b.read())!.canRestore, '新登录许可必须保留');
      check(
        (await freshCredentials.read(namespace))?.password ==
            'synthetic-new-only',
        '旧失败必须保留新登录的凭据',
      );
    } finally {
      if (!release.isCompleted) release.complete();
      await recovery.close();
      await root.delete(recursive: true);
    }
  },
  '缺少持久继任标记的通用冲突直接停止，不重建客户端': () async {
    final root = await fixture();
    final accounts = await openAccounts(root);
    var rebuilds = 0;
    final recovery = RequiredSessionRecovery(
      backend: FileBackend(
        root,
        recoveryError: const BackendException(UbaaErrorCode.operationConflict),
      ),
      credentials: MemoryCredentialVault(initial: saved),
      rebuildBackend: (_) async {
        rebuilds++;
        return FileBackend(root);
      },
    );
    try {
      final error = await failure(ensure(recovery, await capture(accounts)));
      check(
        error is BackendException &&
            error.code == UbaaErrorCode.operationConflict &&
            rebuilds == 0,
        '通用冲突不能兑换新客户端',
      );
    } finally {
      await recovery.close();
      await root.delete(recursive: true);
    }
  },
  '恢复结果携带发布后的持久代次与继任客户端': () async {
    final root = await fixture();
    final accounts = await openAccounts(root), recovery = service(root);
    try {
      final result = await ensure(recovery, await capture(accounts));
      check(
        result.scope!.accountGeneration == (await accounts.read())!.generation,
        '恢复结果必须携带继任持久代次',
      );
      check(identical(result.backend, recovery.backend), '恢复结果必须携带实际客户端');
    } finally {
      await recovery.close();
      await root.delete(recursive: true);
    }
  },
  for (final stop in ['取消', '期限', '关闭'])
    '等待跨进程恢复锁时$stop只结束本消费者': () async {
      final root = await fixture();
      final a = await openAccounts(root), b = await openAccounts(root);
      final entered = Completer<void>(), release = Completer<void>();
      final first = service(
        root,
        backend: FileBackend(
          root,
          loginGate: release.future,
          loginEntered: entered.complete,
        ),
      );
      final second = service(root);
      final cancellation = RecoveryCancellation();
      try {
        final scopes = await Future.wait([capture(a), capture(b)]);
        final active = ensure(first, scopes[0]);
        await entered.future;
        final waiting = failure(
          second.ensureRequiredSession(
            feature: FeatureId.schedule,
            scope: scopes[1],
            deadline: DateTime.now().add(
              stop == '期限'
                  ? const Duration(milliseconds: 30)
                  : const Duration(seconds: 5),
            ),
            cancellation: cancellation,
          ),
        );
        if (stop == '取消') cancellation.cancel();
        if (stop == '关闭') await second.close();
        final error = await waiting as RecoveryInterrupted;
        check(
          error.reason ==
              (stop == '取消'
                  ? RecoveryStopReason.cancelled
                  : stop == '期限'
                  ? RecoveryStopReason.deadline
                  : RecoveryStopReason.closed),
          '消费者撤销原因不符',
        );
        check((await a.read())!.canRestore, '等待者不能撤销共享许可');
        release.complete();
        await active;
        check(
          root
                  .listSync()
                  .whereType<File>()
                  .where(
                    (file) =>
                        file.uri.pathSegments.last.startsWith('submission-'),
                  )
                  .length ==
              1,
          '等待者不应提交密码',
        );
      } finally {
        if (!release.isCompleted) release.complete();
        await first.close();
        await second.close();
        await root.delete(recursive: true);
      }
    },
  '两个独立消费者同时恢复只提交一次密码': () async {
    final root = await fixture();
    final a = await openAccounts(root), b = await openAccounts(root);
    final one = service(root), two = service(root);
    try {
      final scopes = await Future.wait([capture(a), capture(b)]);
      await Future.wait([ensure(one, scopes[0]), ensure(two, scopes[1])]);
      check(
        root
                .listSync()
                .whereType<File>()
                .where(
                  (file) =>
                      file.uri.pathSegments.last.startsWith('submission-'),
                )
                .length ==
            1,
        '密码只提交一次',
      );
    } finally {
      await one.close();
      await two.close();
      await root.delete(recursive: true);
    }
  },
  for (final action in ['退出', '切号', '退出重登'])
    '恢复挂起时另一消费者$action阻止交付': () async {
      final root = await fixture();
      final a = await openAccounts(root), b = await openAccounts(root);
      final entered = Completer<void>(), release = Completer<void>();
      final recovery = service(
        root,
        backend: FileBackend(
          root,
          loginGate: release.future,
          loginEntered: entered.complete,
        ),
      );
      try {
        final result = failure(ensure(recovery, await capture(a)));
        await entered.future;
        await b.signOut();
        if (action == '切号')
          await b.retain('synthetic-other', retainSession: true);
        if (action == '退出重登')
          await b.retain(profile.username, retainSession: true);
        release.complete();
        check(await result is RecoveryInterrupted, '持久变更后旧任务必须停止');
      } finally {
        if (!release.isCompleted) release.complete();
        await recovery.close();
        await root.delete(recursive: true);
      }
    },
};

Future<void> main(List<String> args) async {
  for (final entry in cases.entries) {
    try {
      await entry.value();
      stdout.writeln('通过：${entry.key}');
    } on Object catch (error, stack) {
      stderr.writeln('失败：${entry.key}\n$error\n$stack');
      exitCode = 1;
    }
  }
}
