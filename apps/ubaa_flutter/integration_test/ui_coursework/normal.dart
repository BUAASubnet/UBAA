part of '../ui_coursework_test.dart';

void _registerNormal(IntegrationTestWidgetsFlutterBinding binding) {
  for (final brightness in Brightness.values) {
    testWidgets('原生课程全部子视图与typed有序父返回：${brightness.name}', (tester) async {
      final backend = await _login(tester, brightness, 'normal');
      final prefix = '${brightness.name}-normal';
      await _open(tester, FeatureId.spoc);
      expect(
        _snapshot(tester, FeatureId.spoc).overview,
        isA<SpocTermOverview>(),
      );
      await _search(tester, 'SPOC课程b');
      final before = backend.reads.length;
      await _tap(tester, find.byTooltip('查看作业详情'));
      _expectQuery(
        tester,
        FeatureId.spoc,
        const FeatureQuery(
          view: FeatureQueryView.spocDetail,
          assignmentId: 'spoc-b',
        ),
      );
      final spoc =
          _snapshot(tester, FeatureId.spoc).details.single.presentation
              as SpocAssignmentPresentation;
      expect(spoc.assignmentId, 'spoc-b');
      expect(spoc.contentPlainText, contains('SPOCb 正文尾部'));
      await _shot(binding, tester, '$prefix-spoc-detail', FeatureId.spoc);
      final revision = _snapshot(
        tester,
        FeatureId.spoc,
      ).readContext!.requestRevision;
      await _tap(tester, find.byTooltip('返回'));
      expect(await _searchDraft(tester), 'SPOC课程b');
      expect(backend.reads.length, before + 1);
      expect(
        _snapshot(tester, FeatureId.spoc).readContext!.requestRevision,
        revision,
      );
      await _shot(binding, tester, '$prefix-spoc-parent', FeatureId.spoc);

      await _open(tester, FeatureId.judge);
      await _panel(tester, true);
      await _tap(tester, find.text('包含已过期作业'));
      await _apply(
        tester,
        FeatureId.judge,
        const FeatureQuery(includeExpired: true),
      );
      expect(_snapshot(tester, FeatureId.judge).details.length, 3);
      await _search(tester, 'judge-a');
      await _tap(tester, find.byTooltip('查看作业详情'));
      _expectQuery(
        tester,
        FeatureId.judge,
        const FeatureQuery(
          view: FeatureQueryView.judgeDetail,
          courseId: 'judge-a',
          assignmentId: 'shared',
          includeExpired: true,
        ),
      );
      expect(
        (_snapshot(tester, FeatureId.judge).details.single.presentation
                as JudgeAssignmentPresentation)
            .problems
            .first
            .score,
        '11',
      );
      await _shot(binding, tester, '$prefix-judge-single', FeatureId.judge);
      await _tap(tester, find.byTooltip('返回'));
      await _search(tester, 'judge-b');
      await _shot(
        binding,
        tester,
        '$prefix-judge-return-search-b',
        FeatureId.judge,
      );
      expect(await _searchDraft(tester), 'judge-b');
      expect(find.text('没有匹配的详情'), findsNothing);

      await _tap(
        tester,
        find.byKey(const ValueKey(('judge-selection', 'judge-b', 'shared'))),
      );
      await _search(tester, 'judge-a');
      await _tap(
        tester,
        find.byKey(const ValueKey(('judge-selection', 'judge-a', 'shared'))),
      );
      expect(find.text('已选择 2 份作业'), findsOneWidget);
      final beforeBatch = backend.reads.length;
      await _tap(tester, find.text('查看所选作业'));
      _expectQuery(
        tester,
        FeatureId.judge,
        const FeatureQuery(
          view: FeatureQueryView.judgeBatchDetails,
          includeExpired: true,
          judgeKeys: [
            JudgeAssignmentQueryKey(
              courseId: 'judge-b',
              assignmentId: 'shared',
            ),
            JudgeAssignmentQueryKey(
              courseId: 'judge-a',
              assignmentId: 'shared',
            ),
          ],
        ),
      );
      final batch = _snapshot(tester, FeatureId.judge).details
          .map((d) => d.presentation as JudgeAssignmentPresentation)
          .toList();
      expect(batch.map((p) => p.courseId), ['judge-b', 'judge-a']);
      expect(batch.map((p) => p.problems.first.score), ['22', '11']);
      await _search(tester, 'judge-b 嵌套检索标记');
      expect(find.text('希冀课程judge-a'), findsNothing);
      await _shot(
        binding,
        tester,
        '$prefix-judge-batch-nested-search',
        FeatureId.judge,
      );
      await _tap(tester, find.byTooltip('返回'));
      expect(find.text('已选择 2 份作业'), findsOneWidget);
      expect(await _searchDraft(tester), 'judge-a');
      expect(backend.reads.length, beforeBatch + 1);
      await _shot(
        binding,
        tester,
        '$prefix-judge-parent-selection',
        FeatureId.judge,
      );

      await _open(tester, FeatureId.signin);
      expect(_snapshot(tester, FeatureId.signin).details.length, 6);
      await _shot(binding, tester, '$prefix-signin-all', FeatureId.signin);
      final beforeSigninSearch = backend.reads.length;
      for (final index in [2, 3, 4, 5]) {
        await _search(tester, '合成签到课程$index');
        final reason = index < 4 ? '未提供签到目标，请刷新课程后重试。' : '当前签到资格无法确认，请刷新后重试。';
        await _ensure(tester, find.text(reason));
        for (final button in tester.widgetList<OutlinedButton>(
          find.widgetWithText(OutlinedButton, '准备签到'),
        )) {
          expect(button.onPressed, isNull);
        }
        await _shot(
          binding,
          tester,
          '$prefix-signin-unknown-$index',
          FeatureId.signin,
        );
      }
      await _search(tester, '');
      expect(backend.reads.length, beforeSigninSearch);

      await _view(tester, '可签到');
      await _apply(
        tester,
        FeatureId.signin,
        const FeatureQuery(view: FeatureQueryView.signinPending),
      );
      expect(_snapshot(tester, FeatureId.signin).details.length, 1);
      await _tap(tester, find.text('准备签到'));
      expect(backend.preparedSignin, ['schedule-0']);
      expect(find.text('确认提交'), findsOneWidget);
      await _shot(
        binding,
        tester,
        '$prefix-signin-confirm-cancel',
        FeatureId.signin,
      );
      await _tap(tester, find.text('取消'));
      expect(backend.discarded.length, 1);
      expect(backend.commitCalls, 0);
      await _view(tester, '已签到');
      await _apply(
        tester,
        FeatureId.signin,
        const FeatureQuery(view: FeatureQueryView.signinCompleted),
      );
      expect(
        (_snapshot(tester, FeatureId.signin).details.single.presentation
                as SigninPresentation)
            .signStatus,
        1,
      );
      await _shot(
        binding,
        tester,
        '$prefix-signin-completed',
        FeatureId.signin,
      );

      await _open(tester, FeatureId.evaluation);
      expect(find.text('已评 3 / 6 门'), findsOneWidget);
      await _shot(
        binding,
        tester,
        '$prefix-evaluation-all',
        FeatureId.evaluation,
      );
      final beforeEvaluationSearch = backend.reads.length;
      await _search(tester, 'task-4_');
      await _ensure(tester, find.text('当前评教资格无法确认，请刷新后重试。'));
      expect(find.text('准备提交评教'), findsNothing);
      await _shot(
        binding,
        tester,
        '$prefix-evaluation-unknown',
        FeatureId.evaluation,
      );
      await _search(tester, '');
      expect(backend.reads.length, beforeEvaluationSearch);

      await _view(tester, '待评课程');
      await _apply(
        tester,
        FeatureId.evaluation,
        const FeatureQuery(view: FeatureQueryView.evaluationPending),
      );
      expect(_snapshot(tester, FeatureId.evaluation).details.length, 3);
      expect(find.text('全选待评'), findsNothing);
      await _tap(tester, find.byType(CheckboxListTile).first);
      await _tap(tester, find.text('全选待评'));
      await _tap(tester, find.text('准备批量评教'));
      expect(backend.preparedEvaluation.single.map((t) => t.rwid), [
        'task-0',
        'task-2',
      ]);
      expect(backend.preparedEvaluation.single.map((t) => t.wjid), [
        'form-0',
        'form-2',
      ]);
      expect(backend.preparedEvaluation.single.map((t) => t.kcdm), [
        'course-0',
        'course-2',
      ]);
      expect(backend.preparedEvaluation.single.map((t) => t.bpdm), [
        'teacher-0',
        'teacher-2',
      ]);
      await _shot(
        binding,
        tester,
        '$prefix-evaluation-confirm-cancel',
        FeatureId.evaluation,
      );
      await _tap(tester, find.text('取消'));
      expect(backend.discarded.length, 2);
      expect(backend.commitCalls, 0);
      expect(find.text('已评 3 / 6 门'), findsOneWidget);
      await _shot(
        binding,
        tester,
        '$prefix-evaluation-pending',
        FeatureId.evaluation,
      );
    });
    testWidgets('原生待评空详情仍显示全局进度：${brightness.name}', (tester) async {
      await _login(tester, brightness, 'all-evaluated');
      await _open(tester, FeatureId.evaluation);
      await _view(tester, '待评课程');
      await _apply(
        tester,
        FeatureId.evaluation,
        const FeatureQuery(view: FeatureQueryView.evaluationPending),
      );
      expect(_snapshot(tester, FeatureId.evaluation).details, isEmpty);
      expect(find.text('已评 4 / 4 门'), findsOneWidget);
      expect(find.text('待评 0 门'), findsOneWidget);
      await _shot(
        binding,
        tester,
        '${brightness.name}-evaluation-empty-pending-progress',
        FeatureId.evaluation,
      );
    });
  }
}
