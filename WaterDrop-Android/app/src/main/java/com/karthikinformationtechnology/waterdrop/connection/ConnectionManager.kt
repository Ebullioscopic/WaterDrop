package com.karthikinformationtechnology.waterdrop.connection

import android.content.Context
import android.net.Uri
import android.os.Environment
import android.util.Log
import com.karthikinformationtechnology.waterdrop.data.DatabaseProvider
import com.karthikinformationtechnology.waterdrop.data.database.TransferItemDao
import com.karthikinformationtechnology.waterdrop.data.model.*
import com.karthikinformationtechnology.waterdrop.webrtc.WebRTCManager
import com.karthikinformationtechnology.waterdrop.webrtc.WebRTCConnectionState
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import java.io.File
import java.security.MessageDigest
import java.util.*
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
    private val webRTCManager = WebRTCManager(context)
    companion object {
        private const val TAG = "WaterDrop_ConnectionManager"
        private const val VERBOSE_LOGGING = true
        
        private fun logVerbose(message: String) {
            if (VERBOSE_LOGGING) {
                Log.v(TAG, "🔍 $message")
            }
        }
        
        private fun logInfo(message: String) {
            Log.i(TAG, "ℹ️ $message")
        }
        
        private fun logWarning(message: String) {
            Log.w(TAG, "⚠️ $message")
        }
        
        private fun logError(message: String, throwable: Throwable? = null) {
            Log.e(TAG, "❌ $message", throwable)
        }
        
        private fun logSuccess(message: String) {
            Log.d(TAG, "✅ $message")
        }
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
    
    private val _webRTCConnectionState = MutableStateFlow(WebRTCConnectionState.NEW)
    val webRTCConnectionState: StateFlow<WebRTCConnectionState> = _webRTCConnectionState.asStateFlow()
    
    // Helper methods to update states with logging
    private fun updateConnectionState(newState: ConnectionState) {
        val oldState = _connectionState.value
        _connectionState.value = newState
        logInfo("Connection state changed: $oldState → $newState")
    }
    
    private fun updateConnectedDevice(device: DiscoveredDevice?) {
        val oldDevice = _connectedDevice.value
        _connectedDevice.value = device
        if (device != null) {
            logSuccess("Connected device updated: ${device.name} (${device.address}) - Signal: ${device.rssi}dBm")
        } else {
            logInfo("Connected device cleared (was: ${oldDevice?.name})")
        }
    }
    
    private fun updateWebRTCState(newState: WebRTCConnectionState) {
        val oldState = _webRTCConnectionState.value
        _webRTCConnectionState.value = newState
        logInfo("WebRTC state changed: $oldState → $newState")
    }

    private val _activeTransfers = MutableStateFlow<List<ActiveTransfer>>(emptyList())
    val activeTransfers: StateFlow<List<ActiveTransfer>> = _activeTransfers.asStateFlow()

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
        logInfo("🚀 Initializing ConnectionManager")
        logInfo("📱 Android Version: ${android.os.Build.VERSION.RELEASE} (API ${android.os.Build.VERSION.SDK_INT})")
        logInfo("📦 Package: ${context.packageName}")
        
        try {
            // Monitor Bluetooth state
            scope.launch {
                logVerbose("Starting Bluetooth state monitoring coroutine")
                while (isActive) {
                    val wasEnabled = _isBluetoothEnabled.value
                    val isEnabled = bluetoothManager.isBluetoothEnabled()
                    _isBluetoothEnabled.value = isEnabled
                    
                    if (wasEnabled != isEnabled) {
                        if (isEnabled) {
                            logSuccess("📶 Bluetooth enabled")
                        } else {
                            logWarning("📶 Bluetooth disabled")
                        }
                    }
                    delay(1000)
                }
            }
            
            // Monitor WebRTC connection state
            scope.launch {
                logVerbose("Starting WebRTC state monitoring coroutine")
                webRTCManager.connectionState.collect { state ->
                    Log.d(TAG, "init: WebRTC connection state: $state")
                    _webRTCConnectionState.value = state
                    
                    // Update main connection state based on WebRTC state
                    when (state) {
                        WebRTCConnectionState.CONNECTED -> {
                            _connectionState.value = ConnectionState.CONNECTED
                        }
                        WebRTCConnectionState.CONNECTING -> {
                            _connectionState.value = ConnectionState.CONNECTING
                        }
                        WebRTCConnectionState.DISCONNECTED,
                        WebRTCConnectionState.FAILED,
                        WebRTCConnectionState.CLOSED -> {
                            _connectionState.value = ConnectionState.DISCONNECTED
                        }
                        else -> {
                            // Keep current state for other states
                        }
                    }
                }
            }
            
            // Set up WebRTC signaling callback
            logVerbose("Setting up WebRTC signaling callback")
            bluetoothManager.setSignalingCallback { signalingData ->
                logInfo("📡 Received WebRTC signaling data: ${signalingData.type}")
                handleWebRTCSignaling(signalingData)
            }
            
            // Handle received files from WebRTC
            scope.launch {
                logVerbose("Starting WebRTC received files monitoring coroutine")
                webRTCManager.receivedFiles.collect { receivedFile ->
                    logInfo("📥 Received file from WebRTC: ${receivedFile.fileName} (${receivedFile.data.size} bytes)")
                    handleReceivedFile(receivedFile)
                }
            }
            
            logSuccess("🎉 ConnectionManager initialized successfully")
        } catch (e: Exception) {
            logError("💥 Error initializing ConnectionManager", e)
        }
    }

    fun startDiscovery() {
        logInfo("🔍 Starting device discovery")
        logVerbose("Current connection state: ${_connectionState.value}")
        
        if (_connectionState.value == ConnectionState.DISCOVERING) {
            logWarning("Discovery already in progress, stopping first")
            stopDiscovery()
        }

        if (!bluetoothManager.hasBluetoothPermissions()) {
            logError("Bluetooth permissions not granted")
            _errorMessage.value = "Bluetooth permissions are required"
            return
        }

        if (!bluetoothManager.isBluetoothEnabled()) {
            logError("Bluetooth not enabled")
            _errorMessage.value = "Bluetooth is not enabled"
            return
        }

        logSuccess("Prerequisites met - starting discovery and advertising")
        updateConnectionState(ConnectionState.DISCOVERING)
        _discoveredDevices.value = emptyList()
        clearError()

        // Cancel any existing jobs first
        discoveryJob?.cancel()
        advertisingJob?.cancel()

        // Start discovery with better error handling
        discoveryJob = scope.launch {
            try {
                Log.d(TAG, "startDiscovery: Starting Bluetooth discovery coroutine")
                bluetoothManager.startDiscovery()
                    .catch { e ->
                        Log.e(TAG, "startDiscovery: Discovery failed", e)
                        if (e !is CancellationException) {
                            _errorMessage.value = "Discovery failed: ${e.message}"
                            _connectionState.value = ConnectionState.ERROR
                        }
                    }
                    .collect { devices ->
                        _discoveredDevices.value = devices
                        Log.d(TAG, "startDiscovery: Discovered ${devices.size} devices")
                    }
            } catch (e: CancellationException) {
                Log.d(TAG, "startDiscovery: Discovery coroutine cancelled")
                throw e // Re-throw cancellation
            } catch (e: Exception) {
                Log.e(TAG, "startDiscovery: Error during discovery", e)
                _errorMessage.value = "Discovery error: ${e.message}"
                _connectionState.value = ConnectionState.ERROR
            }
        }

        // Start advertising with better error handling  
        advertisingJob = scope.launch {
            try {
                Log.d(TAG, "startDiscovery: Starting Bluetooth advertising coroutine")
                bluetoothManager.startAdvertising()
                    .catch { e ->
                        Log.e(TAG, "startDiscovery: Advertising failed", e)
                        if (e !is CancellationException) {
                            _errorMessage.value = "Advertising failed: ${e.message}"
                        }
                    }
                    .collect { isAdvertising ->
                        Log.d(TAG, "startDiscovery: Advertising status: $isAdvertising")
                    }
            } catch (e: CancellationException) {
                Log.d(TAG, "startDiscovery: Advertising coroutine cancelled")
                throw e // Re-throw cancellation
            } catch (e: Exception) {
                Log.e(TAG, "startDiscovery: Error during advertising", e)
                if (e !is CancellationException) {
                    _errorMessage.value = "Advertising error: ${e.message}"
                }
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
        logInfo("🤝 Attempting to connect to device: ${device.name} (${device.address}) - Signal: ${device.rssi}dBm")
        
        if (_connectionState.value == ConnectionState.CONNECTING ||
            _connectionState.value == ConnectionState.CONNECTED) {
            logWarning("Already connecting or connected, current state: ${_connectionState.value}")
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
        logInfo("📤 Attempting to send ${uris.size} files via WebRTC")
        
        // Log file URIs for debugging
        uris.forEachIndexed { index, uri ->
            logVerbose("File $index: $uri")
        }
        
        val device = _connectedDevice.value
        if (device == null) {
            logError("No device connected for file transfer")
            _errorMessage.value = "No device connected"
            return
        }

        logInfo("📱 Connected device: ${device.name} (${device.address}) - Signal: ${device.rssi}dBm")

        if (_webRTCConnectionState.value != WebRTCConnectionState.CONNECTED) {
            logError("WebRTC not connected, current state: ${_webRTCConnectionState.value}")
            _errorMessage.value = "WebRTC connection not established"
            return
        }

        logSuccess("🚀 Starting WebRTC file transfer to ${device.name}")
        updateConnectionState(ConnectionState.TRANSFERRING)
        clearError()

        scope.launch(Dispatchers.IO) {
            try {
                logInfo("🔄 Processing ${uris.size} files for transfer")
                uris.forEachIndexed { index, uri ->
                    logVerbose("Processing file ${index + 1}/${uris.size}: $uri")
                    val fileName = getFileName(uri)
                    val fileData = readFileData(uri)
                    
                    if (fileData != null) {
                        logInfo("📋 File details: $fileName (${fileData.size} bytes)")
                        
                        // Create and add active transfer
                        val transferId = UUID.randomUUID().toString()
                        logVerbose("Generated transfer ID: $transferId")
                        
                        val activeTransfer = ActiveTransfer(
                            id = transferId,
                            fileName = fileName,
                            fileSize = fileData.size.toLong(),
                            progress = 0f,
                            isIncoming = false
                        )
                        
                        logVerbose("Adding active transfer to UI state")
                        scope.launch(Dispatchers.Main) {
                            _activeTransfers.value = _activeTransfers.value + activeTransfer
                        }
                        
                        logInfo("📡 Initiating WebRTC file send for: $fileName")
                        webRTCManager.sendFile(
                            fileData = fileData,
                            fileName = fileName,
                            onProgress = { progress ->
                                val progressPercent = (progress * 100).toInt()
                                logVerbose("📊 Transfer progress for $fileName: $progressPercent%")
                                
                                // Update active transfer progress on main thread
                                scope.launch(Dispatchers.Main) {
                                    val updated = _activeTransfers.value.map { transfer ->
                                        if (transfer.id == transferId) {
                                            transfer.copy(progress = progress)
                                        } else transfer
                                    }
                                    _activeTransfers.value = updated
                                    logVerbose("🔄 Updated UI progress for $fileName to $progressPercent%")
                                }
                            }
                        )
                        
                        logSuccess("✅ File sent successfully: $fileName")
                        
                        // Mark transfer as complete and remove from active transfers
                        scope.launch(Dispatchers.Main) {
                            _activeTransfers.value = _activeTransfers.value.filter { it.id != transferId }
                            logVerbose("🗑️ Removed completed transfer from active list: $fileName")
                        }
                        
                        // Calculate checksum and save to transfer history
                        val checksum = calculateSHA256(fileData)
                        logVerbose("🔐 File checksum calculated: $checksum")
                        
                        val filePath = getExternalFilePath(fileName)
                        logInfo("💾 Saving transfer history - File: $fileName, Size: ${fileData.size}, Path: $filePath")
                        
                        val transferItem = TransferItem(
                            fileName = fileName,
                            fileSize = fileData.size.toLong(),
                            transferDate = java.util.Date(),
                            isIncoming = false,
                            checksum = checksum,
                            filePath = filePath
                        )
                        transferItemDao.insertTransferItem(transferItem)
                        
                    } else {
                        Log.e(TAG, "sendFiles: Failed to read file data for $fileName")
                    }
                }
                
                scope.launch(Dispatchers.Main) {
                    _connectionState.value = ConnectionState.CONNECTED
                    Log.d(TAG, "sendFiles: All files sent successfully")
                }
                
            } catch (e: Exception) {
                Log.e(TAG, "sendFiles: Error during file transfer", e)
                scope.launch(Dispatchers.Main) {
                    _errorMessage.value = "File transfer failed: ${e.message}"
                    _connectionState.value = ConnectionState.CONNECTED
                }
            }
        }
    }
    
    private fun getFileName(uri: Uri): String {
        return try {
            context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIndex = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                    if (nameIndex >= 0) cursor.getString(nameIndex) else "unknown_file"
                } else "unknown_file"
            } ?: "unknown_file"
        } catch (e: Exception) {
            Log.e(TAG, "getFileName: Error getting file name", e)
            "unknown_file"
        }
    }
    
    private fun readFileData(uri: Uri): ByteArray? {
        return try {
            context.contentResolver.openInputStream(uri)?.use { inputStream ->
                inputStream.readBytes()
            }
        } catch (e: Exception) {
            Log.e(TAG, "readFileData: Error reading file data", e)
            null
        }
    }
    
    private fun calculateSHA256(data: ByteArray): String {
        return try {
            val digest = java.security.MessageDigest.getInstance("SHA-256")
            digest.digest(data).joinToString("") { "%02x".format(it) }
        } catch (e: Exception) {
            Log.e(TAG, "calculateSHA256: Error calculating checksum", e)
            ""
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
            webRTCManager.cleanup()
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
    
    // WebRTC Signaling Handler
    private fun handleWebRTCSignaling(signalingData: WebRTCSignalingData) {
        Log.d(TAG, "handleWebRTCSignaling: Received ${signalingData.type} from ${signalingData.deviceName}")
        
        when (signalingData.type) {
            WebRTCSignalingData.SignalingType.OFFER -> {
                Log.d(TAG, "handleWebRTCSignaling: Processing WebRTC offer")
                signalingData.sdp?.let { sdp ->
                    webRTCManager.createAnswer(
                        remoteOffer = sdp,
                        onLocalDescription = { answerSdp ->
                            Log.d(TAG, "handleWebRTCSignaling: WebRTC answer created, sending back")
                            val answerSignaling = WebRTCSignalingData(
                                deviceName = android.os.Build.MODEL ?: "Android Device",
                                type = WebRTCSignalingData.SignalingType.ANSWER,
                                sdp = answerSdp
                            )
                            // Send answer back via Bluetooth
                            _connectedDevice.value?.let { device ->
                                bluetoothManager.sendWebRTCSignaling(device, answerSignaling)
                            }
                        },
                        onIceCandidate = { candidate ->
                            Log.d(TAG, "handleWebRTCSignaling: ICE candidate ready, sending back")
                            val candidateSignaling = WebRTCSignalingData(
                                deviceName = android.os.Build.MODEL ?: "Android Device",
                                type = WebRTCSignalingData.SignalingType.ICE_CANDIDATE,
                                iceCandidate = candidate
                            )
                            _connectedDevice.value?.let { device ->
                                bluetoothManager.sendWebRTCSignaling(device, candidateSignaling)
                            }
                        }
                    )
                }
            }
            
            WebRTCSignalingData.SignalingType.ANSWER -> {
                Log.d(TAG, "handleWebRTCSignaling: Processing WebRTC answer")
                signalingData.sdp?.let { sdp ->
                    webRTCManager.setRemoteAnswer(sdp)
                }
            }
            
            WebRTCSignalingData.SignalingType.ICE_CANDIDATE -> {
                Log.d(TAG, "handleWebRTCSignaling: Processing ICE candidate")
                signalingData.iceCandidate?.let { candidate ->
                    webRTCManager.addIceCandidate(candidate)
                }
            }
        }
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
    
    private fun getExternalFilePath(fileName: String): String {
        val downloadsDir = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
        val filePath = File(downloadsDir, fileName).absolutePath
        logVerbose("📂 Generated file path: $filePath")
        return filePath
    }
    
    private fun handleReceivedFile(receivedFile: com.karthikinformationtechnology.waterdrop.webrtc.ReceivedFile) {
        logInfo("📥 Handling received file: ${receivedFile.fileName} (${receivedFile.fileSize} bytes)")
        
        scope.launch(Dispatchers.IO) {
            try {
                // Save file to Downloads directory
                val downloadsDir = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
                logVerbose("📁 Downloads directory: ${downloadsDir?.absolutePath}")
                
                if (downloadsDir != null) {
                    if (!downloadsDir.exists()) {
                        val created = downloadsDir.mkdirs()
                        logInfo("📁 Created downloads directory: $created")
                    }
                    
                    val file = File(downloadsDir, receivedFile.fileName)
                    logInfo("💾 Saving file to: ${file.absolutePath}")
                    
                    file.writeBytes(receivedFile.data)
                    logSuccess("✅ File saved successfully: ${file.absolutePath} (${file.length()} bytes)")
                    
                    // Verify file integrity
                    val savedChecksum = calculateSHA256(receivedFile.data)
                    logVerbose("🔐 File checksum: $savedChecksum")
                    
                    // Add to transfer history
                    val transferItem = TransferItem(
                        fileName = receivedFile.fileName,
                        fileSize = receivedFile.fileSize,
                        transferDate = Date(),
                        isIncoming = true,
                        checksum = calculateSHA256(receivedFile.data),
                        filePath = file.absolutePath
                    )
                    transferItemDao.insertTransferItem(transferItem)
                    
                    Log.d(TAG, "handleReceivedFile: File saved to ${file.absolutePath}")
                } else {
                    Log.e(TAG, "handleReceivedFile: Downloads directory not available")
                }
            } catch (e: Exception) {
                Log.e(TAG, "handleReceivedFile: Error saving file", e)
            }
        }
    }

    // Data class for active transfers
    data class ActiveTransfer(
        val id: String,
        val fileName: String,
        val fileSize: Long,
        val progress: Float,
        val isIncoming: Boolean
    )
}
