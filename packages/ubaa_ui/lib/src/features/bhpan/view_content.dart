part of 'view.dart';

/// 云盘列表的错误、空状态与读取内容。
extension _BhpanContent on _BhpanViewState {
  Widget _errorPanel(Object error) {
    final code = error is UiError ? error.code : null;
    // 学校 SSO 会话过期时上游给的是「权限不足」码、认证类错误，按登录失效展示。
    final authExpired =
        error is UiError && error.kind == UbaaErrorKind.authentication;
    if (_received)
      return UiStatePanel(
        icon: Icons.link_off,
        title: '没能打开这个分享',
        detail: _message(error),
        action: '重新输入链接',
        onAction: _loading ? null : _receivedShare,
      );
    return switch (code) {
      _ when authExpired => UiStatePanel(
        icon: Icons.lock_outline,
        title: '云盘登录已失效',
        detail: _message(error),
        action: '重新登录云盘',
        onAction: _loading ? null : () => _load(reconnect: true),
      ),
      UbaaErrorCode.authenticationRequired ||
      UbaaErrorCode.invalidCredentials => UiStatePanel(
        icon: Icons.lock_outline,
        title: '云盘登录已失效',
        detail: '重新登录后会回到个人文档库',
        action: '重新登录云盘',
        onAction: _loading ? null : () => _load(reconnect: true),
      ),
      UbaaErrorCode.permissionDenied => UiStatePanel(
        icon: Icons.block,
        title: '没有权限访问这里',
        detail: _message(error),
        action: '重试',
        onAction: _loading ? null : _load,
      ),
      UbaaErrorCode.networkError ||
      UbaaErrorCode.timeout ||
      UbaaErrorCode.upstreamUnavailable => UiStatePanel(
        icon: Icons.wifi_off,
        title: '暂时连不上北航云盘',
        detail: '请检查网络后重试',
        action: '重试',
        onAction: _loading ? null : _load,
      ),
      _ => UiStatePanel(
        icon: Icons.cloud_off_outlined,
        title: '没能读取这个文件夹',
        detail: _message(error),
        action: '重试',
        onAction: _loading ? null : _load,
      ),
    };
  }

  Widget _content(List<BhpanItem> items, bool selecting) {
    if (_error case final error?)
      return PullToRefresh(
        onRefresh: _refresh,
        child: RefreshViewport(child: _errorPanel(error)),
      );
    // 首次进入目录只留空白，进度显示在标题栏右上角。
    if (_page == null) return const LoadingPlaceholder();
    if (items.isEmpty)
      return PullToRefresh(
        onRefresh: _refresh,
        child: RefreshViewport(
          child: _filter.isNotEmpty
              ? UiStatePanel(
                  icon: Icons.search_off,
                  title: '没有找到「$_filter」',
                  detail: '只搜索当前文件夹里的名称',
                )
              : UiStatePanel(
                  icon: Icons.folder_open_outlined,
                  title: '这个文件夹是空的',
                  action: _canUpload ? '上传文件' : null,
                  onAction: _canUpload ? _upload : null,
                ),
        ),
      );
    return PullToRefresh(
      onRefresh: _refresh,
      child: ListView.builder(
        key: ValueKey(
          '${_base.view}/${_base.root}/${_base.link}/${_trail.map((f) => f.handle).join('/')}',
        ),
        padding: EdgeInsets.only(bottom: selecting ? 16 : 96),
        itemCount: items.length + 1,
        itemBuilder: (c, index) => index == items.length
            ? _footer(items.length)
            : _row(items[index], selecting),
      ),
    );
  }
}
