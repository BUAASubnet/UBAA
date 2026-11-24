import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../support/bridge/recording_client.dart'
    show FixtureCharacterizationBridgeClient, fixtureWebVpnRoute;

void registerCourseworkTests() {
  test('课件服务保留路线、列表标识、许可和宿主选择的路径', () async {
    final native = _FilesClient();
    final service = BridgeBackend(native).spocFiles!;
    final courses = await service.courses();
    expect(courses.route, ConnectionMode.webvpn);
    expect(courses.data.single.teacher, '合成教师');
    final items = (await service.courseFiles(
      courses.data.single.courseId,
      folderId: 'folder',
    )).data;
    expect(items.first.uploadedAtText, '2026-03-01');
    expect(items.first.extension, 'pdf');
    expect(
      (await service.downloadCourseFile(items.first, 'chosen')).data.byteLen,
      12,
    );
    expect(
      (await service.downloadAssignmentFile(
        const SpocSubmittedFile(fileId: 'answer'),
        'chosen',
      )).data.fileName,
      '合成.pdf',
    );
    await expectLater(
      service.downloadCourseFile(items.last, 'chosen'),
      throwsA(isA<BackendException>()),
    );
    expect(
      BridgeBackend(FixtureCharacterizationBridgeClient()).spocFiles,
      isNull,
    );
  });
  test('SPOC列表typed导航只携作业ID并保留集合学期', () async {
    final client = FixtureCharacterizationBridgeClient();
    final result = await BridgeBackend(client).loadFeature(FeatureId.spoc);
    expect(
      result.details.single.readNavigation?.query.assignmentId,
      'spoc-list-1',
    );
    expect(result.details.single.readNavigation?.query.courseId, isNull);
    final presentation =
        result.details.single.presentation! as SpocAssignmentPresentation;
    expect(presentation.courseId, 'course-spoc-1');
    expect(
      result.details.single.fields
          .singleWhere((field) => field.label == '课程编号')
          .value,
      'course-spoc-1',
    );
    expect(presentation.score, isNull);
    expect((result.overview! as SpocTermOverview).termCode, '2026-fall');
    expect(client.calls, hasLength(1));
  });
  test('希冀批量同名异二元键按B到A顺序保留父题归属', () async {
    final result = await BridgeBackend(_CourseworkClient()).loadFeatureQuery(
      FeatureId.judge,
      const FeatureQuery(
        view: FeatureQueryView.judgeBatchDetails,
        judgeKeys: [
          JudgeAssignmentQueryKey(courseId: 'B', assignmentId: 'same'),
          JudgeAssignmentQueryKey(courseId: 'A', assignmentId: 'same'),
        ],
      ),
    );
    expect(result.details, hasLength(2));
    final b = result.details[0].presentation! as JudgeAssignmentPresentation;
    final a = result.details[1].presentation! as JudgeAssignmentPresentation;
    expect(b.courseId, 'B');
    expect(a.courseId, 'A');
    expect(b.assignmentId, 'same');
    expect(a.assignmentId, 'same');
    expect(b.status, AssignmentSubmissionStatus.partial);
    expect(b.problems.single.status, AssignmentSubmissionStatus.unknown);
    expect(b.problems.single.maxScore, '题满分');
    expect(b.maxScore, '满分B');
    expect(a.myScore, isNull);
    expect(b.problems.single.score, 'B分');
    expect(a.problems.single.score, 'A分');
    expect(b.problems.single.name, '同名题');
    expect(
      result.details.first.fields.map((field) => field.label),
      contains('题目数'),
    );
    expect(result.resolvedRoute, ConnectionMode.webvpn);
    expect(result.details.every((d) => d.readNavigation == null), isTrue);
    expect(
      result.details.first.fields.any((f) => f.value.contains('同名题')),
      isTrue,
    );
  });
  test('希冀列表导航保留includeExpired及二元键', () async {
    final result = await BridgeBackend(FixtureCharacterizationBridgeClient())
        .loadFeatureQuery(
          FeatureId.judge,
          const FeatureQuery(includeExpired: true),
        );
    final navigation = result.details.single.readNavigation!;
    expect(navigation.query.courseId, 'course-list-1');
    expect(navigation.query.assignmentId, 'assignment-list-1');
    expect(navigation.query.includeExpired, isTrue);
  });
  test('SPOC详情可选字段逐项保留且不提供重复详情导航', () async {
    final result = await BridgeBackend(_CourseworkClient()).loadFeatureQuery(
      FeatureId.spoc,
      const FeatureQuery(
        view: FeatureQueryView.spocDetail,
        assignmentId: 'exact',
      ),
    );
    final p = result.details.single.presentation! as SpocAssignmentPresentation;
    expect(p.assignmentId, 'exact');
    expect(p.teacherName, '合成教师');
    expect(p.startTime, '原开始');
    expect(p.dueTime, '原截止');
    expect(p.score, '优秀');
    expect(
      result.details.single.fields.any(
        (f) => f.label == '分值' && f.value == '优秀',
      ),
      isTrue,
    );
    expect(result.details.single.fields.any((f) => f.label == '得分'), isFalse);
    expect(p.contentPlainText, '纯文本内容');
    expect(p.submittedAt, '原提交时间');
    expect(p.attachment?.fileName, '合成附件.zip');
    expect(p.attachment?.sizeText, '2MB');
    expect(p.submittedFile?.fileId, 'answer');
    expect(p.submissionCount, 1);
    expect(p.submitModes, ['5', '1']);
    expect(p.allowedExtensions, ['.pdf']);
    expect(p.maxSubmissions, isNull);
    expect(p.isGroupAssignment, isTrue);
    expect(p.submitUnavailableReason, '小组作业暂不支持');
    expect(result.details.single.action<SpocSubmitAction>(), isNull);
    expect(p.lateSubmissionDeadline, '补交截止');
    expect(p.status, AssignmentSubmissionStatus.submitted);
    expect(p.isDetail, isTrue);
    expect(result.details.single.readNavigation, isNull);
  });
  test('评教固定路线映射仍有相同总progress及课程typed展示', () async {
    final backend = BridgeBackend(FixtureCharacterizationBridgeClient());
    final normal = await backend.loadFeature(FeatureId.evaluation);
    final pinned = await backend.loadEvaluationOnRoute(
      route: ConnectionMode.webvpn,
    );
    expect((normal.overview! as EvaluationProgressOverview).totalCourses, 1);
    expect((pinned.overview! as EvaluationProgressOverview).totalCourses, 1);
    expect(
      (pinned.details.single.presentation! as EvaluationCoursePresentation)
          .isEvaluated,
      isFalse,
    );
    expect(pinned.resolvedRoute, ConnectionMode.webvpn);
  });
  test('全待评空列表仍保留Core总进度', () async {
    final result = await BridgeBackend(_CourseworkClient()).loadFeatureQuery(
      FeatureId.evaluation,
      const FeatureQuery(view: FeatureQueryView.evaluationPending),
    );
    expect(result.details, isEmpty);
    expect((result.overview! as EvaluationProgressOverview).totalCourses, 7);
    expect(
      (result.overview! as EvaluationProgressOverview).evaluatedCourses,
      7,
    );
    expect((result.overview! as EvaluationProgressOverview).pendingCourses, 0);
  });
  test('上课资格被拒绝的未上课课程仍属于未上课分组', () async {
    final backend = BridgeBackend(_CourseworkClient());
    final completed = await backend.loadFeatureQuery(
      FeatureId.signin,
      const FeatureQuery(view: FeatureQueryView.signinCompleted),
    );
    expect(completed.details, isEmpty);
    final result = await backend.loadFeatureQuery(
      FeatureId.signin,
      const FeatureQuery(view: FeatureQueryView.signinPending),
    );
    expect(result.details, hasLength(1));
    final p = result.details.single.presentation! as SigninPresentation;
    expect(p.signStatus, 0);
    expect(
      result.details.single.action<SigninPerformAction>()?.scheduleId,
      'signin-target',
    );
    expect(
      result.details.single.action<SigninPerformAction>()!.eligibility,
      ActionEligibility.denied,
    );
    expect(result.details.single.fields.any((f) => f.value == '已上课'), isFalse);
  });
}

