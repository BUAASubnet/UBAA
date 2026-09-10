import 'dart:async';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../ui_coursework/backend.dart';

/// 学业旧布局的显式合成backend，全部读写都留在内存。
class AcademicOldBackend extends CourseworkBackend {
  AcademicOldBackend({super.state}) {
    signedIn = true;
  }
  final academicReads = <(FeatureId, FeatureQuery)>[];
  final failFeatures = <FeatureId>{};
  Completer<void>? pending;
  String title(String value) => state == 'long'
      ? '$value 大学生校园学习与课程安排的完整较长名称 大学生校园学习与课程安排的完整较长名称'
      : value;
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) =>
      loadFeatureQuery(feature, const FeatureQuery());
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    academicReads.add((feature, query));
    if (pending case final gate?) await gate.future;
    if (failFeatures.contains(feature) ||
        (state == 'first-error' &&
            academicReads.where((r) => r.$1 == feature).length == 1)) {
      throw const BackendException(UbaaErrorCode.networkError);
    }
    if (query.view == FeatureQueryView.scheduleTerms) {
      return const FeatureResult.success(
        details: [
          FeatureDetail(
            title: '合成学期',
            presentation: TermPresentation(
              code: '2026-2027-1',
              selected: true,
              index: 1,
            ),
          ),
        ],
        resolvedRoute: ConnectionMode.direct,
      );
    }
    if (state == 'empty') {
      return const FeatureResult.empty(resolvedRoute: ConnectionMode.direct);
    }
    final details = <FeatureDetail>[];
    if (feature == FeatureId.exam) {
      for (var i = 1; i <= (state == 'many' ? 42 : 2); i++) {
        details.add(
          FeatureDetail(
            title: title('合成已结束考试 $i'),
            presentation: ExamPresentation(
              arranged: true,
              date: i == 1 ? '2020-03-02' : '2020-03-01',
              startTime: '08:00',
              endTime: '09:40',
              place: '合成教学楼 A203',
              seat: '018',
            ),
          ),
        );
      }
      details.addAll([
        FeatureDetail(
          title: title('合成待考课程'),
          presentation: ExamPresentation(
            arranged: true,
            date: '2999-10-01',
            startTime: '09:00',
            endTime: '11:00',
            place: title('合成教学楼 B301'),
            seat: 'A018',
            courseNo: 'EXAM-SAFE',
            taskId: 'TASK-SAFE',
            type: '闭卷',
          ),
        ),
        FeatureDetail(
          title: title('合成日期待定课程'),
          presentation: const ExamPresentation(
            arranged: true,
            description: '教务安排待确认',
          ),
        ),
        FeatureDetail(
          title: title('合成未安排课程'),
          presentation: const ExamPresentation(
            arranged: false,
            courseNo: 'OTHER-SAFE',
          ),
        ),
      ]);
      if (query.view == FeatureQueryView.examArranged) {
        details.removeWhere(
          (d) => !(d.presentation! as ExamPresentation).arranged,
        );
      } else if (query.view == FeatureQueryView.examNotArranged) {
        details.removeWhere(
          (d) => (d.presentation! as ExamPresentation).arranged,
        );
      }
    } else if (feature == FeatureId.signin) {
      for (final (id, status, eligibility) in [
        ('可签到', 0, ActionEligibility.allowed),
        ('已签到', 1, ActionEligibility.denied),
        ('未知状态', 8, ActionEligibility.unknown),
        ('缺少目标', 0, ActionEligibility.unknown),
      ]) {
        details.add(
          FeatureDetail(
            title: title('合成$id课程'),
            fields: const [FeatureField(label: '原字段', value: '合成低频字段')],
            presentation: SigninPresentation(
              courseId: 'course-$id',
              classBeginTime: '08:00',
              classEndTime: '09:40',
              signStatus: status,
            ),
            actions: id == '缺少目标'
                ? []
                : [
                    SigninPerformAction(
                      scheduleId: 'target-$id',
                      eligibility: eligibility,
                    ),
                  ],
          ),
        );
      }
      // 与现有 BridgeBackend 的显式查询合同一致；不由展示文字猜资格。
      final eligibility = switch (query.view) {
        FeatureQueryView.signinPending => ActionEligibility.allowed,
        FeatureQueryView.signinCompleted => ActionEligibility.denied,
        _ => null,
      };
      if (eligibility != null) {
        details.removeWhere(
          (detail) =>
              detail.action<SigninPerformAction>()?.eligibility != eligibility,
        );
      }
    }
    return FeatureResult.success(
      details: details,
      resolvedRoute: ConnectionMode.direct,
    );
  }
}
