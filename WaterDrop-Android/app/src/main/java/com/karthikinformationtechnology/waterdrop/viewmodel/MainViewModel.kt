package com.karthikinformationtechnology.waterdrop.viewmodel

import android.app.Application
import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.karthikinformationtechnology.waterdrop.connection.ConnectionManager
import com.karthikinformationtechnology.waterdrop.data.model.ConnectionState
import com.karthikinformationtechnology.waterdrop.data.model.DiscoveredDevice
import com.karthikinformationtechnology.waterdrop.data.model.FileTransfer
import com.karthikinformationtechnology.waterdrop.data.model.TransferItem
// import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
// import javax.inject.Inject

// @HiltViewModel
class MainViewModel(
    application: Application
    // @Inject constructor(
    // private val connectionManager: ConnectionManager
) : ViewModel() {

    // Temporary manual initialization
    private val connectionManager = ConnectionManager(application)

    val connectionState: StateFlow<ConnectionState> = connectionManager.connectionState
    val discoveredDevices: StateFlow<List<DiscoveredDevice>> = connectionManager.discoveredDevices
    val connectedDevice: StateFlow<DiscoveredDevice?> = connectionManager.connectedDevice
    val activeTransfers: StateFlow<List<FileTransfer>> = connectionManager.activeTransfers
    val transferHistory: StateFlow<List<TransferItem>> = connectionManager.transferHistory
    val errorMessage: StateFlow<String?> = connectionManager.errorMessage
    val isBluetoothEnabled: StateFlow<Boolean> = connectionManager.isBluetoothEnabled

    fun startDiscovery() {
        connectionManager.startDiscovery()
    }

    fun stopDiscovery() {
        connectionManager.stopDiscovery()
    }

    fun connectToDevice(device: DiscoveredDevice) {
        connectionManager.connectToDevice(device)
    }

    fun disconnectFromDevice() {
        connectionManager.disconnectFromDevice()
    }

    fun sendFiles(uris: List<Uri>) {
        connectionManager.sendFiles(uris)
    }

    fun pauseTransfer(transferId: String) {
        connectionManager.pauseTransfer(transferId)
    }

    fun cancelTransfer(transferId: String) {
        connectionManager.cancelTransfer(transferId)
    }

    fun clearError() {
        connectionManager.clearError()
    }

    fun canTransferFiles(): Boolean {
        return connectionManager.canTransferFiles()
    }

    fun getSignalStrength(rssi: Int): String {
        return connectionManager.getSignalStrength(rssi)
    }

    fun formatFileSize(bytes: Long): String {
        return connectionManager.formatFileSize(bytes)
    }

    fun cleanup() {
        connectionManager.cleanup()
    }

    override fun onCleared() {
        super.onCleared()
        cleanup()
    }
}
