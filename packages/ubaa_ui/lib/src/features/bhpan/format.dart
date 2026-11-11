import 'package:ubaa_domain/ubaa_domain.dart';

String bhpanBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024)
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

String bhpanDate(DateTime time) {
  final d = time.toUtc().add(const Duration(hours: 8));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// 点文件时直接预览的大小上限。
const bhpanPreviewLimit = 20 * 1024 * 1024;

const _previewable = {
  'pdf',
  'doc',
  'docx',
  'ppt',
  'pptx',
  'xls',
  'xlsx',
  'csv',
  'rtf',
  'key',
  'numbers',
  'pages',
  'txt',
  'md',
  'html',
  'png',
  'jpg',
  'jpeg',
  'gif',
  'heic',
  'webp',
  'bmp',
  'tiff',
  'mp4',
  'mov',
  'm4v',
  'mp3',
  'm4a',
  'wav',
  'aac',
};

/// 系统预览能打开的常见类型，仅按扩展名判断展示行为。
bool bhpanPreviewable(BhpanItem item) {
  if (item.isFolder) return false;
  final name = item.name.toLowerCase();
  final dot = name.lastIndexOf('.');
  return dot >= 0 && _previewable.contains(name.substring(dot + 1));
}
