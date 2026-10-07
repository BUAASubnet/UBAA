import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../../recovery/startup_test.dart' as support;

void main() {
  test('首页磁盘读取挂起不阻塞独立遮罩资料', () async {
    final backend = _Backend()..homeGate = Completer<void>();
    final controller = await setup(backend);
    try {
      await until(() => controller.displayUser?.profileEvidence != null);
      expect(controller.displayUser!.displayName, '已***名');
      expect(backend.authCalls, 0);
    } finally {
      backend.homeGate!.complete();
    }
  });

  test('手动登录已取得的新资料不能被随后打开的缓存倒退', () async {
    final backend = _Backend()
      ..signedIn = false
      ..manualName = '刚登录的资料'
      ..freshGate = Completer<ProfileRefresh>();
    final controller = await setup(backend);
    await controller.recoverSession();
    controller.setPassword('synthetic');
    await controller.submitLogin(preserveHome: true);
    await backend.refreshStarted.future;
    expect(controller.displayUser!.displayName, '刚登录的资料');
    expect(
      controller.displayUser!.profileEvidence?.origin,
      isNot(DataOrigin.persisted),
    );
    backend.freshGate!.complete(backend.fresh());
  });

  test('资料缓存展示不改变身份或认证，恢复后自动刷新失败仍保留页面', () async {
    final backend = _Backend()
      ..gate = Completer<AuthStatus>()
      ..freshGate = Completer<ProfileRefresh>();
    final controller = await setup(backend);
    await until(() => controller.displayUser?.profileEvidence != null);
    expect(controller.displayUser!.username, 'f***r');
    expect(controller.user!.username, 'fixture-user');
    expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.idle);
    controller.onHomeFirstFrame();
    final recovery = controller.recoverSession();
    backend.gate!.complete(AuthStatus.signedIn);
    await recovery;
    await backend.refreshStarted.future;
    backend.freshGate!.completeError(
      const BackendException(UbaaErrorCode.networkError),
    );
    await until(() => controller.displayUser?.profileNotice != null);
    expect(controller.phase, AppPhase.home);
    expect(controller.displayUser!.displayName, '已***名');
    expect(
      controller.displayUser!.profileEvidence!.fetchedAt,
      DateTime.fromMillisecondsSinceEpoch(100000),
    );
    expect(controller.user!.username, 'fixture-user');
    expect(backend.loginCalls, 0);
  });
  test('迟到本地资料不能覆盖同代次线上完整资料且重复恢复合并', () async {
    final backend = _Backend()..diskGate = Completer<void>();
    final controller = await setup(backend);
    controller.onHomeFirstFrame();
    await controller.recoverSession();
    await until(
      () =>
          controller.displayUser?.profileEvidence?.origin == DataOrigin.online,
    );
    backend.diskGate!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(controller.displayUser!.displayName, '线上合成姓名');
    expect(controller.displayUser!.phone, '合成手机');
    expect(controller.user!.phone, isNull);
    expect(controller.user!.displayName, isNull);
    await controller.recoverSession();
    await Future<void>.delayed(Duration.zero);
    expect(backend.refreshCalls, 1);
  });
  test('迟到的本地资料失败不把已更新在线资料标成刷新失败', () async {
    final backend = _Backend()..diskGate = Completer<void>();
    final controller = await setup(backend);
    controller.onHomeFirstFrame();
    await controller.recoverSession();
    await until(
      () =>
          controller.displayUser?.profileEvidence?.origin == DataOrigin.online,
    );
    backend.diskGate!.completeError(
      const BackendException(UbaaErrorCode.internalError),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(controller.displayUser!.profileNotice, isNull);
  });
  test('退出开始后的每次通知均隐藏展示资料', () async {
    final controller = await setup(_Backend());
    controller.onHomeFirstFrame();
    await controller.recoverSession();
    await until(
      () =>
          controller.displayUser?.profileEvidence?.origin == DataOrigin.online,
    );
    final seen = <UserSummary?>[];
    controller.addListener(() => seen.add(controller.displayUser));
    await controller.logout();
    expect(seen, isNotEmpty);
    expect(seen.whereType<UserSummary>(), isEmpty);
  });
  test('资料刷新迟到不能撤销退出或显示上一账号资料', () async {
    final backend = _Backend()..freshGate = Completer<ProfileRefresh>();
    final controller = await setup(backend);
    controller.onHomeFirstFrame();
    await controller.recoverSession();
    await backend.refreshStarted.future;
    await controller.logout();
    backend.freshGate!.complete(backend.fresh());
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(controller.user, isNull);
    expect(controller.displayUser, isNull);
    expect(controller.phase, AppPhase.login);
  });
  test('待确认写意图阻止已排队资料刷新，取消后才继续', () async {
    final backend = _Backend()..gate = Completer<AuthStatus>();
    final controller = await setup(backend);
    controller.onHomeFirstFrame();
    final recovering = controller.recoverSession();
    controller.setAppForeground(false);
    backend.gate!.complete(AuthStatus.signedIn);
    await recovering;
    controller.writeCoordinator.setIntent(
      WriteIntent(
        intentId: 'synthetic',
        operation: WriteOperation.bykcSelectCourse,
        targetSummary: '合成目标',
        resolvedRoute: ConnectionMode.direct,
        warnings: const [],
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
        requestDigest: 'synthetic',
      ),
    );
    controller.setAppForeground(true);
    await Future<void>.delayed(Duration.zero);
    expect(backend.refreshCalls, 0);
    await controller.writeCoordinator.cancel();
    await backend.refreshStarted.future;
    expect(backend.refreshCalls, 1);
  });
  test('资料刷新等待前台和现有调度器，未启动时不占网络锁', () async {
    final backend = _Backend()..gate = Completer<AuthStatus>();
    final controller = await setup(backend);
    controller.onHomeFirstFrame();
    final recovery = controller.recoverSession();
    controller.setAppForeground(false);
    backend.gate!.complete(AuthStatus.signedIn);
    await recovery;
    await Future<void>.delayed(Duration.zero);
    expect(backend.refreshCalls, 0);
    controller.setAppForeground(true);
    await backend.refreshStarted.future;
    expect(backend.refreshCalls, 1);
  });
  test('Core明确身份冲突错误也必须关闭旧账号展示', () async {
    final backend = _Backend()..freshGate = Completer<ProfileRefresh>();
    final controller = await setup(backend);
    controller.onHomeFirstFrame();
    await controller.recoverSession();
    await backend.refreshStarted.future;
    backend.freshGate!.completeError(
      const BackendException(
        UbaaErrorCode.authenticationRequired,
        accountMismatch: true,
      ),
    );
    await until(() => controller.phase == AppPhase.login);
    expect(controller.displayUser, isNull);
  });
  test('资料刷新身份不符不得投影其他账号', () async {
    final backend = _Backend()..foreign = true;
    final controller = await setup(backend);
    controller.onHomeFirstFrame();
    await controller.recoverSession();
    await until(() => controller.phase == AppPhase.login);
    expect(controller.user, isNull);
    expect(controller.displayUser, isNull);
    expect(backend.closed, greaterThan(0));
  });
}

