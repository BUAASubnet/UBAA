import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_test_support/ubaa_test_support.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

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
