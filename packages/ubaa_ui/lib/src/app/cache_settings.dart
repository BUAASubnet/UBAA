import '../shared/loading.dart' show LoadingGlyph;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

class CacheSettings extends StatefulWidget {
  const CacheSettings({
    required this.accountId,
    required this.read,
    required this.clear,
    required this.enabled,
  });
  final String accountId;
  final Future<CacheUsageSummary> Function(String) read;
  final Future<CacheClearOutcome> Function(String) clear;
  final bool enabled;
  @override
  State<CacheSettings> createState() => _CacheSettingsState();
}

class _CacheSettingsState extends State<CacheSettings> {
  CacheUsageSummary? _usage;
  String? _notice;
  bool _busy = false, _failed = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  @override
  void didUpdateWidget(covariant CacheSettings old) {
    super.didUpdateWidget(old);
    if (old.accountId != widget.accountId) {
      _generation++;
      _usage = null;
      _notice = null;
      _busy = false;
      unawaited(_read());
    }
  }

  Future<void> _read() async {
    final generation = ++_generation, accountId = widget.accountId;
    try {
      final value = await widget.read(accountId);
      if (!mounted || generation != _generation) return;
      setState(() {
        _usage = value.accountId == accountId ? value : null;
        _failed = value.accountId != accountId;
      });
    } on Object {
      if (mounted && generation == _generation) setState(() => _failed = true);
    }
  }

  Future<void> _clear() async {
    if (_busy || !widget.enabled) return;
    final accountId = widget.accountId, generation = _generation;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理本机缓存？'),
        content: const Text(
          '将清除本机保存的课表、待办、查询内容和待核实提示，保留登录状态与账号。查询内容之后可重新获取，待核实提示无法恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认清理'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        _busy ||
        !widget.enabled ||
        accountId != widget.accountId ||
        generation != _generation)
      return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final result = await widget.clear(accountId);
      if (!mounted || generation != _generation) return;
      setState(() {
        _usage = result.usage;
        _failed = false;
        _notice = !result.cacheReady
            ? '内容已清除，本机保存暂不可用，请稍后重试。'
            : result.maintenanceError == null && result.compacted
            ? '缓存已清除。'
            : '内容已清除，空间回收暂未完成。';
      });
    } on Object {
      if (mounted && generation == _generation)
        setState(() => _notice = '缓存未能清除，请稍后重试。');
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  String _bytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('本机缓存', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_usage == null && !_failed && _notice == null)
            const LoadingGlyph()
          else
            Text(
              _usage != null
                  ? '${_usage!.entryCount} 条 · 内容 ${_bytes(_usage!.contentBytes)} · 文件 ${_bytes(_usage!.databaseBytes)}'
                  : (_failed ? '用量暂不可用' : '用量暂无统计'),
            ),
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_notice!),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy || !widget.enabled ? null : _clear,
            icon: const Icon(Icons.cleaning_services_outlined),
            label: Text(_busy ? '正在清理…' : '清理缓存'),
          ),
        ],
      ),
    ),
  );
}
