package com.splayer.next.web.api

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Android Keystore 支持的 AES-GCM 加解密，用于流媒体密码等敏感配置。
 *
 * 密钥由系统托管、不可导出；密文格式为 `v1:<base64(iv + ciphertext)>`。
 * 应用卸载或清除数据后密钥失效，配置随之不可解密（符合预期）。
 */
object SecureStore {
    private const val KEYSTORE = "AndroidKeyStore"
    private const val ALIAS = "splayer_config_key"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val IV_SIZE = 12
    private const val TAG_BITS = 128

    private fun secretKey(): SecretKey {
        val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (store.getEntry(ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build()
        )
        return generator.generateKey()
    }

    /** 加密明文，返回带版本前缀的 Base64 密文 */
    fun encrypt(plainText: String): String {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val encrypted = cipher.doFinal(plainText.toByteArray(Charsets.UTF_8))
        val payload = cipher.iv + encrypted
        return "v1:" + Base64.encodeToString(payload, Base64.NO_WRAP)
    }

    /** 解密 encrypt 产出的 Base64 密文 */
    fun decrypt(encoded: String): String {
        val raw = Base64.decode(encoded.removePrefix("v1:"), Base64.NO_WRAP)
        require(raw.size > IV_SIZE) { "密文长度非法" }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(TAG_BITS, raw, 0, IV_SIZE))
        return String(cipher.doFinal(raw, IV_SIZE, raw.size - IV_SIZE), Charsets.UTF_8)
    }
}
