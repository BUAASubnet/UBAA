import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/coursework/course_participation.dart';
import 'package:ubaa_ui/src/features/coursework/signin_qr_sheet.dart';
import 'package:ubaa_ui/src/features/coursework/assignment_content.dart';
import 'package:ubaa_ui/src/common/tag.dart';
import 'package:ubaa_ui/src/theme.dart';

void main() {
  test('签到窗口包含课前十分钟和下课整点，缺少有效时间或目标时不可用', () {
    SigninPhase phase(
      int hour,
      int minute, {
      String begin = '08:00',
      String end = '09:40',
      int? status = 0,
      String? target = '课次',
    }) => signinPhase(
      SigninPresentation(
        courseId: '合成课程',
        actionTarget: target,
        classBeginTime: begin,
        classEndTime: end,
        signStatus: status,
      ),
      homeCampusTime(DateTime.utc(2026, 10, 28, hour - 8, minute)),
    );

    for (final (hour, minute, expected) in [
      (7, 49, SigninPhase.upcoming),
      (7, 50, SigninPhase.open),
      (7, 54, SigninPhase.open),
      (7, 55, SigninPhase.open),
      (7, 56, SigninPhase.open),
      (8, 29, SigninPhase.open),
      (8, 30, SigninPhase.open),
      (9, 39, SigninPhase.open),
      (9, 40, SigninPhase.open),
      (9, 41, SigninPhase.ended),
    ]) {
      expect(phase(hour, minute), expected, reason: '$hour:$minute');
    }
    expect(phase(8, 0, begin: ''), SigninPhase.unknown);
    expect(phase(8, 0, end: ''), SigninPhase.unknown);
    expect(phase(8, 0, end: '09:60'), SigninPhase.unknown);
    expect(phase(8, 0, begin: '2026-02-30 08:00'), SigninPhase.unknown);
    expect(phase(8, 0, end: '09:40无效'), SigninPhase.unknown);
    expect(phase(8, 0, target: null), SigninPhase.unknown);
    expect(phase(8, 0, status: null), SigninPhase.unknown);
    expect(phase(7, 49, status: 1), SigninPhase.completed);
    expect(phase(7, 50, status: 1), SigninPhase.completedOpen);
    expect(phase(9, 40, status: 1), SigninPhase.completedOpen);
    expect(phase(9, 41, status: 1), SigninPhase.completed);
    expect(phase(8, 0, begin: '', status: 1), SigninPhase.completed);
    expect(phase(8, 0, target: null, status: 1), SigninPhase.completed);
  });

  for (final (hour, minute, phase) in [
    (7, 49, SigninPhase.upcoming),
    (7, 50, SigninPhase.open),
    (7, 55, SigninPhase.open),
    (9, 40, SigninPhase.open),
    (9, 41, SigninPhase.ended),
    (9, 41, SigninPhase.completed),
  ]) {
    testWidgets(
      '上课入口 $hour:$minute 状态=${phase.name}',
      (tester) => withClock(
        Clock.fixed(DateTime.utc(2026, 10, 28, hour - 8, minute)),
        () async {
          final reads = <(String, Duration)>[];
          final checks = <String>[];
          await tester.pumpWidget(
            _signinCard(
              signed: phase == SigninPhase.completed,
              fetch: (scheduleId, offset) async {
                reads.add((scheduleId, offset));
                return '合成二维码';
              },
              check: (scheduleId) async {
                checks.add(scheduleId);
                return false;
              },
            ),
          );
          final button = find.widgetWithText(FilledButton, '上课');
          if (phase == SigninPhase.completed || phase == SigninPhase.ended) {
            expect(button, findsNothing);
          } else {
            expect(
              tester.widget<FilledButton>(button).enabled,
              phase == SigninPhase.open,
            );
          }
          expect(
            find.text('上课前 10 分钟开放'),
            phase == SigninPhase.upcoming ? findsOneWidget : findsNothing,
          );
          if (phase == SigninPhase.completed) {
            expect(find.text('已签到'), findsOneWidget);
            expect(
              tester.widget<UiTag>(find.byType(UiTag)).tone,
              UiTagTone.primary,
            );
          }
          if (phase == SigninPhase.ended)
            expect(find.text('未签到'), findsOneWidget);
          if (phase == SigninPhase.open) {
            await tester.tap(button);
            await tester.pumpAndSettle();
            expect(find.byType(SigninQrSheet), findsWidgets);
            expect(reads, [('课次', Duration.zero)]);
            await tester.pump(const Duration(seconds: 3));
            expect(checks, ['课次']);
          }
          await tester.pumpWidget(const SizedBox());
        },
      ),
    );
  }
  testWidgets(
    '缺少签到目标时二维码不可用',
    (tester) =>
        withClock(Clock.fixed(DateTime.utc(2026, 10, 28, 0, 10)), () async {
          await tester.pumpWidget(
            _signinCard(scheduleId: ' ', fetch: (_, _) async => '合成二维码'),
          );
          final button = find.widgetWithText(FilledButton, '上课');
          expect(tester.widget<FilledButton>(button).onPressed, isNull);
        }),
  );

  testWidgets(
    '缺少二维码读取回调时上课不可点',
    (tester) =>
        withClock(Clock.fixed(DateTime.utc(2026, 10, 28, 0, 10)), () async {
          await tester.pumpWidget(_signinCard());
          final button = find.widgetWithText(FilledButton, '上课');
          expect(tester.widget<FilledButton>(button).enabled, isFalse);
        }),
  );
  testWidgets('课程时间缺失时上课不可点', (tester) async {
    await tester.pumpWidget(
      _signinCard(begin: '', end: '', fetch: (_, _) async => '合成二维码'),
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '上课'))
          .enabled,
      isFalse,
    );
  });
  for (final eligibility in [
    ActionEligibility.denied,
    ActionEligibility.unknown,
  ]) {
    testWidgets(
      '弃用的写入资格不控制二维码（$eligibility）',
      (tester) =>
          withClock(Clock.fixed(DateTime.utc(2026, 10, 28, 0, 10)), () async {
            var reads = 0;
            await tester.pumpWidget(
              _signinCard(
                eligibility: eligibility,
                fetch: (_, _) async {
                  reads++;
                  return '合成二维码';
                },
              ),
            );
            final button = find.widgetWithText(FilledButton, '上课');
            expect(tester.widget<FilledButton>(button).enabled, isTrue);
            await tester.tap(button);
            await tester.pumpAndSettle();
            expect(reads, 1);
            await tester.pumpWidget(const SizedBox.shrink());
          }),
    );
  }
  for (final days in [2, 3, 4]) {
    testWidgets(
      '作业剩余 $days 天与三天标橙边界',
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
          final warning = UbaaTheme.warning(
            Theme.of(tester.element(deadline)).colorScheme,
          );
          final hint = (text.textSpan! as TextSpan).children!.last as TextSpan;
          expect(hint.style?.color, days <= 3 ? warning : isNull);
          // 未临近截止的“未提交”只是中性提示，三天内才用错误色。
          final tag = tester.widget<UiTag>(find.byType(UiTag));
          expect(tag.tone, days <= 3 ? UiTagTone.error : UiTagTone.neutral);
        },
      ),
    );
  }
}

Widget _signinCard({
  bool signed = false,
  ActionEligibility eligibility = ActionEligibility.allowed,
  String scheduleId = '课次',
  String begin = '08:00',
  String end = '09:40',
  Future<String> Function(String, Duration)? fetch,
  Future<bool> Function(String)? check,
}) => MaterialApp(
  home: Scaffold(
    body: CourseParticipationContent(
      feature: FeatureId.signin,
      details: [
        FeatureDetail(
          title: '合成课程',
          presentation: SigninPresentation(
            courseId: '展示课程编号',
            actionTarget: scheduleId,
            classBeginTime: begin,
            classEndTime: end,
            signStatus: signed ? 1 : 0,
          ),
          actions: [
            SigninPerformAction(
              scheduleId: scheduleId,
              eligibility: eligibility,
            ),
          ],
        ),
      ],
      evaluationRow: (_) => const SizedBox(),
      onFetchSigninQr: fetch,
      onCheckSigninStatus: check,
    ),
  ),
);
