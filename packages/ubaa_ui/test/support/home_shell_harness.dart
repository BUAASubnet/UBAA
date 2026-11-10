import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:ubaa_app/src/controller/home/coordinator.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'home_todos.dart';

/// 界面夹具复用生产首页编排，模拟后端只提供既有来源数据。
class HomeShellHarness extends StatefulWidget {
  const HomeShellHarness({
    super.key,
    required this.child,
    this.project,
    this.loadSupplement,
  });
  final UbaaMainShell child;
  final HomeTodoReader? project;
  final Future<FeatureResult> Function(HomeSupplement, bool)? loadSupplement;
  @override
  State<HomeShellHarness> createState() => _HomeShellHarnessState();
}

class _HomeShellHarnessState extends State<HomeShellHarness> {
  late final HomeCoordinator model;
  @override
  void initState() {
    super.initState();
    model = HomeCoordinator(
      loadSupplement: (s, f) =>
          widget.loadSupplement?.call(s, f) ??
          Future.value(const FeatureResult.empty()),
      loadDay: (_, _) async => const FeatureResult.empty(),
      project: (r) => (widget.project ?? homeTodoFixture)(r),
      refreshMain: () => widget.child.onRefresh(),
      retryMain: (f) => widget.child.onRetryFeature(f),
      changed: () {
        if (mounted) setState(() {});
      },
      now: () => (widget.child.homeClock ?? clock).now(),
    );
    sync();
  }

  void sync() {
    final shell = widget.child;
    model.update(
      owner: (
        shell.user?.username,
        shell.routePolicy,
        shell.businessCacheEpoch,
      ),
      snapshots: shell.snapshots,
      epoch: shell.readCacheEpoch,
      agenda: shell.agendaEpoch,
      active: true,
      online: widget.loadSupplement != null && !shell.connecting,
      blocked: false,
      foreground: true,
      readDays: false,
    );
  }

