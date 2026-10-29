import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  for (final clearAccount in [false, true]) {
    testWidgets('损坏筛选可经宿主明确清除且保留其他账号：退出=$clearAccount', (tester) async {
      _largeView(tester);
      await tester.runAsync(() async {
        final values = _PreferenceValues();
        final store = PreferencesBykcCourseFilterStore(
          scope: 'synthetic-corrupt-recovery',
          values: values,
        );
        await store.write('fixture-a', BykcCourseFilters(categories: ['美育']));
        final damagedKey = values.values.keys.single;
        await store.write('fixture-b', BykcCourseFilters(categories: ['德育']));
        values.values[damagedKey] = '{';
        await tester.pumpWidget(_host(_BykcBackend(), store: store));
        await tester.pumpAndSettle();
        if (clearAccount) {
          await tester
              .widget<UbaaMainShell>(find.byType(UbaaMainShell))
              .onLogoutAndClearAccount();
          await tester.pumpAndSettle();
          expect(find.byType(UbaaLoginView), findsOneWidget);
        } else {
          await _openBykc(tester);
          await _openFilters(tester);
          await _chip(tester, '美育');
          await _tapTextButton(tester, '恢复默认');
        }
        expect(await store.read('fixture-a'), isNull);
        expect((await store.read('fixture-b'))!.categories, {'德育'});
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    });
  }

  testWidgets('普通退出后重新登录同一账号恢复三维选择及状态不限', (tester) async {
    _largeView(tester);
    await tester.pumpWidget(_host(_BykcBackend()));
    await tester.pumpAndSettle();
    await _openBykc(tester);
    await _openFilters(tester);
    await _tapTextButton(tester, '状态不限');
    await _chip(tester, '美育');
    await _chip(tester, '沙河校区');
    await _closeFilters(tester);
    expect(find.widgetWithText(Card, '合成美育沙河'), findsOneWidget);
    expect(find.widgetWithText(Card, '合成德育学院路'), findsNothing);

    await tester.widget<UbaaMainShell>(find.byType(UbaaMainShell)).onLogout();
    await tester.pumpAndSettle();
    await _login(tester, 'fixture-a');
    await _openBykc(tester);
    await _openFilters(tester);

    expect(_selected(tester, '美育'), isTrue);
    expect(_selected(tester, '沙河校区'), isTrue);
    expect(_selected(tester, '可选'), isFalse);
    expect(_selected(tester, '已选'), isFalse);
    expect(_selected(tester, '预告'), isFalse);
    expect(_selected(tester, '人数已满'), isFalse);
  });

  testWidgets('新宿主及新插件存储恢复三维，恢复默认后再次重建保持默认', (tester) async {
    _largeView(tester);
    await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp(
        'ubaa-bykc-host-test-',
      );
      try {
        final preferences = _PreferenceValues();
        var store = PreferencesBykcCourseFilterStore(
          scope: directory.path,
          values: preferences,
        );
        await tester.pumpWidget(_host(_BykcBackend(), store: store));
        await tester.pumpAndSettle();
        await store.read('fixture-a');
        await tester.pumpAndSettle();
        await _openBykc(tester);
        await _openFilters(tester);
        await _tapTextButton(tester, '状态不限');
        await _chip(tester, '美育');
        await _chip(tester, '沙河校区');
        final stored = await store.read('fixture-a');
        expect(stored!.statuses, isEmpty);
        expect(stored.categories, {'美育'});
        expect(stored.campuses, {'沙河校区'});

        await tester.pumpWidget(const SizedBox());
        store = PreferencesBykcCourseFilterStore(
          scope: directory.path,
          values: preferences,
        );
        await tester.pumpWidget(_host(_BykcBackend(), store: store));
        await tester.pumpAndSettle();
        await store.read('fixture-a');
        await tester.pumpAndSettle();
        await _openBykc(tester);
        await _openFilters(tester);
        expect(_selected(tester, '美育'), isTrue);
        expect(_selected(tester, '沙河校区'), isTrue);
        expect(_selected(tester, '可选'), isFalse);
        await _tapTextButton(tester, '恢复默认');
        expect(await store.read('fixture-a'), isNull);

        await tester.pumpWidget(const SizedBox());
        store = PreferencesBykcCourseFilterStore(
          scope: directory.path,
          values: preferences,
        );
        await tester.pumpWidget(_host(_BykcBackend(), store: store));
        await tester.pumpAndSettle();
        await store.read('fixture-a');
        await tester.pumpAndSettle();
        await _openBykc(tester);
        await _openFilters(tester);
        expect(_selected(tester, '美育'), isFalse);
        expect(_selected(tester, '沙河校区'), isFalse);
        expect(_selected(tester, '可选'), isTrue);
        expect(_selected(tester, '预告'), isTrue);
        expect(_selected(tester, '人数已满'), isTrue);
        expect(_selected(tester, '已选'), isTrue);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await directory.delete(recursive: true);
      }
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('同一宿主切换账号只恢复本账号偏好且旧保存回调被拒绝', (tester) async {
    _largeView(tester);
    final store = MemoryBykcCourseFilterStore();
    await store.write('fixture-a', BykcCourseFilters(categories: ['美育']));
    await store.write('fixture-b', BykcCourseFilters(categories: ['德育']));
    await tester.pumpWidget(_host(_BykcBackend(), store: store));
    await tester.pumpAndSettle();
    final oldShell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    await oldShell.onLogout();
    await tester.pumpAndSettle();
    await _login(tester, 'fixture-b');
    await _openBykc(tester);
    await _openFilters(tester);
    expect(_selected(tester, '美育'), isFalse);
    expect(_selected(tester, '德育'), isTrue);
    await expectLater(
      oldShell.onSaveBykcFilters!(BykcCourseFilters(statuses: const [])),
      throwsA(isA<UiError>()),
    );
    expect((await store.read('fixture-a'))!.categories, {'美育'});
    expect((await store.read('fixture-b'))!.categories, {'德育'});
  });

  for (final failures in [
    (vault: false, grade: false, filters: false),
    (vault: true, grade: false, filters: false),
    (vault: false, grade: true, filters: false),
    (vault: true, grade: true, filters: false),
    (vault: false, grade: false, filters: true),
  ]) {
    testWidgets('明确退出继续尝试所有清理并汇总：$failures', (tester) async {
      final vault = _FailingVault()..failClear = failures.vault;
      final grades = _GradeStore()..failClear = failures.grade;
      final filters = _FilterStore()..failClear = failures.filters;
      await filters.memory.write(
        'fixture-a',
        BykcCourseFilters(categories: ['美育']),
      );
      await filters.memory.write(
        'fixture-b',
        BykcCourseFilters(categories: ['德育']),
      );
      await tester.pumpWidget(
        _host(_BykcBackend(), store: filters, vault: vault, grades: grades),
      );
      await tester.pumpAndSettle();
      final clearing = tester
          .widget<UbaaMainShell>(find.byType(UbaaMainShell))
          .onLogoutAndClearAccount();
      if (failures.vault || failures.grade || failures.filters) {
        await expectLater(
          clearing,
          throwsA(
            isA<UiError>().having(
              (e) => e.message,
              '固定反馈',
              '本机数据未能完全清除，请稍后重试。',
            ),
          ),
        );
      } else {
        await clearing;
      }
      await tester.pumpAndSettle();

      expect(vault.attempts, 1);
      expect(grades.cleared, ['fixture-a']);
      expect(filters.cleared, ['fixture-a']);
      expect(
        await filters.memory.read('fixture-a'),
        failures.filters ? isNotNull : isNull,
      );
      expect((await filters.memory.read('fixture-b'))!.categories, {'德育'});
      expect(find.byType(UbaaMainShell), findsNothing);
      expect(find.byType(UbaaLoginView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('保存后明确清除在后台恢复交叉时保持顺序，成绩和筛选在途均阻止重建', (tester) async {
    _largeView(tester);
    final state = _BykcSession();
    final grades = _GradeStore()..clearGate = Completer<void>();
    final filters = _FilterStore()
      ..writeGate = Completer<void>()
      ..clearGate = Completer<void>();
    var factories = 0;
    await tester.pumpWidget(
      UbaaAppHost(
        backendFactory: () {
          factories++;
          return _BykcBackend(session: state);
        },
        initialDestination: UiDestination.coursework,
        credentialVault: MemoryCredentialVault(),
        reminderStore: MemoryYgdkReminderStore(),
        gradeScoreStore: grades,
        bykcFilterStore: filters,
      ),
    );
    await tester.pumpAndSettle();
    await _openBykc(tester);
    await _openFilters(tester);
    await _chip(tester, '美育');
    final clearing = tester
        .widget<UbaaMainShell>(find.byType(UbaaMainShell))
        .onLogoutAndClearAccount();
    await tester.pumpAndSettle();
    await _backgroundAndResume(tester);
    expect(factories, 1);
    expect(grades.cleared, ['fixture-a']);
    expect(filters.cleared, isEmpty);
    grades.clearGate!.complete();
    await tester.pumpAndSettle();
    expect(filters.cleared, ['fixture-a']);
    expect(factories, 1);
    filters.writeGate!.complete();
    await tester.pumpAndSettle();
    expect(factories, 1);
    filters.clearGate!.complete();
    await clearing;
    await tester.pumpAndSettle();

    expect(factories, 1);
    expect(filters.mutations, ['保存完成:fixture-a', '清除完成:fixture-a']);
    expect(await filters.memory.read('fixture-a'), isNull);
    expect(find.byType(UbaaLoginView), findsOneWidget);
    await _login(tester, 'fixture-a');
    await _openBykc(tester);
    await _openFilters(tester);
    expect(_selected(tester, '美育'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('旧账号清除收尾前阻止新登录且新偏好不被旧回调覆盖', (tester) async {
    _largeView(tester);
    final grades = _GradeStore()..clearGate = Completer<void>();
    final filters = _FilterStore();
    await filters.memory.write(
      'fixture-a',
      BykcCourseFilters(categories: ['美育']),
    );
    await tester.pumpWidget(
      _host(_BykcBackend(), store: filters, grades: grades),
    );
    await tester.pumpAndSettle();
    final oldShell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    final clearing = oldShell.onLogoutAndClearAccount();
    await tester.pumpAndSettle();
    final pendingLogin = tester.widget<UbaaLoginView>(
      find.byType(UbaaLoginView),
    );
    pendingLogin.onUsernameChanged('fixture-b');
    pendingLogin.onPasswordChanged('fixture-password');
    pendingLogin.onSubmit();
    await tester.pumpAndSettle();
    expect(find.byType(UbaaMainShell), findsNothing);
    grades.clearGate!.complete();
    await clearing;
    await tester.pumpAndSettle();
    await _login(tester, 'fixture-b');
    await _openBykc(tester);
    await _openFilters(tester);
    await _chip(tester, '德育');
    await expectLater(
      oldShell.onSaveBykcFilters!(BykcCourseFilters(statuses: const [])),
      throwsA(isA<UiError>()),
    );

    expect(await filters.memory.read('fixture-a'), isNull);
    expect((await filters.memory.read('fixture-b'))!.categories, {'德育'});
    expect(_selected(tester, '德育'), isTrue);
    expect(_selected(tester, '美育'), isFalse);
    expect(filters.cleared, ['fixture-a']);
  });
}

void _largeView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(980, 1080);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Widget _host(
  _BykcBackend backend, {
  BykcCourseFilterStore? store,
  CredentialVault? vault,
  GradeScoreStore? grades,
}) => UbaaAppHost(
  backend: backend,
  initialDestination: UiDestination.coursework,
  credentialVault: vault ?? MemoryCredentialVault(),
  reminderStore: MemoryYgdkReminderStore(),
  gradeScoreStore: grades ?? MemoryGradeScoreStore(),
  bykcFilterStore: store,
);

Future<void> _login(WidgetTester tester, String account) async {
  final view = tester.widget<UbaaLoginView>(find.byType(UbaaLoginView));
  view.onUsernameChanged(account);
  view.onPasswordChanged('fixture-password');
  view.onSubmit();
  await tester.pumpAndSettle();
  expect(find.byType(UbaaMainShell), findsOneWidget);
}

Future<void> _openBykc(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(Card, FeatureId.bykc.title));
  await tester.pumpAndSettle();
}

Future<void> _openFilters(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('feature-filter-button')));
  await tester.pumpAndSettle();
}

Future<void> _closeFilters(WidgetTester tester) async {
  await tester.tap(find.byTooltip('关闭筛选'));
  await tester.pumpAndSettle();
}

Future<void> _tapTextButton(WidgetTester tester, String label) async {
  final button = find.widgetWithText(TextButton, label);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _chip(WidgetTester tester, String label) async {
  final chip = find.widgetWithText(FilterChip, label);
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

bool _selected(WidgetTester tester, String label) =>
    tester.widget<FilterChip>(find.widgetWithText(FilterChip, label)).selected;

class _BykcBackend implements UbaaBackend, FeatureQueryBackend {
  _BykcBackend({_BykcSession? session}) : session = session ?? _BykcSession();
  final _BykcSession session;
  int bykcReads = 0;

  @override
  Future<AuthStatus> authStatus() async =>
      session.signedIn ? AuthStatus.signedIn : AuthStatus.signedOut;
  @override
  Future<UserSummary?> userInfo() async => session.signedIn
      ? UserSummary(username: session.account, schoolId: session.account)
      : null;
  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}
  @override
  Future<void> login(LoginInput input) async {
    session.account = input.username;
    session.signedIn = true;
  }

  @override
  Future<void> logout() async => session.signedIn = false;
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) =>
      loadFeatureQuery(feature, const FeatureQuery());
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    if (feature != FeatureId.bykc) return const FeatureResult.empty();
    bykcReads++;
    return FeatureResult.success(
      summary: '合成博雅列表',
      resolvedRoute: ConnectionMode.direct,
      details: const [
        FeatureDetail(
          title: '合成美育沙河',
          presentation: BykcCoursePresentation(
            id: 901,
            courseName: '合成美育沙河',
            status: BykcCourseStatus.available,
            subCategory: BykcCourseSubCategory.aesthetic,
            audienceCampuses: ['沙河校区'],
          ),
        ),
        FeatureDetail(
          title: '合成德育学院路',
          presentation: BykcCoursePresentation(
            id: 902,
            courseName: '合成德育学院路',
            status: BykcCourseStatus.available,
            subCategory: BykcCourseSubCategory.moral,
            audienceCampuses: ['学院路校区'],
          ),
        ),
      ],
    );
  }
}

class _BykcSession {
  String account = 'fixture-a';
  bool signedIn = true;
}

class _FailingVault extends MemoryCredentialVault {
  bool failClear = false;
  int attempts = 0;
  @override
  Future<void> clear() async {
    attempts++;
    if (failClear) throw StateError('fixture-private-vault-failure');
    await super.clear();
  }
}

class _GradeStore implements GradeScoreStore {
  final cleared = <String>[];
  bool failClear = false;
  Completer<void>? clearGate;
  @override
  Future<GradeScoreBaseline?> update(
    String account,
    ConnectionMode route,
    GradeScoreBaseline value,
  ) async => null;
  @override
  Future<void> clearAccount(String account) async {
    cleared.add(account);
    await clearGate?.future;
    if (failClear) throw StateError('fixture-private-grade-failure');
  }
}

class _FilterStore implements BykcCourseFilterStore {
  final memory = MemoryBykcCourseFilterStore();
  final cleared = <String>[], mutations = <String>[];
  bool failClear = false;
  Completer<void>? writeGate, clearGate;
  Future<void> _tail = Future.value();
  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  @override
  Future<BykcCourseFilters?> read(String account) =>
      _serial(() => memory.read(account));
  @override
  Future<void> write(String account, BykcCourseFilters value) =>
      _serial(() async {
        await writeGate?.future;
        await memory.write(account, value);
        mutations.add('保存完成:$account');
      });
  @override
  Future<void> clearAccount(String account) {
    cleared.add(account);
    return _serial(() async {
      await clearGate?.future;
      if (failClear) throw StateError('fixture-private-filter-failure');
      await memory.clearAccount(account);
      mutations.add('清除完成:$account');
    });
  }
}

Future<void> _backgroundAndResume(WidgetTester tester) async {
  for (final state in [
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

class _PreferenceValues implements PreferenceValues {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}
