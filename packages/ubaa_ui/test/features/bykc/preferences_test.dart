import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

import '../../support/navigation.dart';

void main() {
  testWidgets('偏好慢读取不覆盖已编辑三维，筛选及恢复均不增学校查询', (tester) async {
    final pending = Completer<BykcCourseFilters?>();
    final state = _Scenario()..load = (_) => pending.future;
    await _mount(tester, state);
    await openFeature(tester, FeatureId.bykc);
    await openQueryPanel(tester);
    await _button(tester, '状态不限');
    await _chip(tester, '美育');
    await _chip(tester, '沙河校区');
    pending.complete(_stored);
    await tester.pumpAndSettle();

    expect(_selected(tester, '美育'), isTrue);
    expect(_selected(tester, '德育'), isFalse);
    expect(_selected(tester, '沙河校区'), isTrue);
    expect(_selected(tester, '已过期'), isFalse);
    expect(_selected(tester, '可选'), isFalse);
    expect(state.saved.last.$2.statuses, isEmpty);
    await closeQueryPanel(tester);
    expect(find.widgetWithText(Card, '合成美育沙河'), findsOneWidget);
    expect(find.widgetWithText(Card, '合成德育学院路'), findsNothing);
    expect(state.queries, 0);
  });

  for (final failOld in [false, true]) {
    testWidgets('同显示名切换学号后旧账号迟到偏好不覆盖新账号：旧读取失败=$failOld', (tester) async {
      final pending = Completer<BykcCourseFilters?>();
      final current = BykcCourseFilters(categories: ['美育'], campuses: ['沙河校区']);
      final state = _Scenario()
        ..load = (account) async =>
            account == 'fixture-a' ? await pending.future : current;
      await _mount(tester, state);
      state.update(() => state.account = 'fixture-b');
      await tester.pumpAndSettle();
      await openFeature(tester, FeatureId.bykc);
      await openQueryPanel(tester);
      if (failOld) {
        pending.completeError(StateError('fixture-private-path-and-account'));
      } else {
        pending.complete(_stored);
      }
      await tester.pumpAndSettle();

      expect(_selected(tester, '美育'), isTrue);
      expect(_selected(tester, '德育'), isFalse);
      expect(_selected(tester, '沙河校区'), isTrue);
      expect(find.textContaining('读取失败'), findsNothing);
      expect(find.textContaining('fixture-private'), findsNothing);
      await _chip(tester, '德育');
      expect(state.saved.single.$1, 'fixture-b');
      expect(state.queries, 0);
    });
  }

  testWidgets('读取坏数据回默认并提供固定反馈，不影响业务列表', (tester) async {
    final state = _Scenario()
      ..load = (_) =>
          Future.error(StateError('fixture-private-json-path-account'));
    await _mount(tester, state);
    await openFeature(tester, FeatureId.bykc);
    expect(find.text('博雅筛选读取失败，已恢复默认选择。'), findsOneWidget);
    expect(find.widgetWithText(Card, '合成美育沙河'), findsOneWidget);
    expect(find.widgetWithText(Card, '合成德育学院路'), findsOneWidget);
    expect(find.textContaining('fixture-private'), findsNothing);
    await openQueryPanel(tester);
    expect(_selected(tester, '可选'), isTrue);
    expect(_selected(tester, '预告'), isTrue);
    expect(_selected(tester, '已选'), isTrue);
    expect(_selected(tester, '人数已满'), isTrue);
    expect(_selected(tester, '已过期'), isFalse);
    expect(_selected(tester, '美育'), isFalse);
    await _chip(tester, '美育');
    expect(find.text('博雅筛选读取失败，已恢复默认选择。'), findsNothing);
    expect(state.queries, 0);
  });

  testWidgets('保存失败仍保留实际筛选并反馈，恢复默认失败也保留默认选择', (tester) async {
    final state = _Scenario()
      ..save = (_, _) =>
          Future.error(StateError('fixture-private-json-path-account'));
    await _mount(tester, state);
    await openFeature(tester, FeatureId.bykc);
    await openQueryPanel(tester);
    await _chip(tester, '美育');
    await _chip(tester, '沙河校区');
    await closeQueryPanel(tester);
    expect(find.widgetWithText(Card, '合成美育沙河'), findsOneWidget);
    expect(find.widgetWithText(Card, '合成德育学院路'), findsNothing);
    expect(find.text('筛选已生效，但未能保存，下次打开可能恢复原选择。'), findsOneWidget);
    expect(find.textContaining('fixture-private'), findsNothing);
    await openQueryPanel(tester);
    await _button(tester, '恢复默认');
    expect(_selected(tester, '美育'), isFalse);
    expect(_selected(tester, '沙河校区'), isFalse);
    expect(_selected(tester, '可选'), isTrue);
    expect(state.saved.last.$2.isDefault, isTrue);
    await closeQueryPanel(tester);
    expect(find.widgetWithText(Card, '合成德育学院路'), findsOneWidget);
    expect(find.text('筛选已生效，但未能保存，下次打开可能恢复原选择。'), findsOneWidget);
  });

  testWidgets('前次保存迟到失败不覆盖新选择或已成功保存的反馈', (tester) async {
    final pending = Completer<void>();
    var saves = 0;
    final state = _Scenario()
      ..save = (_, _) => ++saves == 1 ? pending.future : Future.value();
    await _mount(tester, state);
    await openFeature(tester, FeatureId.bykc);
    await openQueryPanel(tester);
    await _chip(tester, '美育');
    await _chip(tester, '沙河校区');
    pending.completeError(StateError('fixture-private-old-save'));
    await tester.pumpAndSettle();

    expect(_selected(tester, '美育'), isTrue);
    expect(_selected(tester, '沙河校区'), isTrue);
    expect(state.saved.first.$2.campuses, isEmpty);
    expect(state.saved.last.$2.campuses, {'沙河校区'});
    expect(find.textContaining('未能保存'), findsNothing);
    expect(find.textContaining('fixture-private'), findsNothing);
  });

  testWidgets('读取帧失效保留筛选且不重新读取偏好', (tester) async {
    final state = _Scenario();
    await _mount(tester, state);
    await openFeature(tester, FeatureId.bykc);
    await openQueryPanel(tester);
    await _chip(tester, '美育');
    state.update(() => state.epoch++);
    await tester.pumpAndSettle();
    expect(_selected(tester, '美育'), isTrue);
    expect(state.loads, 1);
    expect(state.queries, 1);
  });

  testWidgets('后台销毁旧页面后迟到读取不能改写新页面选择', (tester) async {
    final pending = Completer<BykcCourseFilters?>();
    await _mount(tester, _Scenario()..load = (_) => pending.future);
    await tester.pumpWidget(const SizedBox());
    final next = _Scenario()
      ..load = (_) async => BykcCourseFilters(statuses: const []);
    await _mount(tester, next);
    await openFeature(tester, FeatureId.bykc);
    await openQueryPanel(tester);
    pending.complete(_stored);
    await tester.pumpAndSettle();
    expect(_selected(tester, '已过期'), isFalse);
    expect(_selected(tester, '可选'), isFalse);
    expect(_selected(tester, '德育'), isFalse);
    expect(next.saved, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

final _stored = BykcCourseFilters(
  statuses: [BykcCourseStatus.expired],
  categories: ['德育'],
  campuses: ['学院路校区'],
);

class _Scenario {
  late StateSetter update;
  String account = 'fixture-a';
  int epoch = 0, queries = 0, loads = 0;
  final saved = <(String, BykcCourseFilters)>[];
  Future<BykcCourseFilters?> Function(String) load = (_) async => null;
  Future<void> Function(String, BykcCourseFilters) save = (_, _) async {};
}

Future<void> _mount(WidgetTester tester, _Scenario state) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(980, 1080);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      home: StatefulBuilder(
        builder: (context, update) {
          state.update = update;
          final account = state.account;
          return UbaaMainShell(
            user: UserSummary(username: '合成显示名', schoolId: account),
            snapshots: {
              for (final feature in FeatureId.values)
                feature: FeatureSnapshot(
                  feature: feature,
                  status: FeatureLoadStatus.success,
                  details: feature == FeatureId.bykc ? _courses : const [],
                ),
            },
            initialDestination: UiDestination.coursework,
            readCacheEpoch: state.epoch,
            onLoadBykcFilters: () {
              state.loads++;
              return state.load(account);
            },
            onSaveBykcFilters: (value) {
              state.saved.add((account, value));
              return state.save(account, value);
            },
            onFeatureQuery: (_, _) async => state.queries++,
            routePolicy: RoutePolicy.direct,
            telemetryEnabled: false,
            onRefresh: () async {},
            onRetryFeature: (_) async {},
            onLogout: () async {},
            onLogoutAndClearAccount: () async {},
            onRoutePolicyChanged: (_) {},
            onTelemetryChanged: (_) {},
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _courses = [
  FeatureDetail(
    title: '合成美育沙河',
    presentation: BykcCoursePresentation(
      id: 1,
      courseName: '合成美育沙河',
      status: BykcCourseStatus.available,
      subCategory: BykcCourseSubCategory.aesthetic,
      audienceCampuses: ['沙河校区'],
    ),
  ),
  FeatureDetail(
    title: '合成德育学院路',
    presentation: BykcCoursePresentation(
      id: 2,
      courseName: '合成德育学院路',
      status: BykcCourseStatus.available,
      subCategory: BykcCourseSubCategory.moral,
      audienceCampuses: ['学院路校区'],
    ),
  ),
];

Future<void> _button(WidgetTester tester, String label) async {
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
