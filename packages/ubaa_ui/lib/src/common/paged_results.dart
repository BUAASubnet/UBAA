import 'package:ubaa_domain/ubaa_domain.dart';

/// 当前导航帧的展示集合，不回写业务快照或改变写操作资格。
class PagedResults {
  FeatureSnapshot? _base;
  FeatureQuery? _scope;
  final List<FeatureDetail> _details = [];
  int? _expected;
  PagedResults? _recovery;
  int _recoveryLastPage = 0;
  FeatureQuery? _recoveryQuery;
  FeatureQuery? get recoveryQuery => _recoveryQuery;
  int generation = 0;
  String? error;
  FeatureSnapshot? get snapshot => _base;
  bool get loading => _expected != null;
  List<FeatureDetail> get details => List.unmodifiable(_details);

  static bool supports(FeatureId feature, FeatureQuery? query) =>
      switch (feature) {
        FeatureId.bykc =>
          (query?.view ?? FeatureQueryView.summary) == FeatureQueryView.summary,
        FeatureId.cgyy => query?.view == FeatureQueryView.cgyyOrders,
        FeatureId.libbook => query?.view == FeatureQueryView.libbookBookings,
        FeatureId.ygdk => query?.view == FeatureQueryView.ygdkRecords,
        _ => false,
      };

  static int firstPage(FeatureId feature) => feature == FeatureId.cgyy ? 0 : 1;

  bool get hasMore {
    final base = _base;
    final page = base?.pagination;
    return page != null &&
        base?.error == null &&
        base?.status == FeatureLoadStatus.success &&
        base?.evidence?.complete != false &&
        base?.evidence?.origin != DataOrigin.persisted &&
        (page.hasMore ?? (page.page < page.effectiveTotalPages));
  }

  void cancelPending() {
    generation++;
    _expected = null;
    error = null;
    if (_base case final base?) {
      final retained = readonlyFeatureDetails(base.details);
      _details
        ..clear()
        ..addAll(retained);
      _base = base.copyWith(
        status: FeatureLoadStatus.stale,
        details: retained,
        overview: readonlyFeatureOverview(base.overview),
      );
      _recoveryLastPage = base.pagination?.page ?? 1;
      _recovery = _recoveryLastPage > 1 ? PagedResults() : null;
      _recoveryQuery = null;
    }
  }

  void reset() {
    generation++;
    _base = null;
    _scope = null;
    _details.clear();
    _expected = null;
    error = null;
    _recovery = null;
    _recoveryQuery = null;
  }

  bool _sameScope(FeatureQuery a, FeatureQuery b) => a
      .copyWith(page: 0, fullRefresh: false)
      .hasSameParameters(b.copyWith(page: 0, fullRefresh: false));

  FeatureQuery? begin(FeatureSnapshot current, FeatureQuery query) {
    if (loading || !supports(current.feature, query)) return null;
    if (_recovery != null && error != null) {
      error = null;
      return _recoveryQuery = query.copyWith(page: firstPage(current.feature));
    }
    if (_base == null) accept(current, query);
    if (!hasMore || _base?.pagination == null) return null;
    error = null;
    _expected = _base!.pagination!.page + 1;
    return query.copyWith(
      page: _expected! - (current.feature == FeatureId.cgyy ? 1 : 0),
    );
  }

  void fail([String message = '加载更多失败，请重试']) {
    _expected = null;
    error = message;
    _recovery?.reset();
    _recoveryQuery = null;
  }

  /// 放弃进行中的续载但不报错：已显示内容不变，之后仍可继续加载下一页。
  void abandon() {
    if (_recovery != null) return fail();
    _expected = null;
  }

