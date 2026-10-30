import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'support/visual/tolerant_comparator.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Flutter 已按当前测试文件设置本地比较器，这里沿用同一目录并加入容差。
  final current = goldenFileComparator;
  if (current is LocalFileComparator) {
    goldenFileComparator = TolerantGoldenComparator(
      current.basedir.resolve('flutter_test_config.dart'),
    );
  }
  await testMain();
}
