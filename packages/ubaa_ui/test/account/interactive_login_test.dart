import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  testWidgets('人工验证窗口提交答案，刷新后清空旧答案并允许取消', (tester) async {
    final state = ValueNotifier(_verification(1));
    addTearDown(state.dispose);
    final submissions = <String>[];
    var refreshes = 0;
    var cancellations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<LoginRouteVerification>(
            valueListenable: state,
            builder: (_, value, _) => UbaaCaptchaDialog(
              verification: value,
              isLoading: false,
              onAnswerChanged: (answer) =>
                  state.value = state.value.withAnswer(answer),
              onRefresh: () {
                refreshes++;
                state.value = _verification(2);
              },
              onSubmit: () => submissions.add(state.value.answer),
              onCancel: () => cancellations++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('captcha-answer-webvpn')),
      'a2b3c4',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('captcha-submit')));
    expect(submissions, ['a2b3c4']);
    await tester.tap(find.byKey(const ValueKey('captcha-image-webvpn')));
    await tester.pumpAndSettle();
    expect(refreshes, 1);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('captcha-answer-webvpn')),
          )
          .controller!
          .text,
      isEmpty,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('captcha-submit')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    expect(cancellations, 1);
    expect(tester.takeException(), isNull);
  });
}

LoginRouteVerification _verification(int revision) => LoginRouteVerification(
  route: ConnectionMode.webvpn,
  status: LoginRouteVerificationStatus.captchaRequired,
  revision: revision,
  validFor: const Duration(seconds: 120),
  frame: CaptchaPixelFrame(
    width: 1,
    height: 1,
    rgba: Uint8List.fromList([17, 83, 149, 255]),
  ),
);
