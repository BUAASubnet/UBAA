import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';

final currentBridgeContractVersion = _readCurrentBridgeContractVersion();

int _readCurrentBridgeContractVersion() {
  const relative = 'lib/src/bridge/bridge_backend.dart';
  final local = File(relative);
  final source = local.existsSync()
      ? local
      : File('packages/ubaa_app/$relative');
  final declaration = RegExp(r'const _supportedBridgeContractVersion = (\d+);');
  return int.parse(declaration.firstMatch(source.readAsStringSync())![1]!);
}

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
  int contractVersion() => 54;
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

BridgeWriteIntent fixtureWriteIntent(
  BridgeWriteOperation operation, {
  BridgeLibraryLoanRenewTarget? libraryLoanRenewTarget,
}) => BridgeWriteIntent(
  intentId: 'intent',
  operation: operation,
  targetSummary: 'typed',
  resolvedRoute: BridgeConnectionMode.direct,
  warnings: const <String>[],
  expiresAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 120,
  requestDigest: 'digest',
  libraryLoanRenewTarget: libraryLoanRenewTarget,
);
