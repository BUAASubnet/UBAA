import 'package:ubaa_domain/ubaa_domain.dart';

/// 当前导航帧的展示集合，不回写业务快照或改变写操作资格。
class PagedResults {
  FeatureSnapshot? _base;
  FeatureQuery? _scope;
  final List<FeatureDetail> _details = [];
  int? _expected;
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

  void reset() {
    generation++;
    _base = null;
    _scope = null;
    _details.clear();
    _expected = null;
    error = null;
  }

  bool _sameScope(FeatureQuery a, FeatureQuery b) => a
      .copyWith(page: 0, fullRefresh: false)
      .hasSameParameters(b.copyWith(page: 0, fullRefresh: false));

  FeatureQuery? begin(FeatureSnapshot current, FeatureQuery query) {
    if (loading || !supports(current.feature, query)) return null;
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
  }

  FeatureSnapshot accept(FeatureSnapshot incoming, FeatureQuery? query) {
    if (!supports(incoming.feature, query)) return incoming;
    final scope = query ?? const FeatureQuery();
    if (_scope != null && !_sameScope(_scope!, scope)) reset();
    _scope = scope;
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
        fail('数据来源已变化，请刷新列表');
        return incoming.copyWith(
          status: FeatureLoadStatus.failure,
          clearDetails: true,
          error: const UiError(
            code: UbaaErrorCode.operationConflict,
            title: '请刷新列表',
            message: '数据来源已变化',
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
        fail('分页结果未更新，请重试');
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
