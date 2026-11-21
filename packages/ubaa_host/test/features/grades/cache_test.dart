import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_test_support/grades.dart' as fixtures;
import 'package:ubaa_test_support/recovery.dart' as startup;
import 'package:ubaa_test_support/privacy.dart';

void main() {
  testWidgets('宿主刷新统计时先交付本地集合，恢复失败保留内容', (tester) async {
    final accounts = await startup.widgetAccounts(tester);
    final backend = _Backend();
    await tester.pumpWidget(
      UbaaAppHost(
        preferenceValues: acceptedPrivacyPreferences(),
        backend: backend,
        localAccountStore: accounts,
      ),
    );
    await accounts.settle(tester);
    await backend.localHomeRead.future;
    await tester.pump();
    final shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    GradesAggregate? progress, result;
    final delivered = Completer<void>();
    final pending = shell
        .onLoadAllGrades!(true, (value) {
          progress = value;
          if (!delivered.isCompleted) delivered.complete();
        })
        .then((value) => result = value);
    await tester.pump();
    await delivered.future;
    expect(progress?.loadedTerms, 2);
    expect(progress?.hasSavedData, isTrue);
    expect(result, isNull);
    backend.gate.completeError(
      const BackendException(UbaaErrorCode.networkError),
    );
    await accounts.settle(tester);
    await tester.pumpAndSettle();
    await pending;
    expect(result!.loadedTerms, 2);
    expect(result!.error, isNotNull);
    await tester.pumpWidget(const SizedBox());
  });
}

class _Backend extends fixtures.GradesBackend {
  final gate = Completer<RecoveredRouteSession>();
  final localHomeRead = Completer<void>();
  @override
  Future<OfflineHomeRead> readCachedHome(RoutePolicy policy) async {
    final result = await super.readCachedHome(policy);
    localHomeRead.complete();
    return result;
  }

  @override
  Future<RecoveredRouteSession> recoverRequiredSession(FeatureId feature) =>
      gate.future;
}
