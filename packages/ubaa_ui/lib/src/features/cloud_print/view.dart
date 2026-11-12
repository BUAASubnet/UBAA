import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import '../../shared/create_button.dart';
import '../../shared/file_list/file_action_sheet.dart';
import '../../shared/file_list/file_tile.dart';
import '../../shared/file_list/selection_bar.dart';
import '../../shared/when.dart' show uiCampusNow;
import '../../theme.dart';

part 'documents.dart';
part 'document_entries.dart';
part 'document_preview.dart';
part 'records.dart';
part 'upload.dart';

enum _Section {
  queue('待打印'),
  scans('扫描文档'),
  stations('打印点'),
  records('使用记录'),
  help('帮助');

  const _Section(this.label);
  final String label;
}

class CloudPrintView extends StatefulWidget {
  const CloudPrintView({
    super.key,
    required this.service,
    this.connecting = false,
    this.pickFiles,
    this.pickFolder,
    this.previewPdf,
    this.renderPdf,
  });

  final CloudPrintService? service;
  final bool connecting;
  final Future<List<PrintSource>> Function()? pickFiles;
  final Future<PrintDownloadFolder?> Function(bool Function())? pickFolder;
  final PrintPdfPreview? previewPdf;
  final PrintPdfRenderer? renderPdf;

  @override
  State<CloudPrintView> createState() => _CloudPrintViewState();
}

class _CloudPrintViewState extends State<CloudPrintView> {
  _Section _section = _Section.queue;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    if (service == null) {
      return widget.connecting
          ? const Center(child: CircularProgressIndicator())
          : const Center(child: Text('请登录学校账号后使用图书馆云打印'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: UbaaTheme.pageInsets(context, top: 8, bottom: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final section in _Section.values)
                ChoiceChip(
                  label: Text(section.label),
                  selected: _section == section,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _section = section),
                ),
            ],
          ),
        ),
        Expanded(
          child: switch (_section) {
            _Section.queue || _Section.scans => _Documents(
              key: ValueKey(_section),
              service: service,
              scans: _section == _Section.scans,
              pickFiles: widget.pickFiles,
              pickFolder: widget.pickFolder,
              previewPdf: widget.previewPdf,
              renderPdf: widget.renderPdf,
              onBusy: (value) => setState(() => _busy = value),
            ),
            _Section.stations => _Stations(service: service),
            _Section.records => _Records(service: service),
            _Section.help => const _Help(),
          },
        ),
      ],
    );
  }
}

class _Load<T> extends StatelessWidget {
  const _Load({required this.read, required this.retry, required this.body});
  final Future<T> read;
  final VoidCallback retry;
  final Widget Function(T) body;

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: read,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error(snapshot.error), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: retry, child: const Text('重试')),
              ],
            ),
          ),
        );
      }
      return body(snapshot.data as T);
    },
  );
}

String _error(Object? error) =>
    error is UiError ? error.message : '操作未完成，请稍后重试';

String _dateTime(String date, String time) {
  final d = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(date);
  final t = RegExp(r'^(\d{2})(\d{2})(\d{2})$').firstMatch(time.padLeft(6, '0'));
  final day = d == null ? date : '${d[1]}-${d[2]}-${d[3]}';
  return t == null ? '$day $time' : '$day ${t[1]}:${t[2]}';
}

String _bytes(int n) => n >= 1024 * 1024
    ? '${(n / (1024 * 1024)).toStringAsFixed(1)} MiB'
    : n >= 1024
    ? '${(n / 1024).toStringAsFixed(1)} KiB'
    : '$n B';

class _Help extends StatelessWidget {
  const _Help();

  @override
  Widget build(BuildContext context) => ListView(
    padding: UbaaTheme.pageInsets(context),
    children: const [
      ListTile(
        leading: Icon(Icons.upload_file_outlined),
        title: Text('上传与打印'),
        subtitle: Text('多选本机文件并设置打印选项。上传成功后，在待打印中核对文档和页数，再到图书馆自助设备登录取件。'),
      ),
      ListTile(
        leading: Icon(Icons.insert_drive_file_outlined),
        title: Text('文件格式'),
        subtitle: Text(
          'PDF、JPG、PNG、DOCX、XLSX、PPTX 已实测可提交。官网也列有其他格式，是否能转换以服务器结果为准；遇到排版问题时建议转为 PDF。',
        ),
      ),
      ListTile(
        leading: Icon(Icons.document_scanner_outlined),
        title: Text('扫描与下载'),
        subtitle: Text('先在图书馆设备完成扫描。回到扫描文档，选择要保存的原文件，再选一次保存文件夹。过期的扫描件不能下载。'),
      ),
      ListTile(
        leading: Icon(Icons.history),
        title: Text('查找打印点与使用记录'),
        subtitle: Text('可查看各打印点的设备状态，或按日期和类型查询打印、复印、扫描记录。'),
      ),
    ],
  );
}

/// Private previews live only as long as the displayed page.
class _PreviewImage extends StatefulWidget {
  const _PreviewImage({super.key, required this.bytes, required this.label});
  final Uint8List bytes;
  final String label;

  @override
  State<_PreviewImage> createState() => _PreviewImageState();
}

class _PreviewImageState extends State<_PreviewImage> {
  @override
  void dispose() {
    unawaited(MemoryImage(widget.bytes).evict());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: InteractiveViewer(
      maxScale: 6,
      child: SizedBox.expand(
        child: Image.memory(
          widget.bytes,
          fit: BoxFit.contain,
          semanticLabel: widget.label,
          errorBuilder: (_, _, _) =>
              const Center(child: Text('此文件无法预览，可以下载后查看。')),
        ),
      ),
    ),
  );
}
