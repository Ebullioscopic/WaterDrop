package com.karthikinformationtechnology.waterdrop.data

import android.content.Context
import androidx.room.Room
import com.karthikinformationtechnology.waterdrop.data.database.WaterDropDatabase

object DatabaseProvider {
    @Volatile
    private var INSTANCE: WaterDropDatabase? = null

    fun getDatabase(context: Context): WaterDropDatabase {
        return INSTANCE ?: synchronized(this) {
            val instance = Room.databaseBuilder(
                context.applicationContext,
                WaterDropDatabase::class.java,
                "water_drop_database"
            ).build()
            INSTANCE = instance
            instance
        }
    }
}
