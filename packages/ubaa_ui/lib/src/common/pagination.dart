part of '../widgets.dart';

extension _FeatureDetailPagination on _FeatureDetailListState {
  List<Widget> _paginationFields(
    StateSetter setState,
    FeaturePagination? serverPagination,
    int pageCount,
    int page,
  ) => <Widget>[
    if (serverPagination != null &&
        widget.onQuery != null &&
        widget.query != null)
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
                      widget.query!.copyWith(page: serverPagination.page - 1),
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
                      widget.query!.copyWith(page: serverPagination.page + 1),
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
