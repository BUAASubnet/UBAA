import 'package:ubaa_domain/ubaa_domain.dart';

/// 同一加密账号库中的派生基线，完全独立于认证与学校业务写入。
abstract interface class GradeScoreBaselineBackend {
  Future<GradeScoreBaseline?> updateGradeScoreBaseline({
    required String accountId,
    required ConnectionMode route,
    required GradeScoreBaseline latest,
    GradeScoreBaseline? legacy,
  });
}
