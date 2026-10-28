import 'package:ubaa_ui/ubaa_ui.dart' show UiDestination;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import '../../../../ubaa_app/test/session/cgyy_lock_display_test.dart'
    as synthetic;

void main() {
  for (final size in [const Size(390, 844), const Size(1024, 900)]) {
    testWidgets(
      '查看密码入口在${size.width}宽度显示专用内容并支持刷新返回',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final backend = synthetic.SyntheticLockBackend();
        await tester.pumpWidget(
          UbaaAppHost(
            backend: backend,
            initialDestination: UiDestination.campus,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('研讨室预约').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('查看密码').first);
        await tester.pump();
        await tester.pump();
        expect(backend.sessions, hasLength(1));
        final session = backend.sessions.single;
        expect(session.reads, hasLength(1));
        session.reads.single.complete(
          CgyyLockDisplay(
            code: '001234',
            reservationReference: 'synthetic-reference',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('001234'), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('feature-search-field')),
          findsNothing,
        );
        expect(backend.ordinaryLockReads, 0);
        await tester.tap(find.byTooltip('刷新当前查询'));
        await tester.pump();
        expect(find.text('001234'), findsNothing);
        expect(session.reads, hasLength(2));
        session.reads.last.complete(CgyyLockDisplay(reservationDate: '合成日期'));
        await tester.pumpAndSettle();
        expect(find.text('未到开门时段'), findsOneWidget);
        await tester.tap(find.byTooltip('返回'));
        await tester.pumpAndSettle();
        expect(session.closed, isTrue);
        expect(find.text('合成日期'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }
}
