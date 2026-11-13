part of 'view.dart';

typedef _PreviewFrame = ({Uint8List bytes, bool openAsPdf});

class _DocumentPreview extends StatefulWidget {
  const _DocumentPreview({
    required this.entry,
    required this.title,
    required this.scans,
    required this.readSource,
    required this.isCurrent,
    this.download,
    this.previewPdf,
    this.renderPdf,
  });

  final _DocumentEntry entry;
  final String title;
  final bool scans;
  // For scans the index identifies an original file; for print jobs it is a page.
  final Future<Uint8List> Function(int index) readSource;
  final bool Function() isCurrent;
  final Future<void> Function()? download;
  final PrintPdfPreview? previewPdf;
  final PrintPdfRenderer? renderPdf;

  @override
  State<_DocumentPreview> createState() => _DocumentPreviewState();
}

class _DocumentPreviewState extends State<_DocumentPreview> {
  // The device usually writes one page per file. Refine counts as files open.
  late final _scanPageCounts = List.filled(widget.entry.files.length, 1);
  ({int file, Uint8List bytes})? _scanSource;
  int _page = 1;
  late Future<_PreviewFrame> _frame = _load(_page)..ignore();
  bool _loading = true;
  bool _busy = false;

  bool _current() => mounted && widget.isCurrent();
  int get _totalPages => widget.scans
      ? _scanPageCounts.fold(0, (sum, pages) => sum + pages)
      : widget.entry.first.pages ?? 1;

  ({int file, int inFile}) _scanLocation(int page) {
    for (final (index, count) in _scanPageCounts.indexed) {
      if (page <= count) return (file: index + 1, inFile: page);
      page -= count;
    }
    throw StateError('扫描预览页码超出范围');
  }

  Future<_PreviewFrame> _read(int page) async {
    if (!_current()) throw _previewClosed;
    if (!widget.scans) {
      final bytes = await widget.readSource(page);
      if (!_current()) throw _previewClosed;
      return (bytes: bytes, openAsPdf: false);
    }

    final (:file, :inFile) = _scanLocation(page);
    final cached = _scanSource;
    final bytes = cached != null && cached.file == file
        ? cached.bytes
        : await widget.readSource(file);
    if (!_current()) throw _previewClosed;
    _scanSource = (file: file, bytes: bytes);
    final pdf =
        bytes.length >= 5 && String.fromCharCodes(bytes.take(5)) == '%PDF-';
    final render = widget.renderPdf;
    if (!pdf || render == null) return (bytes: bytes, openAsPdf: pdf);

    final rendered = await render(bytes, inFile, _current);
    if (!_current()) throw _previewClosed;
    _scanPageCounts[file - 1] = rendered.totalPages;
    return (bytes: rendered.image, openAsPdf: false);
  }

  Future<_PreviewFrame> _load(int page) => _read(page).whenComplete(() {
    if (mounted) setState(() => _loading = false);
  });

  void _openPage(int page) {
    if (_loading || _busy) return;
    setState(() {
      _page = page;
      _loading = true;
      _frame = _load(page)..ignore();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || !_current()) return;
    setState(() => _busy = true);
    try {
      await action();
    } on Object catch (error) {
      if (_current()) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_error(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = _totalPages;
    final canTurn = !_busy && !_loading;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: '返回文档列表',
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (widget.download case final download?)
              IconButton(
                tooltip: '下载扫描文档',
                onPressed: _busy ? null : () => _run(download),
                icon: const Icon(Icons.download_outlined),
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (widget.scans || pages > 1)
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      tooltip: '上一页',
                      onPressed: canTurn && _page > 1
                          ? () => _openPage(_page - 1)
                          : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text('第 $_page / $pages 页'),
                    IconButton(
                      tooltip: '下一页',
                      onPressed: canTurn && _page < pages
                          ? () => _openPage(_page + 1)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              Expanded(
                child: _Load(
                  read: _frame,
                  retry: () => _openPage(_page),
                  body: (frame) {
                    if (frame.openAsPdf) {
                      return Center(
                        child: widget.previewPdf == null
                            ? const Padding(
                                padding: EdgeInsets.all(24),
                                child: Text('当前平台无法在应用内打开扫描 PDF，可以下载查看。'),
                              )
                            : FilledButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _run(
                                        () => widget.previewPdf!(
                                          frame.bytes,
                                          _current,
                                        ),
                                      ),
                                icon: const Icon(Icons.picture_as_pdf_outlined),
                                label: const Text('打开 PDF 预览'),
                              ),
                      );
                    }
                    return _PreviewImage(
                      key: ValueKey(_page),
                      bytes: frame.bytes,
                      label: '${widget.title} 第 $_page 页',
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _previewClosed = UiError(
  code: UbaaErrorCode.operationConflict,
  title: '预览已失效',
  message: '请返回文档列表后重试',
);
