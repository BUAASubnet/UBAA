part of 'shell.dart';

/// 当前页面路线说明与默认策略选择；读取结果的来源不随选择改写。
extension UbaaShellRoute on _UbaaMainShellState {
  Future<void> _showRouteOptions(
    BuildContext context,
    ConnectionMode? route, {
    Map<String, ConnectionMode>? homeRoutes,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('连接路线'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '当前页面：${homeRoutes != null && homeRoutes.values.toSet().length > 1 ? '直连与WebVPN' : route?.label ?? '未确定'}',
              ),
              if (homeRoutes != null) ...[
                const SizedBox(height: 8),
                for (final entry in homeRoutes.entries)
                  Text('${entry.key}：${entry.value.label}'),
              ],
              const SizedBox(height: 8),
              const Text('下次查询使用'),
              const SizedBox(height: 16),
              DropdownButton<RoutePolicy>(
                value: widget.routePolicy,
                isExpanded: true,
                items: RoutePolicy.values
                    .map(
                      (item) => DropdownMenuItem(
                        value: item,
                        child: Text(item.label),
                      ),
                    )
                    .toList(),
                onChanged: widget.writeState.intent != null
                    ? null
                    : (value) {
                        if (value == null) return;
                        Navigator.of(context).pop();
                        widget.onRoutePolicyChanged(value);
                      },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
