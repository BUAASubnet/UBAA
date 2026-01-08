package cn.edu.ubaa.auth

import cn.edu.ubaa.model.dto.CaptchaInfo

/** 登录相关的异常基类 */
open class LoginException(message: String) : Exception(message)

/** 需要验证码时抛出的异常 */
class CaptchaRequiredException(
  val captchaInfo: CaptchaInfo,
  val execution: String,
  message: String = "CAPTCHA verification required",
) : LoginException(message)
