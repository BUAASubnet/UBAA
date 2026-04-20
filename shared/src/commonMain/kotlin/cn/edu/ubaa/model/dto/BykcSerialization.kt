package cn.edu.ubaa.model.dto

import kotlinx.datetime.LocalDateTime
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder

/** BYKC 时间字段序列化器：代码中使用 [LocalDateTime]，线上传输仍保持 `yyyy-MM-dd HH:mm:ss`。 */
object BykcLocalDateTimeSerializer : KSerializer<LocalDateTime> {
  override val descriptor: SerialDescriptor =
      PrimitiveSerialDescriptor("BykcLocalDateTime", PrimitiveKind.STRING)

  override fun serialize(encoder: Encoder, value: LocalDateTime) {
    encoder.encodeString(
        buildString {
          append(value.year)
          append('-')
          append((value.month.ordinal + 1).toString().padStart(2, '0'))
          append('-')
          append(value.day.toString().padStart(2, '0'))
          append(' ')
          append(value.hour.toString().padStart(2, '0'))
          append(':')
          append(value.minute.toString().padStart(2, '0'))
          append(':')
          append(value.second.toString().padStart(2, '0'))
        }
    )
  }

  override fun deserialize(decoder: Decoder): LocalDateTime {
    val raw = decoder.decodeString().trim()
    return runCatching { LocalDateTime.parse(raw.replace(' ', 'T')) }
        .getOrElse { throw SerializationException("Invalid BYKC datetime: $raw", it) }
  }
}
