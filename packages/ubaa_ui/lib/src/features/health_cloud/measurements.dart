import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import 'mascot.dart';
import 'metric_slider.dart';

enum _Metric {
  weight('体重', 'kg', 32, 120, 62, 0.1),
  height('身高', 'cm', 135, 205, 170, 0.1),
  lung('肺活量', 'mL', 1000, 7000, 4000, 1),
  reach('坐位体前屈', 'cm', -35, 35, 0, 0.1);

  const _Metric(
    this.title,
    this.unit,
    this.min,
    this.max,
    this.base,
    this.step,
  );
  final String title, unit;
  final double min, max, base, step;
}

class HealthCloudMeasurements extends StatefulWidget {
  const HealthCloudMeasurements({
    super.key,
    required this.report,
    required this.viewportHeight,
  });
  final HealthCloudReport report;
  final double viewportHeight;

  @override
  State<HealthCloudMeasurements> createState() =>
      _HealthCloudMeasurementsState();
}

class _HealthCloudMeasurementsState extends State<HealthCloudMeasurements> {
  final _changes = <_Metric, double>{};

  double? _original(_Metric metric) => switch (metric) {
    _Metric.weight => widget.report.weightKg,
    _Metric.height => widget.report.heightCm,
    _Metric.lung => widget.report.lungMl,
    _Metric.reach => widget.report.reachCm,
  };

  double _value(_Metric metric) =>
      _changes[metric] ?? _original(metric) ?? metric.base;

  double _scale(_Metric metric, double shrink, double grow) {
    final delta = _value(metric) - metric.base;
    final span = delta < 0
        ? metric.base - _min(metric)
        : _max(metric) - metric.base;
    return 1 + (delta / span) * (delta < 0 ? shrink : grow);
  }

  double _min(_Metric metric) =>
      math.min(metric.min, _original(metric) ?? metric.min);
  double _max(_Metric metric) =>
      math.max(metric.max, _original(metric) ?? metric.max);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final textHeight = MediaQuery.textScalerOf(context).scale(14);
      final height = widget.viewportHeight;
      final gap = (width * .03).clamp(8.0, 24.0);
      final aside = (width * .40).clamp(200.0, 320.0);
      final sideBySide =
          width >= math.max(580, textHeight * 23) && width > height * 1.38;
      final figureSpace = sideBySide ? width - aside - gap : width;
      final verticalHeightSlider =
          figureSpace >= math.max(250, textHeight * 13);
      final heightControlWidth = verticalHeightSlider
          ? 42 + textHeight * 1.5
          : 0.0;
      final figureTarget =
          height -
          (sideBySide ? 75 : 174 + textHeight * 2.7) -
          (verticalHeightSlider ? 0 : 58 + textHeight);
      final figureHeight = math.min(
        (figureSpace - heightControlWidth) * 1.22,
        figureTarget.clamp(verticalHeightSlider ? 175.0 : 120.0, 450.0),
      );
      final figureWidth = math.min(
        figureSpace,
        figureHeight * 1.03 + heightControlWidth,
      );
      final figure = SizedBox(
        width: figureWidth,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsetsDirectional.only(end: heightControlWidth),
              child: _horizontal(_Metric.weight),
            ),
            SizedBox(
              height: figureHeight,
              child: Row(
                children: [
                  Expanded(
                    child: HealthCloudMascot(
                      widthScale: _scale(_Metric.weight, .4, .5),
                      heightScale: _scale(_Metric.height, .3, .25),
                      belly: ((_value(_Metric.lung) - _Metric.lung.base) / 3000)
                          .clamp(-1.0, 1.0),
                      shear: (_value(_Metric.reach) / 35).clamp(-1.0, 1.0),
                    ),
                  ),
                  if (verticalHeightSlider)
                    SizedBox(
                      width: heightControlWidth,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 42,
                            height: figureHeight * .92,
                            child: RotatedBox(
                              quarterTurns: 3,
                              child: _slider(_Metric.height),
                            ),
                          ),
                          Expanded(
                            child: RotatedBox(
                              quarterTurns: 1,
                              child: _label(_Metric.height, maxLines: 2),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (!verticalHeightSlider) _horizontal(_Metric.height),
          ],
        ),
      );
      final other = SizedBox(
        width: sideBySide
            ? aside
            : math.min(width, math.max(240.0, figureWidth)),
        child: Column(
          spacing: gap / 3,
          children: [_horizontal(_Metric.lung), _horizontal(_Metric.reach)],
        ),
      );
      return sideBySide
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: gap,
              children: [figure, other],
            )
          : Column(spacing: gap / 2, children: [figure, other]);
    },
  );

  String _display(_Metric metric) {
    final actual = _changes[metric] ?? _original(metric);
    return actual == null
        ? '缺项'
        : '${actual.toStringAsFixed(actual == actual.roundToDouble() ? 0 : 1)} ${metric.unit}';
  }

  Widget _label(_Metric metric, {int? maxLines}) => Text(
    '${metric.title} · ${_display(metric)}',
    textAlign: TextAlign.center,
    maxLines: maxLines,
    style: Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
  );

  Widget _slider(_Metric metric) => HealthCloudMetricSlider(
    key: ValueKey(metric),
    value: _value(metric),
    min: _min(metric),
    max: _max(metric),
    step: metric.step,
    label: '${metric.title} ${_display(metric)}',
    symmetric: metric == _Metric.weight || metric == _Metric.height,
    markZero: metric == _Metric.reach,
    onChanged: (value) => setState(() => _changes[metric] = value),
  );

  Widget _horizontal(_Metric metric) => Column(
    children: [
      _label(metric),
      SizedBox(height: 38, width: double.infinity, child: _slider(metric)),
    ],
  );
}
