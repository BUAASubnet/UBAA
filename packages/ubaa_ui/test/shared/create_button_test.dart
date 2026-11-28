import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerPhase;
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_ui/src/shared/create_button.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

const _phoneSize = Size(390, 844);
const _wideSize = Size(1400, 800);
const _successMessage = '创建成功';
const _warningMessage =
    '操作结果尚未核实，请刷新页面并检查列表中是否已经出现新项目。'
    '如果暂时没有看到新项目，请稍后重新检查。在确认结果之前，请不要重复提交。';

void main() {
  for (final (description, message, kind) in [
    ('成功短提示', _successMessage, UbaaFeedbackKind.success),
    ('换行警告', _warningMessage, UbaaFeedbackKind.warning),
  ]) {
    testWidgets('$description避开手机创建按钮，按钮仍可点击', (tester) async {
      var presses = 0;
      await _showFeedback(
        tester,
        size: _phoneSize,
        body: _pageWithButton(
          ubaaPositionedCreateButton(tooltip: '新增', onPressed: () => presses++),
        ),
        message: message,
        kind: kind,
      );

      _expectCardAbovePhoneButton(tester);
      await tester.tap(find.byType(FloatingActionButton));
      expect(presses, 1);
    });
  }

  testWidgets('成功提示避开手动定位的云盘创建按钮，按钮仍可点击', (tester) async {
    var presses = 0;
    await _showFeedback(
      tester,
      size: _phoneSize,
      body: _pageWithButton(
        Positioned(
          right: ubaaCreateButtonMargin,
          bottom: ubaaCreateButtonMargin,
          child: ubaaCreateButton(tooltip: '上传或新建', onPressed: () => presses++),
        ),
      ),
    );

    _expectCardAbovePhoneButton(tester);
    await tester.tap(find.byType(FloatingActionButton));
    expect(presses, 1);
  });

  testWidgets('页面没有创建按钮时保留提示与底栏的默认间距', (tester) async {
    await _showFeedback(tester, size: _phoneSize, body: _pageWithButton());

    _expectDefaultNavigationGap(tester);
  });

  testWidgets('不可见页面中的创建按钮不改变提示位置', (tester) async {
    await _showFeedback(
      tester,
      size: _phoneSize,
      body: IndexedStack(
        index: 0,
        children: [
          const SizedBox.expand(),
          TickerMode(
            enabled: false,
            child: Stack(
              children: [
                ubaaPositionedCreateButton(tooltip: '新增', onPressed: () {}),
              ],
            ),
          ),
        ],
      ),
    );

    _expectDefaultNavigationGap(tester);
  });

  testWidgets('提示显示期间切到有创建按钮的页面时实时避让，按钮仍可点击', (tester) async {
    var selectedIndex = 0;
    var presses = 0;
    late StateSetter updatePage;
    await _showFeedback(
      tester,
      size: _phoneSize,
      body: StatefulBuilder(
        builder: (context, setState) {
          updatePage = setState;
          return IndexedStack(
            index: selectedIndex,
            children: [
              _pageWithButton(),
              TickerMode(
                enabled: selectedIndex == 1,
                child: _pageWithButton(
                  ubaaPositionedCreateButton(
                    tooltip: '新增',
                    onPressed: () => presses++,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    _expectDefaultNavigationGap(tester);
    updatePage(() => selectedIndex = 1);
    await tester.pumpAndSettle();

    expect(find.text(_successMessage), findsOneWidget);
    _expectCardAbovePhoneButton(tester);
    await tester.tap(find.byType(FloatingActionButton));
    expect(presses, 1);
  });

  testWidgets('提示显示期间卸载创建按钮后恢复与底栏的默认间距', (tester) async {
    var showButton = true;
    late StateSetter updatePage;
    await _showFeedback(
      tester,
      size: _phoneSize,
      body: StatefulBuilder(
        builder: (context, setState) {
          updatePage = setState;
          return _pageWithButton(
            showButton
                ? ubaaPositionedCreateButton(tooltip: '新增', onPressed: () {})
                : null,
          );
        },
      ),
    );

    _expectCardAbovePhoneButton(tester);
    updatePage(() => showButton = false);
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text(_successMessage), findsOneWidget);
    _expectDefaultNavigationGap(tester);
  });

  testWidgets('占位不新增浮动操作按钮，也不进入语义树', (tester) async {
    const tooltip = '新增';
    await _showFeedback(
      tester,
      size: _phoneSize,
      body: _pageWithButton(
        ubaaPositionedCreateButton(tooltip: tooltip, onPressed: () {}),
      ),
    );

    expect(find.byType(FloatingActionButton), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.floatingActionButton, isNotNull);
    final footprint = find.byWidget(scaffold.floatingActionButton!);
    expect(tester.getSize(footprint), const Size.square(56));
    expect(footprint.hitTestable(), findsNothing);
    final excluded = find.descendant(
      of: footprint,
      matching: find.byWidgetPredicate(
        (widget) => widget is ExcludeSemantics && widget.excluding,
      ),
    );
    expect(excluded, findsOneWidget);
    expect(
      find.semantics.byPredicate(
        (node) => node.getSemanticsData().tooltip == tooltip,
      ),
      findsOne,
    );
  });

  testWidgets('宽屏提示与创建按钮不重叠，卡片限宽且按钮仍可点击', (tester) async {
    var presses = 0;
    await _showFeedback(
      tester,
      size: _wideSize,
      withNavigationBar: false,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: UbaaTheme.pageMaxWidth),
          child: _pageWithButton(
            ubaaPositionedCreateButton(
              tooltip: '新增',
              onPressed: () => presses++,
            ),
          ),
        ),
      ),
    );

    final card = _feedbackCardRect(tester);
    final button = tester.getRect(find.byType(FloatingActionButton));
    expect(card.right, lessThanOrEqualTo(button.left), reason: '卡片与按钮在水平方向分离');
    expect(card.overlaps(button), isFalse, reason: '提示卡片不应与创建按钮重叠');
    expect(card.bottom, lessThanOrEqualTo(button.top));
    expect(card.width, lessThanOrEqualTo(420));
    await tester.tap(find.byType(FloatingActionButton));
    expect(presses, 1);
  });

  testWidgets('抬高后的警告提示仍可关闭', (tester) async {
    await _showFeedback(
      tester,
      size: _phoneSize,
      body: _pageWithButton(
        ubaaPositionedCreateButton(tooltip: '新增', onPressed: () {}),
      ),
      message: _warningMessage,
      kind: UbaaFeedbackKind.warning,
    );

    final card = _feedbackCardRect(tester);
    final button = tester.getRect(find.byType(FloatingActionButton));
    final snackBar = find.byType(SnackBar);
    final closeButton = find.descendant(
      of: snackBar,
      matching: find.byType(IconButton),
    );
    expect(closeButton, findsOneWidget);
    await tester.tap(closeButton);
    await tester.pumpAndSettle();
    expect(snackBar, findsNothing);
    expect(card.bottom, lessThanOrEqualTo(button.top), reason: '关闭前卡片位于按钮上方');
  });

  // 真机冷启动时 runApp 在帧外挂载根组件，按钮首次构建时调度器处于空闲阶段。
  testWidgets('帧外首次构建时按钮正常显示，占位在帧末出现', (tester) async {
    expect(tester.binding.schedulerPhase, SchedulerPhase.idle);
    tester.binding.attachRootWidget(
      tester.binding.wrapWithDefaultView(
        MaterialApp(
          home: UiCreateButtonHost(
            builder: (_, createButton) => Scaffold(
              floatingActionButton: createButton,
              body: _pageWithButton(
                ubaaPositionedCreateButton(tooltip: '新增', onPressed: () {}),
              ),
            ),
          ),
        ),
      ),
    );
    // 测试绑定已有根元素，attachRootWidget 只标脏；这里在帧外立即构建，复现真机首次挂载。
    tester.binding.buildOwner!.buildScope(tester.binding.rootElement!);
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).floatingActionButton,
      isNotNull,
    );
  });
}

Widget _pageWithButton([Widget? button]) => Stack(
  children: [
    ListView(
      children: [
        for (var row = 1; row <= 6; row++) ListTile(title: Text('第 $row 行')),
      ],
    ),
    ?button,
  ],
);

Future<void> _showFeedback(
  WidgetTester tester, {
  required Size size,
  required Widget body,
  bool withNavigationBar = true,
  String message = _successMessage,
  UbaaFeedbackKind kind = UbaaFeedbackKind.success,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  late BuildContext bodyContext;
  await tester.pumpWidget(
    MaterialApp(
      theme: UbaaTheme.light(),
      home: UiCreateButtonHost(
        builder: (context, createButton) => Scaffold(
          floatingActionButton: createButton,
          body: Builder(
            builder: (context) {
              bodyContext = context;
              return body;
            },
          ),
          bottomNavigationBar: withNavigationBar
              ? NavigationBar(
                  destinations: const [
                    NavigationDestination(icon: Icon(Icons.home), label: '首页'),
                    NavigationDestination(
                      icon: Icon(Icons.folder),
                      label: '文件',
                    ),
                  ],
                )
              : null,
        ),
      ),
    ),
  );
  UbaaFeedback.show(bodyContext, message, kind: kind);
  await tester.pumpAndSettle();
}

Rect _feedbackCardRect(WidgetTester tester) => tester.getRect(
  find
      .descendant(
        of: find.byType(SnackBar),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Material && widget.shape is RoundedRectangleBorder,
        ),
      )
      .first,
);

void _expectCardAbovePhoneButton(WidgetTester tester) {
  final card = _feedbackCardRect(tester);
  final button = tester.getRect(find.byType(FloatingActionButton));
  expect(card.overlaps(button), isFalse, reason: '提示卡片不应与创建按钮重叠');
  expect(card.bottom, lessThanOrEqualTo(button.top));
  expect(card.top, greaterThanOrEqualTo(0));
  expect(card.width, lessThanOrEqualTo(420));
  expect(card.left, greaterThanOrEqualTo(16));
  expect(card.right, lessThanOrEqualTo(_phoneSize.width - 16));
}

void _expectDefaultNavigationGap(WidgetTester tester) {
  final navTop = tester.getTopLeft(find.byType(NavigationBar)).dy;
  expect(_feedbackCardRect(tester).bottom, closeTo(navTop - 10, 0.5));
}
