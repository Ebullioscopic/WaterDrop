package com.karthikinformationtechnology.waterdrop.connection

import android.content.Context
import android.net.Uri
import android.util.Log
import com.karthikinformationtechnology.waterdrop.data.database.TransferItemDao
import com.karthikinformationtechnology.waterdrop.data.model.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
// import javax.inject.Inject
// import javax.inject.Singleton

// @Singleton
class ConnectionManager(
    private val context: Context
    // @Inject constructor(
    // private val context: Context,
    // private val bluetoothManager: WaterDropBluetoothManager,
    // private val fileTransferManager: FileTransferManager,
    // private val transferItemDao: TransferItemDao
) {
    // Temporary manual initialization
    private val bluetoothManager = WaterDropBluetoothManager(context)
    private val fileTransferManager = FileTransferManager(context)
    companion object {
        private const val TAG = "ConnectionManager"
    }

    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    private val _connectionState = MutableStateFlow(ConnectionState.DISCONNECTED)
    val connectionState: StateFlow<ConnectionState> = _connectionState.asStateFlow()

    private val _discoveredDevices = MutableStateFlow<List<DiscoveredDevice>>(emptyList())
    val discoveredDevices: StateFlow<List<DiscoveredDevice>> = _discoveredDevices.asStateFlow()

    private val _connectedDevice = MutableStateFlow<DiscoveredDevice?>(null)
    val connectedDevice: StateFlow<DiscoveredDevice?> = _connectedDevice.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    private val _isBluetoothEnabled = MutableStateFlow(false)
    val isBluetoothEnabled: StateFlow<Boolean> = _isBluetoothEnabled.asStateFlow()

    val activeTransfers = fileTransferManager.activeTransfers
    val transferHistory: StateFlow<List<TransferItem>> = MutableStateFlow<List<TransferItem>>(emptyList()).asStateFlow()
    // val transferHistory: StateFlow<List<TransferItem>> = transferItemDao.getAllTransferItems()
        .stateIn(scope, SharingStarted.WhileSubscribed(), emptyList())

    private var discoveryJob: Job? = null
    private var advertisingJob: Job? = null
    private var connectionJob: Job? = null

    init {
        // Monitor Bluetooth state
        scope.launch {
            while (isActive) {
                _isBluetoothEnabled.value = bluetoothManager.isBluetoothEnabled()
                delay(1000)
            }
        }
    }

    fun startDiscovery() {
        if (_connectionState.value == ConnectionState.DISCOVERING) {
            return
        }

        if (!bluetoothManager.hasBluetoothPermissions()) {
            _errorMessage.value = "Bluetooth permissions are required"
            return
        }

        if (!bluetoothManager.isBluetoothEnabled()) {
            _errorMessage.value = "Bluetooth is not enabled"
            return
        }

        _connectionState.value = ConnectionState.DISCOVERING
        _discoveredDevices.value = emptyList()
        clearError()

        // Start discovery
        discoveryJob = scope.launch {
            try {
                bluetoothManager.startDiscovery()
                    .catch { e ->
                        Log.e(TAG, "Discovery failed", e)
                        _errorMessage.value = "Discovery failed: ${e.message}"
                        _connectionState.value = ConnectionState.ERROR
                    }
                    .collect { devices ->
                        _discoveredDevices.value = devices
                        Log.d(TAG, "Discovered ${devices.size} devices")
                    }
            } catch (e: Exception) {
                Log.e(TAG, "Error during discovery", e)
                _errorMessage.value = "Discovery error: ${e.message}"
                _connectionState.value = ConnectionState.ERROR
            }
        }

        // Start advertising
        advertisingJob = scope.launch {
            try {
                bluetoothManager.startAdvertising()
                    .catch { e ->
                        Log.e(TAG, "Advertising failed", e)
                        _errorMessage.value = "Advertising failed: ${e.message}"
                    }
                    .collect { isAdvertising ->
                        Log.d(TAG, "Advertising status: $isAdvertising")
                    }
            } catch (e: Exception) {
                Log.e(TAG, "Error during advertising", e)
                _errorMessage.value = "Advertising error: ${e.message}"
            }
        }
    }

    fun stopDiscovery() {
        discoveryJob?.cancel()
        advertisingJob?.cancel()
        bluetoothManager.stopAllOperations()
        
        if (_connectionState.value == ConnectionState.DISCOVERING) {
            _connectionState.value = ConnectionState.DISCONNECTED
        }
        
        _discoveredDevices.value = emptyList()
    }

    fun connectToDevice(device: DiscoveredDevice) {
        if (_connectionState.value == ConnectionState.CONNECTING ||
            _connectionState.value == ConnectionState.CONNECTED) {
            return
        }

        _connectionState.value = ConnectionState.CONNECTING
        _connectedDevice.value = device
        clearError()

        connectionJob = scope.launch {
            try {
                bluetoothManager.connectToDevice(device)
                    .catch { e ->
                        Log.e(TAG, "Connection failed", e)
                        _errorMessage.value = "Connection failed: ${e.message}"
                        _connectionState.value = ConnectionState.ERROR
                        _connectedDevice.value = null
                    }
                    .collect { isConnected ->
                        if (isConnected) {
                            _connectionState.value = ConnectionState.CONNECTED
                            Log.d(TAG, "Connected to device: ${device.name}")
                            
                            // Stop discovery once connected
                            stopDiscovery()
                        } else {
                            _connectionState.value = ConnectionState.DISCONNECTED
                            _connectedDevice.value = null
                            Log.d(TAG, "Disconnected from device: ${device.name}")
                        }
                    }
            } catch (e: Exception) {
                Log.e(TAG, "Error during connection", e)
                _errorMessage.value = "Connection error: ${e.message}"
                _connectionState.value = ConnectionState.ERROR
                _connectedDevice.value = null
            }
        }
    }

    fun disconnectFromDevice() {
        connectionJob?.cancel()
        bluetoothManager.stopAllOperations()
        fileTransferManager.cancelAllTransfers()
        
        _connectionState.value = ConnectionState.DISCONNECTED
        _connectedDevice.value = null
        clearError()
    }

    fun sendFiles(uris: List<Uri>) {
        val device = _connectedDevice.value
        if (device == null) {
            _errorMessage.value = "No device connected"
            return
        }

        if (_connectionState.value != ConnectionState.CONNECTED) {
            _errorMessage.value = "Device not connected"
            return
        }

        _connectionState.value = ConnectionState.TRANSFERRING
        clearError()

        fileTransferManager.sendFiles(
            files = uris,
            deviceName = device.name,
            onProgress = { fileName, progress ->
                Log.d(TAG, "Transfer progress: $fileName - ${(progress * 100).toInt()}%")
            },
            onComplete = { fileName, success, error ->
                if (!success && error != null) {
                    _errorMessage.value = "Transfer failed: $error"
                }
                
                // Check if all transfers are complete
                scope.launch {
                    delay(100) // Small delay to ensure state is updated
                    if (activeTransfers.value.none { it.status == FileTransfer.TransferStatus.TRANSFERRING }) {
                        _connectionState.value = ConnectionState.CONNECTED
                    }
                }
            }
        )
    }

    fun pauseTransfer(transferId: String) {
        fileTransferManager.pauseTransfer(transferId)
    }

    fun cancelTransfer(transferId: String) {
        fileTransferManager.cancelTransfer(transferId)
    }

    fun clearError() {
        _errorMessage.value = null
    }

    fun getTransferStats(): Flow<Triple<Int, Long, Long>> = flow {
        while (currentCoroutineContext().isActive) {
            val count = 0 // transferItemDao.getTransferCount()
            val sentBytes = 0L // transferItemDao.getTotalSentBytes() ?: 0L
            val receivedBytes = 0L // transferItemDao.getTotalReceivedBytes() ?: 0L
            emit(Triple(count, sentBytes, receivedBytes))
            delay(1000)
        }
    }

    fun cleanup() {
        scope.cancel()
        bluetoothManager.stopAllOperations()
        fileTransferManager.cancelAllTransfers()
    }

    // Helper function to check if device can transfer files
    fun canTransferFiles(): Boolean {
        return _connectionState.value == ConnectionState.CONNECTED && 
               bluetoothManager.isBluetoothEnabled() &&
               bluetoothManager.hasBluetoothPermissions()
    }

    // Get signal strength description
    fun getSignalStrength(rssi: Int): String {
        return when {
            rssi >= -50 -> "Excellent"
            rssi >= -60 -> "Good"
            rssi >= -70 -> "Fair"
            rssi >= -80 -> "Weak"
            else -> "Poor"
        }
    }

    // Format file size for display
    fun formatFileSize(bytes: Long): String {
        val units = arrayOf("B", "KB", "MB", "GB", "TB")
        var size = bytes.toDouble()
        var unitIndex = 0

        while (size >= 1024 && unitIndex < units.size - 1) {
            size /= 1024.0
            unitIndex++
        }

        return if (unitIndex == 0) {
            "${size.toInt()} ${units[unitIndex]}"
        } else {
            "%.1f %s".format(size, units[unitIndex])
        }
    }
}
