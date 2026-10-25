import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 宽屏所有待办统一高度，单列按内容增高；页面负责滚动。
class HomeTodoGrid extends StatelessWidget {
  const HomeTodoGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns = constraints.maxWidth >= 640 * scale + 12 ? 2 : 1;
      return _TodoGrid(columns: columns, children: children);
    },
  );
}

class _TodoGrid extends MultiChildRenderObjectWidget {
  const _TodoGrid({required this.columns, required super.children});
  final int columns;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTodoGrid(columns);

  @override
  void updateRenderObject(BuildContext context, _RenderTodoGrid renderObject) {
    renderObject.columns = columns;
  }
}

class _TodoParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderTodoGrid extends RenderBox
    with
        ContainerRenderObjectMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        >,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  _RenderTodoGrid(this._columns);
  int _columns;
  static const gap = 12.0;

  set columns(int value) {
    if (_columns == value) return;
    _columns = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ContainerBoxParentData<RenderBox>) {
      child.parentData = _TodoParentData();
    }
  }

  // 按当前宽度和字体测量自然高度，避免固定高度裁切长地点和大字。
  List<double> _heights(double width) {
    final heights = <double>[];
    var child = firstChild;
    while (child != null) {
      heights.add(child.getMaxIntrinsicHeight(width));
      child = childAfter(child);
    }
    if (_columns > 1 && heights.isNotEmpty) {
      final tallest = heights.reduce(math.max);
      return List.filled(heights.length, tallest);
    }
    return heights;
  }

  double _height(List<double> heights) {
    var total = 0.0;
    for (var i = 0; i < heights.length; i += _columns) {
      total += heights[i] + (i == 0 ? 0 : gap);
    }
    return total;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final width = (constraints.maxWidth - gap * (_columns - 1)) / _columns;
    return constraints.constrain(
      Size(constraints.maxWidth, _height(_heights(width))),
    );
  }

  @override
  void performLayout() {
    final width = (constraints.maxWidth - gap * (_columns - 1)) / _columns;
    final heights = _heights(width);
    var child = firstChild;
    var y = 0.0;
    var index = 0;
    while (child != null) {
      child.layout(
        BoxConstraints.tightFor(width: width, height: heights[index]),
      );
      final data = child.parentData! as ContainerBoxParentData<RenderBox>;
      data.offset = Offset((index % _columns) * (width + gap), y);
      if (index % _columns == _columns - 1) y += heights[index] + gap;
      child = childAfter(child);
      index++;
    }
    size = constraints.constrain(Size(constraints.maxWidth, _height(heights)));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
