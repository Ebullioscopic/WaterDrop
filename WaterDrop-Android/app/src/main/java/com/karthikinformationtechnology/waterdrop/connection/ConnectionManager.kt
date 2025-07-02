package com.karthikinformationtechnology.waterdrop.connection

import android.content.Context
import android.net.Uri
import android.util.Log
import com.karthikinformationtechnology.waterdrop.data.DatabaseProvider
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
    // Manual initialization with database
    private val database = DatabaseProvider.getDatabase(context)
    private val transferItemDao = database.transferItemDao()
    private val bluetoothManager = WaterDropBluetoothManager(context)
    private val fileTransferManager = FileTransferManager(context, transferItemDao)
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
    val transferHistory: StateFlow<List<TransferItem>> = transferItemDao.getAllTransferItems()
        .stateIn(
            scope = CoroutineScope(Dispatchers.IO + SupervisorJob()),
            started = SharingStarted.Lazily,
            initialValue = emptyList()
        )
        .stateIn(scope, SharingStarted.WhileSubscribed(), emptyList())

    private var discoveryJob: Job? = null
    private var advertisingJob: Job? = null
    private var connectionJob: Job? = null

    init {
        Log.d(TAG, "init: Initializing ConnectionManager")
        try {
            // Monitor Bluetooth state
            scope.launch {
                Log.d(TAG, "init: Starting Bluetooth state monitoring")
                while (isActive) {
                    val wasEnabled = _isBluetoothEnabled.value
                    val isEnabled = bluetoothManager.isBluetoothEnabled()
                    _isBluetoothEnabled.value = isEnabled
                    
                    if (wasEnabled != isEnabled) {
                        Log.d(TAG, "init: Bluetooth state changed: $isEnabled")
                    }
                    delay(1000)
                }
            }
            Log.d(TAG, "init: ConnectionManager initialized successfully")
        } catch (e: Exception) {
            Log.e(TAG, "init: Error initializing ConnectionManager", e)
        }
    }

    fun startDiscovery() {
        Log.d(TAG, "startDiscovery: Starting device discovery")
        
        if (_connectionState.value == ConnectionState.DISCOVERING) {
            Log.w(TAG, "startDiscovery: Discovery already in progress, skipping")
            return
        }

        if (!bluetoothManager.hasBluetoothPermissions()) {
            Log.e(TAG, "startDiscovery: Bluetooth permissions not granted")
            _errorMessage.value = "Bluetooth permissions are required"
            return
        }

        if (!bluetoothManager.isBluetoothEnabled()) {
            Log.e(TAG, "startDiscovery: Bluetooth not enabled")
            _errorMessage.value = "Bluetooth is not enabled"
            return
        }

        Log.d(TAG, "startDiscovery: Prerequisites met, starting discovery and advertising")
        _connectionState.value = ConnectionState.DISCOVERING
        _discoveredDevices.value = emptyList()
        clearError()

        // Start discovery
        discoveryJob = scope.launch {
            try {
                Log.d(TAG, "startDiscovery: Starting Bluetooth discovery")
                bluetoothManager.startDiscovery()
                    .catch { e ->
                        Log.e(TAG, "startDiscovery: Discovery failed", e)
                        _errorMessage.value = "Discovery failed: ${e.message}"
                        _connectionState.value = ConnectionState.ERROR
                    }
                    .collect { devices ->
                        _discoveredDevices.value = devices
                        Log.d(TAG, "startDiscovery: Discovered ${devices.size} devices")
                    }
            } catch (e: Exception) {
                Log.e(TAG, "startDiscovery: Error during discovery", e)
                _errorMessage.value = "Discovery error: ${e.message}"
                _connectionState.value = ConnectionState.ERROR
            }
        }

        // Start advertising
        advertisingJob = scope.launch {
            try {
                Log.d(TAG, "startDiscovery: Starting Bluetooth advertising")
                bluetoothManager.startAdvertising()
                    .catch { e ->
                        Log.e(TAG, "startDiscovery: Advertising failed", e)
                        _errorMessage.value = "Advertising failed: ${e.message}"
                    }
                    .collect { isAdvertising ->
                        Log.d(TAG, "startDiscovery: Advertising status: $isAdvertising")
                    }
            } catch (e: Exception) {
                Log.e(TAG, "startDiscovery: Error during advertising", e)
                _errorMessage.value = "Advertising error: ${e.message}"
            }
        }
    }

    fun stopDiscovery() {
        Log.d(TAG, "stopDiscovery: Stopping device discovery")
        try {
            discoveryJob?.cancel()
            advertisingJob?.cancel()
            bluetoothManager.stopAllOperations()
            
            if (_connectionState.value == ConnectionState.DISCOVERING) {
                Log.d(TAG, "stopDiscovery: Setting connection state to DISCONNECTED")
                _connectionState.value = ConnectionState.DISCONNECTED
            }
            
            _discoveredDevices.value = emptyList()
            Log.d(TAG, "stopDiscovery: Discovery stopped successfully")
        } catch (e: Exception) {
            Log.e(TAG, "stopDiscovery: Error stopping discovery", e)
        }
    }

    fun connectToDevice(device: DiscoveredDevice) {
        Log.d(TAG, "connectToDevice: Attempting to connect to device: ${device.name} (${device.address})")
        
        if (_connectionState.value == ConnectionState.CONNECTING ||
            _connectionState.value == ConnectionState.CONNECTED) {
            Log.w(TAG, "connectToDevice: Already connecting or connected, current state: ${_connectionState.value}")
            return
        }

        Log.d(TAG, "connectToDevice: Setting connection state to CONNECTING")
        _connectionState.value = ConnectionState.CONNECTING
        _connectedDevice.value = device
        clearError()

        connectionJob = scope.launch {
            try {
                Log.d(TAG, "connectToDevice: Starting connection process")
                bluetoothManager.connectToDevice(device)
                    .catch { e ->
                        Log.e(TAG, "connectToDevice: Connection failed to ${device.name}", e)
                        _errorMessage.value = "Connection failed: ${e.message}"
                        _connectionState.value = ConnectionState.ERROR
                        _connectedDevice.value = null
                    }
                    .collect { isConnected ->
                        if (isConnected) {
                            _connectionState.value = ConnectionState.CONNECTED
                            Log.d(TAG, "connectToDevice: Successfully connected to device: ${device.name}")
                            
                            // Stop discovery once connected
                            stopDiscovery()
                        } else {
                            _connectionState.value = ConnectionState.DISCONNECTED
                            _connectedDevice.value = null
                            Log.d(TAG, "connectToDevice: Disconnected from device: ${device.name}")
                        }
                    }
            } catch (e: Exception) {
                Log.e(TAG, "connectToDevice: Error during connection to ${device.name}", e)
                _errorMessage.value = "Connection error: ${e.message}"
                _connectionState.value = ConnectionState.ERROR
                _connectedDevice.value = null
            }
        }
    }

    fun disconnectFromDevice() {
        Log.d(TAG, "disconnectFromDevice: Disconnecting from current device")
        try {
            val currentDevice = _connectedDevice.value
            if (currentDevice != null) {
                Log.d(TAG, "disconnectFromDevice: Disconnecting from ${currentDevice.name}")
            }
            
            connectionJob?.cancel()
            bluetoothManager.stopAllOperations()
            fileTransferManager.cancelAllTransfers()
            
            _connectionState.value = ConnectionState.DISCONNECTED
            _connectedDevice.value = null
            clearError()
            
            Log.d(TAG, "disconnectFromDevice: Successfully disconnected")
        } catch (e: Exception) {
            Log.e(TAG, "disconnectFromDevice: Error during disconnection", e)
        }
    }

    fun sendFiles(uris: List<Uri>) {
        Log.d(TAG, "sendFiles: Attempting to send ${uris.size} files")
        
        val device = _connectedDevice.value
        if (device == null) {
            Log.e(TAG, "sendFiles: No device connected")
            _errorMessage.value = "No device connected"
            return
        }

        if (_connectionState.value != ConnectionState.CONNECTED) {
            Log.e(TAG, "sendFiles: Device not connected, current state: ${_connectionState.value}")
            _errorMessage.value = "Device not connected"
            return
        }

        Log.d(TAG, "sendFiles: Starting file transfer to ${device.name}")
        _connectionState.value = ConnectionState.TRANSFERRING
        clearError()

        try {
            fileTransferManager.sendFiles(
                files = uris,
                deviceName = device.name,
                onProgress = { fileName, progress ->
                    Log.d(TAG, "sendFiles: Transfer progress for $fileName - ${(progress * 100).toInt()}%")
                },
                onComplete = { fileName, success, error ->
                    if (success) {
                        Log.d(TAG, "sendFiles: Successfully transferred $fileName")
                    } else {
                        Log.e(TAG, "sendFiles: Failed to transfer $fileName - $error")
                        if (error != null) {
                            _errorMessage.value = "Transfer failed: $error"
                        }
                    }
                    
                    // Check if all transfers are complete
                    scope.launch {
                        delay(100) // Small delay to ensure state is updated
                        val activeTransferCount = activeTransfers.value.count { it.status == FileTransfer.TransferStatus.TRANSFERRING }
                        Log.d(TAG, "sendFiles: Active transfers remaining: $activeTransferCount")
                        if (activeTransferCount == 0) {
                            Log.d(TAG, "sendFiles: All transfers complete, returning to CONNECTED state")
                            _connectionState.value = ConnectionState.CONNECTED
                        }
                    }
                }
            )
        } catch (e: Exception) {
            Log.e(TAG, "sendFiles: Error initiating file transfer", e)
            _errorMessage.value = "Failed to start transfer: ${e.message}"
            _connectionState.value = ConnectionState.CONNECTED
        }
    }

    fun pauseTransfer(transferId: String) {
        Log.d(TAG, "pauseTransfer: Pausing transfer with ID: $transferId")
        try {
            fileTransferManager.pauseTransfer(transferId)
            Log.d(TAG, "pauseTransfer: Successfully paused transfer $transferId")
        } catch (e: Exception) {
            Log.e(TAG, "pauseTransfer: Error pausing transfer $transferId", e)
        }
    }

    fun cancelTransfer(transferId: String) {
        Log.d(TAG, "cancelTransfer: Cancelling transfer with ID: $transferId")
        try {
            fileTransferManager.cancelTransfer(transferId)
            Log.d(TAG, "cancelTransfer: Successfully cancelled transfer $transferId")
        } catch (e: Exception) {
            Log.e(TAG, "cancelTransfer: Error cancelling transfer $transferId", e)
        }
    }

    fun clearError() {
        if (_errorMessage.value != null) {
            Log.d(TAG, "clearError: Clearing error message: ${_errorMessage.value}")
        }
        _errorMessage.value = null
    }

    fun getTransferStats(): Flow<Triple<Int, Long, Long>> = flow {
        Log.d(TAG, "getTransferStats: Starting transfer stats monitoring")
        try {
            while (currentCoroutineContext().isActive) {
                val count = transferItemDao.getTransferCount()
                val sentBytes = transferItemDao.getTotalSentBytes() ?: 0L
                val receivedBytes = transferItemDao.getTotalReceivedBytes() ?: 0L
                Log.v(TAG, "getTransferStats: Count=$count, Sent=${formatFileSize(sentBytes)}, Received=${formatFileSize(receivedBytes)}")
                emit(Triple(count, sentBytes, receivedBytes))
                delay(1000)
            }
        } catch (e: Exception) {
            Log.e(TAG, "getTransferStats: Error getting transfer stats", e)
        }
    }

    fun cleanup() {
        Log.d(TAG, "cleanup: Cleaning up ConnectionManager resources")
        try {
            scope.cancel()
            bluetoothManager.stopAllOperations()
            fileTransferManager.cancelAllTransfers()
            Log.d(TAG, "cleanup: Successfully cleaned up ConnectionManager")
        } catch (e: Exception) {
            Log.e(TAG, "cleanup: Error during cleanup", e)
        }
    }

    // Helper function to check if device can transfer files
    fun canTransferFiles(): Boolean {
        val canTransfer = _connectionState.value == ConnectionState.CONNECTED && 
               bluetoothManager.isBluetoothEnabled() &&
               bluetoothManager.hasBluetoothPermissions()
        Log.d(TAG, "canTransferFiles: $canTransfer (state=${_connectionState.value}, bt=${bluetoothManager.isBluetoothEnabled()}, perms=${bluetoothManager.hasBluetoothPermissions()})")
        return canTransfer
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
