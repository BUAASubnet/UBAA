import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_test_support/write_cache.dart' as fixtures;
import 'package:ubaa_test_support/recovery.dart' as startup;
import 'package:ubaa_test_support/navigation.dart' show openFeature;

void main() {
  testWidgets('直接选课只调用一次脱敏提交，回读和同步失败仍撤下旧动作', (tester) async {
    final backend = fixtures.SyntheticWriteCacheBackend()..failRefresh = true;
    final accounts = await startup.widgetAccounts(tester);
    await tester.pumpWidget(
      UbaaAppHost(
        backend: backend,
        localAccountStore: accounts,
        initialDestination: UiDestination.academic,
      ),
    );
    await accounts.settle(tester);
    await tester.pumpAndSettle();
    await openFeature(tester, FeatureId.bykc);
    expect(find.widgetWithText(OutlinedButton, '选课'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, '选课'));
    await tester.pump();
    expect(backend.prepares, 1);
    await accounts.settle(tester);
    expect(backend.cachedCommits, 1);
    expect(backend.ordinaryCommits, 0);
    expect(
      backend.account,
      (await tester.runAsync(accounts.read))!.account!.id,
    );
    await tester.pump();
    var shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    expect(shell.snapshots[FeatureId.bykc]!.details.single.actions, isEmpty);
    expect(
      tester
          .widget<OutlinedButton>(
            find.ancestor(
              of: find.byType(CircularProgressIndicator),
              matching: find.byType(OutlinedButton),
            ),
          )
          .onPressed,
      isNull,
    );
    backend.readback.completeError(
      const BackendException(UbaaErrorCode.networkError),
    );
    await accounts.settle(tester);
    await tester.pumpAndSettle();
    expect(backend.cachedCommits, 1);
    expect(backend.postCommitQueries, greaterThan(0));
    shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    expect(
      shell.snapshots[FeatureId.bykc]!.details.expand(
        (detail) => detail.actions,
      ),
      isEmpty,
    );
    for (final button in tester.widgetList<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '选课'),
    )) {
      expect(button.onPressed, isNull);
    }
    expect(backend.prepares, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
