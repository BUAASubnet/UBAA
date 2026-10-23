import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../../../../ubaa_app/test/recovery/startup_test.dart' as startup;
import '../../../../ubaa_ui/test/support/navigation.dart';

void main() {
  testWidgets('生产宿主进入课表自动下载，取消后右上角重新下载整学期', (tester) async {
    final backend = _Backend();
    await tester.pumpWidget(
      UbaaAppHost(
        backend: backend,
        localAccountStore: await startup.savedAccounts(),
      ),
    );
    await tester.pumpAndSettle();
    UbaaMainShell shell() => tester.widget(find.byType(UbaaMainShell));
    expect(shell().onSaveScheduleSemester, isNotNull);
    await openFeature(tester, FeatureId.schedule);
    for (var i = 0; i < 20 && backend.task.calls == 0; i++) {
      await tester.pump();
    }
    expect(backend.term, 'selected');
    expect(
      shell().scheduleImports['selected']!.status,
      ScheduleImportStatus.running,
    );
    await tester.tap(find.text('取消下载'));
    await tester.pump();
    backend.task.pending.complete(
      const ScheduleImportProgress(
        term: 'selected',
        completedWeeks: 1,
        totalWeeks: 1,
        finished: true,
        route: ConnectionMode.direct,
      ),
    );
    await tester.pumpAndSettle();
    expect(backend.task.cancelled, isTrue);
    expect(
      shell().scheduleImports['selected']!.status,
      ScheduleImportStatus.cancelled,
    );
    final reads = backend.weekReads;
    await tester.tap(find.byTooltip('刷新整学期课表'));
    await tester.pumpAndSettle();
    expect(backend.importTerms, ['selected', 'selected']);
    expect(backend.weekReads, reads);
    expect(
      shell().scheduleImports['selected']!.status,
      ScheduleImportStatus.saved,
    );
    expect(find.text('合成第3周'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

class _Backend extends startup.FakeRecoveryBackend
    implements
        ScheduleImportBackend,
        ProgressiveReadBackend,
        FeatureQueryBackend {
  final importTerms = <String>[];
  int weekReads = 0;
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    if (query.view == FeatureQueryView.scheduleTerms) {
      return FeatureResult.success(
        resolvedRoute: ConnectionMode.direct,
        details: const [
          FeatureDetail(
            title: '合成本学期',
            presentation: TermPresentation(
              code: 'selected',
              selected: true,
              index: 0,
            ),
          ),
        ],
      );
    }
    if (query.view == FeatureQueryView.scheduleWeeks) {
      return FeatureResult.success(
        resolvedRoute: ConnectionMode.direct,
        details: const [
          FeatureDetail(
            title: '合成第3周',
            presentation: WeekPresentation(
              requestTerm: 'selected',
              responseTerm: 'selected',
              number: 3,
              current: true,
              startDate: '2026-10-19',
              endDate: '2026-10-25',
            ),
          ),
        ],
      );
    }
    weekReads++;
    return const FeatureResult.empty(resolvedRoute: ConnectionMode.direct);
  }

  final task = _Task();
  String? term;
  @override
  Future<ScheduleImportTask> beginScheduleImport(String term) async {
    this.term = term;
    importTerms.add(term);
    return task;
  }

  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) async => null;
}

class _Task implements ScheduleImportTask {
  int calls = 0;
  bool cancelled = false;
  final pending = Completer<ScheduleImportProgress>();
  @override
  Future<ScheduleImportProgress> next() {
    calls++;
    return pending.future;
  }

  @override
  void cancel() => cancelled = true;
}
