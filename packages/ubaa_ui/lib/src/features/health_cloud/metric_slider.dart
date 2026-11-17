import 'package:flutter/material.dart';

class HealthCloudMetricSlider extends StatelessWidget {
  const HealthCloudMetricSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.label,
    required this.onChanged,
    this.symmetric = false,
    this.markZero = false,
  });

  final double value, min, max, step;
  final String label;
  final ValueChanged<double> onChanged;
  final bool symmetric, markZero;

  // 留出最短有效线段，使两个把手在最小值时仍能分别操作。
  static const _minHalfSpan = .13;
  static const _halfTravel = .5 - _minHalfSpan;

  double _quantize(double input) =>
      ((input / step).round() * step).clamp(min, max);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final half = _minHalfSpan + (value - min) / (max - min) * _halfTravel;
    final ends = RangeValues(.5 - half, .5 + half);
    final slider = symmetric
        ? RangeSlider(
            values: ends,
            semanticFormatterCallback: (_) => label,
            onChanged: (next) {
              final fromStart = (next.start - ends.start).abs();
              final fromEnd = (next.end - ends.end).abs();
              final distance = fromStart > fromEnd
                  ? .5 - next.start
                  : next.end - .5;
              final fraction = ((distance - _minHalfSpan) / _halfTravel).clamp(
                0.0,
                1.0,
              );
              onChanged(_quantize(min + fraction * (max - min)));
            },
          )
        : Slider(
            value: value,
            min: min,
            max: max,
            semanticFormatterCallback: (_) => label,
            onChanged: (next) => onChanged(_quantize(next)),
          );

    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4,
        trackShape: _MetricTrack(markZero ? -min / (max - min) : null),
        rangeTrackShape: const RoundedRectRangeSliderTrackShape(),
        activeTrackColor: colors.primary,
        inactiveTrackColor: colors.primary.withValues(
          alpha: symmetric ? .12 : .19,
        ),
        thumbColor: colors.primary,
        overlayColor: colors.primary.withValues(alpha: .12),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        thumbShape: _OutlineThumb(colors.surface),
        rangeThumbShape: _OutlineRangeThumb(colors.surface),
        minThumbSeparation: 0,
        showValueIndicator: ShowValueIndicator.never,
      ),
      child: slider,
    );
  }
}

class _MetricTrack extends RoundedRectSliderTrackShape {
  const _MetricTrack(this.zero);
  final double? zero;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
    );
    final fraction = zero;
    if (fraction == null) return;
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final x =
        rect.left +
        (textDirection == TextDirection.rtl ? 1 - fraction : fraction) *
            rect.width;
    final y = rect.center.dy;
    context.canvas.drawLine(
      Offset(x, y - 6),
      Offset(x, y + 6),
      Paint()
        ..color = sliderTheme.activeTrackColor!
        ..strokeWidth = 1.5,
    );
  }
}

class _OutlineThumb extends RoundSliderThumbShape {
  const _OutlineThumb(this.fill) : super(enabledThumbRadius: 7);
  final Color fill;

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) => _paintHandle(context, center, fill, sliderTheme.thumbColor!);
}

class _OutlineRangeThumb extends RoundRangeSliderThumbShape {
  const _OutlineRangeThumb(this.fill) : super(enabledThumbRadius: 7);
  final Color fill;

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    bool isDiscrete = false,
    bool isEnabled = false,
    bool? isOnTop,
    required SliderThemeData sliderTheme,
    TextDirection? textDirection,
    Thumb? thumb,
    bool? isPressed,
  }) => _paintHandle(context, center, fill, sliderTheme.thumbColor!);
}

void _paintHandle(
  PaintingContext context,
  Offset center,
  Color fill,
  Color edge,
) {
  context.canvas.drawCircle(center, 7, Paint()..color = edge);
  context.canvas.drawCircle(center, 4.75, Paint()..color = fill);
}
