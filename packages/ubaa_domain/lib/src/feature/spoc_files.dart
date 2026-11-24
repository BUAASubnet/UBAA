import '../common/route.dart';
import '../bhpan/models.dart';

extension SpocUploadProgress on BhpanTransferProgress {
  ({int number, int totalChunks})? get spocChunk {
    if (phase != BhpanTransferPhase.uploading || total <= 0) return null;
    const size = 2048000;
    final count = (total ~/ size).clamp(1, total);
    return (number: (bytes ~/ size + 1).clamp(1, count), totalChunks: count);
  }
}

final class SpocSubmittedFile {
  const SpocSubmittedFile({required this.fileId, this.fileName});
  final String fileId;
  final String? fileName;
}

final class SpocAttachment extends SpocSubmittedFile {
  const SpocAttachment({
    required super.fileId,
    super.fileName,
    this.sizeText,
    this.extension,
  });
  final String? sizeText, extension;
}

final class SpocCourse {
  const SpocCourse({required this.courseId, required this.name, this.teacher});
  final String courseId, name;
  final String? teacher;
}

final class SpocCourseFile {
  const SpocCourseFile({
    required this.id,
    required this.name,
    required this.isFolder,
    required this.downloadAllowed,
    this.sizeText,
    this.extension,
    this.uploadedAtText,
  });
  final String id, name;
  final bool isFolder, downloadAllowed;
  final String? sizeText, extension, uploadedAtText;
}

final class SpocDownloadReceipt {
  const SpocDownloadReceipt(this.fileName, this.byteLen);
  final String fileName;
  final int byteLen;
}

typedef SpocRead<T> = ({T data, ConnectionMode route});

abstract interface class SpocFilesService {
  Future<SpocRead<List<SpocCourse>>> courses();
  Future<SpocRead<List<SpocCourseFile>>> courseFiles(
    String courseId, {
    String? folderId,
  });
  Future<SpocRead<SpocDownloadReceipt>> downloadAssignmentFile(
    SpocSubmittedFile file,
    String destPath,
  );
  Future<SpocRead<SpocDownloadReceipt>> downloadCourseFile(
    SpocCourseFile file,
    String destPath,
  );
}
