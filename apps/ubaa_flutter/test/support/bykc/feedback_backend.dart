import 'dart:async';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'backend.dart';

// 固定路线回读会触发真实控制器的读取失效，逐阶段停住以观察中间帧。
class BoyaFeedbackBackend extends BoyaBackend
    implements
        PinnedWriteReadbackBackend,
        CacheWriteBackend,
        ProgressiveReadBackend {
  BoyaFeedbackBackend({super.state});
  final refreshedPages = <int>[];
  final readback = Completer<void>();
  final refresh = Completer<void>();
  int readbacks = 0, refreshes = 0;
  int cachedCommits = 0;
  bool failRefresh = false;

  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) async => null;

  @override
  Future<WriteCommitResult> commitWriteWithCache(
    String intentId, {
    required String accountId,
  }) {
    cachedCommits++;
    return super.commitWrite(intentId);
  }

  @override
  Future<FeatureResult> readAfterWriteOnRoute(
    WriteOperation operation, {
    required ConnectionMode route,
    FeatureQuery? query,
  }) async {
    readbacks++;
    await readback.future;
    return super.loadFeatureQuery(FeatureId.bykc, query!);
  }

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    if (feature == FeatureId.bykc &&
        commitCalls > 0 &&
        query.view == FeatureQueryView.summary) {
      refreshes++;
      refreshedPages.add(query.page);
      await refresh.future;
      if (failRefresh) throw const BackendException(UbaaErrorCode.networkError);
    }
    return super.loadFeatureQuery(feature, query);
  }
}
