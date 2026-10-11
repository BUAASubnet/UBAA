import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';

class FixtureContractVersionClient implements BridgeClient {
  FixtureContractVersionClient(this.version);

  final int version;
  int disposeCalls = 0;

  @override
  int contractVersion() => version;

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError('unexpected bridge call: ${invocation.memberName}');
  }
}

abstract class FixtureCompatibleBridgeClient implements BridgeClient {
  @override
  int contractVersion() => 41;
}

class FixtureFakeClassroomClient extends FixtureCompatibleBridgeClient {
  FixtureFakeClassroomClient(this.response);

  final BridgeRoutedClassroomQuery response;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #classroomSearch) {
      return Future<BridgeRoutedClassroomQuery>.value(response);
    }
    throw UnsupportedError('unexpected bridge call: ${invocation.memberName}');
  }
}

class FixtureFakeBykcChosenCoursesClient extends FixtureCompatibleBridgeClient {
  FixtureFakeBykcChosenCoursesClient(this.response);

  final BridgeRoutedBykcChosenCourses response;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #bykcChosenCourses) {
      return Future<BridgeRoutedBykcChosenCourses>.value(response);
    }
    throw UnsupportedError('unexpected bridge call: ${invocation.memberName}');
  }
}

class FixtureFakeComplexWriteClient extends FixtureCompatibleBridgeClient {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final method = invocation.memberName;
    final named = invocation.namedArguments;
    if (method == #prepareYgdkSubmit) {
      final request = named[#request] as BridgeYgdkSubmitRequest;
      expect(request.target.classifyId, 31);
      expect(request.target.itemId, 7);
      expect(request.photo.bytes, <int>[1, 2]);
      expect(request.photo.fileName, 'safe.jpg');
      return Future<BridgeWriteIntent>.value(
        fixtureWriteIntent(BridgeWriteOperation.ygdkSubmit),
      );
    }
    if (method == #prepareCgyySubmitReservation) {
      final request = named[#request] as BridgeCgyySubmitReservationRequest;
      expect(request.venueSiteId, 3);
      expect(request.selections.single.spaceId, 4);
      expect(request.selections.single.timeId, 5);
      expect(request.selections.single.venueSpaceGroupId, 9);
      expect(request.phone, 'phone-placeholder');
      return Future<BridgeWriteIntent>.value(
        fixtureWriteIntent(BridgeWriteOperation.cgyySubmitReservation),
      );
    }
    if (method == #prepareEvaluationSubmitCourses) {
      final request = named[#request] as BridgeEvaluationSubmitCoursesRequest;
      expect(request.targets.single.rwid, 'task-1');
      expect(request.targets.single.wjid, 'questionnaire-1');
      expect(request.targets.single.kcdm, 'K1');
      return Future<BridgeWriteIntent>.value(
        fixtureWriteIntent(BridgeWriteOperation.evaluationSubmitCourses),
      );
    }
    throw UnsupportedError('unexpected bridge call: $method');
  }
}

class FixtureFakeCgyyCommitClient extends FixtureCompatibleBridgeClient {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #commitWrite) {
      return Future<BridgeWriteCommitResult>.value(
        BridgeWriteCommitResult(
          operation: BridgeWriteOperation.cgyySubmitReservation,
          success: true,
          message: '研讨室预约已提交',
          outcomeUnknown: false,
          resolvedRoute: BridgeConnectionMode.direct,
          cgyyReceipt: const BridgeCgyyReservationReceipt(
            orderId: 42,
            venueSiteId: 3,
            reservationDate: '2026-09-03',
            orderStatus: 1,
          ),
        ),
      );
    }
    throw UnsupportedError('unexpected bridge call: ${invocation.memberName}');
  }
}

class FixtureFakeCgyyDayClient extends FixtureCompatibleBridgeClient {
  FixtureFakeCgyyDayClient(this.response);

  final BridgeRoutedCgyyDayInfo response;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #cgyyDayInfo) {
      expect(invocation.namedArguments[#siteId], 3);
      expect(invocation.namedArguments[#date], isNotEmpty);
      return Future<BridgeRoutedCgyyDayInfo>.value(response);
    }
    throw UnsupportedError('unexpected bridge call: ${invocation.memberName}');
  }
}

class FixtureFakeCancellationProjectionClient
    extends FixtureCompatibleBridgeClient {
  FixtureFakeCancellationProjectionClient({
    required this.libbook,
    required this.cgyy,
  });

  final BridgeRoutedLibBookBookings libbook;
  final BridgeRoutedCgyyOrders cgyy;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #libbookBookings) {
      return Future<BridgeRoutedLibBookBookings>.value(libbook);
    }
    if (invocation.memberName == #cgyyOrders) {
      return Future<BridgeRoutedCgyyOrders>.value(cgyy);
    }
    throw UnsupportedError('unexpected bridge call: ${invocation.memberName}');
  }
}

class FixtureFakeYgdkRecordsClient extends FixtureCompatibleBridgeClient {
  FixtureFakeYgdkRecordsClient(this.response);

  final BridgeRoutedYgdkRecords response;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #ygdkRecords) {
      expect(invocation.namedArguments[#page], 1);
      expect(invocation.namedArguments[#size], 20);
      return Future<BridgeRoutedYgdkRecords>.value(response);
    }
    throw UnsupportedError('unexpected bridge call: ${invocation.memberName}');
  }
}

BridgeWriteIntent fixtureWriteIntent(BridgeWriteOperation operation) =>
    BridgeWriteIntent(
      intentId: 'intent',
      operation: operation,
      targetSummary: 'typed',
      resolvedRoute: BridgeConnectionMode.direct,
      warnings: const <String>[],
      expiresAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 120,
      requestDigest: 'digest',
    );
