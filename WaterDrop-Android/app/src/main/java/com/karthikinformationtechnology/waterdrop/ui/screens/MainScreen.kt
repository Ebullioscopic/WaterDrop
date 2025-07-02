package com.karthikinformationtechnology.waterdrop.ui.screens

import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.karthikinformationtechnology.waterdrop.data.model.*
import com.karthikinformationtechnology.waterdrop.viewmodel.MainViewModel
import kotlin.math.cos
import kotlin.math.sin

@Composable
fun MainScreen(
    viewModel: MainViewModel,
    onFilePick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val connectionState by viewModel.connectionState.collectAsStateWithLifecycle()
    val discoveredDevices by viewModel.discoveredDevices.collectAsStateWithLifecycle()
    val connectedDevice by viewModel.connectedDevice.collectAsStateWithLifecycle()
    val activeTransfers by viewModel.activeTransfers.collectAsStateWithLifecycle()
    val errorMessage by viewModel.errorMessage.collectAsStateWithLifecycle()
    
    var showTransferHistory by remember { mutableStateOf(false) }

    // Show error snackbar
    LaunchedEffect(errorMessage) {
        if (errorMessage != null) {
            // Handle error display
        }
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    colors = listOf(
                        Color.Black,
                        Color(0xFF0A0A0A),
                        Color.Black
                    )
                )
            )
    ) {
        // Animated background particles
        AnimatedBackground()
        
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            item {
                HeaderSection()
            }
            
            item {
                ConnectionStatusCard(
                    connectionState = connectionState,
                    connectedDevice = connectedDevice,
                    onStartDiscovery = { viewModel.startDiscovery() },
                    onDisconnect = { viewModel.disconnectFromDevice() }
                )
            }
            
            if (discoveredDevices.isNotEmpty()) {
                item {
                    Text(
                        text = "Nearby Devices",
                        fontSize = 20.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color.White,
                        modifier = Modifier.padding(vertical = 8.dp)
                    )
                }
                
                items(discoveredDevices) { device ->
                    DeviceCard(
                        device = device,
                        isConnected = connectedDevice?.id == device.id,
                        onConnect = { viewModel.connectToDevice(device) },
                        getSignalStrength = { viewModel.getSignalStrength(it) }
                    )
                }
            }
            
            if (connectionState == ConnectionState.CONNECTED) {
                item {
                    FileTransferCard(
                        onFilePick = onFilePick,
                        canTransfer = viewModel.canTransferFiles()
                    )
                }
            }
            
            if (activeTransfers.isNotEmpty()) {
                item {
                    Text(
                        text = "Active Transfers",
                        fontSize = 20.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color.White,
                        modifier = Modifier.padding(vertical = 8.dp)
                    )
                }
                
                items(activeTransfers) { transfer ->
                    TransferCard(
                        transfer = transfer,
                        onPause = { viewModel.pauseTransfer(transfer.id) },
                        onCancel = { viewModel.cancelTransfer(transfer.id) },
                        formatFileSize = { viewModel.formatFileSize(it) }
                    )
                }
            }
            
            item {
                Spacer(modifier = Modifier.height(100.dp)) // Bottom padding
            }
        }
        
        // Floating action button for history
        FloatingActionButton(
            onClick = { showTransferHistory = true },
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(16.dp),
            containerColor = Color.White.copy(alpha = 0.1f),
            contentColor = Color.White
        ) {
            Icon(Icons.Default.Add, contentDescription = "Transfer History")
        }
    }
    
    if (showTransferHistory) {
        TransferHistoryScreen(
            viewModel = viewModel,
            onDismiss = { showTransferHistory = false }
        )
    }
}

