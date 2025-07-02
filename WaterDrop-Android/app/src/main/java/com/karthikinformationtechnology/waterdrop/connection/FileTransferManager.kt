package com.karthikinformationtechnology.waterdrop.connection

import android.content.Context
import android.net.Uri
import android.util.Log
import com.karthikinformationtechnology.waterdrop.data.database.TransferItemDao
import com.karthikinformationtechnology.waterdrop.data.model.FileTransfer
import com.karthikinformationtechnology.waterdrop.data.model.TransferItem
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.sync.Semaphore
import java.io.*
import java.security.MessageDigest
import java.util.*
// import javax.inject.Inject
// import javax.inject.Singleton

// @Singleton
class FileTransferManager(
    private val context: Context,
    private val transferItemDao: TransferItemDao,
    private val scope: CoroutineScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    // @Inject constructor(
) {
    companion object {
        private const val TAG = "FileTransferManager"
        private const val CHUNK_SIZE = 8192 // 8KB chunks
        private const val MAX_CONCURRENT_TRANSFERS = 4
    }

    private val _activeTransfers = MutableStateFlow<List<FileTransfer>>(emptyList())
    val activeTransfers: StateFlow<List<FileTransfer>> = _activeTransfers.asStateFlow()

    private val transferSemaphore = Semaphore(MAX_CONCURRENT_TRANSFERS)
    private val activeJobs = mutableMapOf<String, Job>()

    fun sendFiles(
        files: List<Uri>,
        deviceName: String,
        onProgress: (String, Float) -> Unit = { _, _ -> },
        onComplete: (String, Boolean, String?) -> Unit = { _, _, _ -> }
    ) {
        Log.d(TAG, "sendFiles: Starting transfer of ${files.size} files to $deviceName")
        
        files.forEachIndexed { index, uri ->
            val transferId = UUID.randomUUID().toString()
            val fileName = getFileName(uri)
            Log.d(TAG, "sendFiles: Queuing file ${index + 1}/${files.size} - $fileName (ID: $transferId)")
            
            val job = scope.launch {
                try {
                    Log.d(TAG, "sendFiles: Acquiring transfer semaphore for $fileName")
                    transferSemaphore.acquire()
                    Log.d(TAG, "sendFiles: Starting transfer for $fileName")
                    sendFile(transferId, uri, fileName, deviceName, onProgress, onComplete)
                } catch (e: Exception) {
                    Log.e(TAG, "sendFiles: Error transferring $fileName", e)
                    onComplete(fileName, false, "Transfer error: ${e.message}")
                } finally {
                    Log.d(TAG, "sendFiles: Releasing transfer semaphore for $fileName")
                    transferSemaphore.release()
                    activeJobs.remove(transferId)
                    Log.d(TAG, "sendFiles: Completed transfer cleanup for $fileName")
                }
            }
            
            activeJobs[transferId] = job
        }
        Log.d(TAG, "sendFiles: All transfer jobs queued")
    }

    private suspend fun sendFile(
        transferId: String,
        uri: Uri,
        fileName: String,
        deviceName: String,
        onProgress: (String, Float) -> Unit,
        onComplete: (String, Boolean, String?) -> Unit
    ) {
        Log.d(TAG, "sendFile: Starting transfer - $fileName to $deviceName")
        try {
            val inputStream = context.contentResolver.openInputStream(uri)
                ?: throw IOException("Cannot open file input stream")
            Log.d(TAG, "sendFile: Opened input stream for $fileName")

            val fileSize = getFileSize(uri)
            Log.d(TAG, "sendFile: File size for $fileName: ${formatFileSize(fileSize)}")
            
            val checksum = calculateChecksum(uri)
            Log.d(TAG, "sendFile: Calculated checksum for $fileName: $checksum")

            val transfer = FileTransfer(
                id = transferId,
                fileName = fileName,
                fileSize = fileSize,
                isIncoming = false,
                status = FileTransfer.TransferStatus.TRANSFERRING,
                checksum = checksum,
                deviceName = deviceName
            )

            updateActiveTransfer(transfer)
            Log.d(TAG, "sendFile: Added transfer to active transfers list")

            inputStream.use { input ->
                val buffer = ByteArray(CHUNK_SIZE)
                var totalBytesRead = 0L
                var bytesRead: Int

                while (input.read(buffer).also { bytesRead = it } != -1 && currentCoroutineContext().isActive) {
                    // Simulate sending data over network/bluetooth
                    delay(10) // Simulate network latency
                    
                    totalBytesRead += bytesRead
                    val progress = totalBytesRead.toFloat() / fileSize
                    
                    val updatedTransfer = transfer.copy(
                        progress = progress,
                        bytesTransferred = totalBytesRead
                    )
                    updateActiveTransfer(updatedTransfer)
                    onProgress(fileName, progress)
                }

                if (currentCoroutineContext().isActive) {
                    // Transfer completed successfully
                    val completedTransfer = transfer.copy(
                        progress = 1.0f,
                        bytesTransferred = fileSize,
                        status = FileTransfer.TransferStatus.COMPLETED
                    )
                    updateActiveTransfer(completedTransfer)

                    // Save to database
                    val transferItem = TransferItem(
                        fileName = fileName,
                        fileSize = fileSize,
                        transferDate = Date(),
                        isIncoming = false,
                        checksum = checksum,
                        filePath = uri.toString(),
                        deviceName = deviceName
                    )
                    transferItemDao.insertTransferItem(transferItem)

                    onComplete(fileName, true, null)
                    removeActiveTransfer(transferId)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error sending file: $fileName", e)
            
            val failedTransfer = FileTransfer(
                id = transferId,
                fileName = fileName,
                fileSize = getFileSize(uri),
                isIncoming = false,
                status = FileTransfer.TransferStatus.FAILED,
                deviceName = deviceName
            )
            updateActiveTransfer(failedTransfer)
            
            onComplete(fileName, false, e.message)
            
            // Remove after a delay to show error state
            scope.launch {
                delay(3000)
                removeActiveTransfer(transferId)
            }
        }
    }

    fun receiveFile(
        fileName: String,
        fileSize: Long,
        deviceName: String,
        inputStream: InputStream,
        onProgress: (String, Float) -> Unit = { _, _ -> },
        onComplete: (String, Boolean, String?) -> Unit = { _, _, _ -> }
    ) {
        val transferId = UUID.randomUUID().toString()
        
        val job = scope.launch {
            transferSemaphore.acquire()
            try {
                receiveFileInternal(transferId, fileName, fileSize, deviceName, inputStream, onProgress, onComplete)
            } finally {
                transferSemaphore.release()
                activeJobs.remove(transferId)
            }
        }
        
        activeJobs[transferId] = job
    }

    private suspend fun receiveFileInternal(
        transferId: String,
        fileName: String,
        fileSize: Long,
        deviceName: String,
        inputStream: InputStream,
        onProgress: (String, Float) -> Unit,
        onComplete: (String, Boolean, String?) -> Unit
    ) {
        try {
            val downloadsDir = File(context.getExternalFilesDir(null), "WaterDrop")
            if (!downloadsDir.exists()) {
                downloadsDir.mkdirs()
            }

            val outputFile = File(downloadsDir, fileName)
            val transfer = FileTransfer(
                id = transferId,
                fileName = fileName,
                fileSize = fileSize,
                isIncoming = true,
                status = FileTransfer.TransferStatus.TRANSFERRING,
                deviceName = deviceName
            )

            updateActiveTransfer(transfer)

            inputStream.use { input ->
                FileOutputStream(outputFile).use { output ->
                    val buffer = ByteArray(CHUNK_SIZE)
                    var totalBytesRead = 0L
                    var bytesRead: Int

                    while (input.read(buffer).also { bytesRead = it } != -1 && currentCoroutineContext().isActive) {
                        output.write(buffer, 0, bytesRead)
                        totalBytesRead += bytesRead
                        
                        val progress = totalBytesRead.toFloat() / fileSize
                        val updatedTransfer = transfer.copy(
                            progress = progress,
                            bytesTransferred = totalBytesRead
                        )
                        updateActiveTransfer(updatedTransfer)
                        onProgress(fileName, progress)
                    }

                    if (currentCoroutineContext().isActive) {
                        // Calculate checksum of received file
                        val checksum = calculateFileChecksum(outputFile)
                        
                        val completedTransfer = transfer.copy(
                            progress = 1.0f,
                            bytesTransferred = fileSize,
                            status = FileTransfer.TransferStatus.COMPLETED,
                            checksum = checksum
                        )
                        updateActiveTransfer(completedTransfer)

                        // Save to database
                        val transferItem = TransferItem(
                            fileName = fileName,
                            fileSize = fileSize,
                            transferDate = Date(),
                            isIncoming = true,
                            checksum = checksum,
                            filePath = outputFile.absolutePath,
                            deviceName = deviceName
                        )
                        transferItemDao.insertTransferItem(transferItem)

                        onComplete(fileName, true, null)
                        removeActiveTransfer(transferId)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error receiving file: $fileName", e)
            
            val failedTransfer = FileTransfer(
                id = transferId,
                fileName = fileName,
                fileSize = fileSize,
                isIncoming = true,
                status = FileTransfer.TransferStatus.FAILED,
                deviceName = deviceName
            )
            updateActiveTransfer(failedTransfer)
            
            onComplete(fileName, false, e.message)
            
            scope.launch {
                delay(3000)
                removeActiveTransfer(transferId)
            }
        }
    }

    fun pauseTransfer(transferId: String) {
        Log.d(TAG, "pauseTransfer: Pausing transfer $transferId")
        try {
            activeJobs[transferId]?.cancel()
            updateTransferStatus(transferId, FileTransfer.TransferStatus.PAUSED)
            Log.d(TAG, "pauseTransfer: Successfully paused transfer $transferId")
        } catch (e: Exception) {
            Log.e(TAG, "pauseTransfer: Error pausing transfer $transferId", e)
        }
    }

    fun cancelTransfer(transferId: String) {
        Log.d(TAG, "cancelTransfer: Cancelling transfer $transferId")
        try {
            activeJobs[transferId]?.cancel()
            removeActiveTransfer(transferId)
            Log.d(TAG, "cancelTransfer: Successfully cancelled transfer $transferId")
        } catch (e: Exception) {
            Log.e(TAG, "cancelTransfer: Error cancelling transfer $transferId", e)
        }
    }

    fun cancelAllTransfers() {
        Log.d(TAG, "cancelAllTransfers: Cancelling all ${activeJobs.size} active transfers")
        try {
            activeJobs.values.forEach { it.cancel() }
            activeJobs.clear()
            _activeTransfers.value = emptyList()
            Log.d(TAG, "cancelAllTransfers: All transfers cancelled successfully")
        } catch (e: Exception) {
            Log.e(TAG, "cancelAllTransfers: Error cancelling transfers", e)
        }
    }

    private fun updateActiveTransfer(transfer: FileTransfer) {
        val currentTransfers = _activeTransfers.value.toMutableList()
        val index = currentTransfers.indexOfFirst { it.id == transfer.id }
        
        if (index >= 0) {
            currentTransfers[index] = transfer
        } else {
            currentTransfers.add(transfer)
        }
        
        _activeTransfers.value = currentTransfers
    }

    private fun removeActiveTransfer(transferId: String) {
        val currentTransfers = _activeTransfers.value.toMutableList()
        currentTransfers.removeAll { it.id == transferId }
        _activeTransfers.value = currentTransfers
    }

    private fun updateTransferStatus(transferId: String, status: FileTransfer.TransferStatus) {
        val currentTransfers = _activeTransfers.value.toMutableList()
        val index = currentTransfers.indexOfFirst { it.id == transferId }
        
        if (index >= 0) {
            currentTransfers[index] = currentTransfers[index].copy(status = status)
            _activeTransfers.value = currentTransfers
        }
    }

    private fun getFileName(uri: Uri): String {
        var fileName = "unknown_file"
        context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                if (nameIndex >= 0) {
                    fileName = cursor.getString(nameIndex) ?: "unknown_file"
                }
            }
        }
        return fileName
    }

    private fun getFileSize(uri: Uri): Long {
        var fileSize = 0L
        context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val sizeIndex = cursor.getColumnIndex(android.provider.OpenableColumns.SIZE)
                if (sizeIndex >= 0) {
                    fileSize = cursor.getLong(sizeIndex)
                }
            }
        }
        return fileSize
    }

    private fun calculateChecksum(uri: Uri): String {
        return try {
            val inputStream = context.contentResolver.openInputStream(uri) ?: return ""
            val digest = MessageDigest.getInstance("MD5")
            val buffer = ByteArray(8192)
            
            inputStream.use { input ->
                var bytesRead: Int
                while (input.read(buffer).also { bytesRead = it } != -1) {
                    digest.update(buffer, 0, bytesRead)
                }
            }
            
            digest.digest().joinToString("") { "%02x".format(it) }
        } catch (e: Exception) {
            Log.e(TAG, "Error calculating checksum", e)
            ""
        }
    }

    private fun calculateFileChecksum(file: File): String {
        return try {
            val digest = MessageDigest.getInstance("MD5")
            val buffer = ByteArray(8192)
            
            FileInputStream(file).use { input ->
                var bytesRead: Int
                while (input.read(buffer).also { bytesRead = it } != -1) {
                    digest.update(buffer, 0, bytesRead)
                }
            }
            
            digest.digest().joinToString("") { "%02x".format(it) }
        } catch (e: Exception) {
            Log.e(TAG, "Error calculating file checksum", e)
            ""
        }
    }

    private fun formatFileSize(bytes: Long): String {
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
