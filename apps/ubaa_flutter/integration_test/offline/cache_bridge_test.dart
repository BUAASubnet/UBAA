import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('原生 Bridge 缓存句柄可重开且退出栅栏跨句柄生效', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('本地缓存合成验证'))),
    );
    await RustLib.init();
    final directory = await Directory.systemTemp.createTemp(
      'ubaa-cache-probe-',
    );
    final key = Uint8List.fromList(List.filled(32, 7));
    BridgeOfflineCache? first;
    BridgeOfflineCache? second;
    BridgeClient? client;
    try {
      client = BridgeClient.open(configDir: directory.path);
      expect(client.contractVersion(), 32);
      await client.setDefaultRoutePolicy(policy: BridgeRoutePolicy.direct);
      await expectLater(
        client.recoverRequiredSession(feature: BridgeRecoveryFeature.schedule),
        throwsA(
          isA<BridgeError>()
              .having(
                (error) => error.code,
                '缺少会话',
                BridgeErrorCode.authenticationRequired,
              )
              .having(
                (error) => error.resolvedRoute,
                'Core 目标路线',
                BridgeConnectionMode.direct,
              ),
        ),
      );
      await expectLater(
        client.beginJudgeOnline(
          options: const BridgeJudgeOnlineOptions(
            includeExpired: false,
            expectedIdentity: 'synthetic',
          ),
        ),
        throwsA(
          isA<BridgeError>().having(
            (error) => error.code,
            '无缓存新RPC保留缺会话错误',
            BridgeErrorCode.authenticationRequired,
          ),
        ),
      );
      await expectLater(
        client.beginSpocOnline(expectedIdentity: 'synthetic'),
        throwsA(
          isA<BridgeError>().having(
            (error) => error.code,
            'SPOC 分段 RPC 缺会话',
            BridgeErrorCode.authenticationRequired,
          ),
        ),
      );
      await expectLater(
        client.beginSpocDetailOnline(
          expectedIdentity: 'synthetic',
          assignmentId: 'a1',
        ),
        throwsA(
          isA<BridgeError>().having(
            (error) => error.code,
            'SPOC 详情分段 RPC 缺会话',
            BridgeErrorCode.authenticationRequired,
          ),
        ),
      );
      await expectLater(
        client.beginEvaluationOnline(expectedIdentity: 'synthetic'),
        throwsA(
          isA<BridgeError>().having(
            (error) => error.code,
            '评教分段 RPC 缺会话',
            BridgeErrorCode.authenticationRequired,
          ),
        ),
      );
      first = await BridgeOfflineCache.open(
        configDir: directory.path,
        accountId: '0123456789abcdef0123456789abcdef',
        expectedIdentity: 'synthetic',
        key: key,
      );
      await expectLater(
        client.commitWriteCached(cache: first, intentId: 'synthetic-missing'),
        throwsA(
          isA<BridgeError>().having(
            (error) => error.code,
            '新提交 RPC 拒绝不存在的意图且不触发学校请求',
            BridgeErrorCode.intentExpired,
          ),
        ),
      );
      await expectLater(
        client.beginScheduleImport(cache: first, term: 'synthetic-term'),
        throwsA(
          isA<BridgeError>().having(
            (error) => error.code,
            '新导入RPC保留缺会话错误',
            BridgeErrorCode.authenticationRequired,
          ),
        ),
      );
      expect(
        await first.readBykcProfile(route: BridgeConnectionMode.direct),
        isNull,
      );
      expect(
        await first.readBykcCourses(
          route: BridgeConnectionMode.direct,
          page: 1,
          size: 20,
          all: true,
        ),
        isNull,
      );
      expect(
        await first.readBykcDetail(
          route: BridgeConnectionMode.direct,
          courseId: 42,
        ),
        isNull,
      );
      expect(
        await first.readBykcChosen(route: BridgeConnectionMode.direct),
        isNull,
      );
      expect(
        await first.readBykcStatistics(route: BridgeConnectionMode.direct),
        isNull,
      );
      await expectLater(
        client.bykcCoursesCached(cache: first, page: 1, size: 20, all: true),
        throwsA(
          isA<BridgeError>().having(
            (error) => error.code,
            '缺少会话',
            BridgeErrorCode.authenticationRequired,
          ),
        ),
      );
      expect(
        await first.readYgdkRecordsSelection(
          route: BridgeConnectionMode.direct,
        ),
        isNull,
      );
      expect(
        await first.readYgdkRecords(
          route: BridgeConnectionMode.direct,
          classifyId: 1,
          page: 1,
          size: 20,
        ),
        isNull,
      );
      for (final read in <Future<dynamic> Function()>[
        () => client!.ygdkRecordsCached(cache: first!, page: 1, size: 20),
        () => client!.ygdkRecordsForOverviewCached(
          cache: first!,
          route: BridgeConnectionMode.direct,
          classifyId: 1,
          page: 1,
          size: 20,
        ),
      ]) {
        await expectLater(
          read(),
          throwsA(
            isA<BridgeError>().having(
              (error) => error.code,
              '合成阳光缺会话',
              BridgeErrorCode.authenticationRequired,
            ),
          ),
        );
      }
      expect(
        await first.readProfile(route: BridgeConnectionMode.direct),
        isNull,
      );
      await expectLater(
        client.userInfoCached(cache: first),
        throwsA(
          isA<BridgeError>().having(
            (error) => error.code,
            '合成资料缺会话',
            BridgeErrorCode.authenticationRequired,
          ),
        ),
      );
      await _checkLibbookCache(client, first);
      expect(
        await first.readEvaluation(route: BridgeConnectionMode.direct),
        isNull,
      );
      await expectLater(
        client.evaluationCached(cache: first),
        throwsA(
          isA<BridgeError>().having(
            (error) => error.code,
            '合成评教缺会话',
            BridgeErrorCode.authenticationRequired,
          ),
        ),
      );
      expect(
        await first.readCgyySites(route: BridgeConnectionMode.direct),
        isNull,
      );
      expect(
        await first.readCgyyPurposes(route: BridgeConnectionMode.direct),
        isNull,
      );
      expect(
        await first.readCgyyDay(
          route: BridgeConnectionMode.direct,
          siteId: 4,
          date: '2026-09-22',
        ),
        isNull,
      );
      expect(
        await first.readCgyyOrders(
          route: BridgeConnectionMode.direct,
          page: 0,
          size: 20,
        ),
        isNull,
      );
      expect(
        await first.readCgyyDetail(
          route: BridgeConnectionMode.direct,
          orderId: 9,
        ),
        isNull,
      );
      await expectLater(
        client.cgyyOrdersCached(cache: first, page: 0, size: 20),
        throwsA(
          isA<BridgeError>().having(
            (error) => error.code,
            '缺少会话',
            BridgeErrorCode.authenticationRequired,
          ),
        ),
      );
      expect(await first.readToday(route: BridgeConnectionMode.direct), isNull);
      expect(
        await first.readJudge(
          route: BridgeConnectionMode.direct,
          includeExpired: false,
        ),
        isNull,
      );
      expect(
        await first.readJudgeDetail(
          route: BridgeConnectionMode.direct,
          courseId: '12',
          assignmentId: '101',
        ),
        isNull,
      );
      expect(
        await first.readAcademicTerms(route: BridgeConnectionMode.direct),
        isNull,
      );
      expect(
        await first.readAcademicWeeks(
          route: BridgeConnectionMode.direct,
          term: '2025-2026-1',
        ),
        isNull,
      );
      expect(
        await first.readAcademicWeek(
          route: BridgeConnectionMode.direct,
          term: '2025-2026-1',
          week: 3,
        ),
        isNull,
      );
      expect(
        await first.readAcademicExams(
          route: BridgeConnectionMode.direct,
          term: '2025-2026-1',
        ),
        isNull,
      );
      expect(
        await first.readAcademicGrades(
          route: BridgeConnectionMode.direct,
          term: '2025-2026-1',
        ),
        isNull,
      );
      expect(
        await first.readAcademicClassrooms(
          route: BridgeConnectionMode.direct,
          campus: 1,
          date: '2026-09-22',
        ),
        isNull,
      );
      expect(
        await first.readHomeSignin(route: BridgeConnectionMode.direct),
        isNull,
      );
      expect(
        await first.readHomeSpoc(route: BridgeConnectionMode.direct),
        isNull,
      );
      expect(
        await first.readHomeSpocDetail(
          route: BridgeConnectionMode.direct,
          assignmentId: 'synthetic',
        ),
        isNull,
      );
      expect(
        await first.readHomeYgdk(route: BridgeConnectionMode.direct),
        isNull,
      );
      await expectLater(
        client.homeSigninCached(cache: first),
        throwsA(
          isA<BridgeError>().having(
            (error) => error.code,
            '缺少会话',
            BridgeErrorCode.authenticationRequired,
          ),
        ),
      );
      await expectLater(
        client.academicGradesCached(cache: first, term: '2025-2026-1'),
        throwsA(
          isA<BridgeError>().having(
            (error) => error.code,
            '缺少会话',
            BridgeErrorCode.authenticationRequired,
          ),
        ),
      );
      await expectLater(
        client.beginJudgeRefresh(
          cache: first,
          options: const BridgeJudgeRefreshOptions(
            includeExpired: false,
            fullRefresh: true,
          ),
        ),
        throwsA(
          isA<BridgeError>()
              .having(
                (error) => error.code,
                '新刷新出口缺少会话',
                BridgeErrorCode.authenticationRequired,
              )
              .having(
                (error) => error.resolvedRoute,
                '固定目标路线',
                BridgeConnectionMode.direct,
              ),
        ),
      );
      second = await BridgeOfflineCache.open(
        configDir: directory.path,
        accountId: '0123456789abcdef0123456789abcdef',
        expectedIdentity: 'synthetic',
        key: key,
      );
      await first.deactivate();
      await expectLater(
        second.readToday(route: BridgeConnectionMode.direct),
        throwsA(
          isA<BridgeError>().having(
            (error) => error.code,
            '退出栅栏',
            BridgeErrorCode.authenticationRequired,
          ),
        ),
      );
      await second.activate();
      expect(
        await first.readBykcProfile(route: BridgeConnectionMode.direct),
        isNull,
      );
      expect(
        await first.readBykcCourses(
          route: BridgeConnectionMode.direct,
          page: 1,
          size: 20,
          all: true,
        ),
        isNull,
      );
      expect(
        await first.readBykcDetail(
          route: BridgeConnectionMode.direct,
          courseId: 42,
        ),
        isNull,
      );
      expect(
        await first.readBykcChosen(route: BridgeConnectionMode.direct),
        isNull,
      );
      expect(
        await first.readBykcStatistics(route: BridgeConnectionMode.direct),
        isNull,
      );
      await expectLater(
        client.bykcCoursesCached(cache: first, page: 1, size: 20, all: true),
        throwsA(
          isA<BridgeError>().having(
            (error) => error.code,
            '缺少会话',
            BridgeErrorCode.authenticationRequired,
          ),
        ),
      );
      expect(
        await first.readCgyySites(route: BridgeConnectionMode.direct),
        isNull,
      );
      expect(
        await first.readCgyyPurposes(route: BridgeConnectionMode.direct),
        isNull,
      );
      expect(
        await first.readCgyyDay(
          route: BridgeConnectionMode.direct,
          siteId: 4,
          date: '2026-09-22',
        ),
        isNull,
      );
      expect(
        await first.readCgyyOrders(
          route: BridgeConnectionMode.direct,
          page: 0,
          size: 20,
        ),
        isNull,
      );
      expect(
        await first.readCgyyDetail(
          route: BridgeConnectionMode.direct,
          orderId: 9,
        ),
        isNull,
      );
      await expectLater(
        client.cgyyOrdersCached(cache: first, page: 0, size: 20),
        throwsA(
          isA<BridgeError>().having(
            (error) => error.code,
            '缺少会话',
            BridgeErrorCode.authenticationRequired,
          ),
        ),
      );
      expect(await first.readToday(route: BridgeConnectionMode.webVpn), isNull);
      await second.clear();
      final old = second;
      final reset = await old.clearAndReopen();
      second = reset.cache;
      expect(reset.report.compacted, isTrue);
      expect(reset.report.maintenanceError, isNull);
      expect(reset.report.usage!.entryCount.toInt(), 0);
      expect((await second.usage()).softLimitBytes.toInt(), 50 * 1024 * 1024);
      await expectLater(
        old.usage(),
        throwsA(
          isA<BridgeError>().having(
            (e) => e.code,
            '清理前句柄失效',
            BridgeErrorCode.operationConflict,
          ),
        ),
      );
      old.dispose();
      final beforeRecovery = second;
      await File(
        '${directory.path}/business-cache/0123456789abcdef0123456789abcdef.sqlite',
      ).writeAsString('synthetic-corrupt');
      final recovery = await BridgeOfflineCache.clearOrRebuild(
        configDir: directory.path,
        accountId: '0123456789abcdef0123456789abcdef',
        expectedIdentity: 'synthetic',
        key: key,
      );
      second = recovery.cache;
      expect(second, isNotNull);
      expect(recovery.report.maintenanceError, isNull);
      expect((await second!.usage()).entryCount.toInt(), 0);
      await expectLater(beforeRecovery.usage(), throwsA(isA<BridgeError>()));
      beforeRecovery.dispose();
    } finally {
      key.fillRange(0, key.length, 0);
      await client?.dispose();
      first?.dispose();
      second?.dispose();
      await directory.delete(recursive: true);
    }
  });
}

Future<void> _checkLibbookCache(
  BridgeClient client,
  BridgeOfflineCache cache,
) async {
  const route = BridgeConnectionMode.direct;
  expect(
    await cache.readLibbookLibraries(route: route, day: '2026-09-22'),
    isNull,
  );
  expect(
    await cache.readLibbookAreas(
      route: route,
      premisesId: 'p1',
      storeyId: 'f1',
      day: '2026-09-22',
    ),
    isNull,
  );
  expect(await cache.readLibbookAreaDetail(route: route, areaId: 'a1'), isNull);
  expect(
    await cache.readLibbookSeats(
      route: route,
      areaId: 'a1',
      day: '2026-09-22',
      startTime: '08:00',
      endTime: '09:00',
    ),
    isNull,
  );
  expect(
    await cache.readLibbookBookings(route: route, page: 1, limit: 20),
    isNull,
  );
  await expectLater(
    client.libbookBookingsCached(cache: cache, page: 1, limit: 20),
    throwsA(
      isA<BridgeError>().having(
        (error) => error.code,
        '合成配置缺少会话',
        BridgeErrorCode.authenticationRequired,
      ),
    ),
  );
}
