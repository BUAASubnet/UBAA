import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

class SyntheticLockSession implements CgyyLockDisplaySession {
  final events = StreamController<void>.broadcast(sync: true);
  final reads = <Completer<CgyyLockDisplay>>[];
  bool closed = false;
  @override
  Stream<void> get cancelled => events.stream;
  @override
  Future<CgyyLockDisplay> read() {
    final c = Completer<CgyyLockDisplay>();
    reads.add(c);
    return c.future;
  }

  @override
  void cancel() {
    if (closed) return;
    closed = true;
    events.add(null);
    unawaited(events.close());
  }
}

class SyntheticLockBackend extends DemoBackend
    implements CgyyLockDisplayBackend, FeatureQueryBackend {
  final sessions = <SyntheticLockSession>[];
  Completer<CgyyLockDisplaySession>? opening;
  int ordinaryLockReads = 0;
  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;
  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'synthetic-account');
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      FeatureResult.empty();
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    if (query.view == FeatureQueryView.cgyyLockCode) ordinaryLockReads++;
    return FeatureResult.empty();
  }

  @override
  Future<CgyyLockDisplaySession> openLockDisplay() async {
    if (opening case final gate?) return gate.future;
    final session = SyntheticLockSession();
    sessions.add(session);
    return session;
  }
}

void main() {
  test('门锁材料不入普通快照，后台与路线改变释放并拒绝迟到', () async {
    final backend = SyntheticLockBackend();
    final controller = AppController(backend: backend);
    await controller.initialize();
    addTearDown(controller.dispose);
    final session = await controller.openLockDisplay();
    final pending = session.read();
    controller.setAppForeground(false);
    expect(backend.sessions.single.closed, isTrue);
    final late = CgyyLockDisplay(code: 'late-secret');
    backend.sessions.single.reads.single.complete(late);
    await expectLater(pending, throwsA(isA<BackendException>()));
    expect(late.code, isNull);
    controller.setAppForeground(true);
    final next = await controller.openLockDisplay();
    final read = next.read();
    final value = CgyyLockDisplay(code: '001234');
    backend.sessions.last.reads.single.complete(value);
    await read;
    expect(controller.snapshots[FeatureId.cgyy]!.details, isEmpty);
    await controller.setRoutePolicy(RoutePolicy.webvpn);
    expect(value.code, isNull);
    expect(backend.sessions.last.closed, isTrue);
  });
  test('打开门锁途中账号退出和较新页面均撤销旧句柄', () async {
    final backend = SyntheticLockBackend();
    final controller = AppController(backend: backend);
    await controller.initialize();
    addTearDown(controller.dispose);
    final first = Completer<CgyyLockDisplaySession>();
    backend.opening = first;
    final old = controller.openLockDisplay();
    backend.opening = null;
    await controller.openLockDisplay();
    final stale = SyntheticLockSession();
    first.complete(stale);
    await expectLater(old, throwsA(isA<BackendException>()));
    expect(stale.closed, isTrue);
    final second = Completer<CgyyLockDisplaySession>();
    backend.opening = second;
    final duringLogout = controller.openLockDisplay();
    await controller.logout();
    final signedOut = SyntheticLockSession();
    second.complete(signedOut);
    await expectLater(duringLogout, throwsA(isA<BackendException>()));
    expect(signedOut.closed, isTrue);
  });
}
