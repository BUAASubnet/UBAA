import 'dart:async';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../ui_coursework/backend.dart';
part 'data.dart';

/// 仅显式合成阳光数据；不使用FRB、账号或网络，commit拒绝执行。
class SportsBackend extends CourseworkBackend
    implements YgdkWriteBackend, YgdkSubmissionReadbackBackend {
  SportsBackend({super.state}) {
    signedIn = true;
  }
  final queries = <FeatureQuery>[];
  final pinnedReads = <String>[];
  final prepared = <YgdkSubmitInput>[];
  Completer<void>? pending;
  bool failNext = false, emptyNext = false;
  int backgroundReads = 0;
  int recordVersion = 1;
  bool _recordErrorShown = false;
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    if (feature != FeatureId.ygdk) {
      return const FeatureResult.empty(resolvedRoute: ConnectionMode.direct);
    }
    backgroundReads++;
    if (state == 'first-error' && backgroundReads == 1) {
      throw const BackendException(UbaaErrorCode.networkError);
    }
    return sportsData(
      const FeatureQuery(),
      state,
      version: recordVersion,
      includeRecords: false,
    );
  }

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    if (feature != FeatureId.ygdk) {
      return const FeatureResult.empty(resolvedRoute: ConnectionMode.direct);
    }
    queries.add(query);
    if (state == 'first-error' &&
        query.view == FeatureQueryView.ygdkRecords &&
        !_recordErrorShown) {
      _recordErrorShown = true;
      throw const BackendException(UbaaErrorCode.networkError);
    }
    final gate = pending;
    if (gate != null) await gate.future;
    if (identical(gate, pending)) pending = null;
    if (failNext) {
      failNext = false;
      throw const BackendException(UbaaErrorCode.networkError);
    }
    final empty = emptyNext;
    emptyNext = false;
    return sportsData(query, empty ? 'empty' : state, version: recordVersion);
  }

  @override
  Future<FeatureResult> loadYgdkOverviewOnRoute({
    required ConnectionMode route,
  }) async {
    pinnedReads.add('overview:${route.name}');
    return sportsData(
      const FeatureQuery(),
      state,
      version: recordVersion,
      includeRecords: false,
    );
  }

  @override
  Future<FeatureResult> loadYgdkRecordsOnRoute({
    required ConnectionMode route,
    required int page,
    required int size,
  }) async {
    pinnedReads.add('records:${route.name}:$page:$size');
    return sportsData(
      FeatureQuery(view: FeatureQueryView.ygdkRecords, page: page, size: size),
      state,
      version: recordVersion,
    );
  }

  @override
  Future<WriteIntent> prepareYgdkSubmit(YgdkSubmitInput input) async {
    prepared.add(input);
    return WriteIntent(
      intentId: 'sports-${prepared.length}',
      operation: WriteOperation.ygdkSubmit,
      targetSummary: '合成体育项目 ${input.action.itemId}',
      resolvedRoute: ConnectionMode.direct,
      warnings: const ['显式合成数据，仅准备与取消'],
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      requestDigest: 'synthetic-digest',
    );
  }
}
