import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_test_support/ubaa_test_support.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  testWidgets('考试自动进入首页待办并可点击打开已安排考试', (tester) async {
    final backend = _ExamHomeBackend();
    await tester.pumpWidget(UbaaAppHost(backend: backend));
    await tester.pumpAndSettle();
    final task = find.widgetWithText(Card, '合成待办考试');
    await tester.ensureVisible(task);
    await tester.tap(task);
    await tester.pumpAndSettle();
    expect(backend.queries.single.view, FeatureQueryView.examArranged);
    expect(find.widgetWithText(AppBar, '考试查询'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final feature in [
    FeatureId.grades,
    FeatureId.bykc,
    FeatureId.classroom,
    FeatureId.libbook,
    FeatureId.cgyy,
    FeatureId.evaluation,
  ]) {
    testWidgets('${feature.title}首次打开自动读取，返回重进复用结果', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final backend = _LazyBackend();
      await tester.pumpWidget(UbaaAppHost(backend: backend));
      await tester.pumpAndSettle();
      UbaaMainShell shell() =>
          tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
      expect(shell().snapshots[feature]!.status, FeatureLoadStatus.idle);
      expect(backend.reads, isNot(contains(feature)));
      backend.reads.clear();

      final tab = UiDestination.forFeature(feature).index;
      await tester.tap(find.byType(NavigationDestination).at(tab));
      await tester.pumpAndSettle();
      final card = find.widgetWithText(Card, feature.title);
      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(backend.reads, [feature]);
      expect(shell().snapshots[feature]!.status, FeatureLoadStatus.empty);

      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(backend.reads, [feature]);
      expect(tester.takeException(), isNull);
    });
  }
}

class _LazyBackend extends DemoBackend {
  final reads = <FeatureId>[];
  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;
  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'synthetic-lazy-home');
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    reads.add(feature);
    return const FeatureResult.empty(resolvedRoute: ConnectionMode.direct);
  }
}

class _ExamHomeBackend extends _LazyBackend implements FeatureQueryBackend {
  final queries = <FeatureQuery>[];
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    if (feature != FeatureId.exam) return super.loadFeature(feature);
    return const FeatureResult.success(
      details: [
        FeatureDetail(
          title: '合成待办考试',
          presentation: ExamPresentation(
            arranged: true,
            date: '2099-10-25',
            startTime: '10:00',
            endTime: '12:00',
            place: '合成考场',
            seat: '8',
          ),
        ),
      ],
      resolvedRoute: ConnectionMode.direct,
    );
  }

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    if (feature == FeatureId.exam) queries.add(query);
    return loadFeature(feature);
  }
}
