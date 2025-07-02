package com.karthikinformationtechnology.waterdrop

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.core.view.WindowCompat
import com.google.accompanist.permissions.ExperimentalPermissionsApi
import com.google.accompanist.permissions.isGranted
import com.google.accompanist.permissions.rememberMultiplePermissionsState
import com.karthikinformationtechnology.waterdrop.ui.screens.MainScreen
import com.karthikinformationtechnology.waterdrop.ui.screens.PermissionsScreen
import com.karthikinformationtechnology.waterdrop.ui.theme.WaterDropTheme
import com.karthikinformationtechnology.waterdrop.viewmodel.MainViewModel
// import dagger.hilt.android.AndroidEntryPoint

// @AndroidEntryPoint
class MainActivity : ComponentActivity() {
    companion object {
        private const val TAG = "MainActivity"
    }
    
    // private val viewModel: MainViewModel by viewModels()
    private lateinit var viewModel: MainViewModel

    @OptIn(ExperimentalPermissionsApi::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        Log.d(TAG, "onCreate: Starting MainActivity")
        super.onCreate(savedInstanceState)
        
        try {
            // Temporary manual initialization without Hilt
            Log.d(TAG, "onCreate: Initializing MainViewModel")
            viewModel = MainViewModel(application)
            Log.d(TAG, "onCreate: MainViewModel initialized successfully")
        } catch (e: Exception) {
            Log.e(TAG, "onCreate: Failed to initialize MainViewModel", e)
            throw e
        }
        
        enableEdgeToEdge()
        
        WindowCompat.setDecorFitsSystemWindows(window, false)

        setContent {
            WaterDropTheme {
                val requiredPermissions = remember {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        listOf(
                            Manifest.permission.BLUETOOTH_SCAN,
                            Manifest.permission.BLUETOOTH_ADVERTISE,
                            Manifest.permission.BLUETOOTH_CONNECT,
                            Manifest.permission.ACCESS_FINE_LOCATION
                        )
                    } else {
                        listOf(
                            Manifest.permission.BLUETOOTH,
                            Manifest.permission.BLUETOOTH_ADMIN,
                            Manifest.permission.ACCESS_FINE_LOCATION,
                            Manifest.permission.READ_EXTERNAL_STORAGE,
                            Manifest.permission.WRITE_EXTERNAL_STORAGE
                        )
                    }
                }

                val permissionsState = rememberMultiplePermissionsState(requiredPermissions)

                val filePickerLauncher = rememberLauncherForActivityResult(
                    contract = ActivityResultContracts.GetMultipleContents()
                ) { uris: List<Uri> ->
                    Log.d(TAG, "filePickerLauncher: Received ${uris.size} files")
                    if (uris.isNotEmpty()) {
                        try {
                            uris.forEach { uri ->
                                Log.d(TAG, "filePickerLauncher: Selected file URI: $uri")
                            }
                            viewModel.sendFiles(uris)
                        } catch (e: Exception) {
                            Log.e(TAG, "filePickerLauncher: Error processing selected files", e)
                        }
                    } else {
                        Log.w(TAG, "filePickerLauncher: No files selected")
                    }
                }

                LaunchedEffect(Unit) {
                    Log.d(TAG, "LaunchedEffect: Handling incoming intent")
                    // Handle incoming shared files
                    handleIncomingIntent(intent)
                }

                Scaffold(
                    modifier = Modifier.fillMaxSize()
                ) { innerPadding ->
                    Log.d(TAG, "Scaffold: Checking permissions state")
                    if (permissionsState.permissions.all { it.status.isGranted }) {
                        Log.d(TAG, "Scaffold: All permissions granted, showing MainScreen")
                        MainScreen(
                            viewModel = viewModel,
                            onFilePick = { 
                                Log.d(TAG, "onFilePick: Launching file picker")
                                filePickerLauncher.launch("*/*") 
                            },
                            modifier = Modifier.padding(innerPadding)
                        )
                    } else {
                        Log.w(TAG, "Scaffold: Missing permissions, showing PermissionsScreen")
                        val deniedPermissions = permissionsState.permissions.filter { !it.status.isGranted }
                        deniedPermissions.forEach { permission ->
                            Log.w(TAG, "Missing permission: ${permission.permission}")
                        }
                        PermissionsScreen(
                            permissionsState = permissionsState,
                            modifier = Modifier.padding(innerPadding)
                        )
                    }
                }
            }
        }
    }

    private fun handleIncomingIntent(intent: Intent?) {
        Log.d(TAG, "handleIncomingIntent: Processing intent with action: ${intent?.action}")
        
        try {
            when (intent?.action) {
                Intent.ACTION_SEND -> {
                    Log.d(TAG, "handleIncomingIntent: Processing ACTION_SEND")
                    val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                    if (uri != null) {
                        Log.d(TAG, "handleIncomingIntent: Received single file URI: $uri")
                        viewModel.sendFiles(listOf(uri))
                    } else {
                        Log.w(TAG, "handleIncomingIntent: ACTION_SEND with null URI")
                    }
                }
                Intent.ACTION_SEND_MULTIPLE -> {
                    Log.d(TAG, "handleIncomingIntent: Processing ACTION_SEND_MULTIPLE")
                    val uris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                    if (!uris.isNullOrEmpty()) {
                        Log.d(TAG, "handleIncomingIntent: Received ${uris.size} file URIs")
                        uris.forEach { uri ->
                            Log.d(TAG, "handleIncomingIntent: File URI: $uri")
                        }
                        viewModel.sendFiles(uris)
                    } else {
                        Log.w(TAG, "handleIncomingIntent: ACTION_SEND_MULTIPLE with empty URI list")
                    }
                }
                else -> {
                    Log.d(TAG, "handleIncomingIntent: No relevant action found")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "handleIncomingIntent: Error processing intent", e)
        }
    }

    override fun onNewIntent(intent: Intent) {
        Log.d(TAG, "onNewIntent: Received new intent with action: ${intent.action}")
        super.onNewIntent(intent)
        handleIncomingIntent(intent)
    }

    override fun onDestroy() {
        Log.d(TAG, "onDestroy: Cleaning up MainActivity")
        super.onDestroy()
        try {
            viewModel.cleanup()
            Log.d(TAG, "onDestroy: ViewModel cleanup completed")
        } catch (e: Exception) {
            Log.e(TAG, "onDestroy: Error during cleanup", e)
        }
    }
}