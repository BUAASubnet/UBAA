/// 课堂签到二维码内容及写入二维码的毫秒时间戳。
final class SigninQr {
  const SigninQr({required this.content, required this.timestamp});

  final String content;
  final int timestamp;
}

abstract interface class SigninQrBackend {
  Future<SigninQr> fetchSigninQr(String courseId, Duration offset);
}
