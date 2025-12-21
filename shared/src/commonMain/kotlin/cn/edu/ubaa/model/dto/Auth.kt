package cn.edu.ubaa.model.dto

import kotlinx.serialization.Serializable

@Serializable
data class LoginRequest(
        val username: String,
        val password: String,
        val captcha: String? = null,
        val execution: String? = null,
        val clientId: String? = null // 客户端标识，用于关联 preload 时创建的会话
)

@Serializable data class UserData(val name: String, val schoolid: String)

@Serializable data class LoginResponse(val user: UserData, val token: String)

@Serializable
data class CaptchaInfo(
        val id: String,
        val type: String = "image",
        val imageUrl: String,
        val base64Image: String? = null
)

@Serializable
data class CaptchaRequiredResponse(
        val captcha: CaptchaInfo,
        val execution: String,
        val message: String = "CAPTCHA verification required"
)

/** 登录预加载请求 */
@Serializable
data class LoginPreloadRequest(
        val clientId: String // 客户端标识（设备 ID 或 UUID）
)

/** 登录预加载响应：包含是否需要验证码及相关信息 */
@Serializable
data class LoginPreloadResponse(
        val captchaRequired: Boolean,
        val captcha: CaptchaInfo? = null,
        val execution: String? = null,
        val clientId: String? = null // 返回客户端标识，用于后续登录
)
