import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/coursework/course_participation.dart';
import 'package:ubaa_ui/src/features/coursework/assignment_content.dart';

void main() {
  for (final sample in [
    (7, 49, false),
    (7, 50, true),
    (8, 30, true),
    (9, 40, false),
    (9, 41, false),
  ]) {
    for (final done in [false, true]) {
      testWidgets(
        '签到时间窗 ${sample.$1}:${sample.$2} 已签到=$done',
        (tester) => withClock(
          Clock.fixed(DateTime.utc(2026, 10, 28, sample.$1 - 8, sample.$2)),
          () async {
            var calls = 0;
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: CourseParticipationContent(
                    feature: FeatureId.signin,
                    details: [
                      FeatureDetail(
                        title: '合成课程',
                        presentation: SigninPresentation(
                          courseId: '课程',
                          classBeginTime: '08:00',
                          classEndTime: '09:40',
                          signStatus: done ? 1 : 0,
                        ),
                        actions: const [
                          SigninPerformAction(
                            scheduleId: '课次',
                            eligibility: ActionEligibility.allowed,
                          ),
                        ],
                      ),
                    ],
                    evaluationRow: (_) => const SizedBox(),
                    onSignin: (_) async {
                      calls++;
                    },
                  ),
                ),
              ),
            );
            final button = find.widgetWithText(FilledButton, '签到');
            expect(button, sample.$3 && !done ? findsOneWidget : findsNothing);
            if (sample.$3 && !done) {
              await tester.tap(button);
              expect(calls, 1);
            }
            await tester.pumpWidget(const SizedBox());
          },
        ),
      );
    }
  }
  testWidgets(
    '资格未知时禁用签到且不显示内部提示',
    (tester) =>
        withClock(Clock.fixed(DateTime.utc(2026, 10, 28, 0, 30)), () async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: CourseParticipationContent(
                  feature: FeatureId.signin,
                  details: const [
                    FeatureDetail(
                      title: '合成课',
                      presentation: SigninPresentation(
                        courseId: '课程',
                        classBeginTime: '08:00',
                        classEndTime: '09:40',
                        signStatus: 0,
                      ),
                      actions: [
                        SigninPerformAction(
                          scheduleId: '课次',
                          eligibility: ActionEligibility.unknown,
                        ),
                      ],
                    ),
                  ],
                  evaluationRow: (_) => const SizedBox(),
                  onSignin: (_) async {},
                ),
              ),
            ),
          );
          expect(
            tester
                .widget<FilledButton>(find.widgetWithText(FilledButton, '签到'))
                .onPressed,
            isNull,
          );
          expect(find.textContaining('资格'), findsNothing);
          await tester.pumpWidget(const SizedBox());
        }),
  );
  testWidgets('课程时间缺失时不显示可提交签到按钮', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CourseParticipationContent(
            feature: FeatureId.signin,
            details: const [
              FeatureDetail(
                title: '时间缺失课程',
                presentation: SigninPresentation(
                  courseId: '课程',
                  classBeginTime: '',
                  classEndTime: '',
                  signStatus: 0,
                ),
                actions: [
                  SigninPerformAction(
                    scheduleId: '课次',
                    eligibility: ActionEligibility.allowed,
                  ),
                ],
              ),
            ],
            evaluationRow: (_) => const SizedBox(),
            onSignin: (_) async {},
          ),
        ),
      ),
    );
    expect(find.widgetWithText(FilledButton, '签到'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  for (final days in [2, 3, 4]) {
    testWidgets(
      '作业剩余 $days 天与三天标红边界',
      (tester) => withClock(
        Clock.fixed(DateTime.utc(2026, 10, 28, 0)),
        () async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: AssignmentContent(
                  details: [
                    FeatureDetail(
                      title: '合成作业',
                      presentation: SpocAssignmentPresentation(
                        courseId: '课程',
                        courseName: '课程',
                        assignmentId: '作业',
                        status: AssignmentSubmissionStatus.unsubmitted,
                        statusText: '未提交',
                        dueTime: DateTime(
                          2026,
                          10,
                          28 + days,
                          8,
                        ).toIso8601String(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          final deadline = find.textContaining('还有 $days 天');
          expect(deadline, findsOneWidget);
          final text = tester.widget<Text>(deadline);
          final error = Theme.of(tester.element(deadline)).colorScheme.error;
          final hint = (text.textSpan! as TextSpan).children!.last as TextSpan;
          expect(hint.style?.color, days <= 3 ? error : isNot(error));
        },
      ),
    );
  }
}
