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
  test('签到二维码与直接签到时间窗保留八个分钟边界', () {
    const course = SigninPresentation(
      courseId: '合成课程',
      classBeginTime: '08:00',
      classEndTime: '09:40',
    );
    for (final (hour, minute, phase, canSubmit) in [
      (7, 49, SigninPhase.upcoming, false),
      (7, 50, SigninPhase.open, false),
      (7, 54, SigninPhase.open, false),
      (7, 55, SigninPhase.open, true),
      (8, 29, SigninPhase.open, true),
      (8, 30, SigninPhase.open, false),
      (9, 39, SigninPhase.open, false),
      (9, 40, SigninPhase.ended, false),
    ]) {
      final window = signinPhase(course, DateTime(2026, 10, 28, hour, minute));
      expect(
        (window.phase, window.submitOpen),
        (phase, canSubmit),
        reason: '$hour:$minute',
      );
      expect(window.opensAt, DateTime(2026, 10, 28, 7, 50));
      expect(window.submitOpensAt, DateTime(2026, 10, 28, 7, 55));
    }
  });

  for (final (hour, minute, qrOpen, canSubmit, done, openSheet) in [
    (7, 49, false, false, false, false),
    (7, 50, true, false, false, false),
    (7, 55, true, true, false, true),
    (8, 29, true, false, true, true),
  ]) {
    testWidgets(
      '签到入口 $hour:$minute 已签到=$done',
      (tester) => withClock(
        Clock.fixed(DateTime.utc(2026, 10, 28, hour - 8, minute)),
        () async {
          final reads = <(String, Duration)>[];
          final checks = <String>[];
          await tester.pumpWidget(
            _signinCard(
              signed: done,
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
          final button = find.widgetWithText(FilledButton, '签到');
          final qrButton = find.byTooltip('签到二维码');
          if (canSubmit) {
            expect(tester.widget<FilledButton>(button).enabled, isTrue);
          } else {
            expect(button, findsNothing);
          }
          expect(
            find.text('07:55 起可签'),
            qrOpen && hour == 7 && !canSubmit ? findsOneWidget : findsNothing,
          );
          expect(qrButton, qrOpen ? findsOneWidget : findsNothing);
          if (done) {
            expect(
              tester.widget<UiTag>(find.byType(UiTag)).tone,
              UiTagTone.primary,
            );
          }
          if (openSheet) {
            await tester.tap(qrButton);
            await tester.pumpAndSettle();
            expect(find.byType(SigninQrSheet), findsWidgets);
            expect(reads, [('课次', Duration.zero)]);
            await tester.pump(const Duration(seconds: 3));
            expect(checks, done ? isEmpty : ['课次']);
          }
          await tester.pumpWidget(const SizedBox());
        },
      ),
    );
  }
  testWidgets(
    '缺少排课 ID 时二维码不可用且直接签到不可点',
    (tester) =>
        withClock(Clock.fixed(DateTime.utc(2026, 10, 28, 0, 10)), () async {
          await tester.pumpWidget(
            _signinCard(scheduleId: ' ', fetch: (_, _) async => '合成二维码'),
          );
          final button = find.widgetWithText(FilledButton, '签到');
          expect(tester.widget<FilledButton>(button).onPressed, isNull);
          expect(find.byTooltip('签到二维码'), findsNothing);
        }),
  );

  testWidgets(
    '缺少二维码读取回调时仍提供直接签到',
    (tester) =>
        withClock(Clock.fixed(DateTime.utc(2026, 10, 28, 0, 10)), () async {
          await tester.pumpWidget(_signinCard());
          final button = find.widgetWithText(FilledButton, '签到');
          expect(tester.widget<FilledButton>(button).enabled, isTrue);
          expect(find.byTooltip('签到二维码'), findsNothing);
        }),
  );
  testWidgets('课程时间缺失时不提供签到入口', (tester) async {
    await tester.pumpWidget(
      _signinCard(begin: '', end: '', fetch: (_, _) async => '合成二维码'),
    );
    expect(find.widgetWithText(FilledButton, '签到'), findsNothing);
  });
  for (final (writesEnabled, eligibility) in [
    (false, ActionEligibility.allowed),
    (true, ActionEligibility.unknown),
  ]) {
    testWidgets(
      '写入禁用或资格未知时二维码仍可读（$writesEnabled, $eligibility）',
      (tester) =>
          withClock(Clock.fixed(DateTime.utc(2026, 10, 28, 0, 10)), () async {
            var reads = 0;
            await tester.pumpWidget(
              _signinCard(
                writesEnabled: writesEnabled,
                eligibility: eligibility,
                fetch: (_, _) async {
                  reads++;
                  return '合成二维码';
                },
              ),
            );
            final button = find.widgetWithText(FilledButton, '签到');
            expect(tester.widget<FilledButton>(button).enabled, isFalse);
            await tester.tap(find.byTooltip('签到二维码'));
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
  bool writesEnabled = true,
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
      onSignin: (_) async {},
      writesEnabled: writesEnabled,
      onFetchSigninQr: fetch,
      onCheckSigninStatus: check,
    ),
  ),
);
