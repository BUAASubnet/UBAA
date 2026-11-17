import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

ColorScheme _colors(Brightness brightness, UbaaAccent accent) =>
    (brightness == Brightness.dark
            ? UbaaTheme.dark(accent: accent)
            : UbaaTheme.light(accent: accent))
        .colorScheme;

/// 随主题色变化的角色；其余中性角色在所有预设下保持一致。
Map<String, Color> _accentRoles(ColorScheme c) => {
  'primary': c.primary,
  'onPrimary': c.onPrimary,
  'primaryContainer': c.primaryContainer,
  'onPrimaryContainer': c.onPrimaryContainer,
  'secondaryContainer': c.secondaryContainer,
  'onSecondaryContainer': c.onSecondaryContainer,
  'inversePrimary': c.inversePrimary,
  'surfaceTint': c.surfaceTint,
  'surfaceContainer': c.surfaceContainer,
  'outlineVariant': c.outlineVariant,
};

double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
}

void main() {
  test('默认主题色保持原有手调蓝色，未知标识回落默认', () {
    expect(UbaaAccent.parse(null), UbaaAccent.blue);
    expect(UbaaAccent.parse('unknown'), UbaaAccent.blue);
    expect(UbaaAccent.parse('teal'), UbaaAccent.teal);
    expect(
      _colors(Brightness.light, UbaaAccent.blue).primary,
      const Color(0xFF1976D2),
    );
    expect(
      _colors(Brightness.dark, UbaaAccent.blue).primary,
      const Color(0xFF83BEF7),
    );
    expect(
      UbaaTheme.light().colorScheme,
      _colors(Brightness.light, UbaaAccent.blue),
    );
  });

  for (final brightness in Brightness.values) {
    for (final accent in UbaaAccent.values.where((a) => a != UbaaAccent.blue)) {
      test('${brightness.name} ${accent.name}：强调角色换色相但亮度与默认一致，中性角色不变', () {
        final base = _colors(brightness, UbaaAccent.blue);
        final tinted = _colors(brightness, accent);
        expect(tinted.primary, isNot(base.primary));
        final accentHue = HSLColor.fromColor(accent.seed).hue;
        final primaryHue = HSLColor.fromColor(tinted.primary).hue;
        final distance = (accentHue - primaryHue).abs();
        expect(distance < 2 || distance > 358, isTrue, reason: '主色色相应跟随预设');
        final baseRoles = _accentRoles(base), roles = _accentRoles(tinted);
        for (final key in baseRoles.keys) {
          // 相对亮度相同即与默认蓝的 WCAG 对比度相同；容差只吸收 8 位取整。
          final expected = baseRoles[key]!.computeLuminance();
          expect(
            roles[key]!.computeLuminance(),
            closeTo(expected, expected * .02 + .001),
            reason: key,
          );
        }
        expect(_contrast(tinted.primary, tinted.onPrimary), greaterThan(4.5));
        expect(
          _contrast(tinted.primaryContainer, tinted.onPrimaryContainer),
          greaterThan(4.5),
        );
        expect(_contrast(tinted.primary, tinted.surface), greaterThan(3));
        expect(
          _contrast(tinted.primary, tinted.surfaceContainer),
          greaterThan(3),
        );
        expect(tinted.surface, base.surface);
        expect(tinted.onSurface, base.onSurface);
        expect(tinted.onSurfaceVariant, base.onSurfaceVariant);
        expect(tinted.error, base.error);
        expect(UbaaTheme.success(tinted), UbaaTheme.success(base));
      });
    }
  }

  test('预设避开成功、警告与错误的语义色相', () {
    double hue(Color c) => HSLColor.fromColor(c).hue;
    final light = _colors(Brightness.light, UbaaAccent.blue);
    final reserved = [
      hue(UbaaTheme.success(light)),
      hue(UbaaTheme.warning(light)),
      hue(light.error),
    ];
    for (final accent in UbaaAccent.values) {
      if (accent == UbaaAccent.graphite) continue;
      for (final r in reserved) {
        final d = (hue(accent.seed) - r).abs();
        expect(
          d.clamp(0, 360 - d) >= 25,
          isTrue,
          reason: '${accent.name} 与语义色相过近',
        );
      }
    }
  });
}
