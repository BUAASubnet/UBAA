import 'dart:collection';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'support.dart';
import 'view_test.dart' show mount;

void main() {
  testWidgets('目录与筛选未变化时，页面更新复用排序结果', (tester) async {
    final items = _CountedItems(
      List.generate(
        100,
        (i) => BhpanItem(
          handle: 'f$i',
          name: '文件 $i',
          kind: BhpanItemKind.file,
          scope: BhpanScope.personal,
        ),
      ),
    );
    final files = Files()..contents = items;
    await mount(tester, files);
    expect(items.reads, greaterThan(0));
    items.reads = 0;
    await mount(tester, files);
    expect(items.reads, 0, reason: '页面更新不能重新扫描同一份目录进行筛选排序');
  });
}

class _CountedItems extends ListBase<BhpanItem> {
  _CountedItems(this.source);
  final List<BhpanItem> source;
  int reads = 0;
  @override
  int get length => source.length;
  @override
  set length(int value) => throw UnsupportedError('只读');
  @override
  BhpanItem operator [](int index) {
    reads++;
    return source[index];
  }

  @override
  void operator []=(int index, BhpanItem value) => throw UnsupportedError('只读');
}