  FeatureSnapshot _recover(FeatureSnapshot incoming, FeatureQuery scope) {
    final previous = _base!;
    final recovery = _recovery!;
    if (incoming.status == FeatureLoadStatus.loading) return previous;
    if (incoming.error != null ||
        incoming.evidence?.complete == false ||
        incoming.evidence?.origin == DataOrigin.persisted ||
        !const {
          FeatureLoadStatus.success,
          FeatureLoadStatus.empty,
        }.contains(incoming.status)) {
      fail('刷新失败，已保留原列表');
      return previous.copyWith(error: incoming.error);
    }
    error = null;
    final requested = _recoveryQuery != null;
    _recoveryQuery ??= scope.copyWith(page: firstPage(incoming.feature));
    final expectedPage =
        _recoveryQuery!.page + (incoming.feature == FeatureId.cgyy ? 1 : 0);
    if (incoming.pagination?.page != expectedPage &&
        incoming.status != FeatureLoadStatus.empty) {
      if (requested) fail('列表已变化，请刷新');
      return previous;
    }
    final merged = recovery.accept(incoming, _recoveryQuery);
    if (recovery.error != null) {
      fail('刷新失败，已保留原列表');
      return previous;
    }
    final next = (incoming.pagination?.page ?? 1) < _recoveryLastPage
        ? recovery.begin(merged, _recoveryQuery!)
        : null;
    if (next != null) {
      _recoveryQuery = next;
      return previous;
    }
    _base = merged;
    _details
      ..clear()
      ..addAll(merged.details);
    _recovery = null;
    _recoveryQuery = null;
    error = null;
    return merged;
  }

  FeatureSnapshot accept(FeatureSnapshot incoming, FeatureQuery? query) {
    if (!supports(incoming.feature, query)) return incoming;
    final scope = query ?? const FeatureQuery();
    if (_scope != null && !_sameScope(_scope!, scope)) reset();
    _scope = scope;
    if (_recovery != null) return _recover(incoming, scope);
    final previous = _base;
    if (_expected != null && previous != null) {
      if (incoming.status == FeatureLoadStatus.loading) {
        return previous.copyWith(
          status: FeatureLoadStatus.loading,
          readContext: incoming.readContext,
        );
      }
      if ((incoming.resolvedRoute != null &&
              previous.resolvedRoute != null &&
              incoming.resolvedRoute != previous.resolvedRoute) ||
          (incoming.evidence?.accountId != null &&
              previous.evidence?.accountId != null &&
              incoming.evidence?.accountId != previous.evidence?.accountId)) {
        reset();
        fail('列表已更新，请刷新');
        return incoming.copyWith(
          status: FeatureLoadStatus.failure,
          clearDetails: true,
          error: const UiError(
            code: UbaaErrorCode.operationConflict,
            title: '请刷新列表',
            message: '列表已更新，请刷新',
          ),
        );
      }
      if (incoming.status == FeatureLoadStatus.failure ||
          incoming.error != null ||
          incoming.evidence?.complete == false ||
          incoming.evidence?.origin == DataOrigin.persisted) {
        fail();
        return previous;
      }
      if (incoming.pagination?.page != _expected) {
        fail('列表已更新，请刷新');
        return previous;
      }
      final oldCount = _details.length;
      final indexed = <Object, int>{};
      for (var i = 0; i < _details.length; i++) {
        final key = _key(_details[i]);
        if (key != null) indexed[key] = i;
      }
      for (final detail in incoming.details) {
        final key = _key(detail);
        final index = key == null ? null : indexed[key];
        if (index != null) {
          _details[index] = detail;
        } else {
          if (key != null) indexed[key] = _details.length;
          _details.add(detail);
        }
      }
      _expected = null;
      _base = incoming.copyWith(
        details: details,
        status: _details.isEmpty ? incoming.status : FeatureLoadStatus.success,
      );
      if (_details.length == oldCount && hasMore) fail('本页没有新增内容，请刷新列表');
      return _base!;
    }
    if (incoming.status == FeatureLoadStatus.success ||
        incoming.status == FeatureLoadStatus.empty ||
        incoming.status == FeatureLoadStatus.stale) {
      _base = incoming;
      _details
        ..clear()
        ..addAll(incoming.details);
    }
    return incoming;
  }

  Object? _key(FeatureDetail detail) => switch (detail.presentation) {
    BykcCoursePresentation value => ('bykc', value.id),
    CgyyOrderPresentation value => ('cgyy', value.id),
    LibbookBookingPresentation value => ('libbook', value.id),
    YgdkRecordPresentation value => ('ygdk', value.recordId),
    _ => null,
  };
}
