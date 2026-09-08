import 'dart:async';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../ui_coursework/backend.dart';
part 'data.dart';

/// 显式博雅合成backend；不读取账号、不进入FRB，commit始终拒绝。
class BoyaBackend extends CourseworkBackend implements BykcWriteBackend {
  BoyaBackend({super.state}) {
    signedIn = true;
  }
  final boyaReads = <FeatureQuery>[];
  final preparedBoya = <(WriteOperation, int, int?)>[];
  final _viewCounts = <FeatureQueryView, int>{};
  Completer<void>? pending;
  bool failNext = false;
  bool emptyNext = false;
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) =>
      loadFeatureQuery(feature, const FeatureQuery());
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    if (feature != FeatureId.bykc) {
      return const FeatureResult.empty(resolvedRoute: ConnectionMode.direct);
    }
    boyaReads.add(query);
    final count = _viewCounts.update(
      query.view,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    final gate = pending;
    if (gate != null) await gate.future;
    if (identical(gate, pending)) pending = null;
    if (failNext || (state == 'first-error' && count == 1)) {
      failNext = false;
      throw const BackendException(UbaaErrorCode.networkError);
    }
    final empty = emptyNext || state == 'empty';
    emptyNext = false;
    return boyaData(query, state, empty: empty);
  }

  Future<WriteIntent> _prepare(
    WriteOperation operation,
    int courseId, [
    int? signType,
  ]) async {
    preparedBoya.add((operation, courseId, signType));
    return WriteIntent(
      intentId: 'boya-${preparedBoya.length}',
      operation: operation,
      targetSummary: '合成博雅课程 $courseId',
      resolvedRoute: ConnectionMode.direct,
      warnings: const ['显式合成数据，仅准备与取消'],
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      requestDigest: 'synthetic-digest',
    );
  }

  @override
  Future<WriteIntent> prepareBykcSelectCourse({required int courseId}) =>
      _prepare(WriteOperation.bykcSelectCourse, courseId);
  @override
  Future<WriteIntent> prepareBykcDeselectCourse({required int courseId}) =>
      _prepare(WriteOperation.bykcDeselectCourse, courseId);
  @override
  Future<WriteIntent> prepareBykcSignCourse({
    required int courseId,
    double? lat,
    double? lng,
    required int signType,
  }) async {
    if (lat != null || lng != null) throw StateError('此合成目标不要求外部定位');
    return _prepare(WriteOperation.bykcSignCourse, courseId, signType);
  }
}
