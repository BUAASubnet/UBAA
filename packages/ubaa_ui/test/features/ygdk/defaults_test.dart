import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/write/ygdk/form.dart';

void main() {
  const action = YgdkSubmitAction(
    classifyId: 1,
    itemId: 2,
    eligibility: ActionEligibility.allowed,
  );
  final items = [
    FeatureDetail(
      title: '跑步',
      fields: const [],
      actions: const [action],
      presentation: const YgdkItemPresentation(itemId: 2, name: '跑步'),
    ),
  ];
  for (final sample in [
    (DateTime.utc(2026, 10, 24, 0, 30), '2026-10-23 20:00', '2026-10-23 21:00'),
    (DateTime.utc(2026, 10, 24, 1), '2026-10-24 08:00', '2026-10-24 09:00'),
    (
      DateTime.utc(2026, 10, 24, 15, 30),
      '2026-10-24 21:00',
      '2026-10-24 22:00',
    ),
  ]) {
    testWidgets('全部留空生成旧版默认输入 ${sample.$1}', (tester) async {
      YgdkSubmitInput? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await uiCollectYgdkForm(
                  context,
                  items: items,
                  onPickPhoto: null,
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await withClock(Clock.fixed(sample.$1), () async {
        await tester.tap(find.text('继续确认'));
        await tester.pumpAndSettle();
      });
      expect(result, isNotNull);
      expect(result!.action.itemId, 2);
      expect(result!.startTime, sample.$2);
      expect(result!.endTime, sample.$3);
      expect(result!.place, '操场');
      expect(result!.photo.fileName, 'ygdk_auto.png');
      expect(result!.photo.bytes, isNotEmpty);
      expect(result!.shareToSquare, isFalse);
    });
  }
  testWidgets('时间只填一项时保留表单且不生成默认提交', (tester) async {
    YgdkSubmitInput? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await uiCollectYgdkForm(
                context,
                items: items,
                onPickPhoto: null,
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '开始时间'),
      '2026-10-24 08:00',
    );
    await tester.tap(find.text('继续确认'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.text('开始时间和结束时间需要同时填写。'), findsOneWidget);
  });
}