class _FilesClient extends FixtureCharacterizationBridgeClient {
  @override
  int contractVersion() => 83;
  @override
  Future<BridgeRoutedSpocCourses> spocCourses() async =>
      const BridgeRoutedSpocCourses(
        route: fixtureWebVpnRoute,
        data: [
          BridgeSpocCourse(courseId: 'course', name: '合成课', teacher: '合成教师'),
        ],
      );
  @override
  Future<BridgeRoutedSpocCourseFiles> spocCourseFiles({
    required String courseId,
    String? folderId,
  }) async {
    expect([courseId, folderId], ['course', 'folder']);
    return const BridgeRoutedSpocCourseFiles(
      route: fixtureWebVpnRoute,
      data: [
        BridgeSpocCourseFile(
          id: 'listed',
          name: '合成.pdf',
          isFolder: false,
          downloadAllowed: true,
          extension_: 'pdf',
          uploadedAtText: '2026-03-01',
        ),
        BridgeSpocCourseFile(
          id: 'locked',
          name: '锁定',
          isFolder: false,
          downloadAllowed: false,
        ),
      ],
    );
  }

  BridgeRoutedSpocDownload get receipt => BridgeRoutedSpocDownload(
    route: fixtureWebVpnRoute,
    data: BridgeSpocDownloadReceipt(
      fileName: '合成.pdf',
      byteLen: BigInt.from(12),
    ),
  );
  @override
  Future<BridgeRoutedSpocDownload> spocDownloadCourseFile({
    required String id,
    required String name,
    required String destPath,
  }) async {
    expect([id, name, destPath], ['listed', '合成.pdf', 'chosen']);
    return receipt;
  }

