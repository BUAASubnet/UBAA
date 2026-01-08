package cn.edu.ubaa.model.dto

import kotlinx.serialization.Serializable

/**
 * 用户详细信息 DTO。
 *
 * @property idCardType 证件类型。
 * @property idCardTypeName 证件类型名称。
 * @property phone 手机号。
 * @property schoolid 学号。
 * @property name 真实姓名。
 * @property idCardNumber 证件号码。
 * @property email 电子邮箱。
 * @property username 用户名（通常同学校 ID）。
 */
@Serializable
data class UserInfo(
  val idCardType: String? = null,
  val idCardTypeName: String? = null,
  val phone: String? = null,
  val schoolid: String? = null,
  val name: String? = null,
  val idCardNumber: String? = null,
  val email: String? = null,
  val username: String? = null,
)

/** 用户信息响应包装类。 */
@Serializable data class UserInfoResponse(val code: Int, val data: UserInfo? = null)

/** 用户认证状态响应。 */
@Serializable data class UserStatusResponse(val code: Int, val data: UserStatusData)

/**
 * 用户认证状态数据。
 *
 * @property name 姓名。
 * @property schoolid 学号。
 * @property username 用户名。
 */
@Serializable
data class UserStatusData(val name: String, val schoolid: String, val username: String)
