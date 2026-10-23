import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

/// 同一学期内记住课程配色；优先分配与已有课程色相距离最大的空位。
class ScheduleCourseColors {
  final _indices = <String, int>{};
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

  String _key(FeatureDetail detail) {
    final code = (detail.presentation! as ScheduleCoursePresentation).courseCode
        .trim();
    return code.isNotEmpty ? code : detail.title.trim();
  }

  void clear() => _indices.clear();

  void register(Iterable<FeatureDetail> details) {
    final keys = details.map(_key).toSet().toList()..sort();
    for (final key in keys) {
      if (_indices.containsKey(key)) continue;
      final used = _indices.values.toSet();
      final free = [
        for (var i = 0; i < _hues.length; i++)
          if (!used.contains(i)) i,
      ];
      if (free.isEmpty) {
        _indices[key] = _indices.length;
        continue;
      }
      final seed = key.codeUnits.fold<int>(
        0,
        (value, c) => (value * 31 + c) & 0x7fffffff,
      );
      var best = free[seed % free.length];
      double distance(int candidate) => used.isEmpty
          ? 180
          : used
                .map((index) {
                  final gap = (_hues[candidate] - _hues[index]).abs();
                  return math.min(gap, 360 - gap);
                })
                .reduce(math.min);
      for (final candidate in free) {
        if (distance(candidate) > distance(best)) best = candidate;
      }
      _indices[key] = best;
    }
  }

  Color background(FeatureDetail detail, Brightness brightness) {
    final index = _indices[_key(detail)]!;
    final hue = index < _hues.length ? _hues[index] : (index * 137.508) % 360;
    return HSLColor.fromAHSL(
      1,
      hue,
      .62,
      brightness == Brightness.dark ? .32 : .82,
    ).toColor();
  }

  static Color foreground(Color background) =>
      background.computeLuminance() > .179 ? Colors.black : Colors.white;
}
