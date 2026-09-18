package cn.edu.ubaa.model.dto

import kotlinx.serialization.Serializable

@Serializable
enum class IhomeScope {
  PUBLIC,
  MINE,
  FOLLOWED,
  APPRAISED,
}

@Serializable
enum class IhomeFilter {
  ALL,
  NEWEST,
  OLDEST,
  REPLIED,
  UNREPLIED,
  REPLY_TIME,
}

@Serializable
data class IhomeQuery(
    val scope: IhomeScope = IhomeScope.PUBLIC,
    val page: Int = 1,
    val limit: Int = 15,
    val keyword: String = "",
    val filter: IhomeFilter = IhomeFilter.ALL,
    val categoryId: Long? = null,
)

@Serializable
data class IhomePage(
    val entries: List<IhomeEntry>,
    val page: Int,
    val lastPage: Int,
    val total: Int,
)

@Serializable
data class IhomeEntry(val appeal: IhomeAppeal, val evaluation: IhomeEvaluation? = null)

@Serializable
data class IhomeAppeal(
    val id: Long,
    val content: String,
    val status: String = "",
    val category: String = "",
    val publishedAt: String = "",
    val departments: List<String> = emptyList(),
    val isMine: Boolean = false,
    val isFollowed: Boolean? = null,
    val isSupported: Boolean? = null,
    val followCount: Int? = null,
    val supportCount: Int? = null,
    val replies: List<IhomeReply> = emptyList(),
    val evaluations: List<IhomeEvaluation> = emptyList(),
    val history: List<IhomeHistory> = emptyList(),
)

@Serializable
data class IhomeReply(val content: String, val department: String, val createdAt: String)

@Serializable data class IhomeHistory(val content: String, val createdAt: String)

@Serializable
data class IhomeEvaluation(
    val id: Long,
    val department: String,
    val speed: Int,
    val satisfaction: Int,
    val degree: Int,
    val content: String,
    val createdAt: String,
)

@Serializable data class IhomeCategory(val id: Long, val name: String)

@Serializable
data class IhomeConfig(
    val supportEnabled: Boolean = false,
    val supportLabel: String = "支持",
    val categories: List<IhomeCategory> = emptyList(),
)

@Serializable
data class IhomeNotice(
    val id: Long,
    val title: String,
    val content: String = "",
    val date: String = "",
)

@Serializable
enum class IhomeReaction {
  FOLLOW,
  SUPPORT,
}

@Serializable data class IhomeReactionRequest(val reaction: IhomeReaction, val enabled: Boolean)

@Serializable
data class IhomeReactionResult(
    val appeal: IhomeAppeal? = null,
    val confirmed: Boolean = false,
    val message: String = "",
)
