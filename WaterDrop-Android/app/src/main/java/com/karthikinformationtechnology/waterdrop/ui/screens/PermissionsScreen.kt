package com.karthikinformationtechnology.waterdrop.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.accompanist.permissions.ExperimentalPermissionsApi
import com.google.accompanist.permissions.MultiplePermissionsState
import com.google.accompanist.permissions.shouldShowRationale

@OptIn(ExperimentalPermissionsApi::class)
@Composable
fun PermissionsScreen(
    permissionsState: MultiplePermissionsState,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text(
            text = "WaterDrop",
            fontSize = 32.sp,
            fontWeight = FontWeight.Light,
            color = MaterialTheme.colorScheme.onSurface
        )
        
        Spacer(modifier = Modifier.height(16.dp))
        
        Text(
            text = "Permissions Required",
            fontSize = 24.sp,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onSurface
        )
        
        Spacer(modifier = Modifier.height(24.dp))
        
        Text(
            text = "WaterDrop needs the following permissions to function properly:",
            fontSize = 16.sp,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
            textAlign = TextAlign.Center
        )
        
        Spacer(modifier = Modifier.height(16.dp))
        
        Column {
            PermissionItem("📶", "Bluetooth", "To discover and connect to nearby devices")
            PermissionItem("📍", "Location", "Required for Bluetooth device scanning")
            PermissionItem("📁", "Storage", "To access and save files")
        }
        
        Spacer(modifier = Modifier.height(32.dp))
        
        Button(
            onClick = { permissionsState.launchMultiplePermissionRequest() },
            modifier = Modifier
                .fillMaxWidth()
                .height(48.dp)
        ) {
            Text("Grant Permissions")
        }
        
        if (permissionsState.permissions.any { it.status.shouldShowRationale }) {
            Spacer(modifier = Modifier.height(16.dp))
            
            Text(
                text = "Some permissions were denied. Please enable them in Settings to use WaterDrop.",
                fontSize = 14.sp,
                color = MaterialTheme.colorScheme.error,
                textAlign = TextAlign.Center
            )
        }
    }
}

@Composable
private fun PermissionItem(
    icon: String,
    title: String,
    description: String
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = icon,
            fontSize = 24.sp,
            modifier = Modifier.width(40.dp)
        )
        
        Column(
            modifier = Modifier.weight(1f)
        ) {
            Text(
                text = title,
                fontSize = 16.sp,
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.onSurface
            )
            
            Text(
                text = description,
                fontSize = 14.sp,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
            )
        }
    }
}
