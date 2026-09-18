package cn.edu.ubaa.api.feature

import cn.edu.ubaa.api.local.LocalSpocParsers
import cn.edu.ubaa.model.dto.*
import kotlinx.serialization.json.*

class IhomeException(val code: String, message: String) : Exception(message)

/** 仅提取页面所需字段，原始用户对象、联系方式和凭据不进入跨层 DTO。 */
object IhomeProtocol {
  private val json = Json { ignoreUnknownKeys = true }

  fun envelope(text: String): JsonElement {
    val root =
        try {
          json.parseToJsonElement(text) as? JsonObject
        } catch (_: Exception) {
          null
        } ?: throw IhomeException("ihome_protocol", "ihome 返回了无法识别的数据")
    if (root.number("code") != 20000L || root["success"] != JsonPrimitive(true)) {
      throw IhomeException("ihome_business", "ihome 暂时无法完成此操作，请刷新后重试")
    }
    return root["data"] ?: throw IhomeException("ihome_protocol", "ihome 响应缺少数据")
  }

  fun page(data: JsonElement, scope: IhomeScope): IhomePage {
    val obj = data.asObject()
    val rows = obj["data"] as? JsonArray ?: invalid()
    return IhomePage(
        entries =
            rows.map { row ->
              val item = row.asObject()
              if (scope == IhomeScope.APPRAISED)
                  IhomeEntry(appeal(item["appeal"] ?: invalid()), evaluation(item))
              else IhomeEntry(appeal(item))
            },
        page = obj.integer("current_page") ?: invalid(),
        lastPage = obj.integer("last_page") ?: invalid(),
        total = obj.integer("total") ?: invalid(),
    )
  }

  fun appeal(data: JsonElement): IhomeAppeal {
    val o = data.asObject()
    val restart = o.integer("is_restart") ?: 0
    return IhomeAppeal(
        id = o.number("id") ?: invalid(),
        content = plain(o.text("content")),
        status = o.text("publish_status_text"),
        category = (o["sqlb"] as? JsonObject)?.text("type_name").orEmpty(),
        publishedAt = o.text("publish_date").ifBlank { o.text("created_at") },
        departments = o.objects("departments").map { it.text("name") },
        isMine = o.integer("is_user") == 1,
        isFollowed = o.integer("is_follow")?.let { it == 1 },
        isSupported = o.integer("is_praise")?.let { it == 1 },
        followCount = o.integer("follow_count"),
        supportCount = o.integer("praise_count"),
        replies =
            o.objects("appeal_reply").map {
              IhomeReply(
                  plain(it.text("content")),
                  (it["department"] as? JsonObject)?.text("name").orEmpty(),
                  it.text("created_at"),
              )
            },
        evaluations = o.objects("appraise").map(::evaluation),
        history =
            o.objects("change_history")
                .filter { it.integer("restart") == restart }
                .map { IhomeHistory(plain(it.text("contents")), it.text("created_at")) },
    )
  }

  fun config(settings: JsonElement, types: JsonElement): IhomeConfig {
    val values =
        (settings as? JsonArray ?: invalid())
            .map { it.asObject() }
            .associate { it.text("key") to it.text("value") }
    return IhomeConfig(
        supportEnabled = values["fabulous"] == "1",
        supportLabel = values["fabulous_show"]?.takeIf { it.isNotBlank() } ?: "支持",
        categories =
            types.asObject().objects("SQLB").map {
              IhomeCategory(it.number("id") ?: invalid(), it.text("type_name"))
            },
    )
  }

  fun notices(data: JsonElement): List<IhomeNotice> =
      (data as? JsonArray ?: invalid()).map(::notice)

  fun notice(data: JsonElement): IhomeNotice {
    val o = data.asObject()
    return IhomeNotice(
        o.number("id") ?: invalid(),
        o.text("title"),
        plain(o.text("content")),
        o.text("date"),
    )
  }

  private fun evaluation(o: JsonObject) =
      IhomeEvaluation(
          id = o.number("id") ?: invalid(),
          department = (o["department"] as? JsonObject)?.text("name").orEmpty(),
          speed = o.integer("speed") ?: 0,
          satisfaction = o.integer("satisfaction") ?: 0,
          degree = o.integer("degree") ?: 0,
          content = plain(o.text("content")),
          createdAt = o.text("created_at"),
      )

  private fun plain(value: String) = LocalSpocParsers.toPlainText(value).orEmpty()

  private fun JsonElement.asObject(): JsonObject = this as? JsonObject ?: invalid()

  private fun JsonObject.text(key: String) = (get(key) as? JsonPrimitive)?.contentOrNull.orEmpty()

  private fun JsonObject.number(key: String) = (get(key) as? JsonPrimitive)?.longOrNull

  private fun JsonObject.integer(key: String) = (get(key) as? JsonPrimitive)?.intOrNull

  private fun JsonObject.objects(key: String): List<JsonObject> =
      when (val value = get(key)) {
        null,
        JsonNull -> emptyList()
        is JsonArray -> value.map { it.asObject() }
        else -> invalid()
      }

  private fun invalid(): Nothing = throw IhomeException("ihome_protocol", "ihome 数据结构发生变化，请稍后重试")
}
