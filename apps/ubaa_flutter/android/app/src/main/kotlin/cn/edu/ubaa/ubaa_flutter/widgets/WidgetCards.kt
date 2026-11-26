package cn.edu.ubaa.ubaa_flutter.widgets

import org.json.JSONArray
import org.json.JSONObject

internal interface CardSegment {
    val from: Long
    val state: String
    val message: String?
    val cardLink: String?
}

internal data class AgendaRow(
    val tag: String?,
    val title: String,
    val place: String?,
    val timeText: String,
    val endText: String?,
    val ongoing: Boolean,
    val link: String?,
)

internal data class UpNextSegment(
    override val from: Long,
    override val state: String,
    override val message: String?,
    override val cardLink: String?,
    val primary: AgendaRow?,
    val extraCount: Int,
    val secondary: Secondary?,
) : CardSegment {
    data class Secondary(val kind: String, val text: String, val link: String?)
}

internal data class TodaySegment(
    override val from: Long,
    override val state: String,
    override val message: String?,
    override val cardLink: String?,
    val dayLabel: String?,
    val rows: List<AgendaRow>,
    val dueLine: String?,
) : CardSegment

internal data class TodoSegment(
    override val from: Long,
    override val state: String,
    override val message: String?,
    override val cardLink: String?,
    val smallRow: Row?,
    val smallFooter: String?,
    val mediumRows: List<Row>,
    val mediumFooter: String?,
    val staleText: String?,
) : CardSegment {
    data class Row(
        val kind: String,
        val title: String,
        val leftText: String,
        val sub: String,
        val urgent: Boolean,
        val link: String?,
    )
}

private fun Any?.integer(): Long? = when (this) {
    is Int -> toLong()
    is Long -> this
    else -> null
}

internal fun JSONObject.epochSeconds(key: String): Long? =
    opt(key).integer()?.takeIf { it in (Long.MIN_VALUE / 1000)..(Long.MAX_VALUE / 1000) }

private fun JSONObject.from(): Long = requireNotNull(epochSeconds("from"))
private fun JSONObject.text(key: String): String = get(key) as String
private fun JSONObject.optionalText(key: String): String? = if (isNull(key)) null else text(key)
private fun JSONObject.flag(key: String): Boolean = get(key) as Boolean
private fun JSONObject.optionalObject(key: String): JSONObject? =
    if (isNull(key)) null else getJSONObject(key)

private val itemKinds = setOf("course", "exam", "bykc", "cgyy", "judge", "spoc", "ygdk", "local")

private fun <Row> JSONArray.rows(min: Int, max: Int, parse: (JSONObject) -> Row): List<Row> {
    require(length() in min..max)
    return List(length()) { parse(getJSONObject(it)) }
}

internal fun <Segment : CardSegment> JSONObject.cardTable(
    key: String,
    horizon: Long?,
    parse: (JSONObject) -> Segment,
): List<Segment>? {
    if (horizon == null || isNull(key)) return null
    return runCatching {
        getJSONArray(key).rows(1, 2000, parse).also { table ->
            require(table.last().from < horizon)
            require(table.zipWithNext().all { (left, right) -> left.from < right.from })
        }
    }.getOrNull()
}

private fun JSONObject.agendaRow(): AgendaRow {
    require(text("kind") in itemKinds)
    return AgendaRow(
        optionalText("tag"), text("title"), optionalText("place"), text("timeText"),
        optionalText("endText"), flag("ongoing"), optionalText("link"),
    )
}

internal fun parseUpNext(raw: JSONObject): UpNextSegment = with(raw) {
    val state = text("state")
    require(state in setOf("item", "none", "partial", "termEnd"))
    val primary = optionalObject("primary")
    val message = optionalText("message")
    require(if (state == "item") primary != null else primary == null && !message.isNullOrBlank())
    val count = primary?.run {
        text("dayText")
        text("startText")
        require(isNull("startAt") || epochSeconds("startAt") != null)
        require(isNull("endAt") || epochSeconds("endAt") != null)
        requireNotNull(opt("extraCount").integer()).also { require(it in 0..Int.MAX_VALUE) }.toInt()
    } ?: 0
    val secondary = optionalObject("secondary")?.run {
        val kind = text("kind").also { require(it == "exam" || it == "next") }
        UpNextSegment.Secondary(kind, text("text"), optionalText("link"))
    }
    UpNextSegment(from(), state, message, optionalText("cardLink"), primary?.agendaRow(), count, secondary)
}

internal fun parseToday(raw: JSONObject): TodaySegment = with(raw) {
    val state = text("state")
    require(state in setOf("items", "none", "partial", "termEnd"))
    val message = optionalText("message")
    val dayLabel = optionalText("dayLabel")
    val rows = getJSONArray("rows").rows(0, 8) { row ->
        row.optionalText("rangeText")
        row.agendaRow()
    }
    require(if (state == "items") !dayLabel.isNullOrBlank() && rows.isNotEmpty()
            else rows.isEmpty() && !message.isNullOrBlank())
    TodaySegment(from(), state, message, optionalText("cardLink"), dayLabel, rows, optionalText("dueLine"))
}

private fun JSONObject.todoRow(): TodoSegment.Row = TodoSegment.Row(
    text("kind").also { require(it in itemKinds) }, text("title"), text("leftText"),
    text("sub"), flag("urgent"), optionalText("link"),
)

internal fun parseTodo(raw: JSONObject): TodoSegment = with(raw) {
    val state = text("state")
    require(state in setOf("items", "empty", "noData"))
    val message = optionalText("message")
    val small = optionalObject("smallRow")?.todoRow()
    val medium = getJSONArray("mediumRows").rows(0, 3) { it.todoRow() }
    require(if (state == "items") small != null && medium.isNotEmpty()
            else small == null && medium.isEmpty() && !message.isNullOrBlank())
    TodoSegment(
        from(), state, message, optionalText("cardLink"), small, optionalText("smallFooter"),
        medium, optionalText("mediumFooter"), optionalText("staleText"),
    )
}
