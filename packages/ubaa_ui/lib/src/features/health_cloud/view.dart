import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import 'events.dart';
import 'measurements.dart';
import 'switches.dart';

const healthCloudTitle = '健康云';
const healthCloudAssets = 'assets/health_cloud';

class HealthCloudView extends StatefulWidget {
  const HealthCloudView({super.key, required this.read});

  final ReadHealthCloud? read;

  @override
  State<HealthCloudView> createState() => _HealthCloudViewState();
}

class _HealthCloudViewState extends State<HealthCloudView> {
  HealthCloudPage? _page;
  String? _year;
  int _request = 0;
  bool _showEvents = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _load([String? year]) async {
    final read = widget.read;
    final request = ++_request;
    setState(() {
      _year = year ?? _year;
      _loading = true;
      _error = null;
    });
    try {
      if (read == null) {
        setState(() => _error = '请登录后查看体测成绩');
        return;
      }
      final page = await read(_year);
      if (!mounted || request != _request) return;
      setState(() {
        _page = page;
        _year = page.selectedYear;
      });
    } on Object catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = error is UiError ? error.message : '暂时无法读取体测成绩';
      });
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final report = _page?.report;
      final inset = (constraints.maxWidth * .035).clamp(10.0, 30.0);
      return Column(
        children: [
          if (_page?.years case final years? when years.isNotEmpty)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: inset),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 660),
                  child: Row(
                    children: [
                      // Reserve the same space on both sides so refresh never shifts the track.
                      const SizedBox(width: 42),
                      Expanded(
                        child: HealthCloudSwitch(
                          items: [
                            for (final year in years)
                              (
                                '${year.year}年',
                                Text('${year.year}', maxLines: 1),
                              ),
                          ],
                          selected: years.indexWhere(
                            (year) => year.key == _year,
                          ),
                          onSelected: (index) =>
                              unawaited(_load(years[index].key)),
                        ),
                      ),
                      SizedBox(
                        width: 42,
                        child: IconButton(
                          tooltip: '刷新体测成绩',
                          onPressed: _loading ? null : _load,
                          icon: const Icon(Icons.refresh, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: LayoutBuilder(
                builder: (context, viewport) => ListView(
                  key: PageStorageKey(_showEvents),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(inset, 12, inset, 8),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: SizedBox(
                          width: double.infinity,
                          child: _loading
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(32),
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              : _error != null
                              ? Column(
                                  children: [
                                    Text(_error!, textAlign: TextAlign.center),
                                    TextButton(
                                      onPressed: _load,
                                      child: const Text('重试'),
                                    ),
                                  ],
                                )
                              : report == null
                              ? const Center(child: Text('该年度暂无体测成绩'))
                              : _showEvents
                              ? HealthCloudEvents(
                                  report: report,
                                  viewportHeight: viewport.maxHeight,
                                )
                              : HealthCloudMeasurements(
                                  key: ValueKey(_request),
                                  report: report,
                                  viewportHeight: viewport.maxHeight,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Center(
              child: HealthCloudSwitch(
                iconsOnly: true,
                items: [
                  for (final (file, label) in const [
                    ('measure', '身体指标'),
                    ('events', '运动成绩'),
                  ])
                    (
                      label,
                      Image.asset(
                        '$healthCloudAssets/$file.webp',
                        package: 'ubaa_ui',
                        width: 29,
                        height: 29,
                        color: Theme.of(context).colorScheme.primary,
                        colorBlendMode: BlendMode.srcIn,
                        excludeFromSemantics: true,
                      ),
                    ),
                ],
                selected: _showEvents ? 1 : 0,
                onSelected: (index) {
                  final events = index == 1;
                  if (_showEvents == events) return;
                  setState(() => _showEvents = events);
                  unawaited(_load());
                },
              ),
            ),
          ),
        ],
      );
    },
  );
}