@Composable
private fun AnimatedBackground() {
    val infiniteTransition = rememberInfiniteTransition(label = "background")
    val animatedValue by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(
            animation = tween(20000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "rotation"
    )
    
    Canvas(modifier = Modifier.fillMaxSize()) {
        drawAnimatedDots(animatedValue, size)
    }
}

private fun DrawScope.drawAnimatedDots(rotation: Float, canvasSize: androidx.compose.ui.geometry.Size) {
    val numDots = 30
    val centerX = canvasSize.width / 2
    val centerY = canvasSize.height / 2
    val radius = minOf(centerX, centerY) * 0.8f
    
    repeat(numDots) { i ->
        val angle = (i * 360f / numDots + rotation) * (kotlin.math.PI / 180f)
        val x = centerX + radius * cos(angle).toFloat() * (0.3f + 0.7f * (i % 3) / 2f)
        val y = centerY + radius * sin(angle).toFloat() * (0.3f + 0.7f * (i % 3) / 2f)
        
        drawCircle(
            color = Color.White.copy(alpha = 0.1f * (1f - i.toFloat() / numDots)),
            radius = 2f + (i % 4),
            center = Offset(x, y)
        )
    }
}

@Composable
private fun HeaderSection() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(8.dp)
                    .background(Color.White, CircleShape)
            )
            
            Text(
                text = "WaterDrop",
                fontSize = 36.sp,
                fontWeight = FontWeight.Light,
                color = Color.White
            )
        }
        
        Spacer(modifier = Modifier.height(8.dp))
        
        Text(
            text = "Seamless peer-to-peer file transfer",
            fontSize = 16.sp,
            color = Color.White.copy(alpha = 0.7f)
        )
    }
}

@Composable
private fun ConnectionStatusCard(
    connectionState: ConnectionState,
    connectedDevice: DiscoveredDevice?,
    onStartDiscovery: () -> Unit,
    onDisconnect: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = Color.White.copy(alpha = 0.05f)
        ),
        shape = RoundedCornerShape(16.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(20.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                ConnectionStatusIndicator(connectionState)
                
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = getConnectionStatusText(connectionState),
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color.White
                    )
                    
                    Text(
                        text = connectedDevice?.name ?: getConnectionSubtext(connectionState),
                        fontSize = 14.sp,
                        color = Color.White.copy(alpha = 0.7f)
                    )
                }
                
                when (connectionState) {
                    ConnectionState.DISCONNECTED -> {
                        Button(
                            onClick = onStartDiscovery,
                            colors = ButtonDefaults.buttonColors(
                                containerColor = Color.White,
                                contentColor = Color.Black
                            )
                        ) {
                            Text("Start Discovery")
                        }
                    }
                    ConnectionState.CONNECTED -> {
                        OutlinedButton(
                            onClick = onDisconnect,
                            colors = ButtonDefaults.outlinedButtonColors(
                                contentColor = Color.White
                            )
                        ) {
                            Text("Disconnect")
                        }
                    }
                    else -> {
                        CircularProgressIndicator(
                            modifier = Modifier.size(24.dp),
                            color = Color.White,
                            strokeWidth = 2.dp
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ConnectionStatusIndicator(connectionState: ConnectionState) {
    val color = when (connectionState) {
        ConnectionState.DISCONNECTED -> Color.Red
        ConnectionState.DISCOVERING -> Color.Yellow
        ConnectionState.CONNECTING -> Color(0xFFFF9800)
        ConnectionState.CONNECTED -> Color.Green
        ConnectionState.TRANSFERRING -> Color.Blue
        ConnectionState.ERROR -> Color.Red
    }
    
    val scale by animateFloatAsState(
        targetValue = if (connectionState == ConnectionState.DISCOVERING) 1.5f else 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(600),
            repeatMode = RepeatMode.Reverse
        ),
        label = "scale"
    )
    
    Box(
        modifier = Modifier
            .size(12.dp)
            .scale(scale)
            .background(color, CircleShape)
    )
}

@Composable
private fun DeviceCard(
    device: DiscoveredDevice,
    isConnected: Boolean,
    onConnect: () -> Unit,
    getSignalStrength: (Int) -> String
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { if (!isConnected) onConnect() },
        colors = CardDefaults.cardColors(
            containerColor = if (isConnected) 
                Color.White.copy(alpha = 0.1f) 
            else 
                Color.White.copy(alpha = 0.03f)
        ),
        shape = RoundedCornerShape(12.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Icon(
                imageVector =                when (device.deviceType) {
                    DiscoveredDevice.DeviceType.PHONE -> Icons.Default.Phone
                    DiscoveredDevice.DeviceType.TABLET -> Icons.Default.Phone
                    DiscoveredDevice.DeviceType.LAPTOP -> Icons.Default.Person
                    DiscoveredDevice.DeviceType.DESKTOP -> Icons.Default.Person
                    DiscoveredDevice.DeviceType.UNKNOWN -> Icons.Default.Star
                },
                contentDescription = null,
                tint = Color.White.copy(alpha = 0.8f),
                modifier = Modifier.size(24.dp)
            )
            
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = device.name,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Medium,
                    color = Color.White,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                
                Text(
                    text = "Signal: ${getSignalStrength(device.rssi)}",
                    fontSize = 12.sp,
                    color = Color.White.copy(alpha = 0.6f)
                )
            }
            
            if (isConnected) {
                Icon(
                    imageVector = Icons.Default.CheckCircle,
                    contentDescription = "Connected",
                    tint = Color.Green,
                    modifier = Modifier.size(20.dp)
                )
            } else {
                OutlinedButton(
                    onClick = onConnect,
                    colors = ButtonDefaults.outlinedButtonColors(
                        contentColor = Color.White
                    ),
                    modifier = Modifier.height(32.dp)
                ) {
                    Text("Connect", fontSize = 12.sp)
                }
            }
        }
    }
}

