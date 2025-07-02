package com.karthikinformationtechnology.waterdrop.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.karthikinformationtechnology.waterdrop.data.model.TransferItem
import com.karthikinformationtechnology.waterdrop.viewmodel.MainViewModel
import java.text.SimpleDateFormat
import java.util.*

@Composable
fun TransferHistoryScreen(
    viewModel: MainViewModel,
    onDismiss: () -> Unit
) {
    val transferHistory by viewModel.transferHistory.collectAsStateWithLifecycle()

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(
            usePlatformDefaultWidth = false,
            dismissOnBackPress = true,
            dismissOnClickOutside = true
        )
    ) {
        Card(
            modifier = Modifier
                .fillMaxSize()
                .padding(16.dp),
            colors = CardDefaults.cardColors(
                containerColor = Color.Black.copy(alpha = 0.95f)
            ),
            shape = RoundedCornerShape(16.dp)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(20.dp)
            ) {
                // Header
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "Transfer History",
                        fontSize = 24.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color.White
                    )
                    
                    IconButton(onClick = onDismiss) {
                        Icon(
                            imageVector = Icons.Default.Close,
                            contentDescription = "Close",
                            tint = Color.White
                        )
                    }
                }
                
                Spacer(modifier = Modifier.height(16.dp))
                
                if (transferHistory.isEmpty()) {
                    // Empty state
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .weight(1f),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center
                    ) {
                        Icon(
                            imageVector = Icons.Default.Add,
                            contentDescription = null,
                            tint = Color.White.copy(alpha = 0.3f),
                            modifier = Modifier.size(64.dp)
                        )
                        
                        Spacer(modifier = Modifier.height(16.dp))
                        
                        Text(
                            text = "No transfer history",
                            fontSize = 18.sp,
                            fontWeight = FontWeight.Light,
                            color = Color.White.copy(alpha = 0.7f)
                        )
                        
                        Spacer(modifier = Modifier.height(8.dp))
                        
                        Text(
                            text = "Files you send and receive will appear here",
                            fontSize = 14.sp,
                            color = Color.White.copy(alpha = 0.5f)
                        )
                    }
                } else {
                    // Transfer history list
                    LazyColumn(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        items(transferHistory) { item ->
                            TransferHistoryItem(
                                item = item,
                                formatFileSize = { viewModel.formatFileSize(it) }
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun TransferHistoryItem(
    item: TransferItem,
    formatFileSize: (Long) -> String
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = Color.White.copy(alpha = 0.05f)
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
                imageVector = if (item.isIncoming) Icons.Default.KeyboardArrowDown else Icons.Default.KeyboardArrowUp,
                contentDescription = null,
                tint = if (item.isIncoming) Color.Green else Color.Blue,
                modifier = Modifier.size(20.dp)
            )
            
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = item.fileName,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                    color = Color.White,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = formatFileSize(item.fileSize),
                        fontSize = 12.sp,
                        color = Color.White.copy(alpha = 0.6f)
                    )
                    
                    Text(
                        text = "•",
                        fontSize = 12.sp,
                        color = Color.White.copy(alpha = 0.4f)
                    )
                    
                    Text(
                        text = formatDate(item.transferDate),
                        fontSize = 12.sp,
                        color = Color.White.copy(alpha = 0.6f)
                    )
                }
                
                if (item.deviceName.isNotEmpty()) {
                    Text(
                        text = "from ${item.deviceName}",
                        fontSize = 11.sp,
                        color = Color.White.copy(alpha = 0.5f)
                    )
                }
            }
            
            IconButton(
                onClick = {
                    // TODO: Open file
                },
                modifier = Modifier.size(32.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.Share,
                    contentDescription = "Open file",
                    tint = Color.White.copy(alpha = 0.7f),
                    modifier = Modifier.size(16.dp)
                )
            }
        }
    }
}

private fun formatDate(date: Date): String {
    val now = Date()
    val diff = now.time - date.time
    val seconds = diff / 1000
    val minutes = seconds / 60
    val hours = minutes / 60
    val days = hours / 24

    return when {
        days > 0 -> "${days}d ago"
        hours > 0 -> "${hours}h ago"
        minutes > 0 -> "${minutes}m ago"
        else -> "Just now"
    }
}
