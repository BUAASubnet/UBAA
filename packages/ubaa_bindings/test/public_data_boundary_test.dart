import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 公开数据的安全边界；常规签名由消费者编译与生成零漂移检查负责。
void main() {
  test('重启核对提示只公开本地标识、操作、路线和时间', () {
    final source = File(
      'lib/src/rust/api/write/readback.dart',
    ).readAsStringSync();
    final fields = RegExp(
      r'final\s+\w+\s+(\w+);',
    ).allMatches(source).map((match) => match.group(1)).toList();
    expect(fields, ['id', 'operation', 'route', 'startedAt']);
  });

  test('缓存用量只公开数值且清理结果交付新句柄', () {
    final source = File(
      'lib/src/rust/api/cache_management.dart',
    ).readAsStringSync();
    final body = RegExp(
      r'class BridgeCacheUsage \{(?<body>.*?)\n\}',
      dotAll: true,
    ).firstMatch(source)!.namedGroup('body')!;
    expect(body, isNot(contains('String')));
    for (final field in [
      'entryCount',
      'contentBytes',
      'databaseBytes',
      'reusableBytes',
      'softLimitBytes',
      'hardLimitBytes',
    ]) {
      expect(body, contains(field));
    }
    expect(source, contains('final BridgeOfflineCache cache;'));
    expect(source, contains('maintenanceError'));
  });

  test('离线资料类型不能承载完整身份或联系方式', () {
    final source = File(
      'lib/src/rust/api/offline_profile.dart',
    ).readAsStringSync();
    final body = RegExp(
      r'class BridgeMaskedProfile \{(?<body>.*?)\n\}',
      dotAll: true,
    ).firstMatch(source)!.namedGroup('body')!;
    for (final field in [
      'username',
      'name',
      'schoolId',
      'email',
      'phone',
      'idCardNumber',
      'idCardTypeName',
    ]) {
      expect(body, isNot(contains('final String? $field;')));
    }
    expect(body, contains('maskedUsername'));
    expect(body, contains('maskedName'));
    expect(body, contains('maskedSchoolId'));
  });

  test('阳光记录页使用独立时间且分类索引不冒充数据新鲜度', () {
    final source = File(
      'lib/src/rust/api/offline_ygdk.dart',
    ).readAsStringSync();
    final selector = RegExp(
      r'class BridgeCachedYgdkSelection \{(?<body>.*?)\n\}',
      dotAll: true,
    ).firstMatch(source)!;
    expect(selector.namedGroup('body'), isNot(contains('fetchedAt')));
    expect(source, contains('class BridgeCachedYgdkRecords'));
    expect(source, contains('classifyId'));
    for (final forbidden in [
      'submitTarget',
      'submitEligibility',
      'images',
      'token',
      'cookie',
    ]) {
      expect(source, isNot(contains(forbidden)));
    }
  });

  test('评教缓存类型仅展示课程而不公开提交材料', () {
    final source = File(
      'lib/src/rust/api/offline_evaluation.dart',
    ).readAsStringSync();
    final type = RegExp(
      r'class BridgeCachedEvaluationCourse \{(?<body>.*?)\n\}',
      dotAll: true,
    ).firstMatch(source);
    expect(type, isNotNull);
    for (final field in [
      'Eligibility',
      'Target',
      'rwid',
      'wjid',
      'msid',
      'pjrdm',
      'pjrmc',
    ]) {
      expect(type!.namedGroup('body'), isNot(contains(field)));
    }
  });

  test('图书馆缓存公开类型不含预约取消资格', () {
    final source = File(
      'lib/src/rust/api/offline_libbook.dart',
    ).readAsStringSync();
    for (final name in [
      'BridgeCachedLibBookSeat',
      'BridgeCachedLibBookBooking',
    ]) {
      final type = RegExp(
        'class $name \\{(?<body>.*?)\\n\\}',
        dotAll: true,
      ).firstMatch(source);
      expect(type, isNotNull);
      for (final field in ['Eligibility', 'Target', 'token', 'cookie']) {
        expect(type!.namedGroup('body'), isNot(contains(field)));
      }
    }
  });

  test('研讨室缓存 DTO 不跨公开边界传递资格和内部材料', () {
    final source = File(
      'lib/src/rust/api/offline_cgyy.dart',
    ).readAsStringSync();
    for (final name in [
      'BridgeCachedCgyyOrder',
      'BridgeCachedCgyySlotStatus',
    ]) {
      final type = RegExp(
        'class $name \\{(?<body>.*?)\\n\\}',
        dotAll: true,
      ).firstMatch(source);
      expect(type, isNotNull);
      final body = type!.namedGroup('body')!;
      for (final field in [
        'Eligibility',
        'Target',
        'tradeNo',
        'phone',
        'joiners',
        'checkContent',
        'handleReason',
        'remark',
        'takeUp',
      ]) {
        expect(body, isNot(contains(field)), reason: '$name 禁止透传 $field');
      }
    }
  });

  test('博雅持久只读 DTO 同样遵守内部材料禁曝边界', () {
    final cached = File(
      'lib/src/rust/api/offline_bykc.dart',
    ).readAsStringSync();
    final matched = RegExp(
      r'class BridgeCachedBykcChosenCourse \{(?<body>.*?)\n\}',
      dotAll: true,
    ).firstMatch(cached);
    expect(matched, isNotNull);
    final body = matched!.namedGroup('body')!;
    expect(body, contains('final int? checkin;'));
    for (final field in [
      'homework',
      'homeworkAttachmentName',
      'homeworkAttachmentPath',
      'signInfo',
      'Eligibility',
      'signPoints',
    ]) {
      expect(
        body,
        isNot(contains(field)),
        reason: '缓存 Bridge DTO 不得绕过既有禁曝边界：$field',
      );
    }
  });

  final client = File('lib/src/rust/api/client.dart').readAsStringSync();
  final read = File('lib/src/rust/api/read.dart').readAsStringSync();
  final write = File('lib/src/rust/api/write.dart').readAsStringSync();

  test('评教不恢复已移除的局部读取入口', () {
    expect(client, isNot(contains('evaluationPending')));
    expect(client, isNot(contains('evaluation_pending')));
  });

  test('场馆取消回读固定 caller-pinned 路线且不伪装 Auto 决策', () {
    for (final name in <String>[
      'BridgeCallerPinnedCgyyOrder',
      'BridgeCallerPinnedCgyyOrders',
    ]) {
      final declaration = RegExp(
        'class $name \\{(?<body>.*?)\\n\\}',
        dotAll: true,
      ).firstMatch(read);
      expect(declaration, isNotNull, reason: '生成 DTO 缺少 $name');
      final body = declaration!.namedGroup('body')!;
      expect(body, contains('final BridgeConnectionMode pinnedRoute;'));
      expect(body, isNot(contains('BridgeRouteDecision')));
    }
  });

  test('生成 DTO 快照固定全部公开读取枚举', () {
    const enums = <String, List<String>>{
      'BridgeActionEligibility': <String>['allowed', 'denied', 'unknown'],
      'BridgeBykcCourseCategory': <String>['boya', 'unknown'],
      'BridgeBykcCourseStatus': <String>[
        'expired',
        'selected',
        'preview',
        'ended',
        'full',
        'available',
      ],
      'BridgeBykcCourseSubCategory': <String>[
        'moral',
        'aesthetic',
        'labor',
        'safetyHealth',
        'other',
        'unknown',
      ],
      'BridgeCgyyPurposeSource': <String>['upstream', 'staticFallback'],
      'BridgeJudgeSubmissionStatus': <String>[
        'submitted',
        'partial',
        'unsubmitted',
        'unknown',
      ],
      'BridgeSpocSubmissionStatus': <String>[
        'submitted',
        'unsubmitted',
        'unknown',
      ],
    };
    final enumNames = RegExp(
      r'^enum (Bridge[A-Za-z0-9]+)\b',
      multiLine: true,
    ).allMatches(read).map((match) => match.group(1)!).toSet();

    expect(enumNames, enums.keys.toSet());
    for (final entry in enums.entries) {
      final declaration = RegExp(
        'enum ${RegExp.escape(entry.key)}\\s*\\{(?<body>[^}]*)\\}',
        dotAll: true,
      ).firstMatch(read);
      expect(declaration, isNotNull, reason: '生成 DTO 缺少 ${entry.key}');
      final values = declaration!
          .namedGroup('body')!
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      expect(values, entry.value, reason: '${entry.key} 成员发生漂移');
    }
  });

  test('场馆订单 DTO 不跨 FFI 暴露敏感订单字段', () {
    final match = RegExp(
      r'class BridgeCgyyOrder \{(?<body>.*?)\n\}',
      dotAll: true,
    ).firstMatch(read);
    expect(match, isNotNull);
    final body = match!.namedGroup('body')!;
    for (final forbidden in <String>[
      'tradeNo',
      'phone',
      'payStatus',
      'activityContent',
      'joiners',
      'checkContent',
      'handleReason',
      'remark',
    ]) {
      expect(
        body,
        isNot(contains(forbidden)),
        reason: 'BridgeCgyyOrder 不得暴露 $forbidden',
      );
    }
  });

  test('场馆时段与博雅已选课程 DTO 不暴露内部材料', () {
    final chosen = RegExp(
      r'class BridgeBykcChosenCourse \{(?<body>.*?)\n\}',
      dotAll: true,
    ).firstMatch(read);
    expect(chosen, isNotNull);
    final chosenBody = chosen!.namedGroup('body')!;
    expect(
      chosenBody,
      contains('final int? checkin;'),
      reason: '缺失考勤状态必须跨 Bridge 保留为 null',
    );
    for (final forbidden in <String>[
      'homework',
      'homeworkAttachmentName',
      'homeworkAttachmentPath',
      'signInfo',
      'final bool canSign',
      'final bool canSignOut',
    ]) {
      expect(
        chosenBody,
        isNot(contains(forbidden)),
        reason: 'BridgeBykcChosenCourse 不得暴露 $forbidden',
      );
    }

    final slot = RegExp(
      r'class BridgeCgyySlotStatus \{(?<body>.*?)\n\}',
      dotAll: true,
    ).firstMatch(read);
    expect(slot, isNotNull);
    final slotBody = slot!.namedGroup('body')!;
    expect(slotBody, contains('final int? reservationStatus;'));
    expect(
      slotBody,
      contains('final BridgeActionEligibility reservationEligibility;'),
    );
    expect(
      slotBody,
      contains('final BridgeCgyyReservationTarget? reservationTarget;'),
    );
    expect(slotBody, isNot(contains('isReservable')));
    for (final forbidden in <String>[
      'tradeNo',
      'orderId',
      'useNum',
      'alreadyNum',
      'takeUp',
      'takeUpExplain',
    ]) {
      expect(
        slotBody,
        isNot(contains(forbidden)),
        reason: 'BridgeCgyySlotStatus 不得暴露 $forbidden',
      );
    }
  });

  test('阳光打卡记录 DTO 不暴露图片地址', () {
    final record = RegExp(
      r'class BridgeYgdkRecord \{(?<body>.*?)\n\}',
      dotAll: true,
    ).firstMatch(read);
    expect(record, isNotNull);
    final body = record!.namedGroup('body')!;
    expect(
      body,
      isNot(contains('images')),
      reason: 'BridgeYgdkRecord 不得暴露图片地址列表',
    );
    expect(body, contains('imageCount'));
  });

  test('写入收据不透传完整订单', () {
    expect(write, isNot(contains('final BridgeCgyyOrder? order;')));
  });
}
