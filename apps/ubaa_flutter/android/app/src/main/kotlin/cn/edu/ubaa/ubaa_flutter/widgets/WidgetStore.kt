package cn.edu.ubaa.ubaa_flutter.widgets

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import java.security.KeyStore
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONObject

/** 组件副本只存AES-GCM密文；随机账号别名、选择和课表都处于同一完整性边界。 */
internal object WidgetStore {
    private const val ALIAS = "ubaa.schedule.widgets.v1"
    private const val LIMIT = 4 * 1024 * 1024

    private fun file(context: Context) =
        AtomicFile(java.io.File(context.noBackupFilesDir, "schedule-widgets.enc"))

    private fun key(create: Boolean): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let {
            return it
        }
        check(create) { "组件安全材料缺失" }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            .apply {
                init(
                    KeyGenParameterSpec.Builder(
                            ALIAS,
                            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                        )
                        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                        .setKeySize(256)
                        .build()
                )
            }
            .generateKey()
    }

    @Synchronized
    fun read(context: Context): JSONObject? {
        val file = file(context)
        if (!file.baseFile.exists()) return null
        val bytes =
            file.openRead().use { stream ->
                val out = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (true) {
                    val n = stream.read(buffer)
                    if (n < 0) break
                    check(out.size() + n <= LIMIT + 64)
                    out.write(buffer, 0, n)
                }
                out.toByteArray()
            }
        check(bytes.size >= 29 && bytes[0] == 1.toByte())
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            key(false),
            GCMParameterSpec(128, bytes.copyOfRange(1, 13)),
        )
        cipher.updateAAD(ALIAS.toByteArray(Charsets.UTF_8))
        return JSONObject(String(cipher.doFinal(bytes.copyOfRange(13, bytes.size)), Charsets.UTF_8))
    }

    @Synchronized
    private fun write(context: Context, value: JSONObject) {
        val plain = value.toString().toByteArray(Charsets.UTF_8)
        check(plain.size <= LIMIT)
        val target = file(context)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key(!target.baseFile.exists()))
        cipher.updateAAD(ALIAS.toByteArray(Charsets.UTF_8))
        val encrypted = byteArrayOf(1) + cipher.iv + cipher.doFinal(plain)
        val output = target.startWrite()
        try {
            output.write(encrypted)
            target.finishWrite(output)
        } catch (e: Exception) {
            target.failWrite(output)
            throw e
        }
        check(read(context)?.toString() == value.toString()) { "组件安全存储读回失败" }
    }

    @Synchronized
    fun begin(context: Context, owner: String?): String {
        val scope = UUID.randomUUID().toString()
        if (owner == null) {
            file(context).delete()
            check(!file(context).baseFile.exists()) { "组件副本未清理" }
            return scope
        }
        require(owner.isNotBlank() && owner.length <= 128)
        val old = read(context)
        val same = old?.optString("owner") == owner
        val state = if (same) old!! else JSONObject().put("owner", owner)
        state.put("scope", scope)
        write(context, state)
        return scope
    }

    @Synchronized
    fun publish(context: Context, scope: String, snapshot: JSONObject): Boolean {
        val parsed = parseWidgetSnapshot(snapshot)
        val state = read(context) ?: return false
        if (state.optString("scope") != scope || state.optString("owner") != parsed.owner)
            return false
        state.put("snapshot", snapshot)
        write(context, state)
        return true
    }

    @Synchronized
    fun select(context: Context, id: Int, owner: String, anchor: String, term: String, week: Int) {
        val state = read(context) ?: return
        if (state.optString("owner") != owner) return
        val choices = state.optJSONObject("choices") ?: JSONObject()
        choices.put(
            id.toString(),
            JSONObject().put("anchor", anchor).put("term", term).put("week", week),
        )
        state.put("choices", choices)
        write(context, state)
    }

    @Synchronized
    fun remove(context: Context, ids: IntArray) {
        val state = read(context) ?: return
        ids.forEach { state.optJSONObject("choices")?.remove(it.toString()) }
        write(context, state)
    }
}
