import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/theme.dart';
import '../../common/state_panel.dart' show UiStatePanel;
import '../../shared/dialogs/sheet.dart' show showUiSheet, UiSheetBody;
import '../../shared/feedback.dart' show UbaaFeedback, UbaaFeedbackKind;
import '../../shared/text.dart' show uiNonBlank;
import 'spoc_files_access.dart';

/// 课程文件（课件）浏览：按课程列出文件，可进入文件夹并下载单个文件。
///
/// 只读页面：列表来自 [SpocFilesAccess.service]，下载交给宿主回调；
/// 打包下载整个文件夹和任何写入都不在这里发起。
class CourseFilesView extends StatefulWidget {
  const CourseFilesView({
    super.key,
    required this.access,
    this.courseId,
    this.courseName,
  });
  final SpocFilesAccess access;
  final String? courseId, courseName;

  @override
  State<CourseFilesView> createState() => _CourseFilesViewState();
}

class _CourseFilesViewState extends State<CourseFilesView> {
  List<SpocCourse> _courses = const [];
  String? _courseId, _courseName;
  var _path = <({String id, String name})>[];
  List<SpocCourseFile>? _items;
  Object? _error;
  var _loading = false;
  var _coursesLoading = false;
  String? _downloadingId;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _courseId = widget.courseId;
    _courseName = widget.courseName;
    if (_courseId == null) {
      _loadCourses();
    } else {
      _loadFiles();
    }
  }

  bool _current(int generation) => mounted && generation == _generation;

  Future<void> _loadCourses() async {
    final service = widget.access.service;
    if (service == null) return;
    final generation = ++_generation;
    setState(() {
      _coursesLoading = true;
      _error = null;
    });
    try {
      final read = await service.courses();
      if (!_current(generation)) return;
      setState(() {
        _courses = read.data;
        _coursesLoading = false;
      });
      if (_courses.length == 1) {
        _selectCourse(_courses.single.courseId, _courses.single.name);
      }
    } on Object catch (error) {
      if (!_current(generation)) return;
      setState(() {
        _coursesLoading = false;
        _error = error;
      });
    }
  }

  void _selectCourse(String courseId, String name) {
    if (_courseId == courseId && _path.isEmpty && _items != null) return;
    setState(() {
      _courseId = courseId;
      _courseName = name;
      _path = [];
      _items = null;
    });
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    final service = widget.access.service;
    final courseId = _courseId;
    if (service == null || courseId == null) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final read = await service.courseFiles(
        courseId,
        folderId: _path.isEmpty ? null : _path.last.id,
      );
      if (!_current(generation)) return;
      setState(() {
        _items = read.data;
        _loading = false;
      });
    } on Object catch (error) {
      if (!_current(generation)) return;
      setState(() {
        _loading = false;
        _items = null;
        _error = error;
      });
    }
  }

  void _enter(SpocCourseFile folder) {
    setState(() => _path = [..._path, (id: folder.id, name: folder.name)]);
    _loadFiles();
  }

  void _upTo(int depth) {
    setState(() => _path = _path.sublist(0, depth));
    _loadFiles();
  }

  Future<void> _download(SpocCourseFile file) async {
    final download = widget.access.downloadCourseFile;
    if (download == null || _downloadingId != null) return;
    setState(() => _downloadingId = file.id);
    try {
      final receipt = await download(file);
      if (!mounted) return;
      if (receipt != null) {
        UbaaFeedback.show(
          context,
          '已保存 ${receipt.fileName}（${uiFileSize(receipt.byteLen)}）',
          kind: UbaaFeedbackKind.success,
        );
      }
    } on Object catch (error) {
      if (!mounted) return;
      UbaaFeedback.show(
        context,
        error is UiError ? error.message : '下载失败，请稍后重试',
        error: error is UiError ? error : null,
        kind: UbaaFeedbackKind.error,
      );
    } finally {
      if (mounted) setState(() => _downloadingId = null);
    }
  }

  Future<void> _pickCourse() async {
    if (_courses.isEmpty) {
      if (!_coursesLoading) await _loadCourses();
      return;
    }
    final picked = await showUiSheet<_CourseChoice>(
      context,
      builder: (_) => UiSheetBody(
        title: '选择课程',
        children: [
          for (final course in _courses)
            _CourseRow(
              course: course,
              selected: course.courseId == _courseId,
              onTap: () => Navigator.of(
                context,
              ).pop(_CourseChoice(course.courseId, course.name)),
            ),
        ],
      ),
    );
    if (picked != null && mounted) _selectCourse(picked.id, picked.name);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        // 与应用内其它下钻页保持一致：同一枚返回箭头、同样的标题间距和字号。
        leading: IconButton(
          tooltip: '返回',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
        titleSpacing: 4,
        titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
          fontSize: 20,
        ),
        title: const Text('课程文件'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading || _coursesLoading
                ? null
                : () => _courseId == null ? _loadCourses() : _loadFiles(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        key: const ValueKey('spoc-course-files'),
        padding: UbaaTheme.pageInsets(context, top: 8, bottom: 24),
        children: [
          if (_courses.isNotEmpty || _courseId != null) _header(theme, colors),
          const SizedBox(height: 12),
          if (_coursesLoading || _loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            _errorPanel()
          else if (_courseId == null)
            UiStatePanel(
              icon: Icons.folder_open,
              title: '暂无课程',
              detail: '本学期还没有可浏览的课程文件',
              action: '重新加载',
              onAction: _loadCourses,
            )
          else if ((_items ?? const []).isEmpty)
            const UiStatePanel(
              icon: Icons.folder_open,
              title: '这里还没有文件',
              detail: '老师上传课件后会显示在这里',
            )
          else
            _fileCard(theme, colors),
        ],
      ),
    );
  }

  Widget _header(ThemeData theme, ColorScheme colors) {
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_courses.length > 1 || _courseName == null)
          InkWell(
            borderRadius: BorderRadius.circular(UbaaTheme.controlRadius),
            onTap: _coursesLoading ? null : _pickCourse,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      uiNonBlank(_courseName) ?? '选择课程',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(Icons.unfold_more, size: 20, color: colors.primary),
                ],
              ),
            ),
          )
        else
          Text(
            uiNonBlank(_courseName) ?? '课程',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _crumb('全部文件', 0, muted),
            for (var i = 0; i < _path.length; i++) ...[
              Text('›', style: muted),
              _crumb(
                _path[i].name,
                i + 1,
                muted,
                current: i == _path.length - 1,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _crumb(
    String label,
    int depth,
    TextStyle? style, {
    bool current = false,
  }) {
    final isCurrent = current || depth == _path.length;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: isCurrent
          ? null
          : () {
              if (depth == 0) {
                _upTo(0);
              } else {
                _upTo(depth);
              }
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Text(
          label,
          style: style?.copyWith(
            color: isCurrent ? null : Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _errorPanel() => UiStatePanel(
    icon: Icons.cloud_off,
    title: '课程文件读取失败',
    detail: _error is UiError ? (_error as UiError).message : '请稍后重试',
    error: _error is UiError ? _error as UiError : null,
    action: '重试',
    onAction: () => _courseId == null ? _loadCourses() : _loadFiles(),
  );

  Widget _fileCard(ThemeData theme, ColorScheme colors) {
    final items = _items ?? const <SpocCourseFile>[];
    return Card.outlined(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UbaaTheme.cardRadius),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 1, color: colors.outlineVariant),
            _fileRow(items[i], theme, colors),
          ],
        ],
      ),
    );
  }

  Widget _fileRow(SpocCourseFile file, ThemeData theme, ColorScheme colors) {
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final canDownload =
        !file.isFolder &&
        file.downloadAllowed &&
        widget.access.downloadCourseFile != null;
    final busy = _downloadingId == file.id;
    final size = uiNonBlank(file.sizeText),
        uploaded = uiNonBlank(file.uploadedAtText);
    final meta = [if (size != null) '约 $size', ?uploaded];
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Icon(
            file.isFolder
                ? Icons.folder_outlined
                : uiCourseFileIcon(file.extension),
            size: 22,
            color: file.isFolder ? colors.primary : colors.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
                if (meta.isNotEmpty) Text(meta.join(' · '), style: muted),
                if (!file.isFolder && !file.downloadAllowed)
                  Text('老师限制了下载', style: muted),
              ],
            ),
          ),
          if (file.isFolder)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                Icons.chevron_right,
                size: 20,
                color: colors.onSurfaceVariant,
              ),
            )
          else if (busy)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (canDownload)
            IconButton(
              tooltip: '下载',
              onPressed: _downloadingId == null ? () => _download(file) : null,
              icon: const Icon(Icons.download_outlined, size: 22),
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
    return InkWell(
      onTap: file.isFolder
          ? () => _enter(file)
          : canDownload && _downloadingId == null
          ? () => _download(file)
          : null,
      child: row,
    );
  }
}

