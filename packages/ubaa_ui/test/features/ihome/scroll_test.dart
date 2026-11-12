import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/ihome/view.dart';

import 'view_test.dart' show Service, appeal;

final _body = List.generate(8, (i) => '第$i段文字内容，支持滚动与选择复制。').join('\n');
final _tail = List.generate(40, (i) => '后续内容第$i段').join('\n');

class _ScrollService extends Service {
  @override
  Future<IhomeResult<IhomeNotice>> notice(int id) async => IhomeResult(
    IhomeNotice(id: id, title: '通知', content: '$_body\n$_tail', date: ''),
    ConnectionMode.direct,
  );
}

Future<void> _mount(
  WidgetTester tester,
  Service service,
  TargetPlatform platform,
) async {
  await tester.binding.setSurfaceSize(const Size(390, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      home: Scaffold(body: IhomeView(service: service)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final area in ['诉求正文', '部门回复', '处理进度', '公告正文']) {
      testWidgets('$platform 从$area开始触摸滑动能滚动页面', (tester) async {
        final service = _ScrollService()
          ..detailValue = appeal(
            42,
            history: [IhomeHistory(content: _body, createdAt: '')],
          )
          ..load = (_) async => IhomeResult(
            IhomePage(
              entries: [
                IhomeEntry(
                  appeal: appeal(
                    42,
                    content: area == '诉求正文' ? _body : '测试诉求',
                    replies: area == '部门回复'
                        ? [
                            IhomeReply(
                              content: _body,
                              department: '',
                              createdAt: '',
                            ),
                          ]
                        : const [],
                  ),
                  evaluation: null,
                ),
                IhomeEntry(
                  appeal: appeal(43, content: _tail, replies: const []),
                  evaluation: null,
                ),
              ],
              page: 1,
              lastPage: 1,
              total: 2,
            ),
            ConnectionMode.direct,
          );
        await _mount(tester, service, platform);
        if (area == '处理进度') {
          await tester.tap(find.text('查看详情').first);
          await tester.pumpAndSettle();
        }
        if (area == '公告正文') {
          await tester.ensureVisible(find.text('公告'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('公告'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('通知'));
          await tester.pumpAndSettle();
        }
        final text = find.text(area == '公告正文' ? '$_body\n$_tail' : _body);
        await Scrollable.ensureVisible(tester.element(text));
        await tester.pumpAndSettle();
        final list = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        final before = list.position.pixels;
        final start = tester.getTopLeft(text) + const Offset(60, 40);
        expect(tester.getRect(find.byType(ListView)).contains(start), isTrue);
        await tester.dragFrom(start, const Offset(0, -160));
        await tester.pumpAndSettle();
        expect(list.position.pixels, greaterThan(before + 60));
      });
    }

    testWidgets('$platform 诉求正文长按后仍能选择复制', (tester) async {
      final service = _ScrollService();
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await _mount(tester, service, platform);
      await tester.longPress(find.text('测试诉求'));
      await tester.pumpAndSettle();
      final editable = tester.state<EditableTextState>(
        find.byWidgetPredicate(
          (widget) =>
              widget is EditableText && widget.controller.text == '测试诉求',
        ),
      );
      final selection = editable.textEditingValue.selection;
      expect(selection.isCollapsed, isFalse);
      editable.copySelection(SelectionChangedCause.toolbar);
      await tester.pump();
      expect(copied, selection.textInside('测试诉求'));
      expect(service.detailCalls, 0);
      expect(service.writes, isEmpty);
    });
  }
}
