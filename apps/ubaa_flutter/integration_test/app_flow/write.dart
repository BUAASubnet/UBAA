part of '../app_flow_test.dart';

void _registerPrimaryWriteFlowTests() {
  testWidgets('宿主集成流程写入只提交一次并刷新签到状态', (tester) async {
    final backend = _WriteIntegrationBackend();
    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: backend,
        credentialVault: MemoryCredentialVault(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '2020000001');
    await tester.enterText(find.byType(TextField).at(1), 'fixture-password');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课堂签到'));
    await tester.pumpAndSettle();
    expect(find.text('未签到'), findsOneWidget);

    await tester.tap(find.text('准备签到'));
    await tester.pumpAndSettle();
    expect(find.text('确认课堂签到'), findsNWidgets(2));
    expect(backend.commitCalls, 0);

    final confirm = find.widgetWithText(FilledButton, '确认提交');
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(backend.commitCalls, 1);
    expect(backend.preparedCourse, 'course-integration');
    expect(backend.signinLoads, greaterThanOrEqualTo(2));
    expect(find.text('签到结果已提交，请刷新确认'), findsOneWidget);
    expect(find.text('已签到'), findsOneWidget);
  });

  testWidgets('宿主集成流程课堂签到结果未知时只读刷新一次且不暴露业务上下文', (tester) async {
    final backend = _WriteIntegrationBackend(
      commitFixture: _SigninCommitFixture.outcomeUnknown,
    );
    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: backend,
        credentialVault: MemoryCredentialVault(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '2020000004');
    await tester.enterText(find.byType(TextField).at(1), 'fixture-password');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课堂签到'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('准备签到'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();

    expect(backend.commitCalls, 1);
    expect(backend.signinLoads, 2);
    expect(find.text('提交结果不确定，请先刷新相关状态，不要重复提交。'), findsOneWidget);
    expect(find.text('相关课程状态'), findsNothing);
    expect(find.text('已签到'), findsNothing);
  });

  testWidgets('宿主集成流程课堂签到业务 false 不显示成功且不刷新', (tester) async {
    final backend = _WriteIntegrationBackend(
      commitFixture: _SigninCommitFixture.businessFalse,
    );
    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: backend,
        credentialVault: MemoryCredentialVault(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '2020000005');
    await tester.enterText(find.byType(TextField).at(1), 'fixture-password');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课堂签到'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('准备签到'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();

    expect(backend.commitCalls, 1);
    expect(backend.signinLoads, 1);
    expect(find.text('签到未完成'), findsOneWidget);
    expect(find.text('签到结果已提交，请刷新确认'), findsNothing);
    expect(find.text('已签到'), findsNothing);
  });
}

