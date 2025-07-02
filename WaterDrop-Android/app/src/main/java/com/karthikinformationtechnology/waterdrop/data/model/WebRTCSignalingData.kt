package com.karthikinformationtechnology.waterdrop.data.model

import java.util.*

/**
 * WebRTC Signaling data model for exchanging connection information over Bluetooth
 */
data class WebRTCSignalingData(
    val deviceId: String = UUID.randomUUID().toString(),
    val deviceName: String,
    val type: SignalingType,
    val sdp: String? = null,
    val iceCandidate: String? = null,
    val timestamp: Long = System.currentTimeMillis()
) {
    enum class SignalingType {
        OFFER,
        ANSWER,
        ICE_CANDIDATE
    }
    
    fun toJsonString(): String {
        return """
        {
            "deviceId": "$deviceId",
            "deviceName": "$deviceName",
            "type": "${type.name}",
            "sdp": ${if (sdp != null) "\"$sdp\"" else "null"},
            "iceCandidate": ${if (iceCandidate != null) "\"$iceCandidate\"" else "null"},
            "timestamp": $timestamp
        }
        """.trimIndent()
    }
    
    companion object {
        fun fromJsonString(json: String): WebRTCSignalingData? {
            return try {
                // Simple JSON parsing - in production, use a proper JSON library
                val deviceId = extractJsonValue(json, "deviceId")
                val deviceName = extractJsonValue(json, "deviceName")
                val typeStr = extractJsonValue(json, "type")
                val sdp = extractJsonValue(json, "sdp")?.takeIf { it != "null" }
                val iceCandidate = extractJsonValue(json, "iceCandidate")?.takeIf { it != "null" }
                val timestamp = extractJsonValue(json, "timestamp")?.toLongOrNull() ?: System.currentTimeMillis()
                
                val type = when (typeStr) {
                    "OFFER" -> SignalingType.OFFER
                    "ANSWER" -> SignalingType.ANSWER
                    "ICE_CANDIDATE" -> SignalingType.ICE_CANDIDATE
                    else -> return null
                }
                
                WebRTCSignalingData(
                    deviceId = deviceId ?: return null,
                    deviceName = deviceName ?: return null,
                    type = type,
                    sdp = sdp,
                    iceCandidate = iceCandidate,
                    timestamp = timestamp
                )
            } catch (e: Exception) {
                null
            }
        }
        
        private fun extractJsonValue(json: String, key: String): String? {
            val regex = "\"$key\"\\s*:\\s*\"([^\"]+)\"".toRegex()
            return regex.find(json)?.groupValues?.get(1)
        }
    }
}