Future<AppController> setup(_Backend backend) async {
  final controller = AppController(
    backend: backend,
    localAccountStore: await support.savedAccounts(),
  );
  addTearDown(controller.dispose);
  await controller.initialize();
  return controller;
}

Future<void> until(bool Function() predicate) async {
  for (var i = 0; i < 80 && !predicate(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(predicate(), isTrue);
}

class _Backend extends support.FakeRecoveryBackend
    implements OfflineCacheBackend, ProfileCacheBackend, WriteCommitBackend {
  @override
  Future<void> discardWriteIntent(String intentId) async {}
  @override
  Future<WriteCommitResult> commitWrite(String intentId) async =>
      throw StateError('资料测试禁止学校写入');
  String? manualName;
  @override
  Future<UserSummary?> userInfo() async =>
      UserSummary(username: username, displayName: manualName);
  LocalAccount? account;
  Completer<void>? diskGate, homeGate;
  Completer<ProfileRefresh>? freshGate;
  final refreshStarted = Completer<void>();
  int refreshCalls = 0, closed = 0;
  bool foreign = false;
  @override
  Future<void> openOfflineAccount(LocalAccount account, List<int> key) async {
    this.account = account;
  }

  @override
  Future<OfflineHomeRead> readCachedHome(RoutePolicy policy) async {
    await homeGate?.future;
    return OfflineHomeRead([]);
  }

  @override
  Future<void> deactivateOfflineAccount() async {
    closed++;
  }

  @override
  Future<void> clearOfflineAccount() async {}
  @override
  Future<OfflineProfileRead> readCachedProfile(RoutePolicy policy) async {
    final id = account!.id;
    await diskGate?.future;
    return OfflineProfileRead(
      CachedProfile(
        accountId: id,
        route: ConnectionMode.direct,
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(100000),
        complete: true,
        maskedUsername: 'f***r',
        maskedName: '已***名',
        maskedSchoolId: 'T***1',
      ),
    );
  }

  ProfileRefresh fresh() => ProfileRefresh(
    profile: UserSummary(
      username: foreign ? 'foreign' : 'fixture-user',
      displayName: '线上合成姓名',
      phone: '合成手机',
    ),
    route: ConnectionMode.direct,
    evidence: DataEvidence(
      accountId: account!.id,
      origin: DataOrigin.online,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(200000),
      complete: true,
      savedForOffline: true,
    ),
  );
  @override
  Future<ProfileRefresh> refreshProfile({required LocalAccount account}) async {
    refreshCalls++;
    if (!refreshStarted.isCompleted) refreshStarted.complete();
    return await freshGate?.future ?? fresh();
  }
}
