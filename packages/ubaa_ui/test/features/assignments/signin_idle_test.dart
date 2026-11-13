import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/coursework/course_participation.dart';

void main() {
  testWidgets('签到页隐藏时停止定时重建，重新显示后恢复刷新', (tester) async {
    var reads = 0;
    final details = [_Signin(() => reads++)];
    Future<void> mount(bool visible) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TickerMode(
            enabled: visible,
            child: CourseParticipationContent(
              feature: FeatureId.signin,
              details: details,
              evaluationRow: (_) => const SizedBox(),
            ),
          ),
        ),
      ),
    );
    await mount(false);
    reads = 0;
    await tester.pump(const Duration(seconds: 31));
    expect(reads, 0, reason: '隐藏页面不因签到计时器反复解析和重建');
    await mount(true);
    reads = 0;
    await tester.pump(const Duration(seconds: 31));
    expect(reads, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
  });
}

class _Signin extends FeatureDetail {
  _Signin(this.onRead) : super(title: '合成签到');
  final void Function() onRead;
  @override
  FeaturePresentation get presentation {
    onRead();
    return const SigninPresentation(
      courseId: 'c',
      classBeginTime: '08:00',
      classEndTime: '09:40',
      signStatus: 0,
    );
  }
}
