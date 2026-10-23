import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  for (final feature in [
    FeatureId.exam,
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
