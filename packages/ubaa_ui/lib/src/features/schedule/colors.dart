import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../theme.dart';

/// 课程配色：课表与日程共用，同一门课在本次运行中始终同色。
///
/// 按课程名散列到固定色相；被占用时改用与已有课程色相距离最大的空位。
class ScheduleCourseColors {
  static final _indices = <String, int>{};
  static const _hues = <double>[
    210,
    25,
    155,
    285,
    55,
    335,
    185,
    95,
    255,
    5,
    130,
    310,
    235,
    75,
    175,
    45,
    270,
    355,
    115,
    195,
  ];

  String _key(FeatureDetail detail) => detail.title.trim();

  /// 账号切换时由页面清理自己的实例；共享的课程色保留，不影响显示。
  void clear() {}

  void register(Iterable<FeatureDetail> details) {
    for (final key in details.map(_key).toSet().toList()..sort()) {
      _index(key);
    }
  }

  static int _index(String key) {
    final known = _indices[key];
    if (known != null) return known;
    final used = _indices.values.toSet();
    final free = [
      for (var i = 0; i < _hues.length; i++)
        if (!used.contains(i)) i,
    ];
    if (free.isEmpty) return _indices[key] = _indices.length;
    final seed = key.codeUnits.fold<int>(
      0,
      (value, c) => (value * 31 + c) & 0x7fffffff,
    );
    final preferred = seed % _hues.length;
    if (!used.contains(preferred)) return _indices[key] = preferred;
    double distance(int candidate) => used
        .map((index) {
          final gap = (_hues[candidate] - _hues[index]).abs();
          return math.min(gap, 360 - gap);
        })
        .reduce(math.min);
    var best = free[seed % free.length];
    for (final candidate in free) {
      if (distance(candidate) > distance(best)) best = candidate;
    }
    return _indices[key] = best;
  }

  static double _hue(String key) {
    final index = _index(key);
    return index < _hues.length ? _hues[index] : (index * 137.508) % 360;
  }

  /// 课程块底色：中等饱和度，浅色与深色主题下都能互相区分。
  /// 深色下各色相调到同一相对亮度，避免蓝紫色的课程块陷进背景。
  Color background(FeatureDetail detail, Brightness brightness) {
    final hue = _hue(_key(detail));
    return brightness == Brightness.dark
        ? UbaaTheme.atLuminance(
            HSLColor.fromAHSL(1, hue, .30, .5).toColor(),
            .12,
          )
        : HSLColor.fromAHSL(1, hue, .58, .86).toColor();
  }

  /// 按课程名取强调色：日程的色条与淡染底色使用，与课表同色相。
  static Color accent(String title, Brightness brightness) => HSLColor.fromAHSL(
    1,
    _hue(title.trim()),
    brightness == Brightness.dark ? .55 : .58,
    brightness == Brightness.dark ? .68 : .46,
  ).toColor();

  static Color foreground(Color background) =>
      background.computeLuminance() > .179 ? Colors.black : Colors.white;
}
