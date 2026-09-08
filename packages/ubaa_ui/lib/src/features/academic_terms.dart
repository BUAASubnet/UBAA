part of '../widgets.dart';

class _AcademicTermDialog extends StatefulWidget {
  const _AcademicTermDialog({required this.loader, required this.selected});
  final Future<FeatureResult> Function(bool forceRefresh) loader;
  final String selected;
  @override
  State<_AcademicTermDialog> createState() => _AcademicTermDialogState();
}

class _AcademicTermDialogState extends State<_AcademicTermDialog> {
  late Future<FeatureResult> _result;
  @override
  void initState() {
    super.initState();
    _result = widget.loader(false);
  }

  void _reload() {
    final next = widget.loader(true);
    setState(() {
      _result = next;
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('选择学期'),
    content: SizedBox(
      width: 480,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .65,
        ),
        child: SingleChildScrollView(
          child: FutureBuilder<FeatureResult>(
            future: _result,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox(
                  height: 64,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final result = snapshot.data;
              if (result?.error case final error?) {
                return FriendlyErrorCard(error: error, onRetry: _reload);
              }
              if (snapshot.hasError || result == null) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('暂时无法获取学期，可以重试或手动填写编码。'),
                    TextButton(onPressed: _reload, child: const Text('重试')),
                  ],
                );
              }
              final terms = <String, FeatureDetail>{};
              for (final detail in result.details) {
                if (detail.presentation case final TermPresentation term
                    when term.code.trim().isNotEmpty) {
                  terms.putIfAbsent(term.code, () => detail);
                }
              }
              if (terms.isEmpty)
                return const Center(child: Text('暂无可选学期，可取消后手动填写编码。'));
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final entry in terms.entries)
                    ListTile(
                      title: Text(entry.value.title),
                      subtitle: Text(entry.key),
                      selected: entry.key == widget.selected,
                      trailing:
                          (entry.value.presentation! as TermPresentation)
                              .selected
                          ? const Chip(label: Text('当前'))
                          : null,
                      onTap: () => Navigator.of(context).pop(entry.key),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: _reload, child: const Text('重新获取')),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
    ],
  );
}
