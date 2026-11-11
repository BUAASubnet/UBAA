import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  tearDown(() => UbaaTheme.debugFontFamily = null);

  test('无头渲染字体族同时覆盖正文与自定义标题样式，默认沿用系统字体', () {
    final system = UbaaTheme.light();
    expect(system.appBarTheme.titleTextStyle?.fontFamily, isNull);

    UbaaTheme.debugFontFamily = 'SyntheticSans';
    for (final theme in [UbaaTheme.light(), UbaaTheme.dark()]) {
      expect(theme.appBarTheme.titleTextStyle?.fontFamily, 'SyntheticSans');
      expect(theme.textTheme.bodyMedium?.fontFamily, 'SyntheticSans');
    }
  });
}
