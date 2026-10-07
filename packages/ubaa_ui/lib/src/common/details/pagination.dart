part of 'detail_list.dart';

extension FeatureDetailPagination on _FeatureDetailListState {
  // 展示分页为一基，研讨室订单请求保留上游零基；不改变其它领域。
  int get _serverPageOffset {
    if (widget.feature == FeatureId.cgyy) {
      final view = widget.query?.view;
      if (view == null || view == FeatureQueryView.cgyyOrders) {
        return 1;
      }
    }
    return 0;
  }

  List<Widget> _paginationFields(
    StateSetter setState,
    FeaturePagination? serverPagination,
    int pageCount,
    int page,
  ) {
    final baseQuery = widget.query ?? const FeatureQuery();
    return <Widget>[
      if (serverPagination != null && widget.onQuery != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              IconButton(
                tooltip: '上一页',
                onPressed: serverPagination.page <= 1
                    ? null
                    : () => widget.onQuery!(
                        baseQuery.copyWith(
                          page: serverPagination.page - 1 - _serverPageOffset,
                        ),
                      ),
                icon: const Icon(Icons.chevron_left),
              ),
              Semantics(
                label: '服务端分页',
                child: Text(
                  serverPagination.effectiveTotalPages > 0
                      ? '第 ${serverPagination.page} / ${serverPagination.effectiveTotalPages} 页（共 ${serverPagination.total} 条）'
                      : '第 ${serverPagination.page} 页（共 ${serverPagination.total} 条）',
                ),
              ),
              IconButton(
                tooltip: '下一页',
                onPressed:
                    !(serverPagination.hasMore ??
                        (serverPagination.effectiveTotalPages > 0 &&
                            serverPagination.page <
                                serverPagination.effectiveTotalPages))
                    ? null
                    : () => widget.onQuery!(
                        baseQuery.copyWith(
                          page: serverPagination.page + 1 - _serverPageOffset,
                        ),
                      ),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        )
      else if (pageCount > 1)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              IconButton(
                tooltip: '上一页',
                onPressed: page == 0
                    ? null
                    : () => setState(() => _page = page - 1),
                icon: const Icon(Icons.chevron_left),
              ),
              Semantics(label: '详情分页', child: Text('${page + 1} / $pageCount')),
              IconButton(
                tooltip: '下一页',
                onPressed: page + 1 >= pageCount
                    ? null
                    : () => setState(() => _page = page + 1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
    ];
  }
}
