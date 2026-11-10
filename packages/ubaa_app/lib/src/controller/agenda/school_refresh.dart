import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/query.dart';
import '../read_scheduler.dart';
import '../state/read_scope.dart';
import '../state/state.dart';
import '../state/types.dart';

Future<void> controllerRefreshSchoolAgenda(ControllerState owner) async {
  if (owner.internalDisposed ||
      owner.internalClearingBusinessCache ||
      owner.internalReadTransitionBlocked ||
      owner.internalPhase != AppPhase.home)
    return;
  // 主来源同步推进缓存代次，补充读取再绑定这一代。
  final defaults = owner.refreshHome();
  final scope = owner.internalCaptureReadScope();
  final chosen = owner.internalLoadHomeSupplement(
    HomeSupplement.bykcChosen,
    forceRefresh: true,
  );
  final orders = owner.internalLoadHomeSupplement(
    HomeSupplement.cgyyOrders,
    forceRefresh: true,
  );
  final week = owner.internalLoadHomeSupplement(
    HomeSupplement.currentWeek,
    forceRefresh: true,
  );
  await Future.wait([defaults, chosen, orders, week]);
  if (!scope.isCurrent) return;
  for (final result in [await chosen, await orders, await week]) {
    owner.internalReportSchoolRejection(result.error);
  }
  await _refreshOrderPages(owner, scope, await orders);
  if (scope.isCurrent) await owner.internalWaitHomeSchoolCache();
}

Future<void> _refreshOrderPages(
  ControllerState owner,
  ReadScope scope,
  FeatureResult first,
) async {
  final pagination = first.pagination;
  final backend = scope.backend;
  if (first.error != null ||
      first.evidence?.complete == false ||
      pagination == null ||
      backend is! FeatureQueryBackend)
    return;
  for (var page = 1; page < pagination.effectiveTotalPages; page++) {
    if (!scope.isCurrent) return;
    try {
      final result = await owner.internalScheduleAuxiliaryRead(
        backend,
        FeatureId.cgyy,
        ReadPriority.home,
        () => scope.isCurrent,
        () => (backend as FeatureQueryBackend).loadFeatureQuery(
          FeatureId.cgyy,
          FeatureQuery(view: FeatureQueryView.cgyyOrders, page: page, size: 20),
        ),
      );
      if (!scope.isCurrent) return;
      if (result.error case final error?) {
        owner.internalRecordFailure(
          error,
          DiagnosticOperation.read,
          feature: FeatureId.cgyy,
        );
        return;
      }
      owner.internalAgendaEpoch++;
      owner.internalNotify();
      if (result.evidence?.complete == false) return;
    } on Object catch (error, stack) {
      if (scope.isCurrent)
        owner.internalRecordFailure(
          error,
          DiagnosticOperation.read,
          feature: FeatureId.cgyy,
          stackTrace: stack,
        );
      return;
    }
  }
}
