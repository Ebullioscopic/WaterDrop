package com.karthikinformationtechnology.waterdrop.viewmodel

import android.app.Application
import android.net.Uri
import android.util.Log
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

    companion object {
        private const val TAG = "MainViewModel"
    }

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
        Log.d(TAG, "startDiscovery: Starting device discovery")
        try {
            connectionManager.startDiscovery()
            Log.d(TAG, "startDiscovery: Device discovery started successfully")
        } catch (e: Exception) {
            Log.e(TAG, "startDiscovery: Failed to start discovery", e)
        }
    }

    fun stopDiscovery() {
        Log.d(TAG, "stopDiscovery: Stopping device discovery")
        try {
            connectionManager.stopDiscovery()
            Log.d(TAG, "stopDiscovery: Device discovery stopped successfully")
        } catch (e: Exception) {
            Log.e(TAG, "stopDiscovery: Failed to stop discovery", e)
        }
    }

    fun connectToDevice(device: DiscoveredDevice) {
        Log.d(TAG, "connectToDevice: Attempting to connect to device: ${device.name} (${device.address})")
        try {
            connectionManager.connectToDevice(device)
            Log.d(TAG, "connectToDevice: Connection attempt initiated")
        } catch (e: Exception) {
            Log.e(TAG, "connectToDevice: Failed to connect to device", e)
        }
    }

    fun disconnectFromDevice() {
        Log.d(TAG, "disconnectFromDevice: Disconnecting from current device")
        try {
            connectionManager.disconnectFromDevice()
            Log.d(TAG, "disconnectFromDevice: Disconnection initiated")
        } catch (e: Exception) {
            Log.e(TAG, "disconnectFromDevice: Failed to disconnect", e)
        }
    }

    fun sendFiles(uris: List<Uri>) {
        Log.d(TAG, "sendFiles: Sending ${uris.size} files")
        uris.forEachIndexed { index, uri ->
            Log.d(TAG, "sendFiles: File $index: $uri")
        }
        try {
            connectionManager.sendFiles(uris)
            Log.d(TAG, "sendFiles: File transfer initiated")
        } catch (e: Exception) {
            Log.e(TAG, "sendFiles: Failed to send files", e)
        }
    }

    fun pauseTransfer(transferId: String) {
        Log.d(TAG, "pauseTransfer: Pausing transfer: $transferId")
        try {
            connectionManager.pauseTransfer(transferId)
            Log.d(TAG, "pauseTransfer: Transfer paused")
        } catch (e: Exception) {
            Log.e(TAG, "pauseTransfer: Failed to pause transfer", e)
        }
    }

    fun cancelTransfer(transferId: String) {
        Log.d(TAG, "cancelTransfer: Cancelling transfer: $transferId")
        try {
            connectionManager.cancelTransfer(transferId)
            Log.d(TAG, "cancelTransfer: Transfer cancelled")
        } catch (e: Exception) {
            Log.e(TAG, "cancelTransfer: Failed to cancel transfer", e)
        }
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
        Log.d(TAG, "cleanup: Cleaning up MainViewModel")
        try {
            connectionManager.cleanup()
            Log.d(TAG, "cleanup: ConnectionManager cleanup completed")
        } catch (e: Exception) {
            Log.e(TAG, "cleanup: Error during cleanup", e)
        }
    }

    override fun onCleared() {
        super.onCleared()
        cleanup()
    }
}
