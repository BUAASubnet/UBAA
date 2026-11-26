import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import 'classroom_format.dart' show mediaClock;
import 'classroom_panels.dart' show ClassroomLoad;

/// PPT 缩略图条：横向排列，当前页高亮并随播放滚动；点击跳到该页出现的时刻。
///
/// 无 PPT 或读取失败时整条收起，不占位置（PPT 是辅助信息，不阻塞播放）。
class ClassroomSlideStrip extends StatefulWidget {
  const ClassroomSlideStrip({
    super.key,
    required this.load,
    required this.position,
    required this.onSeek,
  });
  final ClassroomLoad<ClassroomSlides> load;
  final ValueListenable<Duration> position;
  final void Function(Duration) onSeek;

  @override
  State<ClassroomSlideStrip> createState() => _ClassroomSlideStripState();
}

class _ClassroomSlideStripState extends State<ClassroomSlideStrip> {
  static const _thumbWidth = 96.0, _gap = 8.0;
  final _scroll = ScrollController();
  int? _current;

  @override
  void initState() {
    super.initState();
    widget.load.ensure();
    widget.position.addListener(_onPosition);
    widget.load.state.addListener(_onPosition);
  }

  @override
  void dispose() {
    widget.position.removeListener(_onPosition);
    widget.load.state.removeListener(_onPosition);
    _scroll.dispose();
    super.dispose();
  }

  List<ClassroomSlide> get _slides =>
      widget.load.state.value.data?.slides ?? const [];

  void _onPosition() {
    final slides = _slides;
    final ms = widget.position.value.inMilliseconds;
    int? index;
    for (var i = 0; i < slides.length; i++) {
      if (slides[i].offsetMs <= ms) {
        index = i;
      } else {
        break;
      }
    }
    if (index == _current) return;
    setState(() => _current = index);
    if (index != null && _scroll.hasClients) {
      final viewport = _scroll.position.viewportDimension;
      final target =
          (index * (_thumbWidth + _gap)) - (viewport - _thumbWidth) / 2;
      _scroll.animateTo(
        target.clamp(0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: widget.load.state,
    builder: (context, snapshot, _) {
      final slides = snapshot.data?.slides ?? const <ClassroomSlide>[];
      if (slides.isEmpty) return const SizedBox.shrink();
      final colors = Theme.of(context).colorScheme;
      return SizedBox(
        height: 54 + 18 + 16,
        child: ListView.separated(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: slides.length,
          separatorBuilder: (_, _) => const SizedBox(width: _gap),
          itemBuilder: (context, i) {
            final slide = slides[i];
            final active = i == _current;
            return Tooltip(
              message:
                  '第 ${i + 1} 页 · ${mediaClock(Duration(milliseconds: slide.offsetMs))}',
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () =>
                    widget.onSeek(Duration(milliseconds: slide.offsetMs)),
                child: SizedBox(
                  width: _thumbWidth,
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        height: 54,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: active
                                ? colors.primary
                                : colors.outlineVariant,
                            width: active ? 2 : 1,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.network(
                          slide.thumbUrl,
                          fit: BoxFit.cover,
                          width: _thumbWidth,
                          errorBuilder: (_, _, _) => ColoredBox(
                            color: colors.surfaceContainerHighest,
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              size: 18,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        mediaClock(Duration(milliseconds: slide.offsetMs)),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: active
                              ? colors.primary
                              : colors.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    },
  );
}
