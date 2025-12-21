package cn.edu.ubaa.bykc

import java.security.KeyFactory
import java.security.MessageDigest
import java.security.Security
import java.security.spec.X509EncodedKeySpec
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.spec.SecretKeySpec
import org.bouncycastle.jce.provider.BouncyCastleProvider

/** BYKC 加密模块，RSA+AES 混合加密 */
object BykcCrypto {

    init {
        // 注册 BouncyCastle 提供者，兼容加密算法
        if (Security.getProvider(BouncyCastleProvider.PROVIDER_NAME) == null) {
            Security.addProvider(BouncyCastleProvider())
        }
    }

    /** BYKC系统的1024位RSA公钥 (Base64编码的DER格式) 从 app.js 中提取 */
    private const val RSA_PUBLIC_KEY_BASE64 =
            "MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDlHMQ3B5GsWnCe7Nlo1YiG/YmHdlOiKOST5aRm4iaqYSvhvWmwcigoyWTM+8bv2+sf6nQBRDWTY4KmNV7DBk1eDnTIQo6ENA31k5/tYCLEXgjPbEjCK9spiyB62fCT6cqOhbamJB0lcDJRO6Vo1m3dy+fD0jbxfDVBBNtyltIsDQIDAQAB"

    /** 用于生成随机AES密钥的字符集 */
    private const val KEY_CHARS = "ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678"

    /** AES密钥长度 */
    private const val AES_KEY_LENGTH = 16

    /** 加载RSA公钥 */
    private val rsaPublicKey by lazy {
        val keyBytes = Base64.getDecoder().decode(RSA_PUBLIC_KEY_BASE64)
        val keySpec = X509EncodedKeySpec(keyBytes)
        val keyFactory = KeyFactory.getInstance("RSA")
        keyFactory.generatePublic(keySpec)
    }

    /** 生成随机的16字节AES密钥 */
    fun generateAesKey(): ByteArray {
        return (1..AES_KEY_LENGTH)
                .map { KEY_CHARS.random() }
                .joinToString("")
                .toByteArray(Charsets.UTF_8)
    }

    /**
     * 使用AES-ECB模式加密数据
     *
     * @param data 待加密的数据
     * @param key AES密钥 (16字节)
     * @return 加密后的数据
     */
    fun aesEncrypt(data: ByteArray, key: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/ECB/PKCS5Padding")
        val secretKey = SecretKeySpec(key, "AES")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey)
        return cipher.doFinal(data)
    }

    /**
     * 使用AES-ECB模式解密数据
     *
     * @param data 待解密的数据
     * @param key AES密钥 (16字节)
     * @return 解密后的数据
     */
    fun aesDecrypt(data: ByteArray, key: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/ECB/PKCS5Padding")
        val secretKey = SecretKeySpec(key, "AES")
        cipher.init(Cipher.DECRYPT_MODE, secretKey)
        return cipher.doFinal(data)
    }

    /**
     * 使用RSA公钥加密数据
     *
     * @param data 待加密的数据
     * @return Base64编码的加密结果
     */
    fun rsaEncrypt(data: ByteArray): String {
        val cipher = Cipher.getInstance("RSA/ECB/PKCS1Padding", "BC")
        cipher.init(Cipher.ENCRYPT_MODE, rsaPublicKey)
        val encrypted = cipher.doFinal(data)
        return Base64.getEncoder().encodeToString(encrypted)
    }

    /**
     * 对数据进行SHA1签名
     *
     * @param data 待签名的数据
     * @return 小写的十六进制签名字符串
     */
    fun sha1Sign(data: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-1")
        val hash = digest.digest(data)
        return hash.joinToString("") { "%02x".format(it) }
    }

    /**
     * 加密请求数据并生成所需的请求头参数
     *
     * @param jsonData JSON格式的请求数据
     * @return EncryptedRequest 包含加密数据和请求头参数
     */
    fun encryptRequest(jsonData: String): EncryptedRequest {
        val dataBytes = jsonData.toByteArray(Charsets.UTF_8)

        // 生成随机AES密钥
        val aesKey = generateAesKey()

        // RSA加密AES密钥
        val ak = rsaEncrypt(aesKey)

        // 计算数据签名并RSA加密
        val dataSign = sha1Sign(dataBytes)
        val sk = rsaEncrypt(dataSign.toByteArray(Charsets.UTF_8))

        // AES加密请求数据
        val encryptedData = aesEncrypt(dataBytes, aesKey)
        val encryptedDataBase64 = Base64.getEncoder().encodeToString(encryptedData)

        // 时间戳
        val ts = System.currentTimeMillis().toString()

        return EncryptedRequest(
                encryptedData = encryptedDataBase64,
                ak = ak,
                sk = sk,
                ts = ts,
                aesKey = aesKey
        )
    }

    /**
     * 解密响应数据
     *
     * @param responseBase64 Base64编码的加密响应
     * @param aesKey 用于加密请求时生成的AES密钥
     * @return 解密后的JSON字符串
     */
    fun decryptResponse(responseBase64: String, aesKey: ByteArray): String {
        val encryptedBytes = Base64.getDecoder().decode(responseBase64)
        val decryptedBytes = aesDecrypt(encryptedBytes, aesKey)
        return String(decryptedBytes, Charsets.UTF_8)
    }

    /** 加密请求的封装类 */
    data class EncryptedRequest(
            /** Base64编码的AES加密数据 */
            val encryptedData: String,
            /** RSA加密的AES密钥 (Base64) */
            val ak: String,
            /** RSA加密的数据签名 (Base64) */
            val sk: String,
            /** 时间戳 */
            val ts: String,
            /** 原始AES密钥 (用于解密响应) */
            val aesKey: ByteArray
    )
}
