import 'dart:async';
import 'paged_results.dart';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'feature_detail.dart'
    show FeatureDetailViewState, uiReadableCachedContent;
import 'landing_menu.dart' show uiHasLandingMenu, uiReadPageTitle;

/// 父页只保存展示快照，不回写 AppController 或作为写入核对依据。
class FeatureReadNavigator extends StatefulWidget {
  const FeatureReadNavigator({
    required this.snapshot,
    required this.cacheEpoch,
    this.businessCacheEpoch = 0,
    required this.onExit,
    required this.onRetry,
    required this.pageBuilder,
    required this.onVisibleSnapshot,
    this.onQuery,
    super.key,
  });
  final void Function(FeatureSnapshot, String) onVisibleSnapshot;
  final FeatureSnapshot snapshot;
  final int cacheEpoch;
  final int businessCacheEpoch;
  final VoidCallback onExit;
  final Future<void> Function() onRetry;
  final Future<void> Function(FeatureQuery)? onQuery;
  final Widget Function(_ReadPage) pageBuilder;
  @override
  State<FeatureReadNavigator> createState() => FeatureReadNavigatorState();
}

class FeatureReadNavigatorState extends State<FeatureReadNavigator> {
  final List<_ReadFrame> _frames = [];
  int _nextId = 0;
  int? _externalAfterRevision;
  bool _reloadScheduled = false;
  static const _invalidatedError = UiError(
    code: UbaaErrorCode.operationConflict,
    title: '列表需要更新',
    message: '读取状态已变化，请刷新重试。',
    retryable: true,
  );
  _ReadFrame get currentFrame => _current;
  _ReadFrame get _current => _frames.last;
  @override
  void initState() {
    super.initState();
    _frames.add(
      _ReadFrame(
        _nextId++,
        widget.snapshot,
        widget.snapshot.readContext?.query,
        isLanding:
            widget.onQuery != null && uiHasLandingMenu(widget.snapshot.feature),
      ),
    );
    if (widget.snapshot.status == FeatureLoadStatus.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // 首页待办或成绩提醒可能已在同帧打开指定查询，不能再用默认
        // 读取覆盖它；此时宿主的旧 idle 快照还来不及随重建更新。
        if (mounted &&
            widget.snapshot.status == FeatureLoadStatus.idle &&
            _current.snapshot.status == FeatureLoadStatus.idle &&
            _current.query == null) {
          widget.onRetry();
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant FeatureReadNavigator oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = widget.snapshot;
    final context = incoming.readContext;
    if (oldWidget.businessCacheEpoch != widget.businessCacheEpoch) {
      // 清理内容但保留返回路径、查询参数和当前页面key。
      for (final frame in _frames) {
        frame.feed.reset();
        frame.needsReload = false;
        frame.snapshot = FeatureSnapshot(
          feature: frame.snapshot.feature,
          readContext: frame.snapshot.readContext,
        );
      }
      _externalAfterRevision = null;
    }
    if (oldWidget.cacheEpoch != widget.cacheEpoch) {
      final current = _current;
      for (final frame in _frames) {
        frame.feed.reset();
        if (frame.isLanding) {
          frame.needsReload = false;
          frame.snapshot = FeatureSnapshot(feature: frame.snapshot.feature);
        } else if (PagedResults.supports(frame.snapshot.feature, frame.query)) {
          frame.needsReload = true;
          frame.snapshot = FeatureSnapshot(
            feature: frame.snapshot.feature,
            status: FeatureLoadStatus.failure,
            error: _invalidatedError,
          );
        }
      }
      _frames.clear();
      if (!current.isLanding && uiHasLandingMenu(incoming.feature)) {
        _frames.add(
          _ReadFrame(
            _nextId++,
            FeatureSnapshot(feature: incoming.feature),
            null,
            isLanding: true,
          ),
        );
      }
      _frames.add(current);
      // 失效通知可能仍携带旧子页快照；只接收边界之后的新读取代次。
      _externalAfterRevision =
          oldWidget.snapshot.readContext?.requestRevision ?? -1;
      if (current.bykcChosenKey != null) {
        current.snapshot = incoming.copyWith(
          status: FeatureLoadStatus.loading,
          clearDetails: true,
        );
      }
    }
    if (_current.isLanding) {
      if (_externalAfterRevision == null ||
          (context?.requestRevision ?? -1) > _externalAfterRevision!) {
        _current.snapshot = incoming;
      }
      return;
    }
    if ((_current.bykcChosenKey != null ||
            PagedResults.supports(incoming.feature, _current.query)) &&
        _externalAfterRevision != null &&
        (context?.requestRevision ?? -1) <= _externalAfterRevision!)
      return;
    if (context != null &&
        _externalAfterRevision != null &&
        context.requestRevision > _externalAfterRevision!) {
      _externalAfterRevision = null;
      if (!context.hasSameQuery(_current.query)) {
        _frames[_frames.length - 1] = _ReadFrame(
          _nextId++,
          incoming,
          context.query,
        );
        return;
      }
    }
    final isChosenParentRead =
        _current.bykcChosenKey != null &&
        context?.query?.view == FeatureQueryView.bykcChosenCourses &&
        context?.query?.courseId == null;
    if (!identical(incoming, oldWidget.snapshot) &&
        (context == null ||
            context.hasSameQuery(_current.query) ||
            isChosenParentRead)) {
      _current.needsReload = false;
      _current.snapshot =
          incoming.feature == FeatureId.bykc &&
              context?.query?.view == FeatureQueryView.bykcDetail &&
              incoming.status == FeatureLoadStatus.stale
          ? incoming.copyWith(
              status: FeatureLoadStatus.failure,
              clearDetails: true,
            )
          : _current.feed.accept(incoming, _current.query);
      if (_current.bykcChosenKey != null &&
          context != null &&
          incoming.status != FeatureLoadStatus.loading) {
        // 组合详情中的已选读取仍更新具体父帧，返回时不能复活旧记录。
        for (final frame in _frames) {
          if (!identical(frame, _current) &&
              (context.hasSameQuery(frame.query) ||
                  frame.id == _current.bykcChosenParentId)) {
            frame.snapshot = incoming;
          }
        }
      }
    }
  }

  bool get _isAssignmentFeature =>
      widget.snapshot.feature == FeatureId.spoc ||
      widget.snapshot.feature == FeatureId.judge;

  bool _isAssignmentDetail(_ReadFrame frame) =>
      _isAssignmentFeature &&
      (const {
            FeatureQueryView.spocDetail,
            FeatureQueryView.judgeDetail,
            FeatureQueryView.judgeBatchDetails,
          }.contains(frame.query?.view) ||
          frame.snapshot.details.any(
            (detail) => switch (detail.presentation) {
              SpocAssignmentPresentation p => p.isDetail,
              JudgeAssignmentPresentation p => p.isDetail,
              _ => false,
            },
          ));

  _ReadFrame _assignmentList() {
    if (!_isAssignmentDetail(_frames.first)) return _frames.first;
    return _ReadFrame(
      _nextId++,
      FeatureSnapshot(feature: widget.snapshot.feature),
      const FeatureQuery(),
    );
  }

  /// 功能入口回到子菜单或作业列表，具体待办仍沿指定查询打开。
  void openList() {
    if (widget.onQuery == null) return;
    if (uiHasLandingMenu(widget.snapshot.feature)) {
      if (_current.isLanding) return;
      final landing = _frames.first.isLanding
          ? _frames.first
          : _ReadFrame(_nextId++, widget.snapshot, null, isLanding: true);
      setState(() {
        _frames
          ..clear()
          ..add(landing);
      });
      return;
    }
    if (!_isAssignmentFeature) return;
    final parent = _assignmentList();
    setState(() {
      _externalAfterRevision = null;
      _frames
        ..clear()
        ..add(parent);
    });
    if (parent.snapshot.status == FeatureLoadStatus.idle) {
      unawaited(_query(parent, parent.query ?? const FeatureQuery()));
    }
  }

  Future<void> openFromHome(FeatureReadNavigation target) async {
    if (widget.onQuery == null || target.feature != widget.snapshot.feature)
      return;
    final parent = _isAssignmentFeature ? _assignmentList() : null;
    setState(() {
      _externalAfterRevision = null;
      _frames.clear();
      if (parent != null) _frames.add(parent);
      _frames.add(
        _ReadFrame(
          _nextId++,
          FeatureSnapshot(
            feature: target.feature,
            status: FeatureLoadStatus.loading,
          ),
          target.query,
        ),
      );
    });
    await widget.onQuery!(target.query);
  }

  void openPanel() => _current.pageKey.currentState?.togglePanel();

  void selectScheduleTerm() =>
      _current.pageKey.currentState?.selectScheduleTerm();

  void goBack() {
    if (_frames.length == 1) {
      if (_isAssignmentDetail(_current) && widget.onQuery != null) {
        openList();
        return;
      }
      widget.onExit();
    } else {
      setState(() => _frames.removeLast());
      if (_isAssignmentFeature &&
          _current.snapshot.status == FeatureLoadStatus.idle &&
          widget.onQuery != null) {
        unawaited(_query(_current, _current.query ?? const FeatureQuery()));
      } else if ((widget.snapshot.feature == FeatureId.judge ||
              uiReadableCachedContent(_current.snapshot)) &&
          _current.snapshot.status == FeatureLoadStatus.loading &&
          widget.onQuery != null) {
        unawaited(_query(_current, _current.query ?? const FeatureQuery()));
      }
    }
  }

  Future<void> refreshCurrent() {
    final library = _current.pageKey.currentState?.refreshLibrary();
    if (library != null) return library;
    if (!_current.isLanding &&
        widget.onQuery != null &&
        PagedResults.supports(widget.snapshot.feature, _current.query)) {
      return _query(
        _current,
        (_current.query ?? const FeatureQuery()).copyWith(
          page: PagedResults.firstPage(widget.snapshot.feature),
        ),
      );
    }
    return _current.isLanding ||
            _current.query == null ||
            widget.onQuery == null
        ? widget.onRetry()
        : _query(_current, _current.query!);
  }

  Future<void> _query(_ReadFrame frame, FeatureQuery query) async {
    if (widget.onQuery == null || !identical(frame, _current)) return;
    if (_isAssignmentFeature &&
        !_isAssignmentDetail(frame) &&
        const {
          FeatureQueryView.spocDetail,
          FeatureQueryView.judgeDetail,
          FeatureQueryView.judgeBatchDetails,
        }.contains(query.view)) {
      await _navigate(
        FeatureReadNavigation(feature: widget.snapshot.feature, query: query),
      );
      return;
    }
    if (frame.isLanding) {
      await _navigate(
        FeatureReadNavigation(feature: widget.snapshot.feature, query: query),
        force: true,
      );
      return;
    }
    setState(() {
      _externalAfterRevision = null;
      frame.feed.reset();
      frame.needsReload = false;
      if (frame.query == null || !query.hasSameParameters(frame.query!))
        frame.bykcChosenKey = null;
      if (frame.query == null || !query.hasSameParameters(frame.query!))
        frame.scheduleTitle = null;
      frame.query = query;
    });
    await widget.onQuery!(query);
  }

  Future<void> _loadMore(_ReadFrame frame) async {
    if (!mounted ||
        widget.onQuery == null ||
        !identical(frame, _current) ||
        frame.requestingMore ||
        frame.snapshot.status == FeatureLoadStatus.loading ||
        !TickerMode.valuesOf(context).enabled)
      return;
    final next = frame.feed.begin(
      frame.snapshot,
      frame.query ?? const FeatureQuery(),
    );
    if (next == null) return;
    final generation = frame.feed.generation;
    setState(() {
      frame.requestingMore = true;
      frame.query = next;
    });
    try {
      await widget.onQuery!(next);
    } catch (_) {
      if (mounted && generation == frame.feed.generation) {
        frame.feed.fail();
        if (frame.feed.snapshot != null) frame.snapshot = frame.feed.snapshot!;
      }
    } finally {
      // 宿主状态通知在下一帧传入，不能把尚未构建的成功响应当成失败。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          frame.requestingMore = false;
          if (generation == frame.feed.generation && frame.feed.loading) {
            frame.feed.fail();
            if (frame.feed.snapshot != null)
              frame.snapshot = frame.feed.snapshot!;
          }
        });
      });
      if (mounted) setState(() {});
    }
  }

  Future<void> _navigate(
    FeatureReadNavigation target, {
    bool force = false,
  }) async {
    if (widget.onQuery == null ||
        target.feature != widget.snapshot.feature ||
        (_current.snapshot.status == FeatureLoadStatus.loading &&
            !_current.isLanding &&
            widget.snapshot.feature != FeatureId.judge &&
            !uiReadableCachedContent(_current.snapshot)))
      return;
    final cached = _current.snapshot;
    final reuseDefault =
        !force &&
        _current.isLanding &&
        target.query.hasSameParameters(const FeatureQuery()) &&
        (cached.readContext?.query == null ||
            cached.readContext!.query!.hasSameParameters(target.query)) &&
        cached.status != FeatureLoadStatus.idle;
    if (reuseDefault) {
      setState(() {
        _externalAfterRevision = null;
        _frames.add(
          _ReadFrame(
            _nextId++,
            cached,
            cached.readContext?.query,
            navigationQuery: target.query,
          ),
        );
      });
      return;
    }
    final frame = _ReadFrame(
      _nextId++,
      FeatureSnapshot(
        feature: target.feature,
        status: target.query.view == FeatureQueryView.cgyyLockCode
            ? FeatureLoadStatus.idle
            : FeatureLoadStatus.loading,
      ),
      target.query,
    );
    setState(() {
      _externalAfterRevision = null;
      _frames.add(frame);
    });
    await widget.onQuery!(target.query);
  }

  Future<void> _openBykcChosen(FeatureDetail detail) async {
    if (widget.snapshot.feature != FeatureId.bykc ||
        _current.snapshot.status == FeatureLoadStatus.loading ||
        !_current.snapshot.details.any((d) => identical(d, detail)))
      return;
    final value = detail.presentation;
    if (value is! BykcChosenPresentation ||
        value.courseId <= 0 ||
        widget.onQuery == null)
      return;
    final parent = _current;
    final query = FeatureQuery(
      view: FeatureQueryView.bykcChosenCourses,
      courseId: '${value.courseId}',
    );
    setState(
      () => _frames.add(
        _ReadFrame(
          _nextId++,
          parent.snapshot.copyWith(
            status: FeatureLoadStatus.loading,
            clearDetails: true,
          ),
          query,
          bykcChosenKey: (value.recordId, value.courseId),
          bykcChosenParentId: parent.id,
        ),
      ),
    );
    await widget.onQuery!(query);
  }

  void _scheduleInvalidatedReload() {
    final frame = _current;
    if (_reloadScheduled ||
        !frame.needsReload ||
        frame.isLanding ||
        widget.onQuery == null ||
        !TickerMode.valuesOf(context).enabled)
      return;
    _reloadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _reloadScheduled = false;
      if (!mounted ||
          !identical(frame, _current) ||
          !frame.needsReload ||
          !TickerMode.valuesOf(context).enabled)
        return;
      final generation = frame.feed.generation + 1;
      try {
        await _query(
          frame,
          (frame.query ?? const FeatureQuery()).copyWith(
            page: PagedResults.firstPage(frame.snapshot.feature),
          ),
        );
      } catch (_) {
        if (mounted &&
            identical(frame, _current) &&
            frame.feed.generation == generation) {
          setState(
            () => frame.snapshot = FeatureSnapshot(
              feature: frame.snapshot.feature,
              status: FeatureLoadStatus.failure,
              error: _invalidatedError,
            ),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _scheduleInvalidatedReload();
    final visible = _current.visibleSnapshot;
    final title = _current.bykcChosenKey != null
        ? '课程详情'
        : visible.feature == FeatureId.schedule
        ? '课表'
        : _current.scheduleTitle ??
              uiReadPageTitle(
                visible.feature,
                _current.query ?? _current.navigationQuery,
                _current.isLanding,
              );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(visible, _current.visibleSnapshot))
        widget.onVisibleSnapshot(visible, title);
    });
    return IndexedStack(
      index: _frames.length - 1,
      children: [
        for (final frame in _frames)
          ExcludeFocus(
            key: ValueKey<int>(frame.id),
            excluding: !identical(frame, _current),
            child: TickerMode(
              enabled: identical(frame, _current),
              child: widget.pageBuilder(
                _ReadPage(
                  pageKey: frame.pageKey,
                  paginationGeneration: frame.feed.generation,
                  loadingMore: frame.feed.loading || frame.requestingMore,
                  moreError: frame.feed.error,
                  hasMore: frame.feed.snapshot == null
                      ? frame.snapshot.status == FeatureLoadStatus.success &&
                            frame.snapshot.evidence?.complete != false &&
                            frame.snapshot.evidence?.origin !=
                                DataOrigin.persisted &&
                            frame.snapshot.pagination != null &&
                            (frame.snapshot.pagination!.hasMore ??
                                (frame.snapshot.pagination!.page <
                                    frame
                                        .snapshot
                                        .pagination!
                                        .effectiveTotalPages))
                      : frame.feed.hasMore,
                  onLoadMore:
                      widget.onQuery == null ||
                          !PagedResults.supports(
                            frame.snapshot.feature,
                            frame.query,
                          )
                      ? null
                      : () => _loadMore(frame),
                  onScheduleTitle: (title) {
                    if (!mounted ||
                        !identical(frame, _current) ||
                        frame.scheduleTitle == title)
                      return;
                    setState(() => frame.scheduleTitle = title);
                  },
                  isLanding: frame.isLanding,
                  isCurrent: identical(frame, _current),
                  snapshot: frame.bykcChosenKey == null
                      ? frame.snapshot
                      : frame.visibleSnapshot,
                  isBykcChosenDetail: frame.bykcChosenKey != null,
                  onOpenBykcChosen: _openBykcChosen,
                  query: frame.query,
                  backLabel: _frames.indexOf(frame) == 0 ? '返回功能列表' : '返回上一层',
                  onBack: goBack,
                  onRetry: () => frame.query == null || widget.onQuery == null
                      ? widget.onRetry()
                      : _query(frame, frame.query!),
                  onQuery: widget.onQuery == null
                      ? null
                      : (query) => _query(frame, query),
                  onNavigate: widget.onQuery == null ? null : _navigate,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ReadFrame {
  _ReadFrame(
    this.id,
    this.snapshot,
    this.query, {
    this.isLanding = false,
    this.navigationQuery,
    this.bykcChosenKey,
    this.bykcChosenParentId,
  }) : menuSnapshot = FeatureSnapshot(feature: snapshot.feature);
  final bool isLanding;
  String? scheduleTitle;
  final FeatureQuery? navigationQuery;
  final FeatureSnapshot menuSnapshot;
  (int, int)? bykcChosenKey;
  final int? bykcChosenParentId;
  FeatureSnapshot? _chosenSource, _chosenSnapshot;
  FeatureSnapshot get visibleSnapshot {
    if (isLanding) return menuSnapshot;
    final key = bykcChosenKey;
    if (key == null) return snapshot;
    if (!identical(_chosenSource, snapshot)) {
      final matches = snapshot.details
          .where(
            (d) =>
                d.presentation is BykcChosenPresentation &&
                (
                      (d.presentation! as BykcChosenPresentation).recordId,
                      (d.presentation! as BykcChosenPresentation).courseId,
                    ) ==
                    key,
          )
          .toList();
      final unique = matches.length == 1;
      final full = unique
          ? (matches.single.presentation! as BykcChosenPresentation).fullDetail
          : null;
      final complete = full?.id == key.$2 && full?.supplement != null;
      _chosenSource = snapshot;
      if (snapshot.status == FeatureLoadStatus.stale ||
          unique && snapshot.status == FeatureLoadStatus.success && !complete) {
        _chosenSnapshot = snapshot.copyWith(
          status: FeatureLoadStatus.failure,
          clearDetails: true,
          clearPagination: true,
          error:
              snapshot.error ??
              const UiError(
                code: UbaaErrorCode.upstreamChanged,
                title: '详情读取失败',
                message: '课程补充详情尚未读取，请刷新。',
                retryable: true,
              ),
        );
        return _chosenSnapshot!;
      }
      _chosenSnapshot = snapshot.copyWith(
        details: unique ? matches : const [],
        clearPagination: true,
        status: !unique && snapshot.status == FeatureLoadStatus.success
            ? FeatureLoadStatus.empty
            : snapshot.status,
      );
    }
    return _chosenSnapshot!;
  }

  final feed = PagedResults();
  bool requestingMore = false;
  bool needsReload = false;
  final pageKey = GlobalKey<FeatureDetailViewState>();
  final int id;
  FeatureSnapshot snapshot;
  FeatureQuery? query;
}

class _ReadPage {
  const _ReadPage({
    required this.pageKey,
    this.paginationGeneration = 0,
    this.loadingMore = false,
    this.moreError,
    this.hasMore = false,
    this.onLoadMore,
    required this.isLanding,
    required this.isCurrent,
    required this.snapshot,
    required this.query,
    required this.backLabel,
    required this.onBack,
    required this.onRetry,
    this.onQuery,
    this.onNavigate,
    this.isBykcChosenDetail = false,
    this.onOpenBykcChosen,
    this.onScheduleTitle,
  });
  final ValueChanged<String?>? onScheduleTitle;
  final int paginationGeneration;
  final bool loadingMore, hasMore;
  final String? moreError;
  final Future<void> Function()? onLoadMore;
  final bool isBykcChosenDetail;
  final ValueChanged<FeatureDetail>? onOpenBykcChosen;
  final GlobalKey<FeatureDetailViewState> pageKey;
  final bool isLanding;
  final bool isCurrent;
  final FeatureSnapshot snapshot;
  final FeatureQuery? query;
  final String backLabel;
  final VoidCallback onBack;
  final Future<void> Function() onRetry;
  final Future<void> Function(FeatureQuery)? onQuery;
  final Future<void> Function(FeatureReadNavigation)? onNavigate;
}
