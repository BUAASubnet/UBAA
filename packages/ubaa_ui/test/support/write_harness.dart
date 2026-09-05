import 'package:flutter/material.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

/// 测试只组合真实应用协调器，不复制生产写入状态机。
Widget coordinatedShell({
  required UserSummary? user,
  required Map<FeatureId, FeatureSnapshot> snapshots,
  required RoutePolicy routePolicy,
  required bool telemetryEnabled,
  required Future<void> Function() onRefresh,
  required Future<void> Function(FeatureId) onRetryFeature,
  required Future<void> Function() onLogout,
  required Future<void> Function() onLogoutAndClearAccount,
  required ValueChanged<RoutePolicy> onRoutePolicyChanged,
  required ValueChanged<bool> onTelemetryChanged,
  int initialTab = 0,
  List<ConnectionMode> activeRoutes = const <ConnectionMode>[],
  Future<void> Function(FeatureId, FeatureQuery)? onFeatureQuery,
  Future<WriteIntent> Function(WriteOperation, int)? onPrepareBykcWrite,
  BykcSignPreparer? onPrepareBykcSignWrite,
  SigninPreparer? onPrepareSigninWrite,
  CgyyCancelPreparer? onPrepareCgyyCancelWrite,
  LibbookReservePreparer? onPrepareLibbookReserveWrite,
  LibbookCancelPreparer? onPrepareLibbookCancelWrite,
  CgyyReservationPreparer? onPrepareCgyySubmitWrite,
  EvaluationSubmitPreparer? onPrepareEvaluationWrite,
  YgdkSubmitPreparer? onPrepareYgdkSubmitWrite,
  YgdkPhotoPicker? onPickYgdkPhoto,
  WriteIntentDiscarder? onDiscardWriteIntent,
  Future<WriteCommitResult> Function(String)? onCommitWrite,
  WriteSuccessHandler? onWriteSuccess,
  CgyyReceiptVerifier? onVerifyCgyyReceipt,
  CgyyCancellationVerifier? onVerifyCgyyCancellation,
  EvaluationSubmissionRefresher? onRefreshEvaluationAfterWrite,
  YgdkSubmissionRefresher? onRefreshYgdkAfterWrite,
  Key? key,
}) => _WriteHarness(
  key: key,
  shell: UbaaMainShell(
    user: user,
    snapshots: snapshots,
    routePolicy: routePolicy,
    telemetryEnabled: telemetryEnabled,
    onRefresh: onRefresh,
    onRetryFeature: onRetryFeature,
    onLogout: onLogout,
    onLogoutAndClearAccount: onLogoutAndClearAccount,
    onRoutePolicyChanged: onRoutePolicyChanged,
    onTelemetryChanged: onTelemetryChanged,
    initialTab: initialTab,
    activeRoutes: activeRoutes,
    onFeatureQuery: onFeatureQuery,
    onPrepareBykcWrite: onPrepareBykcWrite,
    onPrepareBykcSignWrite: onPrepareBykcSignWrite,
    onPrepareSigninWrite: onPrepareSigninWrite,
    onPrepareCgyyCancelWrite: onPrepareCgyyCancelWrite,
    onPrepareLibbookReserveWrite: onPrepareLibbookReserveWrite,
    onPrepareLibbookCancelWrite: onPrepareLibbookCancelWrite,
    onPrepareCgyySubmitWrite: onPrepareCgyySubmitWrite,
    onPrepareEvaluationWrite: onPrepareEvaluationWrite,
    onPrepareYgdkSubmitWrite: onPrepareYgdkSubmitWrite,
    onPickYgdkPhoto: onPickYgdkPhoto,
    onDiscardWriteIntent: onDiscardWriteIntent,
    onCommitWrite: onCommitWrite,
    onWriteSuccess: onWriteSuccess,
    onVerifyCgyyReceipt: onVerifyCgyyReceipt,
    onVerifyCgyyCancellation: onVerifyCgyyCancellation,
    onRefreshEvaluationAfterWrite: onRefreshEvaluationAfterWrite,
    onRefreshYgdkAfterWrite: onRefreshYgdkAfterWrite,
  ),
);

class _WriteHarness extends StatefulWidget {
  const _WriteHarness({required this.shell, super.key});

  final UbaaMainShell shell;

  @override
  State<_WriteHarness> createState() => _WriteHarnessState();
}

class _WriteHarnessState extends State<_WriteHarness> {
  late final WriteCoordinator _coordinator;

  @override
  void initState() {
    super.initState();
    _coordinator = WriteCoordinator(
      commit: (intentId) async {
        final commit = widget.shell.onCommitWrite;
        if (commit == null) {
          throw const BackendException(UbaaErrorCode.unsupported);
        }
        return commit(intentId);
      },
      discard: (intentId) async {
        final discard = widget.shell.onDiscardWriteIntent;
        if (discard == null) {
          throw const BackendException(UbaaErrorCode.unsupported);
        }
        await discard(intentId);
      },
      receiptVerifier: _HarnessReceiptVerifier(() => widget.shell),
    );
  }

  @override
  void dispose() {
    _coordinator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _coordinator,
    builder: (context, _) {
      final shell = widget.shell;
      return UbaaMainShell(
        user: shell.user,
        snapshots: shell.snapshots,
        routePolicy: shell.routePolicy,
        telemetryEnabled: shell.telemetryEnabled,
        onRefresh: shell.onRefresh,
        onRetryFeature: shell.onRetryFeature,
        onLogout: shell.onLogout,
        onLogoutAndClearAccount: shell.onLogoutAndClearAccount,
        onRoutePolicyChanged: shell.onRoutePolicyChanged,
        onTelemetryChanged: shell.onTelemetryChanged,
        initialTab: shell.initialTab,
        activeRoutes: shell.activeRoutes,
        writeState: _coordinator.state,
        onRunWritePrepare: _coordinator.prepareForUi,
        onCancelWrite: _coordinator.cancelForUi,
        onConfirmWrite: _coordinator.confirmForUi,
        onFeatureQuery: shell.onFeatureQuery,
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
        onDiscardWriteIntent: shell.onDiscardWriteIntent,
        onCommitWrite: shell.onCommitWrite,
        onWriteSuccess: shell.onWriteSuccess,
        onVerifyCgyyReceipt: shell.onVerifyCgyyReceipt,
        onVerifyCgyyCancellation: shell.onVerifyCgyyCancellation,
        onRefreshEvaluationAfterWrite: shell.onRefreshEvaluationAfterWrite,
        onRefreshYgdkAfterWrite: shell.onRefreshYgdkAfterWrite,
      );
    },
  );
}

/// 回调能力可以随父 widget 更新；保留 null，避免虚报已经尝试回读。
class _HarnessReceiptVerifier extends WriteReceiptVerifier {
  const _HarnessReceiptVerifier(this.shell);

  final UbaaMainShell Function() shell;

  @override
  WriteSuccessHandler? get refreshAfterWrite => shell().onWriteSuccess;

  @override
  CgyyReceiptVerifier? get verifyCgyyReceipt => shell().onVerifyCgyyReceipt;

  @override
  CgyyCancellationVerifier? get verifyCgyyCancellation =>
      shell().onVerifyCgyyCancellation;

  @override
  YgdkSubmissionRefresher? get refreshYgdkAfterWrite =>
      shell().onRefreshYgdkAfterWrite;

  @override
  EvaluationSubmissionRefresher? get refreshEvaluationAfterWrite =>
      shell().onRefreshEvaluationAfterWrite;
}
