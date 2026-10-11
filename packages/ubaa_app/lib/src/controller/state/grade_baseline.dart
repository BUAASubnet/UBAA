import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/grade_baseline.dart';
import 'lifecycle_owners.dart';

/// 成绩基线流程只消费账号 scope 与存储端口，可脱离 AppController 验证。
final class GradeBaselineOwner implements GradeScoreStore {
  GradeBaselineOwner(this.capture);
  final OfflineAccountScope Function(String account) capture;

  @override
  Future<GradeScoreBaseline?> update(
    String account,
    ConnectionMode route,
    GradeScoreBaseline latest,
  ) async {
    final scope = capture(account);
    void check() {
      if (!scope.isCurrent)
        throw const BackendException(UbaaErrorCode.operationConflict);
    }

    check();
    await scope.opened;
    check();
    final backend = scope.backend, id = scope.accountId;
    if (id == null || backend is! GradeScoreBaselineBackend) {
      throw const BackendException(
        UbaaErrorCode.internalError,
        cacheFailure: CacheMaintenanceFailure.unavailable,
      );
    }
    final previous = await (backend as GradeScoreBaselineBackend)
        .updateGradeScoreBaseline(accountId: id, route: route, latest: latest);
    check();
    return previous;
  }

  // 账号库删除由缓存生命周期统一执行，没有第二个文件仓库。
  @override
  Future<void> clearAccount(String account) async {}
}