void _registerWriteMatrixFlowTest() {
  testWidgets('宿主集成流程覆盖十项写操作并验证签到签退分支', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final backend = _AllWritesIntegrationBackend();
    final permissionGateway = MemoryPermissionGateway(
      initial: <PlatformPermission, PlatformPermissionStatus>{
        PlatformPermission.photos: PlatformPermissionStatus.granted,
      },
    );
    await tester.pumpWidget(
      UbaaFlutterApp(
        key: const ValueKey<String>('all-writes-smoke'),
        backend: backend,
        credentialVault: MemoryCredentialVault(),
        photoPicker: MemoryPhotoPicker(
          photo: const YgdkPhotoInput(
            bytes: <int>[1, 2, 3],
            fileName: 'integration.jpg',
            mimeType: 'image/jpeg',
          ),
        ),
        permissionGateway: permissionGateway,
        initialTab: 1,
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '2020000099');
    await tester.enterText(find.byType(TextField).at(1), 'fixture-password');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(UbaaMainShell), findsOneWidget);

    Future<void> openFeature(FeatureId feature) async {
      final selectedIcon = ordinaryFeatureIds.contains(feature)
          ? Icons.apps
          : Icons.auto_awesome;
      final unselectedIcon = ordinaryFeatureIds.contains(feature)
          ? Icons.apps_outlined
          : Icons.auto_awesome_outlined;
      final tab = find.byIcon(selectedIcon).evaluate().isNotEmpty
          ? find.byIcon(selectedIcon)
          : find.byIcon(unselectedIcon);
      await tester.tap(tab.first);
      await tester.pumpAndSettle();
      final target = find.text(feature.title).first;
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(find.text('返回功能列表'), findsOneWidget);
    }

    Future<void> leaveFeature() async {
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
    }

    Future<void> confirm(
      String label,
      WriteOperation operation,
      FeatureId readbackFeature,
    ) async {
      await tester.ensureVisible(find.text(label).first);
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
      expect(find.text('确认${operation.title}'), findsAtLeastNWidgets(1));
      final before = backend.commitCalls;
      final beforeReadback = backend.featureLoads[readbackFeature] ?? 0;
      await tester.tap(find.widgetWithText(FilledButton, '确认提交'));
      await tester.pumpAndSettle();
      expect(backend.commitCalls, before + 1);
      expect(backend.committedOperations.last, operation);
      final readbackCount = backend.featureLoads[readbackFeature] ?? 0;
      if (operation == WriteOperation.cgyyCancelOrder) {
        expect(
          readbackCount,
          beforeReadback + 2,
          reason: '场馆取消提交后必须各读一次订单列表和同 ID 详情',
        );
      } else {
        expect(
          readbackCount,
          greaterThan(beforeReadback),
          reason: '${operation.title}提交后必须刷新${readbackFeature.title}核对',
        );
      }
    }

    await openFeature(FeatureId.bykc);
    await confirm('准备选课', WriteOperation.bykcSelectCourse, FeatureId.bykc);
    await leaveFeature();
    await openFeature(FeatureId.bykc);
    await confirm('准备退选', WriteOperation.bykcDeselectCourse, FeatureId.bykc);
    await leaveFeature();
    await openFeature(FeatureId.bykc);
    await confirm('准备博雅签到', WriteOperation.bykcSignCourse, FeatureId.bykc);
    await leaveFeature();
    await openFeature(FeatureId.bykc);
    await confirm('准备博雅签退', WriteOperation.bykcSignCourse, FeatureId.bykc);
    await leaveFeature();

    await openFeature(FeatureId.signin);
    await confirm('准备签到', WriteOperation.signinPerform, FeatureId.signin);
    await leaveFeature();

    await openFeature(FeatureId.libbook);
    await confirm('准备预约此座位', WriteOperation.libbookReserve, FeatureId.libbook);
    await leaveFeature();
    await openFeature(FeatureId.libbook);
    await confirm(
      '准备取消预约',
      WriteOperation.libbookCancelBooking,
      FeatureId.libbook,
    );
    await leaveFeature();

    await openFeature(FeatureId.cgyy);
    expect(find.text('准备场馆预约'), findsOneWidget);
    await tester.tap(find.text('准备场馆预约').first);
    await tester.pumpAndSettle();
    expect(find.text('填写场馆预约信息'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, '联系电话'),
      '010-00000000',
    );
    await tester.enterText(find.widgetWithText(TextField, '预约主题'), '集成测试');
    await tester.enterText(find.widgetWithText(TextField, '用途编号'), '2');
    await tester.enterText(find.widgetWithText(TextField, '参与人数'), '2');
    await tester.enterText(find.widgetWithText(TextField, '活动内容'), '脱敏集成验证');
    await tester.enterText(find.widgetWithText(TextField, '参与人说明'), '脱敏参与人');
    await tester.tap(find.text('继续确认'));
    // 场馆表单在退出动画后延迟释放输入控制器；普通 Timer 不会让
    // pumpAndSettle 主动继续推进时间，因此这里显式越过该安全窗口。
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('填写场馆预约信息'), findsNothing);
    expect(find.text('确认场馆预约'), findsAtLeastNWidgets(1));
    final beforeCgyy = backend.commitCalls;
    final beforeCgyyReadback = backend.featureLoads[FeatureId.cgyy] ?? 0;
    await tester.tap(find.widgetWithText(FilledButton, '确认提交'));
    await tester.pumpAndSettle();
    expect(backend.commitCalls, beforeCgyy + 1);
    expect(
      backend.committedOperations.last,
      WriteOperation.cgyySubmitReservation,
    );
    expect(
      backend.featureLoads[FeatureId.cgyy],
      greaterThan(beforeCgyyReadback),
      reason: '场馆预约提交后必须刷新场馆订单核对',
    );
    await leaveFeature();

    await openFeature(FeatureId.cgyy);
    await confirm('准备取消订单', WriteOperation.cgyyCancelOrder, FeatureId.cgyy);
    await leaveFeature();

    await openFeature(FeatureId.ygdk);
    await tester.tap(find.text('准备阳光打卡').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '开始时间'),
      '2026-09-02 08:00',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '结束时间'),
      '2026-09-02 09:00',
    );
    await tester.tap(find.text('选择照片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续确认'));
    await tester.pumpAndSettle();
    expect(find.text('确认阳光打卡'), findsAtLeastNWidgets(1));
    final beforeYgdk = backend.commitCalls;
    final beforeYgdkReadback = backend.featureLoads[FeatureId.ygdk] ?? 0;
    await tester.tap(find.widgetWithText(FilledButton, '确认提交'));
    await tester.pumpAndSettle();
    expect(backend.commitCalls, beforeYgdk + 1);
    expect(backend.committedOperations.last, WriteOperation.ygdkSubmit);
    expect(
      backend.featureLoads[FeatureId.ygdk],
      greaterThan(beforeYgdkReadback),
      reason: '阳光打卡提交后必须刷新打卡记录核对',
    );
    await leaveFeature();

    await openFeature(FeatureId.evaluation);
    await confirm(
      '准备提交评教',
      WriteOperation.evaluationSubmitCourses,
      FeatureId.evaluation,
    );

    expect(backend.committedOperations, <WriteOperation>[
      WriteOperation.bykcSelectCourse,
      WriteOperation.bykcDeselectCourse,
      WriteOperation.bykcSignCourse,
      WriteOperation.bykcSignCourse,
      WriteOperation.signinPerform,
      WriteOperation.libbookReserve,
      WriteOperation.libbookCancelBooking,
      WriteOperation.cgyySubmitReservation,
      WriteOperation.cgyyCancelOrder,
      WriteOperation.ygdkSubmit,
      WriteOperation.evaluationSubmitCourses,
    ]);
  });
}
