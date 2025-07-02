package com.karthikinformationtechnology.waterdrop.data.database

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update
import com.karthikinformationtechnology.waterdrop.data.model.TransferItem
import kotlinx.coroutines.flow.Flow

@Dao
interface TransferItemDao {
    @Query("SELECT * FROM transfer_items ORDER BY transferDate DESC")
    fun getAllTransferItems(): Flow<List<TransferItem>>

    @Query("SELECT * FROM transfer_items WHERE isIncoming = :isIncoming ORDER BY transferDate DESC")
    fun getTransferItemsByType(isIncoming: Boolean): Flow<List<TransferItem>>

    @Insert
    suspend fun insertTransferItem(transferItem: TransferItem): Long

    @Update
    suspend fun updateTransferItem(transferItem: TransferItem)

    @Query("DELETE FROM transfer_items WHERE id = :id")
    suspend fun deleteTransferItem(id: Long)

    @Query("DELETE FROM transfer_items")
    suspend fun deleteAllTransferItems()

    @Query("SELECT COUNT(*) FROM transfer_items")
    suspend fun getTransferCount(): Int

    @Query("SELECT SUM(fileSize) FROM transfer_items WHERE isIncoming = 0")
    suspend fun getTotalSentBytes(): Long?

    @Query("SELECT SUM(fileSize) FROM transfer_items WHERE isIncoming = 1")
    suspend fun getTotalReceivedBytes(): Long?
}