final class _CourseChoice {
  const _CourseChoice(this.id, this.name);
  final String id, name;
}

class _CourseRow extends StatelessWidget {
  const _CourseRow({
    required this.course,
    required this.selected,
    required this.onTap,
  });
  final SpocCourse course;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(UbaaTheme.controlRadius),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(course.name, style: theme.textTheme.bodyMedium),
                  if (uiNonBlank(course.teacher) case final teacher?)
                    Text(
                      teacher,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (selected) Icon(Icons.check, size: 20, color: colors.primary),
          ],
        ),
      ),
    );
  }
}

/// 课件图标按扩展名区分，未知类型统一用文件图标。
IconData uiCourseFileIcon(String? extension) =>
    switch (extension?.toLowerCase().replaceFirst('.', '')) {
      'pdf' => Icons.picture_as_pdf_outlined,
      'zip' || 'rar' || '7z' => Icons.folder_zip_outlined,
      'ppt' || 'pptx' => Icons.slideshow_outlined,
      'doc' || 'docx' => Icons.description_outlined,
      'xls' || 'xlsx' => Icons.table_chart_outlined,
      'mp4' || 'mov' => Icons.movie_outlined,
      _ => Icons.insert_drive_file_outlined,
    };

/// 文件大小展示（下载回执用真实字节数，列表里的文本是学校给的取整值）。
String uiFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}
