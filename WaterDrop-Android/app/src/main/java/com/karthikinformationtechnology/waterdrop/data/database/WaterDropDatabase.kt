package com.karthikinformationtechnology.waterdrop.data.database

import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import android.content.Context
import com.karthikinformationtechnology.waterdrop.data.model.TransferItem

@Database(
    entities = [TransferItem::class],
    version = 1,
    exportSchema = false
)
@TypeConverters(Converters::class)
abstract class WaterDropDatabase : RoomDatabase() {
    abstract fun transferItemDao(): TransferItemDao

    companion object {
        @Volatile
        private var INSTANCE: WaterDropDatabase? = null

        fun getDatabase(context: Context): WaterDropDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    WaterDropDatabase::class.java,
                    "waterdrop_database"
                ).build()
                INSTANCE = instance
                instance
            }
        }
    }
}
