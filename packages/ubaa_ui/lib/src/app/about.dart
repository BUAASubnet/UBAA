import 'package:ubaa_ui/src/theme.dart';
import '../shared/loading.dart' show LoadingGlyph;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../common/app_links.dart' show uiShowAppLinkFailure;
import '../shared/layout/rail_identity.dart' show UiAppIcon;

class AboutView extends StatefulWidget {
  const AboutView({this.loadVersion, this.openLink});
  final Future<String?> Function()? loadVersion;
  final Future<bool> Function(AppLink)? openLink;
  @override
  State<AboutView> createState() => _AboutViewState();
}

class _AboutViewState extends State<AboutView> {
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
    await uiShowAppLinkFailure(context, link);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: UbaaTheme.pageInsets(context, top: 8),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                const UiAppIcon(size: 64),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'UBAA',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '北航校园生活助手',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (loading && version == null)
                        const LoadingGlyph()
                      else
                        Text(
                          version == null ? '版本信息暂不可用' : '版本 $version',
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                if (!loading && version == null && widget.loadVersion != null)
                  TextButton(
                    onPressed: _loadVersion,
                    child: const Text('重新读取版本'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              for (final (i, link) in AppLink.values.indexed) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  enabled: !opening,
                  leading: Icon(
                    link == AppLink.project
                        ? Icons.code
                        : Icons.feedback_outlined,
                  ),
                  title: Text(link.label),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _open(link),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
