package cn.edu.ubaa.widget

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import cn.edu.ubaa.repository.ScheduleStore
import cn.edu.ubaa.ui.screens.schedule.OfflineScheduleScreen
import cn.edu.ubaa.ui.theme.UBAATheme

/** 小组件点击直接打开相同周次，断网时也无需等待登录。 */
class ScheduleWidgetActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    enableEdgeToEdge()
    val sameAccount = intent.getStringExtra("owner") == ScheduleStore.account()
    setContent {
      UBAATheme {
        OfflineScheduleScreen(
            onBack = { finish() },
            initialTermCode = if (sameAccount) intent.getStringExtra("term") else null,
            initialWeek = if (sameAccount) intent.getIntExtra("week", -1) else null,
        )
      }
    }
  }
}
