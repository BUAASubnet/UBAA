import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_ui/src/shared/dialogs/date_range.dart';
import 'package:ubaa_ui/ubaa_ui.dart' show UbaaTheme;

void main() {
  for (final size in [const Size(390, 800), const Size(1100, 800)]) {
    testWidgets('日期范围在 $size 内以周一开头，选择后返回日期', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: UbaaTheme.light(),
          locale: UbaaTheme.locale,
          supportedLocales: UbaaTheme.supportedLocales,
          localizationsDelegates: UbaaTheme.localizationsDelegates,
          home: Scaffold(
            body: Builder(
              builder: (value) {
                context = value;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      final result = uiShowDateRangePicker(
        context,
        firstDate: DateTime(2026, 11, 1),
        lastDate: DateTime(2026, 11, 30),
        initialDateRange: DateTimeRange(
          start: DateTime(2026, 11, 5),
          end: DateTime(2026, 11, 7),
        ),
        saveText: '使用范围',
      );
      await tester.pumpAndSettle();
      final bounds = tester.getRect(find.byType(DateRangePickerDialog));
      if (size.width >= 720) {
        expect(bounds.width, lessThanOrEqualTo(420));
        expect(bounds.height, lessThanOrEqualTo(640));
        expect(bounds.center.dx, closeTo(size.width / 2, 1));
        expect(bounds.center.dy, closeTo(size.height / 2, 1));
      } else {
        expect(bounds.size, size);
      }

      // 2026 年 11 月 1 日是周日，次日周一应回到最左列。
      final sunday = tester.getCenter(find.text('1'));
      final monday = tester.getCenter(find.text('2'));
      final nextMonday = tester.getCenter(find.text('9'));
      expect(sunday.dx, greaterThan(monday.dx));
      expect(monday.dy, greaterThan(sunday.dy));
      expect(nextMonday.dx, closeTo(monday.dx, .01));
      await tester.tap(find.text('9'));
      await tester.tap(find.text('11'));
      await tester.tap(find.text('使用范围'));
      await tester.pumpAndSettle();
      expect(
        await result,
        DateTimeRange(
          start: DateTime(2026, 11, 9),
          end: DateTime(2026, 11, 11),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
