package cn.edu.ubaa.model.dto

import kotlinx.serialization.Serializable

/**
 * 登录请求 DTO。
 * @property username 用户名（通常为学号）。
 * @property password 登录密码。
 * @property captcha 验证码（如果需要）。
 * @property execution SSO 认证流程的执行标识。
 * @property clientId 客户端唯一标识，用于关联预加载创建的会话。
 */
@Serializable
data class LoginRequest(
        val username: String,
        val password: String,
        val captcha: String? = null,
        val execution: String? = null,
        val clientId: String? = null // 客户端标识，用于关联 preload 时创建的会话
)

/**
 * 用户基本身份数据。
 * @property name 真实姓名。
 * @property schoolid 学号。
 */
@Serializable data class UserData(val name: String, val schoolid: String)

/**
 * 登录成功响应。
 * @property user 用户数据。
 * @property token 颁发的 JWT 认证令牌。
 */
@Serializable data class LoginResponse(val user: UserData, val token: String)

/**
 * 验证码信息。
 * @property id 验证码唯一 ID。
 * @property type 验证码类型，默认为 "image"。
 * @property imageUrl 验证码图片的 URL。
 * @property base64Image 验证码图片的 Base64 编码数据。
 */
@Serializable
data class CaptchaInfo(
        val id: String,
        val type: String = "image",
        val imageUrl: String,
        val base64Image: String? = null
)

/**
 * 登录时提示需要验证码的响应。
 * @property captcha 验证码详细信息。
 * @property execution 当前 SSO 流程的执行标识。
 * @property message 提示消息。
 */
@Serializable
data class CaptchaRequiredResponse(
        val captcha: CaptchaInfo,
        val execution: String,
        val message: String = "需要验证码验证"
)

/**
 * 登录预加载请求。
 * @property clientId 客户端标识（如设备 ID 或 UUID）。
 */
@Serializable
data class LoginPreloadRequest(
        val clientId: String // 客户端标识（设备 ID 或 UUID）
)

/**
 * 登录预加载响应。
 * 包含是否需要验证码及相关登录流程信息。如果用户已通过 session 登录，则直接返回 token。
 * @property captchaRequired 是否需要输入验证码。
 * @property captcha 验证码信息（若需要）。
 * @property execution SSO 执行标识。
 * @property clientId 返回的客户端标识。
 * @property token 已登录用户的 JWT 令牌（若适用）。
 * @property userData 已登录用户的基本信息（若适用）。
 */
@Serializable
data class LoginPreloadResponse(
        val captchaRequired: Boolean,
        val captcha: CaptchaInfo? = null,
        val execution: String? = null,
        val clientId: String? = null, // 返回客户端标识，用于后续登录
        val token: String? = null, // 如果已登录，直接返回 JWT
        val userData: UserData? = null // 如果已登录，直接返回用户信息
)