import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_app/src/controller/state/grade_baseline.dart';
import 'package:ubaa_app/src/controller/state/lifecycle_owners.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

const latest = GradeScoreBaseline(
  termCode: 'synthetic',
  termName: '合成',
  scores: [],
);
void main() {
  test('离线库等待期间换代时不写入旧账号', () async {
    final backend = _Backend();
    final session = SessionLifecycleOwner(backend),
        cache = CacheLifecycleOwner();
    final opened = Completer<void>();
    final owner = GradeBaselineOwner(
      (_) => cache.captureOffline(
        session: session.capture(),
        accountId: 'synthetic',
        opened: opened.future,
        accountCurrent: () => true,
      ),
    );
    final update = owner.update('synthetic', ConnectionMode.webvpn, latest);
    final checked = expectLater(update, throwsA(isA<BackendException>()));
    cache.invalidateOffline();
    opened.complete();
    await checked;
    expect(backend.calls, 0);
  });
  test('基线写入迟到时旧结果不能交付给重建后的会话', () async {
    final backend = _Backend();
    final session = SessionLifecycleOwner(backend),
        cache = CacheLifecycleOwner();
    final owner = GradeBaselineOwner(
      (_) => cache.captureOffline(
        session: session.capture(),
        accountId: 'synthetic',
        opened: Future.value(),
        accountCurrent: () => true,
      ),
    );
    final update = owner.update('synthetic', ConnectionMode.direct, latest);
    final checked = expectLater(update, throwsA(isA<BackendException>()));
    await backend.started.future;
    session.beginRebuild();
    session.endRebuild();
    backend.result.complete(latest);
    await checked;
    expect(backend.calls, 1);
  });
  test('会话退出和缓存失效分别撤销已捕获能力', () {
    final session = SessionLifecycleOwner(_Backend()),
        cache = CacheLifecycleOwner();
    final scope = session.capture();
    final read = cache.captureRead(scope);
    cache.invalidateReads();
    expect(scope.isCurrent, isTrue);
    expect(read.isCurrent, isFalse);
    session.beginSignOut();
    session.endSignOut();
    expect(scope.isCurrent, isFalse);
    expect(session.capture().isCurrent, isTrue);
    session.dispose();
    expect(session.capture().isCurrent, isFalse);
  });
}

class _Backend extends DemoBackend implements GradeScoreBaselineBackend {
  final started = Completer<void>();
  final result = Completer<GradeScoreBaseline?>();
  int calls = 0;
  @override
  Future<GradeScoreBaseline?> updateGradeScoreBaseline({
    required String accountId,
    required ConnectionMode route,
    required GradeScoreBaseline latest,
    GradeScoreBaseline? legacy,
  }) {
    calls++;
    started.complete();
    return result.future;
  }
}
