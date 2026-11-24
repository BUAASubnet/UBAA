part of 'ubaa_app_host.dart';

/// 把 SPOC 文件下载到宿主选定的位置，并按平台习惯交付给系统。
///
/// 只包装交付流程：保存位置与移动端打包交给 [BhpanFileSaver]，
/// 下载本身仍由 Core 完成（含大小上限和路径校验）。
final class SpocFilesDelivery {
  const SpocFilesDelivery({required this.service, required this.saver});
  final SpocFilesService service;
  final BhpanFileSaver saver;

  /// 作业附件或本人已提交文件。
  Future<SpocDownloadReceipt?> downloadAssignment(SpocSubmittedFile file) =>
      _save(
        file.fileName ?? '作业文件',
        (path) => service.downloadAssignmentFile(file, path),
      );

  /// 课件（课程文件）。
  Future<SpocDownloadReceipt?> downloadCourse(SpocCourseFile file) =>
      _save(file.name, (path) => service.downloadCourseFile(file, path));

  Future<SpocDownloadReceipt?> _save(
    String name,
    Future<SpocRead<SpocDownloadReceipt>> Function(String path) run,
  ) async {
    // 上游文件名只用于建议名，去掉分隔符后再交给系统保存面板。
    final suggested = name.replaceAll(RegExp(r'[\\/\r\n]'), '_').trim();
    final destination = await saver.select(
      suggested.isEmpty ? '作业文件' : suggested,
      () => true,
    );
    if (destination == null) return null;
    try {
      final read = await run(destination.path);
      await destination.deliver(() => true);
      return read.data;
    } on Object {
      // 桌面目标的选择是空操作；移动端会清理本次下载的临时目录。
      await destination.discard();
      rethrow;
    }
  }
}

/// 选择要提交给 SPOC 的本机文件。
///
/// 与云盘共用系统文件选择器；选中后只交付路径和名称，大小与扩展名由
/// Core 在准备阶段复核。读取失败时释放原生句柄。
extension _SpocSubmitFilePicker on _UbaaAppHostState {
  Future<SpocSubmitFile?> _pickSpocSubmitFile() async {
    final selected = await widget.bhpanFilePicker.pick();
    if (selected == null) return null;
    return SpocSubmitFile(path: selected.path, name: selected.name);
  }
}
