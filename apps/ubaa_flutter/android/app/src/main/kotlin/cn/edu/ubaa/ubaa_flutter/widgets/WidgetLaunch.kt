package cn.edu.ubaa.ubaa_flutter.widgets

import android.content.Intent

internal const val WIDGET_OPEN = "cn.edu.ubaa.widget.OPEN"
internal const val WIDGET_LINK = "cn.edu.ubaa.widget.LINK"
internal const val WIDGET_LINK_PREFIX = "ubaa://widget/open?"

internal fun widgetRequestCode(appWidgetId: Int, slot: Int): Int = appWidgetId * 16 + slot

internal class WidgetLaunchInbox {
    private var ready = false
    private var pending: String? = null

    fun receive(intent: Intent): String? {
        if (intent.action != WIDGET_OPEN) return null
        val link = intent.getStringExtra(WIDGET_LINK)
        intent.removeExtra(WIDGET_LINK)
        if (link?.startsWith(WIDGET_LINK_PREFIX) == true) return offer(link)
        pending = null
        return null
    }

    fun offer(link: String): String? {
        if (ready) return link
        pending = link
        return null
    }

    fun take(): String? {
        ready = true
        return pending.also { pending = null }
    }

    fun awaitTake() {
        ready = false
    }
}
