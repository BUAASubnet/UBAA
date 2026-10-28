import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/ihome/view.dart';

IhomeAppeal appeal(
  int id, {
  String content = '测试诉求',
  bool followed = false,
  bool supported = false,
  List<IhomeReply> replies = const [
    IhomeReply(content: '官方回复内容', department: '服务中心', createdAt: '2026-10-25'),
  ],
  List<IhomeHistory> history = const [],
}) => IhomeAppeal(
  id: id,
  content: content,
  status: '已回复',
  category: '校园服务',
  publishedAt: '2026-10-25',
  departments: const ['服务中心'],
  isMine: false,
  isFollowed: followed,
  isSupported: supported,
  followCount: 1,
  supportCount: 2,
  replies: replies,
  evaluations: const [],
  history: history,
);
IhomeResult<IhomePage> page(
  int id, {
  int current = 1,
  String content = '测试诉求',
}) => IhomeResult(
  IhomePage(
    entries: [
      IhomeEntry(appeal: appeal(id, content: content), evaluation: null),
    ],
    page: current,
    lastPage: 3,
    total: 3,
  ),
  ConnectionMode.webvpn,
);

class Service implements IhomeService {
  final queries = <IhomeQuery>[];
  Future<IhomeResult<IhomePage>> Function(IhomeQuery)? load;
  int detailCalls = 0;
  IhomeAppeal? detailValue;
  final writes = <(int, IhomeReaction, bool, ConnectionMode)>[];
  bool failWrite = false;
  @override
  Future<IhomeResult<IhomePage>> page(IhomeQuery q) async {
    queries.add(q);
    return load?.call(q) ??
        Future.value(
          IhomeResult(
            IhomePage(
              entries: [IhomeEntry(appeal: appeal(42), evaluation: null)],
              page: 1,
              lastPage: 3,
              total: 3,
            ),
            ConnectionMode.webvpn,
          ),
        );
  }

  @override
  Future<IhomeResult<IhomeConfig>> config() async => const IhomeResult(
    IhomeConfig(
      supportEnabled: true,
      supportLabel: '支持',
      categories: [IhomeCategory(id: 7, name: '生活服务')],
    ),
    ConnectionMode.webvpn,
  );
  @override
  Future<IhomeResult<IhomeAppeal>> detail(int id, {bool mine = false}) async {
    detailCalls++;
    return IhomeResult(
      detailValue ??
          appeal(
            id,
            history: const [
              IhomeHistory(content: '已分办', createdAt: '2026-10-25'),
            ],
          ),
      ConnectionMode.webvpn,
    );
  }

  @override
  Future<IhomeResult<List<IhomeNotice>>> notices() async => const IhomeResult([
    IhomeNotice(id: 8, title: '通知', content: '', date: '2026-10-25'),
  ], ConnectionMode.webvpn);
  @override
  Future<IhomeResult<IhomeNotice>> notice(int id) async => IhomeResult(
    IhomeNotice(id: id, title: '通知', content: '公告正文', date: '2026-10-25'),
    ConnectionMode.webvpn,
  );
  @override
  Future<IhomeResult<IhomeAppeal>> setReaction(
    int id,
    IhomeReaction reaction,
    bool enabled,
    ConnectionMode route,
  ) async {
    writes.add((id, reaction, enabled, route));
    if (failWrite)
      throw const UiError(
        code: UbaaErrorCode.outcomeUnknown,
        title: '结果未知',
        message: '操作结果未确认，请刷新详情后核对',
      );
    return IhomeResult(
      appeal(
        id,
        followed: reaction == IhomeReaction.follow && enabled,
        supported: reaction == IhomeReaction.support && enabled,
      ),
      route,
    );
  }
}

