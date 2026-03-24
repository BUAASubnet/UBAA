package cn.edu.ubaa.api

import com.russhwolf.settings.Settings

data class StoredCgyyReservationForm(
    val phone: String,
    val theme: String,
    val purposeType: Int?,
    val joinerNum: String,
    val activityContent: String,
    val joiners: String,
    val isPhilosophySocialSciences: Boolean,
    val isOffSchoolJoiner: Boolean,
)

object CgyyReservationFormStore {
  private const val KEY_PHONE = "cgyy_reservation_phone"
  private const val KEY_THEME = "cgyy_reservation_theme"
  private const val KEY_PURPOSE_TYPE = "cgyy_reservation_purpose_type"
  private const val KEY_JOINER_NUM = "cgyy_reservation_joiner_num"
  private const val KEY_ACTIVITY_CONTENT = "cgyy_reservation_activity_content"
  private const val KEY_JOINERS = "cgyy_reservation_joiners"
  private const val KEY_IS_PHILOSOPHY_SOCIAL_SCIENCES = "cgyy_reservation_is_philosophy_social_sciences"
  private const val KEY_IS_OFF_SCHOOL_JOINER = "cgyy_reservation_is_off_school_joiner"

  private var _settings: Settings? = null
  var settings: Settings
    get() = _settings ?: Settings().also { _settings = it }
    set(value) {
      _settings = value
    }

  fun save(form: StoredCgyyReservationForm) {
    settings.putString(KEY_PHONE, form.phone)
    settings.putString(KEY_THEME, form.theme)
    form.purposeType?.let { settings.putInt(KEY_PURPOSE_TYPE, it) } ?: settings.remove(KEY_PURPOSE_TYPE)
    settings.putString(KEY_JOINER_NUM, form.joinerNum)
    settings.putString(KEY_ACTIVITY_CONTENT, form.activityContent)
    settings.putString(KEY_JOINERS, form.joiners)
    settings.putBoolean(
        KEY_IS_PHILOSOPHY_SOCIAL_SCIENCES,
        form.isPhilosophySocialSciences,
    )
    settings.putBoolean(KEY_IS_OFF_SCHOOL_JOINER, form.isOffSchoolJoiner)
  }

  fun get(): StoredCgyyReservationForm? {
    val phone = settings.getStringOrNull(KEY_PHONE) ?: return null
    return StoredCgyyReservationForm(
        phone = phone,
        theme = settings.getString(KEY_THEME, ""),
        purposeType = settings.getIntOrNull(KEY_PURPOSE_TYPE),
        joinerNum = settings.getString(KEY_JOINER_NUM, "1"),
        activityContent = settings.getString(KEY_ACTIVITY_CONTENT, ""),
        joiners = settings.getString(KEY_JOINERS, ""),
        isPhilosophySocialSciences =
            settings.getBoolean(KEY_IS_PHILOSOPHY_SOCIAL_SCIENCES, false),
        isOffSchoolJoiner = settings.getBoolean(KEY_IS_OFF_SCHOOL_JOINER, false),
    )
  }

  fun clear() {
    settings.remove(KEY_PHONE)
    settings.remove(KEY_THEME)
    settings.remove(KEY_PURPOSE_TYPE)
    settings.remove(KEY_JOINER_NUM)
    settings.remove(KEY_ACTIVITY_CONTENT)
    settings.remove(KEY_JOINERS)
    settings.remove(KEY_IS_PHILOSOPHY_SOCIAL_SCIENCES)
    settings.remove(KEY_IS_OFF_SCHOOL_JOINER)
  }
}
