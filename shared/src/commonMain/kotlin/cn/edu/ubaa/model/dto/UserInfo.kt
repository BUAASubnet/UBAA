package cn.edu.ubaa.model.dto

import kotlinx.serialization.Serializable

@Serializable
data class UserInfo(
    val idCardType: String? = null,
    val idCardTypeName: String? = null,
    val phone: String? = null,
    val schoolid: String? = null,
    val name: String? = null,
    val idCardNumber: String? = null,
    val email: String? = null,
    val username: String? = null
)

@Serializable
data class UserInfoResponse(
    val code: Int,
    val data: UserInfo? = null
)

@Serializable
data class UserStatusResponse(
    val code: Int,
    val data: UserStatusData
)

@Serializable
data class UserStatusData(
    val name: String,
    val schoolid: String,
    val username: String
)