@Composable
private fun FileTransferCard(
    onFilePick: () -> Unit,
    canTransfer: Boolean
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = Color.White.copy(alpha = 0.05f)
        ),
        shape = RoundedCornerShape(16.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = "File Transfer",
                fontSize = 20.sp,
                fontWeight = FontWeight.Medium,
                color = Color.White,
                modifier = Modifier.padding(bottom = 16.dp)
            )
            
            Button(
                onClick = onFilePick,
                enabled = canTransfer,
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color.White,
                    contentColor = Color.Black
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(48.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.Add,
                    contentDescription = null,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text("Select Files to Send")
            }
        }
    }
}

@Composable
private fun TransferCard(
    transfer: FileTransfer,
    onPause: () -> Unit,
    onCancel: () -> Unit,
    formatFileSize: (Long) -> String
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = Color.White.copy(alpha = 0.05f)
        ),
        shape = RoundedCornerShape(12.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Icon(
                    imageVector = if (transfer.isIncoming) Icons.Default.KeyboardArrowDown else Icons.Default.KeyboardArrowUp,
                    contentDescription = null,
                    tint = if (transfer.isIncoming) Color.Green else Color.Blue,
                    modifier = Modifier.size(20.dp)
                )
                
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = transfer.fileName,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color.White,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    
                    Text(
                        text = formatFileSize(transfer.fileSize),
                        fontSize = 12.sp,
                        color = Color.White.copy(alpha = 0.6f)
                    )
                }
                
                Text(
                    text = "${(transfer.progress * 100).toInt()}%",
                    fontSize = 12.sp,
                    color = Color.White.copy(alpha = 0.8f)
                )
                
                IconButton(
                    onClick = onCancel,
                    modifier = Modifier.size(24.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.Close,
                        contentDescription = "Cancel",
                        tint = Color.Red,
                        modifier = Modifier.size(16.dp)
                    )
                }
            }
            
            Spacer(modifier = Modifier.height(8.dp))
            
            LinearProgressIndicator(
                progress = { transfer.progress },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(4.dp)
                    .clip(RoundedCornerShape(2.dp)),
                color = if (transfer.isIncoming) Color.Green else Color.Blue,
                trackColor = Color.White.copy(alpha = 0.2f)
            )
        }
    }
}

private fun getConnectionStatusText(state: ConnectionState): String {
    return when (state) {
        ConnectionState.DISCONNECTED -> "Disconnected"
        ConnectionState.DISCOVERING -> "Discovering devices..."
        ConnectionState.CONNECTING -> "Connecting..."
        ConnectionState.CONNECTED -> "Connected"
        ConnectionState.TRANSFERRING -> "Transferring files..."
        ConnectionState.ERROR -> "Connection error"
    }
}

private fun getConnectionSubtext(state: ConnectionState): String {
    return when (state) {
        ConnectionState.DISCONNECTED -> "Tap Start Discovery to find devices"
        ConnectionState.DISCOVERING -> "Looking for nearby WaterDrop devices"
        ConnectionState.CONNECTING -> "Establishing secure connection"
        ConnectionState.CONNECTED -> "Ready to transfer files"
        ConnectionState.TRANSFERRING -> "Files are being transferred"
        ConnectionState.ERROR -> "Please try again"
    }
}
