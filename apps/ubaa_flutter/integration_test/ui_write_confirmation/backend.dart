import 'dart:async';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../ui_academic_old/backend.dart';

/// 仅内存写入，用真实协调器消费显式脱敏结果，不调用学校接口。
class ConfirmationBackend extends AcademicOldBackend {
  ConfirmationBackend(this.scenario);
  final String scenario;
  final intents = <String>{};
  Completer<void>? commitGate, cancelGate, readbackGate;
  int cancelCalls = 0;
  bool completed = false;

  @override
  Future<WriteIntent> prepareSigninPerform({required String courseId}) async {
    if (courseId != 'target-可签到') throw StateError('不是原typed签到目标');
    preparedSignin.add(courseId);
    final id = 'synthetic-confirm-${preparedSignin.length}';
    intents.add(id);
    return WriteIntent(
      intentId: id,
      operation: WriteOperation.signinPerform,
      targetSummary: '合成可签到课程',
      resolvedRoute: ConnectionMode.direct,
      warnings: const ['本流程使用内存合成数据，不向学校提交'],
      expiresAt: DateTime.now().add(
        (scenario == 'expired' || scenario == 'commit-cross-deadline')
            ? const Duration(seconds: 2)
            : const Duration(minutes: 5),
      ),
      requestDigest: 'synthetic-digest',
    );
  }

  @override
  Future<void> discardWriteIntent(String intentId) async {
    cancelCalls++;
    if (cancelGate != null) await cancelGate!.future;
    if (scenario == 'cancel-error' && cancelCalls == 1) {
      throw const BackendException(UbaaErrorCode.networkError);
    }
    intents.remove(intentId);
    discarded.add(intentId);
  }

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    if (!intents.remove(intentId)) throw StateError('重复或缺失意图');
    commitCalls++;
    if (commitGate != null) await commitGate!.future;
    if (scenario == 'exception') {
      throw const BackendException(UbaaErrorCode.networkError);
    }
    completed = scenario != 'unknown' && scenario != 'business-false';
    return WriteCommitResult(
      operation: WriteOperation.signinPerform,
      success: completed,
      message: completed ? '合成签到完成' : '合成签到未完成',
      outcomeUnknown: scenario == 'unknown',
      resolvedRoute: ConnectionMode.direct,
    );
  }

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    if (feature == FeatureId.signin && commitCalls > 0) {
      if (readbackGate != null) await readbackGate!.future;
      if (completed) {
        academicReads.add((feature, query));
        return const FeatureResult.success(
          resolvedRoute: ConnectionMode.direct,
          details: [
            FeatureDetail(
              title: '合成可签到课程',
              presentation: SigninPresentation(
                courseId: 'course-可签到',
                classBeginTime: '08:00',
                classEndTime: '09:40',
                signStatus: 1,
              ),
              actions: [
                SigninPerformAction(
                  scheduleId: 'target-可签到',
                  eligibility: ActionEligibility.denied,
                ),
              ],
            ),
          ],
        );
      }
    }
    return super.loadFeatureQuery(feature, query);
  }
}
