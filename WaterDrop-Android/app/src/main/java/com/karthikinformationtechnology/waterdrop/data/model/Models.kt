package com.karthikinformationtechnology.waterdrop.data.model

import androidx.room.Entity
import androidx.room.PrimaryKey
import java.util.Date

@Entity(tableName = "transfer_items")
data class TransferItem(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    val fileName: String,
    val fileSize: Long,
    val transferDate: Date,
    val isIncoming: Boolean,
    val checksum: String,
    val filePath: String,
    val deviceName: String = ""
)

data class DiscoveredDevice(
    val id: String,
    val name: String,
    val address: String,
    val rssi: Int,
    val deviceType: DeviceType = DeviceType.UNKNOWN,
    val isConnectable: Boolean = true,
    val services: List<String> = emptyList()
) {
    enum class DeviceType {
        PHONE, TABLET, LAPTOP, DESKTOP, UNKNOWN
    }
}

data class FileTransfer(
    val id: String,
    val fileName: String,
    val fileSize: Long,
    val progress: Float = 0f,
    val bytesTransferred: Long = 0L,
    val isIncoming: Boolean,
    val status: TransferStatus = TransferStatus.PENDING,
    val checksum: String = "",
    val deviceName: String = "",
    val startTime: Long = System.currentTimeMillis()
) {
    enum class TransferStatus {
        PENDING, TRANSFERRING, COMPLETED, FAILED, PAUSED, CANCELLED
    }
}

enum class ConnectionState {
    DISCONNECTED,
    DISCOVERING,
    CONNECTING,
    CONNECTED,
    TRANSFERRING,
    ERROR
}

data class BluetoothDeviceInfo(
    val name: String,
    val address: String,
    val bondState: Int,
    val deviceClass: Int,
    val type: Int,
    val rssi: Int = -1000
)