  @override
  void didUpdateWidget(covariant HomeShellHarness oldWidget) {
    super.didUpdateWidget(oldWidget);
    sync();
  }

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.child;
    return UbaaMainShell(
      user: shell.user,
      snapshots: shell.snapshots,
      routePolicy: shell.routePolicy,
      appService: shell.appService,
      onRefresh: shell.onRefresh,
      onRetryFeature: shell.onRetryFeature,
      onLogout: shell.onLogout,
      onLogoutAndClearAccount: shell.onLogoutAndClearAccount,
      onRoutePolicyChanged: shell.onRoutePolicyChanged,
      initialDestination: shell.initialDestination,
      campusAccountService: shell.campusAccountService,
      bhpanService: shell.bhpanService,
      onPickBhpanFile: shell.onPickBhpanFile,
      onPickBhpanDownload: shell.onPickBhpanDownload,
      onPreviewBhpanFile: shell.onPreviewBhpanFile,
      connecting: shell.connecting,
      homeClock: shell.homeClock,
      connectionStatus: shell.connectionStatus,
      writeReadbacks: shell.writeReadbacks,
      writeReadbackError: shell.writeReadbackError,
      onDismissWriteReadback: shell.onDismissWriteReadback,
      onRefreshWriteReadbacks: shell.onRefreshWriteReadbacks,
      onReconnect: shell.onReconnect,
      onCompleteLogin: shell.onCompleteLogin,
      themeMode: shell.themeMode,
      onThemeModeChanged: shell.onThemeModeChanged,
      readCacheEpoch: shell.readCacheEpoch,
      businessCacheEpoch: shell.businessCacheEpoch,
      cacheAccountId: shell.cacheAccountId,
      canClearBusinessCache: shell.canClearBusinessCache,
      onReadCacheUsage: shell.onReadCacheUsage,
      onClearBusinessCache: shell.onClearBusinessCache,
      onLoadAcademicTerms: shell.onLoadAcademicTerms,
      onLoadExamTerms: shell.onLoadExamTerms,
      onLoadAcademicWeeks: shell.onLoadAcademicWeeks,
      scheduleImports: shell.scheduleImports,
      onSaveScheduleSemester: shell.onSaveScheduleSemester,
      onCancelScheduleImport: shell.onCancelScheduleImport,
      onLoadCgyyPurposes: shell.onLoadCgyyPurposes,
      onLoadCgyyDefaults: shell.onLoadCgyyDefaults,
      onSaveCgyyDefaults: shell.onSaveCgyyDefaults,
      onLoadAppVersion: shell.onLoadAppVersion,
      ihomeService: shell.ihomeService,
      financeService: shell.financeService,
      onOpenAppLink: shell.onOpenAppLink,
      onLoadAllGrades: shell.onLoadAllGrades,
      gradeScoreNotice: shell.gradeScoreNotice,
      gradeCheckRoute: shell.gradeCheckRoute,
      onConsumeGradeNotice: shell.onConsumeGradeNotice,
      ygdkRecordsReadback: shell.ygdkRecordsReadback,
      homeState: model.state,
      onRefreshHome: model.refresh,
      onRetryHomeSource: model.retry,
      onHomeReminderChanged: model.setReminder,
      agendaEpoch: shell.agendaEpoch,
      agendaSchoolRoute: shell.agendaSchoolRoute,
      agenda: shell.agenda,
      onLoadYgdkReminder: shell.onLoadYgdkReminder,
      onSaveYgdkReminder: shell.onSaveYgdkReminder,
      onLoadBykcFilters: shell.onLoadBykcFilters,
      onSaveBykcFilters: shell.onSaveBykcFilters,
      placePreferences: shell.placePreferences,
      onSavePlacePreference: shell.onSavePlacePreference,
      onLoadRecentFeatures: shell.onLoadRecentFeatures,
      onSaveRecentFeatures: shell.onSaveRecentFeatures,
      activeRoutes: shell.activeRoutes,
      onReadDiagnostics: shell.onReadDiagnostics,
      writeState: shell.writeState,
      onRunWritePrepare: shell.onRunWritePrepare,
      onCancelWrite: shell.onCancelWrite,
      onConfirmWrite: shell.onConfirmWrite,
      onFeatureQuery: shell.onFeatureQuery,
      onOpenLockDisplay: shell.onOpenLockDisplay,
      onReadLockDisplay: shell.onReadLockDisplay,
      onPrepareBykcWrite: shell.onPrepareBykcWrite,
      onPrepareBykcSignWrite: shell.onPrepareBykcSignWrite,
      onPrepareSigninWrite: shell.onPrepareSigninWrite,
      onPrepareCgyyCancelWrite: shell.onPrepareCgyyCancelWrite,
      onPrepareLibbookReserveWrite: shell.onPrepareLibbookReserveWrite,
      onPrepareLibbookCancelWrite: shell.onPrepareLibbookCancelWrite,
      onPrepareCgyySubmitWrite: shell.onPrepareCgyySubmitWrite,
      onPrepareEvaluationWrite: shell.onPrepareEvaluationWrite,
      onPrepareYgdkSubmitWrite: shell.onPrepareYgdkSubmitWrite,
      onPickYgdkPhoto: shell.onPickYgdkPhoto,
      onCaptureYgdkPhoto: shell.onCaptureYgdkPhoto,
      onDiscardWriteIntent: shell.onDiscardWriteIntent,
      onCommitWrite: shell.onCommitWrite,
      onWriteSuccess: shell.onWriteSuccess,
      onVerifyCgyyReceipt: shell.onVerifyCgyyReceipt,
      onVerifyCgyyCancellation: shell.onVerifyCgyyCancellation,
      onRefreshEvaluationAfterWrite: shell.onRefreshEvaluationAfterWrite,
      onRefreshYgdkAfterWrite: shell.onRefreshYgdkAfterWrite,
    );
  }
}
