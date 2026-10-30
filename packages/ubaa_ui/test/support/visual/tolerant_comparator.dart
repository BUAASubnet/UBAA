import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// CI 与本机的字体抗锯齿差异实测为 0.00%–0.05% 像素；容差留约 4 倍余量，
/// 颜色、间距、布局等可见回归仍会失败。
const goldenPixelTolerance = 0.002;

/// 在 [LocalFileComparator] 基础上允许极少量像素差异，失败时照常写出差异图。
class TolerantGoldenComparator extends LocalFileComparator {
  TolerantGoldenComparator(
    super.testFile, {
    this.tolerance = goldenPixelTolerance,
  });

  /// 允许不同的像素比例，0.002 即 0.2%。
  final double tolerance;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= tolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
