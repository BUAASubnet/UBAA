import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../features/cgyy/reservation_test.dart' show fixtureCgyyTextField;

Future<void> fixtureFillCgyyForm(
  WidgetTester tester, {
  required String joiners,
}) async {
  for (final item in {
    '联系电话': 'phone-placeholder',
    '预约主题': '课程讨论',
    '用途编号': '2',
    '参与人数': '3',
    '活动内容': '讨论',
    '参与人说明': joiners,
  }.entries) {
    if (item.key == '用途编号') {
      await tester.ensureVisible(find.widgetWithText(OutlinedButton, '选择活动类型'));
      await tester.tap(find.widgetWithText(OutlinedButton, '选择活动类型'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('手动填写'));
      await tester.pumpAndSettle();
      await tester.enterText(fixtureCgyyTextField('用途编号'), item.value);
      await tester.tap(find.text('使用编号'));
      await tester.pumpAndSettle();
      continue;
    }
    await tester.ensureVisible(fixtureCgyyTextField(item.key));
    await tester.enterText(fixtureCgyyTextField(item.key), item.value);
    await tester.pumpAndSettle();
  }
}
