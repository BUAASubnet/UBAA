import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_ui/src/common/search_field.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'support.dart';
import 'view_test.dart' show mount;

class _ErrorFiles extends Files {
  _ErrorFiles(this.kind);
  final UbaaErrorKind kind;
  bool fail = true;
  int logins = 0;

  @override
  Future<BhpanPage> read(BhpanRead query) async {
    if (fail && query.view == BhpanReadView.directory) {
      reads.add(query);
      throw UiError(
        code: UbaaErrorCode.permissionDenied,
        kind: kind,
        title: '暂时无法读取',
        message: '合成读取失败',
      );
    }
    return super.read(query);
  }

  @override
  Future<void> login() async {
    logins++;
  }
}

void main() {
  for (final modifier in [
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.controlLeft,
  ]) {
    testWidgets('云盘快捷键聚焦搜索，Esc 依次清除多选和搜索 $modifier', (tester) async {
      final files = Files();
      await mount(tester, files);
      final reads = files.reads.length;
      Future<void> search() async {
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(modifier);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<UiSearchField>(find.byType(UiSearchField))
              .focusNode!
              .hasFocus,
          isTrue,
        );
      }

      await search();
      await tester.enterText(find.byType(TextField), '课程');
      await tester.pumpAndSettle();
      expect(find.text('报告.txt'), findsNothing);
      await tester.longPress(find.text('课程资料'));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 项'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('已选 1 项'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '课程',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('报告.txt'), findsOneWidget);
      await search();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(files.reads.length, reads);
    });
  }

  for (final kind in [UbaaErrorKind.authentication, UbaaErrorKind.upstream]) {
    testWidgets('云盘根据错误类别选择重新登录或重读目录 $kind', (tester) async {
      final files = _ErrorFiles(kind);
      await mount(tester, files);
      final authentication = kind == UbaaErrorKind.authentication;
      final action = find.widgetWithText(
        FilledButton,
        authentication ? '重新登录云盘' : '重试',
      );
      files.fail = false;
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(files.logins, authentication ? 1 : 0);
      expect(files.reads.last.target, 'root');
      expect(find.text('报告.txt'), findsOneWidget);
    });
  }
}
