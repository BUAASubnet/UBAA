package cn.edu.ubaa.bykc

/** BYKC 异常基类 */
open class BykcException(message: String, cause: Throwable? = null) : Exception(message, cause)

/** 登录异常 */
class BykcLoginException(message: String, cause: Throwable? = null) : BykcException(message, cause)

/** 选课异常 */
open class BykcSelectException(message: String, cause: Throwable? = null) :
  BykcException(message, cause)

/** 已报名异常 */
class BykcAlreadySelectedException(message: String = "已报名过该课程，请不要重复报名") :
  BykcSelectException(message)

/** 课程已满异常 */
class BykcCourseFullException(message: String = "报名失败，该课程人数已满") : BykcSelectException(message)

/** 课程不可选异常 */
class BykcCourseNotSelectableException(message: String = "选课失败，该课程不可选择") :
  BykcSelectException(message)

/** 会话失效异常 */
class BykcSessionExpiredException(message: String = "您的会话已失效,请重新登录后再试") : BykcException(message)
