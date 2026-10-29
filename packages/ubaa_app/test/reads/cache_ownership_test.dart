import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_test_support/ubaa_test_support.dart';
import 'package:ubaa_app/src/controller/read_scheduler.dart' show ReadDemand;
import 'package:ubaa_app/src/controller/state/academic_terms.dart';
import 'package:ubaa_app/src/controller/state/read_scope.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  test('失效后的旧完成不能发布学期或清掉继任在途读取', () async {
    final owner = AcademicTermsOwner();
    final scope = _scope();
    final old = Completer<FeatureResult>(), fresh = Completer<FeatureResult>();
    final first = _load(owner, scope, (_, _) => old.future);
    owner.invalidate();
    final next = _load(owner, scope, (_, _) => fresh.future);
    old.complete(_term('old'));
    expect((await first).error?.code, UbaaErrorCode.operationConflict);
    final shared = _load(owner, scope, (_, _) => throw StateError('必须合并在途读取'));
    expect(shared, same(next));
    expect(owner.currentTermCode(scope), isNull);
    fresh.complete(_term('new'));
    await next;
    expect(owner.currentTermCode(scope), 'new');
  });

  test('旧会话失效后窄读取接口不提供缓存学期', () async {
    final owner = AcademicTermsOwner();
    var valid = true;
    final scope = _scope(current: () => valid);
    await _load(owner, scope, (_, _) async => _term('current'));
    final CurrentTermsReader reader = owner;
    expect(reader.currentTermCode(scope), 'current');
    valid = false;
    expect(reader.currentTermCode(scope), isNull);
    expect(
      (await _load(
        owner,
        scope,
        (_, _) => throw StateError('不得读取'),
      )).error?.code,
      UbaaErrorCode.operationConflict,
    );
  });

  test('显式读取提升共享后台任务，失败不成为完成缓存', () async {
    final owner = AcademicTermsOwner(), scope = _scope();
    final gate = Completer<FeatureResult>();
    ReadDemand? demand;
    var pumps = 0;
    final first = owner.load(
      scope: scope,
      forceRefresh: false,
      priority: ReadPriority.background,
      fetch: (_, value) {
        demand = value;
        return gate.future;
      },
      conflict: _conflict,
      pump: () => pumps++,
    );
    final next = owner.load(
      scope: scope,
      forceRefresh: true,
      priority: ReadPriority.interactive,
      fetch: (_, _) => throw StateError('不得重复读取'),
      conflict: _conflict,
      pump: () => pumps++,
    );
    expect(next, same(first));
    expect(demand!.priority, ReadPriority.interactive);
    expect(pumps, 1);
    gate.complete(_conflict());
    await next;
    expect(owner.currentTermCode(scope), isNull);
    await _load(owner, scope, (_, _) async => _term('retry'));
    expect(owner.currentTermCode(scope), 'retry');
  });
}

ReadScope _scope({bool Function()? current}) => ReadScope(
  SessionScope(DemoBackend(), 1, current ?? () => true),
  1,
  () => true,
);
Future<FeatureResult> _load(
  AcademicTermsOwner owner,
  ReadScope scope,
  Future<FeatureResult> Function(bool Function(), ReadDemand) fetch,
) => owner.load(
  scope: scope,
  forceRefresh: false,
  priority: ReadPriority.interactive,
  fetch: fetch,
  conflict: _conflict,
  pump: () {},
);
FeatureResult _conflict() => const FeatureResult.failure(
  UiError(code: UbaaErrorCode.operationConflict, title: '已失效', message: '已失效'),
);
FeatureResult _term(String code) => FeatureResult.success(
  details: [
    FeatureDetail(
      title: code,
      presentation: TermPresentation(code: code, selected: true, index: 0),
    ),
  ],
);
