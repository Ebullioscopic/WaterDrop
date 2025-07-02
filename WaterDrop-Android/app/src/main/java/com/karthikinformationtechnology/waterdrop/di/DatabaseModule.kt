package com.karthikinformationtechnology.waterdrop.di

import android.content.Context
import androidx.room.Room
import com.karthikinformationtechnology.waterdrop.data.database.TransferItemDao
import com.karthikinformationtechnology.waterdrop.data.database.WaterDropDatabase

/**
 * Database Module - Manual dependency injection for database components
 * This matches the manual DI approach used throughout the app
 */
object DatabaseModule {

    fun provideWaterDropDatabase(context: Context): WaterDropDatabase {
        return Room.databaseBuilder(
            context.applicationContext,
            WaterDropDatabase::class.java,
            "waterdrop_database"
        ).build()
    }

    fun provideTransferItemDao(database: WaterDropDatabase): TransferItemDao {
        return database.transferItemDao()
    }
}
