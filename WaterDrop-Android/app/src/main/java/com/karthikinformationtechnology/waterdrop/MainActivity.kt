package com.karthikinformationtechnology.waterdrop

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
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
    // private val viewModel: MainViewModel by viewModels()
    private lateinit var viewModel: MainViewModel

    @OptIn(ExperimentalPermissionsApi::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Temporary manual initialization without Hilt
        viewModel = MainViewModel(application)
        
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
                    if (uris.isNotEmpty()) {
                        viewModel.sendFiles(uris)
                    }
                }

                LaunchedEffect(Unit) {
                    // Handle incoming shared files
                    handleIncomingIntent(intent)
                }

                Scaffold(
                    modifier = Modifier.fillMaxSize()
                ) { innerPadding ->
                    if (permissionsState.permissions.all { it.status.isGranted }) {
                        MainScreen(
                            viewModel = viewModel,
                            onFilePick = { filePickerLauncher.launch("*/*") },
                            modifier = Modifier.padding(innerPadding)
                        )
                    } else {
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
        when (intent?.action) {
            Intent.ACTION_SEND -> {
                val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                if (uri != null) {
                    viewModel.sendFiles(listOf(uri))
                }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                val uris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                if (!uris.isNullOrEmpty()) {
                    viewModel.sendFiles(uris)
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIncomingIntent(intent)
    }

    override fun onDestroy() {
        super.onDestroy()
        viewModel.cleanup()
    }
}