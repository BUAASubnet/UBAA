part of '../widgets.dart';

class _AboutView extends StatefulWidget {
  const _AboutView({this.loadVersion, this.openLink});
  final Future<String?> Function()? loadVersion;
  final Future<bool> Function(AppLink)? openLink;
  @override
  State<_AboutView> createState() => _AboutViewState();
}

class _AboutViewState extends State<_AboutView> {
  String? version;
  bool loading = true, opening = false;
  @override
  void initState() {
    super.initState();
    unawaited(_loadVersion());
  }

  Future<void> _loadVersion() async {
    setState(() => loading = true);
    String? value;
    try {
      value = await widget.loadVersion?.call();
    } on Object {
      value = null;
    }
    if (!mounted) return;
    setState(() {
      loading = false;
      version = value;
    });
  }

  Future<void> _open(AppLink link) async {
    if (opening) return;
    setState(() => opening = true);
    var opened = false;
    try {
      opened = await widget.openLink?.call(link) ?? false;
    } on Object {
      opened = false;
    }
    if (!mounted) return;
    setState(() => opening = false);
    if (opened) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('链接未能打开'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('可以复制地址后在浏览器中打开。'),
            const SizedBox(height: 12),
            SelectableText(link.url),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await Clipboard.setData(ClipboardData(text: link.url));
                if (context.mounted) Navigator.pop(context);
              } on Object {
                if (context.mounted)
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('复制失败，请重试。')));
              }
            },
            child: const Text('复制地址'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'UBAA 应用',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    loading
                        ? '正在读取版本…'
                        : version == null
                        ? '版本信息暂不可用'
                        : '版本：$version',
                  ),
                  if (!loading && version == null && widget.loadVersion != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _loadVersion,
                        child: const Text('重新读取版本'),
                      ),
                    ),
                  const SizedBox(height: 16),
                  const Text('UBAA 是一个用于（部分）代替i北航功能的程序。'),
                  const SizedBox(height: 8),
                  Text('主要功能：', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  const Text(
                    '• 课程表查询\n• 今日课程提醒\n• 个人信息管理\n• 博雅课程\n• 考试查询\n• 更多校园功能',
                  ),
                  const SizedBox(height: 24),
                  for (final link in AppLink.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: opening ? null : () => _open(link),
                          icon: Icon(
                            link == AppLink.project
                                ? Icons.code
                                : Icons.feedback_outlined,
                          ),
                          label: Text(link.label),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
