part of '../ui_coursework_test.dart';

void _registerStates(IntegrationTestWidgetsFlutterBinding binding) {
  for (final brightness in Brightness.values) {
    for (final state in [
      'empty',
      'first-error',
      'stale',
      'long',
      'many',
      'loading',
    ]) {
      testWidgets('原生四领域状态矩阵：${brightness.name}/$state', (tester) async {
        final backend = await _login(tester, brightness, state);
        for (final feature in _features) {
          await _open(tester, feature);
          final prefix = '${brightness.name}-$state-${feature.name}';
          if (state == 'first-error') {
            expect(
              _snapshot(tester, feature).status,
              FeatureLoadStatus.failure,
            );
            await _shot(binding, tester, '$prefix-failed', feature);
            // 当前默认读取失败后，只允许一次真实重试；不改变query归属。
            final beforeRetry = backend.reads.length;
            expect(_snapshot(tester, feature).readContext!.query, isNull);
            await _tap(tester, find.byTooltip('刷新当前查询'));
            expect(backend.reads.length, beforeRetry + 1);
            expect(_snapshot(tester, feature).readContext!.query, isNull);
            expect(
              _snapshot(tester, feature).status,
              FeatureLoadStatus.success,
            );
          } else if (state == 'stale') {
            await _apply(tester, feature, const FeatureQuery());
            final old = _snapshot(tester, feature).details;
            await _tap(tester, find.byTooltip('刷新当前查询'));
            expect(_snapshot(tester, feature).status, FeatureLoadStatus.stale);
            expect(_snapshot(tester, feature).details, same(old));
          } else if (state == 'empty') {
            expect(
              _snapshot(tester, feature).status,
              feature == FeatureId.evaluation
                  ? FeatureLoadStatus.success
                  : FeatureLoadStatus.empty,
            );
            expect(_snapshot(tester, feature).details, isEmpty);
            if (feature == FeatureId.evaluation) {
              expect(find.text('已评 0 / 0 门'), findsOneWidget);
              expect(find.text('待评 0 门'), findsOneWidget);
            }
          } else if (state == 'loading') {
            // 截图完成前由Completer保持加载，不能依靠固定延时猜测原生截图时机。
            backend.holdNextRead();
            await _tap(tester, find.byTooltip('刷新当前查询'), settle: false);
            expect(
              _snapshot(tester, feature).status,
              FeatureLoadStatus.loading,
            );
            expect(backend.hasPendingRead, isTrue);
            try {
              await _shot(
                binding,
                tester,
                '$prefix-pending',
                feature,
                settle: false,
              );
              expect(
                _snapshot(tester, feature).status,
                FeatureLoadStatus.loading,
              );
            } finally {
              backend.releaseRead();
            }

            await tester.pumpAndSettle();
            expect(
              _snapshot(tester, feature).status,
              FeatureLoadStatus.success,
            );
          } else if (state == 'many') {
            final before = backend.reads.length;
            final overview = _snapshot(tester, feature).overview;
            expect(_snapshot(tester, feature).details.length, 42);
            await _shot(binding, tester, '$prefix-page-one', feature);
            if (feature == FeatureId.judge) {
              await _tap(
                tester,
                find.byKey(
                  const ValueKey(('judge-selection', 'judge-b', 'shared')),
                ),
              );
            }
            await _tap(tester, find.byTooltip('下一页'));
            expect(find.text('2 / 3'), findsOneWidget);
            await _shot(binding, tester, '$prefix-page-two', feature);
            expect(backend.reads.length, before);
            expect(_snapshot(tester, feature).overview, same(overview));
            var expectedReads = before;
            if (feature == FeatureId.judge) {
              await _tap(
                tester,
                find.byKey(
                  const ValueKey(('judge-selection', 'judge-20', 'shared')),
                ),
              );
              await _tap(tester, find.text('查看所选作业'));
              _expectQuery(
                tester,
                feature,
                const FeatureQuery(
                  view: FeatureQueryView.judgeBatchDetails,
                  judgeKeys: [
                    JudgeAssignmentQueryKey(
                      courseId: 'judge-b',
                      assignmentId: 'shared',
                    ),
                    JudgeAssignmentQueryKey(
                      courseId: 'judge-20',
                      assignmentId: 'shared',
                    ),
                  ],
                ),
              );
              expectedReads++;
              await _tap(tester, find.byTooltip('返回'));
              expect(find.text('2 / 3'), findsOneWidget);
              expect(find.text('已选择 2 份作业'), findsOneWidget);
            }
            final keyword = switch (feature) {
              FeatureId.spoc => 'SPOC课程41',
              FeatureId.judge => 'judge-41',
              FeatureId.signin => '合成签到课程41',
              FeatureId.evaluation => '合成教师40',
              _ => throw StateError('非课程领域'),
            };
            await _search(tester, keyword);
            expect(backend.reads.length, expectedReads);
            if (feature == FeatureId.evaluation) {
              expect(find.text('已评 21 / 42 门'), findsOneWidget);
              expect(find.text('待评 21 门'), findsOneWidget);
            }
            await _shot(binding, tester, '$prefix-local-search', feature);
          } else if (state == 'long' &&
              (feature == FeatureId.spoc || feature == FeatureId.judge)) {
            final course = feature == FeatureId.spoc
                ? 'SPOC课程a'
                : '希冀课程judge-a';
            await _search(tester, course);
            await _tap(tester, find.byTooltip('查看作业详情'));
            final body = find.byType(SelectableText);
            expect(body, findsOneWidget);
            expect(tester.widget<SelectableText>(body).data, contains('正文尾部'));
            await _shot(binding, tester, '$prefix-body-start', feature);
            final more = find.text('更多信息');
            await _ensure(tester, more);
            await Scrollable.ensureVisible(
              tester.element(more),
              alignment: 0.9,
            );
            await tester.pumpAndSettle();
            if (feature == FeatureId.judge) {
              final p =
                  _snapshot(tester, feature).details.single.presentation
                      as JudgeAssignmentPresentation;
              expect(p.problems.length, 2);
              expect(p.problems.last.name, 'judge-a 嵌套检索标记');
            }
          }
          await _shot(binding, tester, '$prefix-result', feature);
          expect(backend.commitCalls, 0);
        }
      });
    }
  }
}
