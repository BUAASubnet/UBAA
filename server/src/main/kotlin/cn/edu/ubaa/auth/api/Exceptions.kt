package cn.edu.ubaa.auth

import cn.edu.ubaa.model.dto.CaptchaInfo

/** 登录相关的异常基类 */
open class LoginException(message: String) : Exception(message)

/** 需要验证码时抛出的异常 */
class CaptchaRequiredException(
    val captchaInfo: CaptchaInfo,
    val execution: String,
    message: String = "需要验证码",
) : LoginException(message)

/** 当前账号类型暂不支持访问该接口。 */
class UnsupportedAcademicPortalException(
    message: String = "当前账号类型暂不支持该接口",
) : Exception(message)
