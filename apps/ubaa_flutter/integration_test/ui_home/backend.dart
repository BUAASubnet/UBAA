import 'dart:async';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../ui_coursework/backend.dart';

/// 首页旧六来源合成数据，所有时间围绕本次运行；绝不使用学校账号或网络。
class HomeBackend extends CourseworkBackend {
  HomeBackend({super.state}) {
    signedIn = true;
  }
  bool mixedRoutes = false;
  Completer<void>? pending;
  final failFeatures = <FeatureId>{};
  Future<FeatureResult> deliver(FeatureId feature, FeatureQuery query) async {
    if (pending case final gate?) await gate.future;
    if (failFeatures.contains(feature) ||
        (state == 'partial-error' && feature == FeatureId.cgyy)) {
      throw const BackendException(UbaaErrorCode.networkError);
    }
    return data(feature, query);
  }

  String title(String value) =>
      state == 'long' ? '$value 校园课程和近期学习任务的较长说明 校园课程和近期学习任务的较长说明' : value;
  final homeQueries = <(FeatureId, FeatureQuery)>[];
  final defaults = <FeatureId>[];
  String time(int minutes) => DateTime.now()
      .add(Duration(minutes: minutes))
      .toIso8601String()
      .substring(0, 19);
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    defaults.add(feature);
    return deliver(feature, const FeatureQuery());
  }

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    homeQueries.add((feature, query));
    return deliver(feature, query);
  }

  FeatureResult data(FeatureId feature, FeatureQuery query) {
    if (state == 'empty' &&
        query.view != FeatureQueryView.scheduleTerms &&
        query.view != FeatureQueryView.scheduleWeeks) {
      return const FeatureResult.empty(resolvedRoute: ConnectionMode.direct);
    }
    final details = <FeatureDetail>[];
    if (feature == FeatureId.schedule) {
      if (query.view == FeatureQueryView.scheduleTerms) {
        details.add(
          const FeatureDetail(
            title: '合成当前学期',
            presentation: TermPresentation(
              code: 'synthetic-term',
              selected: true,
              index: 1,
            ),
          ),
        );
      } else if (query.view == FeatureQueryView.scheduleWeeks) {
        details.add(
          const FeatureDetail(
            title: '合成第12周',
            presentation: WeekPresentation(
              requestTerm: 'synthetic-term',
              responseTerm: 'synthetic-term',
              number: 12,
              current: true,
              startDate: '2026-09-07',
              endDate: '2026-09-13',
            ),
          ),
        );
      } else {
        details.addAll(const [
          FeatureDetail(
            title: '合成下午课程',
            subtitle: '合成课',
            presentation: TodayCoursePresentation(
              time: '14:00-15:30',
              place: '合成教室B',
            ),
          ),
          FeatureDetail(
            title: '合成上午课程',
            subtitle: '合成课',
            presentation: TodayCoursePresentation(
              time: '08:00-09:30',
              place: '合成教室A',
            ),
          ),
        ]);
      }
    } else if (feature == FeatureId.spoc) {
      details.add(
        FeatureDetail(
          title: title('合成SPOC待办'),
          presentation: SpocAssignmentPresentation(
            courseId: 'spoc-c',
            courseName: '合成SPOC课',
            assignmentId: 'spoc-a',
            dueTime: time(180),
            status: AssignmentSubmissionStatus.unsubmitted,
            statusText: '未提交',
            isDetail: query.view == FeatureQueryView.spocDetail,
          ),
          readNavigation: const FeatureReadNavigation(
            feature: FeatureId.spoc,
            query: FeatureQuery(
              view: FeatureQueryView.spocDetail,
              assignmentId: 'spoc-a',
            ),
          ),
        ),
      );
    } else if (feature == FeatureId.judge) {
      details.add(
        FeatureDetail(
          title: title('合成希冀待办'),
          presentation: JudgeAssignmentPresentation(
            courseId: 'judge-c',
            courseName: '合成希冀课',
            assignmentId: 'judge-a',
            dueTime: time(120),
            totalProblems: 2,
            submittedCount: 1,
            status: AssignmentSubmissionStatus.partial,
            statusText: '部分完成',
            isDetail: query.view == FeatureQueryView.judgeDetail,
          ),
        ),
      );
    } else if (feature == FeatureId.bykc &&
        query.view == FeatureQueryView.bykcChosenCourses) {
      details.add(
        FeatureDetail(
          title: '合成博雅待办',
          presentation: BykcChosenPresentation(
            recordId: 10,
            courseId: 20,
            courseName: title('合成博雅待办'),
            courseStartDate: time(60),
            courseEndDate: time(120),
          ),
        ),
      );
    } else if (feature == FeatureId.bykc &&
        query.view == FeatureQueryView.bykcDetail) {
      details.add(
        FeatureDetail(
          title: title('合成博雅待办'),
          presentation: BykcCoursePresentation(
            id: 20,
            courseName: title('合成博雅待办'),
            status: BykcCourseStatus.selected,
            isDetail: true,
            courseStartDate: time(60),
            courseEndDate: time(120),
          ),
        ),
      );
    } else if (feature == FeatureId.cgyy &&
        query.view == FeatureQueryView.cgyyOrders) {
      details.add(
        FeatureDetail(
          title: '合成研讨室待办',
          presentation: CgyyOrderPresentation(
            id: 30,
            venueName: title('合成研讨室待办'),
            reservationStartDate: time(240),
            reservationEndDate: time(300),
            statusText: '合成已确认',
            orderStatus: 1,
            checkStatus: 2,
          ),
        ),
      );
    } else if (feature == FeatureId.signin) {
      details.add(
        FeatureDetail(
          title: '合成签到待办',
          presentation: SigninPresentation(
            courseId: 'signin-c',
            classBeginTime: time(5),
            classEndTime: time(65),
            signStatus: 0,
          ),
          actions: const [
            SigninPerformAction(
              scheduleId: 'signin-target',
              eligibility: ActionEligibility.allowed,
            ),
          ],
        ),
      );
    } else if (feature == FeatureId.ygdk) {
      return const FeatureResult.success(
        overview: YgdkOverview(
          termCount: 15,
          weekCount: 3,
          classifyId: 3,
          classifyName: '合成体育',
          defaultItemId: 7,
          defaultItemName: '合成项目',
          records: YgdkHomeRecords(page: 1, size: 20),
        ),
        resolvedRoute: ConnectionMode.direct,
      );
    }
    if (state == 'many' &&
        feature == FeatureId.spoc &&
        query.view == FeatureQueryView.summary) {
      details.clear();
      for (var i = 1; i <= 42; i++) {
        details.add(
          FeatureDetail(
            title: '合成待办 $i',
            presentation: SpocAssignmentPresentation(
              courseId: 'many-c',
              courseName: '合成课程',
              assignmentId: 'many-$i',
              dueTime: time(180 + i),
              status: AssignmentSubmissionStatus.unsubmitted,
              statusText: '未提交',
            ),
          ),
        );
      }
    }
    return FeatureResult.success(
      details: details,
      resolvedRoute: mixedRoutes && feature == FeatureId.cgyy
          ? ConnectionMode.webvpn
          : ConnectionMode.direct,
    );
  }
}
