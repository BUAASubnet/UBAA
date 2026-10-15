import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../common/app_links.dart' show uiShowAppLinkFailure;

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
                  const Text('北航校园生活助手'),
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