Future<void> mount(WidgetTester tester, Service service) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.macOS),
      home: Scaffold(body: IhomeView(service: service)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('iHome 空列表下拉刷新且按钮加入同一进行中读取', (tester) async {
    final service = Service()
      ..load = (_) async => const IhomeResult(
        IhomePage(entries: [], page: 1, lastPage: 1, total: 0),
        ConnectionMode.direct,
      );
    await mount(tester, service);
    final before = service.queries.length;
    final gate = Completer<IhomeResult<IhomePage>>();
    service.load = (_) => gate.future;
    await tester.drag(find.byType(ListView), const Offset(0, 350));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byTooltip('刷新'));
    await tester.pump();
    expect(service.queries, hasLength(before + 1));
    gate.complete(page(10));
    await tester.pumpAndSettle();
    expect(find.text('测试诉求'), findsOneWidget);
  });

  testWidgets('长诉求和多条回复完整展示且点击复制不触发详情', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final content = List.generate(8, (i) => '诉求第$i段：完整展示并支持选择复制。').join('\n');
    final reply = List.generate(6, (i) => '回复第$i段：说明处理结果和后续安排。').join('\n');
    final service = Service()
      ..load = (q) async => IhomeResult(
        IhomePage(
          entries: [
            IhomeEntry(
              appeal: appeal(
                42,
                content: content,
                replies: [
                  IhomeReply(content: reply, department: '服务中心', createdAt: ''),
                  const IhomeReply(
                    content: '第二条完整回复',
                    department: '另一部门',
                    createdAt: '',
                  ),
                ],
              ),
              evaluation: null,
            ),
          ],
          page: 1,
          lastPage: 1,
          total: 1,
        ),
        ConnectionMode.direct,
      );
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData')
            copied = (call.arguments as Map)['text'] as String;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await mount(tester, service);
    for (final value in [content, '服务中心：$reply', '另一部门：第二条完整回复']) {
      final text = find.text(value);
      await tester.ensureVisible(text);
      await tester.tap(text);
      await tester.pumpAndSettle();
      expect(service.detailCalls, 0);
      final editable = find.byWidgetPredicate(
        (widget) => widget is EditableText && widget.controller.text == value,
      );
      final state = tester.state<EditableTextState>(editable);
      final render = state.renderEditable;
      expect(
        render.getLocalRectForCaret(TextPosition(offset: value.length)).bottom,
        lessThanOrEqualTo(render.size.height + 1),
      );
      state.selectAll(SelectionChangedCause.keyboard);
      state.copySelection(SelectionChangedCause.keyboard);
      await tester.pump();
      expect(copied, value);
      expect(service.detailCalls, 0);
    }
  });
  testWidgets('查看详情只追加进度且保持原回复的布局和内容', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = Service()
      ..detailValue = appeal(
        42,
        content: '详情响应中的其他正文',
        replies: const [
          IhomeReply(content: '详情中的不同回复', department: '其他部门', createdAt: ''),
        ],
        history: const [IhomeHistory(content: '已分办', createdAt: '2026-10-25')],
      );
    await mount(tester, service);
    final reply = find.text('服务中心：官方回复内容');
    final position = tester.getTopLeft(reply);
    final size = tester.getSize(reply);
    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();
    expect(service.detailCalls, 1);
    expect(find.text('已分办'), findsOneWidget);
    expect(tester.getTopLeft(reply), position);
    expect(tester.getSize(reply), size);
    await tester.tap(find.text('收起详情'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(reply), position);
    expect(service.detailCalls, 1);
  });
  testWidgets('展开详情保留搜索与列表位置并可原位收起', (tester) async {
    final service = Service();
    await mount(tester, service);
    await tester.enterText(find.byType(TextField), '校园');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final reads = service.queries.length;
    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();
    expect(find.text('校园'), findsOneWidget);
    expect(find.text('服务中心：官方回复内容'), findsOneWidget);
    expect(service.detailCalls, 1);
    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();
    expect(service.detailCalls, 2);
    expect(find.text('服务中心：官方回复内容'), findsOneWidget);
    await tester.ensureVisible(find.text('收起详情'));
    await tester.tap(find.text('收起详情'));
    await tester.pumpAndSettle();
    expect(find.text('测试诉求'), findsOneWidget);
    expect(service.queries.length, reads + 1);
    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();
    expect(service.detailCalls, 2);
  });
  testWidgets('列表支持无需打开详情并更新按钮状态', (tester) async {
    final service = Service();
    await mount(tester, service);
    await tester.tap(find.byTooltip('支持'));
    await tester.pumpAndSettle();
    expect(service.detailCalls, 0);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(service.writes, [
      (42, IhomeReaction.support, true, ConnectionMode.webvpn),
    ]);
    expect(find.byTooltip('取消支持'), findsOneWidget);
  });
  testWidgets('同一诉求的不同评价均保留且刷新失败保留内容', (tester) async {
    final service = Service();
    service.load = (q) async => IhomeResult(
      IhomePage(
        entries: [
          for (final id in [1, 2])
            IhomeEntry(
              appeal: appeal(42),
              evaluation: IhomeEvaluation(
                id: id,
                department: '服务中心',
                speed: 5,
                satisfaction: 5,
                degree: 5,
                content: '评价$id',
                createdAt: '',
              ),
            ),
        ],
        page: 1,
        lastPage: 1,
        total: 2,
      ),
      ConnectionMode.direct,
    );
    await mount(tester, service);
    await tester.tap(find.text('我的评价'));
    await tester.pumpAndSettle();
    expect(find.text('我的评价：评价1'), findsOneWidget);
    expect(find.text('我的评价：评价2'), findsOneWidget);
    service.load = (q) async => throw StateError('模拟断网');
    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();
    expect(find.text('我的评价：评价1'), findsOneWidget);
  });
  testWidgets('搜索提交到服务且切换个人列表清除公共筛选', (tester) async {
    final service = Service();
    await mount(tester, service);
    await tester.enterText(find.byType(TextField), '校园 回复');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(service.queries.last.keyword, '校园 回复');
    await tester.tap(find.text('我的诉求'));
    await tester.pumpAndSettle();
    expect(service.queries.last.scope, IhomeScope.mine);
    expect(service.queries.last.keyword, '');
    expect(service.queries.last.page, 1);
  });
  testWidgets('迟到的公共搜索不会覆盖已切换的个人列表', (tester) async {
    final service = Service();
    await mount(tester, service);
    final delayed = Completer<IhomeResult<IhomePage>>();
    service.load = (q) => q.scope == IhomeScope.public
        ? delayed.future
        : Future.value(page(9, content: '我的诉求内容'));
    await tester.enterText(find.byType(TextField), '延迟');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.tap(find.text('我的诉求'));
    await tester.pumpAndSettle();
    delayed.complete(page(8, content: '迟到的公共内容'));
    await tester.pumpAndSettle();
    expect(find.text('我的诉求内容'), findsOneWidget);
    expect(find.text('迟到的公共内容'), findsNothing);
  });
  testWidgets('上游重复首屏时终止分页并保留已显示诉求', (tester) async {
    final service = Service();
    await mount(tester, service);
    await tester.ensureVisible(find.text('加载更多'));
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();
    expect(service.queries.last.page, 2);
    expect(find.text('测试诉求'), findsOneWidget);
    expect(find.text('加载更多'), findsNothing);
  });
  testWidgets('列表关注确认固定读取路线且未知结果禁止重复提交', (tester) async {
    final service = Service()..failWrite = true;
    await mount(tester, service);
    expect(service.detailCalls, 0);
    await tester.tap(find.byTooltip('关注'));
    await tester.pumpAndSettle();
    expect(service.writes, isEmpty);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(service.writes, [
      (42, IhomeReaction.follow, true, ConnectionMode.webvpn),
    ]);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == '关注',
            ),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('刷新核对'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == '关注',
            ),
          )
          .onPressed,
      isNotNull,
    );
  });
  testWidgets('公告在窄屏列表内展开收起并保留页签', (tester) async {
    final service = Service();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, service);
    await tester.tap(find.text('公告'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('通知'));
    await tester.pumpAndSettle();
    expect(find.text('公告正文'), findsOneWidget);
    await tester.tap(find.text('通知'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('诉求广场'));
    await tester.pumpAndSettle();
    expect(find.text('测试诉求'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