  @override
  Future<BridgeRoutedSpocDownload> spocDownloadAssignmentFile({
    required String fileId,
    String? fileName,
    required String destPath,
  }) async {
    expect([fileId, fileName, destPath], ['answer', null, 'chosen']);
    return receipt;
  }
}

class _CourseworkClient extends FixtureCharacterizationBridgeClient {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #spocAssignment:
        return Future.value(
          BridgeRoutedSpocAssignmentDetail(
            route: fixtureWebVpnRoute,
            data: BridgeSpocAssignmentDetail(
              assignmentId: invocation.namedArguments[#assignmentId] as String,
              courseId: 'C',
              courseName: '课程',
              title: '作业',
              teacherName: '合成教师',
              startTime: '原开始',
              dueTime: '原截止',
              score: '优秀',
              contentPlainText: '纯文本内容',
              submittedAt: '原提交时间',
              attachment: const BridgeSpocAttachment(
                fileId: 'attachment',
                fileName: '合成附件.zip',
                sizeText: '2MB',
                extension_: 'zip',
              ),
              submittedFile: const BridgeSpocSubmittedFile(fileId: 'answer'),
              submitModes: const ['5', '1'],
              allowedExtensions: const ['.pdf'],
              submissionCount: 1,
              isGroupAssignment: true,
              submitUnavailableReason: '小组作业暂不支持',
              lateSubmissionDeadline: '补交截止',
              submissionStatus: BridgeSpocSubmissionStatus.submitted,
              submissionStatusText: '已提交',
            ),
          ),
        );
      case #judgeAssignmentDetails:
        final keys =
            invocation.namedArguments[#keys] as List<BridgeJudgeAssignmentKey>;
        return Future.value(
          BridgeRoutedJudgeAssignmentDetails(
            route: fixtureWebVpnRoute,
            data: [
              for (final key in keys)
                BridgeJudgeAssignmentDetail(
                  courseId: key.courseId,
                  courseName: '同名课程',
                  assignmentId: key.assignmentId,
                  title: '同名作业',
                  maxScore: '满分${key.courseId}',
                  totalProblems: 2,
                  submittedCount: 1,
                  submissionStatus: BridgeJudgeSubmissionStatus.partial,
                  submissionStatusText: '部分提交',
                  problems: [
                    BridgeJudgeProblem(
                      name: '同名题',
                      score: '${key.courseId}分',
                      maxScore: '题满分',
                      status: BridgeJudgeSubmissionStatus.unknown,
                      statusText: '未识别',
                    ),
                  ],
                ),
            ],
          ),
        );
      case #evaluationAll:
        return Future.value(
          BridgeRoutedEvaluation(
            route: fixtureWebVpnRoute,
            data: const BridgeEvaluationCoursesResponse(
              courses: [],
              progress: BridgeEvaluationProgress(
                totalCourses: 7,
                evaluatedCourses: 7,
                pendingCourses: 0,
              ),
            ),
          ),
        );
      case #signinToday:
        return Future.value(
          const BridgeRoutedSigninClasses(
            route: fixtureWebVpnRoute,
            data: [
              BridgeSigninClass(
                courseId: 's',
                courseName: '合成课程',
                classBeginTime: '8',
                classEndTime: '9',
                signStatus: 0,
                signinEligibility: BridgeActionEligibility.denied,
                signinTarget: 'signin-target',
              ),
            ],
          ),
        );
      default:
        return super.noSuchMethod(invocation);
    }
  }
}

void main() {
  registerCourseworkTests();
}
