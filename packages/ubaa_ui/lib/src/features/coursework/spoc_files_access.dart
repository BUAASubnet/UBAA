import 'package:ubaa_domain/ubaa_domain.dart';

/// 下载一份 SPOC 文件并交付给系统（保存或打开）。
///
/// 返回 null 表示用户取消；失败时抛 [UiError]。宿主负责选择保存位置、
/// 写入本地文件并调起系统交付，界面只显示进行中与结果。
typedef SpocFileDownload =
    Future<SpocDownloadReceipt?> Function(SpocSubmittedFile file);

/// 下载一份课程文件（课件）并交付给系统。
typedef SpocCourseFileDownload =
    Future<SpocDownloadReceipt?> Function(SpocCourseFile file);

/// SPOC 文件能力：作业附件、我的提交与课程文件的读取和下载。
///
/// 读取交给 [service]；下载必须经宿主回调，界面不直接决定保存路径。
class SpocFilesAccess {
  const SpocFilesAccess({
    this.service,
    this.downloadFile,
    this.downloadCourseFile,
  });
  final SpocFilesService? service;
  final SpocFileDownload? downloadFile;
  final SpocCourseFileDownload? downloadCourseFile;

  bool get canDownload => downloadFile != null;
  bool get canBrowseCourses => service != null;
}
