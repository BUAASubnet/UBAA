import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/write/cgyy_validation.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

CgyyReserveAction _action(int timeId, int ordinal) => CgyyReserveAction(
  venueSiteId: 323,
  reservationDate: '2026-11-27',
  spaceId: 70,
  timeId: timeId,
  venueSpaceGroupId: null,
  timeOrdinal: ordinal,
  eligibility: ActionEligibility.allowed,
);

final _actions = [_action(13, 4), _action(9, 0), _action(11, 2)];

void main() {
  test('杭州同一房间可提交三个不相邻时段，并按时段顺序排列', () {
    final input = validateHangzhouCgyySubmitInput(
      HangzhouCgyySubmitInput(
        actions: _actions,
        phone: '10000000000',
        captcha: const HangzhouCgyyCaptcha(
          token: 'captcha-token',
          secretKey: 'captcha-secret-key',
          originalImageBase64: '',
          jigsawImageBase64: '',
        ),
        sliderOffsetX: 100,
        tapX: 1,
        tapY: 1,
      ),
    );
    expect(input.actions.map((a) => a.timeId), [9, 11, 13]);
  });

  test('北京研讨室仍然最多两个相邻时段', () {
    expect(
      () => validateCgyySubmitInput(
        CgyySubmitInput(
          actions: _actions,
          phone: '10000000000',
          theme: '合成主题',
          purposeType: 9,
          joinerNum: 3,
          activityContent: '合成内容',
          joiners: '合成参与人',
          isPhilosophySocialSciences: false,
          isOffSchoolJoiner: false,
        ),
      ),
      throwsA(isA<BackendException>()),
    );
  });
}
