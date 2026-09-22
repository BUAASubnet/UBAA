import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../../../ubaa_app/test/offline/startup_test.dart' as startup;

void main() {
  testWidgets('生产宿主接入整学期任务和进度，取消不触发学校写入', (tester) async {
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
    final pending = shell().onSaveScheduleSemester!('selected');
    for (var i = 0; i < 20 && backend.task.calls == 0; i++) {
      await tester.pump();
    }
    expect(backend.term, 'selected');
    expect(
      shell().scheduleImports['selected']!.status,
      ScheduleImportStatus.running,
    );
    shell().onCancelScheduleImport!('selected');
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
    await pending;
    expect(backend.task.cancelled, isTrue);
    expect(
      shell().scheduleImports['selected']!.status,
      ScheduleImportStatus.cancelled,
    );
    await tester.pumpWidget(const SizedBox());
  });
}

class _Backend extends startup.FakeRecoveryBackend
    implements ScheduleImportBackend, ProgressiveReadBackend {
  final task = _Task();
  String? term;
  @override
  Future<ScheduleImportTask> beginScheduleImport(String term) async {
    this.term = term;
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
