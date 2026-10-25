part of 'view.dart';

extension _IhomeFilters on _IhomeViewState {
  List<Widget> _filters() => [
    if (_scope == IhomeScope.public)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: TextField(
          controller: _search,
          maxLength: 200,
          decoration: InputDecoration(
            labelText: '搜索诉求或回复',
            counterText: '',
            suffixIcon: IconButton(
              tooltip: '搜索',
              onPressed: () {
                _keyword = _search.text.trim();
                unawaited(_load(reset: true));
              },
              icon: const Icon(Icons.search),
            ),
          ),
          onSubmitted: (v) {
            _keyword = v.trim();
            unawaited(_load(reset: true));
          },
        ),
      ),
    if (_scope == IhomeScope.public || _scope == IhomeScope.mine)
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          DropdownButton<IhomeFilter>(
            value: _filter,
            items: [
              const DropdownMenuItem(
                value: IhomeFilter.all,
                child: Text('默认排序'),
              ),
              const DropdownMenuItem(
                value: IhomeFilter.newest,
                child: Text('最新发布'),
              ),
              if (_scope == IhomeScope.public)
                const DropdownMenuItem(
                  value: IhomeFilter.oldest,
                  child: Text('最早发布'),
                ),
              if (_scope == IhomeScope.mine)
                const DropdownMenuItem(
                  value: IhomeFilter.replyTime,
                  child: Text('回复时间'),
                ),
              const DropdownMenuItem(
                value: IhomeFilter.replied,
                child: Text('已回复'),
              ),
              const DropdownMenuItem(
                value: IhomeFilter.unreplied,
                child: Text('未回复'),
              ),
            ],
            onChanged: (v) {
              if (v == null) return;
              _setFilter(v);
              unawaited(_load(reset: true));
            },
          ),
          if (_scope == IhomeScope.public && _config != null)
            DropdownButton<int>(
              value: _category ?? 0,
              items: [
                const DropdownMenuItem(value: 0, child: Text('全部分类')),
                for (final c in _config!.categories)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) {
                _setCategory(v);
                unawaited(_load(reset: true));
              },
            ),
        ],
      ),
  ];
}
