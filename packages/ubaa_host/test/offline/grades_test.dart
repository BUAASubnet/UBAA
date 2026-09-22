import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../../../ubaa_app/test/offline/grades/aggregate_test.dart' as fixtures;
import '../../../ubaa_app/test/offline/startup_test.dart' as startup;

void main() {
  testWidgets('宿主统计回调在恢复挂起时交付本地集合，失败保留内容', (tester) async {
    final backend = _Backend();
    await tester.pumpWidget(
      UbaaAppHost(
        backend: backend,
        localAccountStore: await startup.savedAccounts(),
      ),
    );
    await tester.pump();
    await tester.pump();
    final shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    GradesAggregate? progress, result;
    final pending = shell.onLoadAllGrades!(false, (value) => progress = value)
        .then((value) => result = value);
    for (var i = 0; i < 30 && progress == null; i++) {
      await tester.pump();
    }
    expect(progress?.loadedTerms, 2);
    expect(progress?.hasSavedData, isTrue);
    expect(result, isNull);
    backend.gate.completeError(
      const BackendException(UbaaErrorCode.networkError),
    );
    await tester.pumpAndSettle();
    await pending;
    expect(result!.loadedTerms, 2);
    expect(result!.error, isNotNull);
    await tester.pumpWidget(const SizedBox());
  });
}

class _Backend extends fixtures.GradesBackend {
  final gate = Completer<RecoveredRouteSession>();
  @override
  Future<RecoveredRouteSession> recoverRequiredSession(FeatureId feature) =>
      gate.future;
}
