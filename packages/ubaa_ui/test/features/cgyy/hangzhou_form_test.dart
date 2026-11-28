import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/write/cgyy/hangzhou_form.dart';

const _action = CgyyReserveAction(
  venueSiteId: 323,
  reservationDate: '2026-09-04',
  spaceId: 70,
  timeId: 9,
  venueSpaceGroupId: null,
  timeOrdinal: 0,
  eligibility: ActionEligibility.allowed,
);

/// 合成纯色 PNG，只用于给拼图提供尺寸。
Future<String> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xff336699),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return base64Encode(bytes!.buffer.asUint8List());
}

void main() {
  testWidgets('杭州表单只在用户拖动滑块并点击提交后给出真实位移与坐标', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final images = (await tester.runAsync(
      () => Future.wait([_png(310, 155), _png(47, 155)]),
    ))!;
    var loads = 0;
    HangzhouCgyySubmitInput? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await uiCollectHangzhouCgyyReservation(
                context,
                actions: const [_action],
                selectionLabel: '讨论室\n2026-09-04',
                loadCaptcha: () async {
                  loads++;
                  return HangzhouCgyyCaptcha(
                    token: 'captcha-token',
                    secretKey: 'captcha-secret-key',
                    originalImageBase64: images[0],
                    jigsawImageBase64: images[1],
                  );
                },
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    // 图片解码走真实异步。
    final slider = find.byKey(const ValueKey('hangzhou-cgyy-slider'));
    for (var i = 0; i < 100 && slider.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(loads, 1);
    expect(find.byKey(const ValueKey('hangzhou-cgyy-slider')), findsOneWidget);

    // 未拖动滑块时不能提交。
    await tester.enterText(
      find.byKey(const ValueKey('hangzhou-cgyy-phone')),
      '10000000000',
    );
    await tester.tap(find.byKey(const ValueKey('hangzhou-cgyy-submit')));
    await tester.pumpAndSettle();
    expect(find.text('请先拖动滑块完成验证'), findsOneWidget);
    expect(result, isNull);

    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    await tester.drag(slider, const Offset(100, 0));
    await tester.pumpAndSettle();
    final submit = find.byKey(const ValueKey('hangzhou-cgyy-submit'));
    final tapAt = tester.getCenter(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    final input = result!;
    expect(input.phone, '10000000000');
    expect(input.captcha.token, 'captcha-token');
    expect(input.actions.single.spaceId, 70);
    expect(input.sliderOffsetX, greaterThan(0));
    expect(input.sliderOffsetX, lessThanOrEqualTo(310));
    expect((input.tapX, input.tapY), (tapAt.dx.round(), tapAt.dy.round()));
  });
}
