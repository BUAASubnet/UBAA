import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

class HealthCloudMascot extends StatefulWidget {
  const HealthCloudMascot({
    super.key,
    required this.widthScale,
    required this.heightScale,
    required this.belly,
    required this.shear,
  });

  final double widthScale, heightScale, belly, shear;

  @override
  State<HealthCloudMascot> createState() => _HealthCloudMascotState();
}

class _HealthCloudMascotState extends State<HealthCloudMascot>
    with SingleTickerProviderStateMixin {
  static const _asset = AssetImage(
    'assets/health_cloud/kangaroo.webp',
    package: 'ubaa_ui',
  );
  static final _spring = SpringDescription(
    mass: 1,
    stiffness: 210,
    damping: 10,
  );
  late final _motion = AnimationController.unbounded(vsync: this);
  final _drag = ValueNotifier(Offset.zero);
  late final _repaint = Listenable.merge([_motion, _drag]);
  late final _listener = ImageStreamListener(_loaded);
  ImageStream? _stream;
  ImageInfo? _image;
  int? _activePointer;
  Offset _start = Offset.zero;
  Offset _lean = Offset.zero;
  double _releaseCompression = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final stream = _asset.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  void _loaded(ImageInfo image, bool synchronous) {
    _image?.dispose();
    if (synchronous) {
      _image = image;
    } else {
      setState(() => _image = image);
    }
  }

  void _down(PointerDownEvent event, Size area) {
    if (_activePointer != null ||
        MediaQuery.disableAnimationsOf(context) ||
        (event.kind == PointerDeviceKind.mouse &&
            event.buttons != kPrimaryMouseButton)) {
      return;
    }
    _activePointer = event.pointer;
    _start = event.localPosition;
    _lean = Offset(
      ((_start.dx - area.width / 2) / (area.width / 2)).clamp(-1.0, 1.0),
      ((_start.dy - area.height / 2) / (area.height / 2)).clamp(-1.0, 1.0),
    );
    _drag.value = Offset.zero;
    _motion.value = .34;
    _motion.animateTo(
      1,
      duration: const Duration(milliseconds: 145),
      curve: Curves.easeOut,
    );
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    final offset = (event.localPosition - _start) * .28;
    _drag.value = offset.distance > 28
        ? offset * (28 / offset.distance)
        : offset;
  }

  void _release(PointerEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _bounce();
  }

  void _bounce() {
    final start = math.max(.32, _motion.value);
    _releaseCompression = start;
    _motion.animateWith(
      SpringSimulation(
        _spring,
        start,
        0,
        0,
        tolerance: const Tolerance(distance: .003, velocity: .04),
      ),
    );
  }

  void _tap() {
    if (MediaQuery.disableAnimationsOf(context) || _activePointer != null)
      return;
    _lean = Offset.zero;
    _drag.value = Offset.zero;
    _motion.value = .8;
    _bounce();
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _image?.dispose();
    _motion.dispose();
    _drag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image?.image;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final area = constraints.biggest;
            return Semantics(
              button: true,
              label: '袋鼠预览',
              hint: '按压、长按或拖动后松手',
              onTap: _tap,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) => _down(event, area),
                onPointerMove: _move,
                onPointerUp: _release,
                onPointerCancel: _release,
                child: GestureDetector(
                  // 赢得拖动手势，避免在袋鼠上拖动时带动外层列表。
                  onPanUpdate: (_) {},
                  child: AnimatedBuilder(
                    animation: _repaint,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        size: area,
                        painter: image == null
                            ? null
                            : _MascotPainter(
                                image,
                                widthScale: widget.widthScale,
                                heightScale: widget.heightScale,
                                belly: widget.belly,
                                shear: widget.shear,
                              ),
                      ),
                    ),
                    builder: (context, child) {
                      final displacement = _motion.value;
                      final offset =
                          _drag.value *
                          (_activePointer == null
                              ? displacement / _releaseCompression
                              : 1);
                      return Transform(
                        alignment: Alignment.center,
                        transformHitTests: false,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, .003)
                          ..translateByDouble(
                            offset.dx,
                            offset.dy,
                            35 * displacement,
                            1,
                          )
                          ..rotateX(_lean.dy * .26 * displacement)
                          ..rotateY(-_lean.dx * .28 * displacement),
                        child: child,
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MascotPainter extends CustomPainter {
  _MascotPainter(
    this.image, {
    required this.widthScale,
    required this.heightScale,
    required this.belly,
    required this.shear,
  });

  final ui.Image image;
  final double widthScale, heightScale, belly, shear;
  static const _rows = 28;
  static const _columns = 16;
  static final _indices = [
    for (var y = 0; y < _rows; y++)
      for (var x = 0; x < _columns; x++) ..._triangles(y * (_columns + 1) + x),
  ];

  static List<int> _triangles(int a) {
    final b = a + _columns + 1;
    return [a, a + 1, b, a + 1, b + 1, b];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final h = math.min(size.height * .74, size.width / 1.09);
    final w = h * image.width / image.height;
    final width = w * widthScale;
    final height = h * heightScale;
    final center = size.center(Offset.zero);
    final positions = <Offset>[];
    final textures = <Offset>[];
    for (var row = 0; row <= _rows; row++) {
      final y = row / _rows;
      // 肚皮在图面偏下。沿竖直方向做平滑包络，让头和脚保持比例。
      final bulge = math.exp(-math.pow((y - .63) / .18, 2));
      final dx = (y - .5) * shear * width * .42;
      for (var col = 0; col <= _columns; col++) {
        final x = col / _columns;
        final localX = x - .5;
        final distortion = 1 + .33 * belly * bulge * (1 - .65 * localX.abs());
        positions.add(
          Offset(
            center.dx + localX * width * distortion + dx,
            center.dy + (y - .5) * height,
          ),
        );
        textures.add(Offset(x * image.width, y * image.height));
      }
    }
    final shader = ui.ImageShader(
      image,
      TileMode.clamp,
      TileMode.clamp,
      Matrix4.identity().storage,
      filterQuality: FilterQuality.low,
    );
    final mesh = ui.Vertices(
      VertexMode.triangles,
      positions,
      textureCoordinates: textures,
      indices: _indices,
    );
    canvas.drawVertices(mesh, BlendMode.src, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_MascotPainter old) =>
      old.image != image ||
      old.widthScale != widthScale ||
      old.heightScale != heightScale ||
      old.belly != belly ||
      old.shear != shear;
}
