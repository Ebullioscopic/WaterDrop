package com.karthikinformationtechnology.waterdrop.connection

import android.Manifest
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.ParcelUuid
import android.util.Log
import androidx.core.app.ActivityCompat
import com.karthikinformationtechnology.waterdrop.data.model.BluetoothDeviceInfo
import com.karthikinformationtechnology.waterdrop.data.model.DiscoveredDevice
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import java.security.MessageDigest
import java.util.*
// import javax.inject.Inject
// import javax.inject.Singleton

// @Singleton
class WaterDropBluetoothManager(
    private val context: Context
    // @Inject constructor(
) {
    companion object {
        private const val TAG = "WaterDropBluetoothManager"
        
        // WaterDrop service UUID
        val SERVICE_UUID: UUID = UUID.fromString("12345678-1234-1234-1234-123456789ABC")
        val CHARACTERISTIC_UUID: UUID = UUID.fromString("87654321-4321-4321-4321-CBA987654321")
        
        private const val DEVICE_NAME = "WaterDrop"
        private const val SCAN_TIMEOUT_MS = 30000L
    }

    private val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as android.bluetooth.BluetoothManager
    private val bluetoothAdapter = bluetoothManager.adapter
    
    private var bluetoothLeScanner: BluetoothLeScanner? = null
    private var bluetoothLeAdvertiser: BluetoothLeAdvertiser? = null
    private var gattServer: BluetoothGattServer? = null
    private var gattClient: BluetoothGatt? = null
    
    private val discoveredDevices = mutableMapOf<String, DiscoveredDevice>()
    private var isScanning = false
    private var isAdvertising = false
    
    private var currentChannelCallback: ((List<DiscoveredDevice>) -> Unit)? = null
    
    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val device = result.device
            val rssi = result.rssi
            
            if (ActivityCompat.checkSelfPermission(
                    context,
                    Manifest.permission.BLUETOOTH_CONNECT
                ) == PackageManager.PERMISSION_GRANTED
            ) {
                val deviceInfo = DiscoveredDevice(
                    id = device.address,
                    name = device.name ?: "Unknown Device",
                    address = device.address,
                    rssi = rssi,
                    deviceType = determineDeviceType(device),
                    services = result.scanRecord?.serviceUuids?.map { it.toString() } ?: emptyList()
                )
                
                discoveredDevices[device.address] = deviceInfo
                currentChannelCallback?.invoke(discoveredDevices.values.toList())
            }
        }

        override fun onScanFailed(errorCode: Int) {
            Log.e(TAG, "Scan failed with error code: $errorCode")
            isScanning = false
        }
    }

    fun isBluetoothEnabled(): Boolean {
        return bluetoothAdapter?.isEnabled == true
    }

    fun hasBluetoothPermissions(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            hasPermission(Manifest.permission.BLUETOOTH_SCAN) &&
            hasPermission(Manifest.permission.BLUETOOTH_ADVERTISE) &&
            hasPermission(Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            hasPermission(Manifest.permission.BLUETOOTH) &&
            hasPermission(Manifest.permission.BLUETOOTH_ADMIN) &&
            hasPermission(Manifest.permission.ACCESS_FINE_LOCATION)
        }
    }

    private fun hasPermission(permission: String): Boolean {
        return ActivityCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
    }

    fun startDiscovery(): Flow<List<DiscoveredDevice>> = callbackFlow {
        if (!isBluetoothEnabled() || !hasBluetoothPermissions()) {
            close(IllegalStateException("Bluetooth not available or permissions missing"))
            return@callbackFlow
        }

        bluetoothLeScanner = bluetoothAdapter.bluetoothLeScanner
        
        currentChannelCallback = { devices ->
            trySend(devices)
        }

        val scanFilter = ScanFilter.Builder()
            .setServiceUuid(ParcelUuid(SERVICE_UUID))
            .build()

        val scanSettings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
            .build()

        if (ActivityCompat.checkSelfPermission(
                context,
                Manifest.permission.BLUETOOTH_SCAN
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            bluetoothLeScanner?.startScan(listOf(scanFilter), scanSettings, scanCallback)
            isScanning = true
            Log.d(TAG, "Started Bluetooth LE scan")
        }

        awaitClose {
            if (isScanning && ActivityCompat.checkSelfPermission(
                    context,
                    Manifest.permission.BLUETOOTH_SCAN
                ) == PackageManager.PERMISSION_GRANTED
            ) {
                bluetoothLeScanner?.stopScan(scanCallback as ScanCallback)
                isScanning = false
                Log.d(TAG, "Stopped Bluetooth LE scan")
            }
        }
    }

    fun startAdvertising(): Flow<Boolean> = callbackFlow {
        if (!isBluetoothEnabled() || !hasBluetoothPermissions()) {
            close(IllegalStateException("Bluetooth not available or permissions missing"))
            return@callbackFlow
        }

        bluetoothLeAdvertiser = bluetoothAdapter.bluetoothLeAdvertiser

        val advertiseCallback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                isAdvertising = true
                Log.d(TAG, "Advertising started successfully")
                trySend(true)
            }

            override fun onStartFailure(errorCode: Int) {
                isAdvertising = false
                Log.e(TAG, "Advertising failed with error: $errorCode")
                trySend(false)
            }
        }

        val advertiseSettings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(true)
            .build()

        val advertiseData = AdvertiseData.Builder()
            .setIncludeDeviceName(true)
            .setIncludeTxPowerLevel(false)
            .addServiceUuid(ParcelUuid(SERVICE_UUID))
            .build()

        if (ActivityCompat.checkSelfPermission(
                context,
                Manifest.permission.BLUETOOTH_ADVERTISE
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            bluetoothLeAdvertiser?.startAdvertising(advertiseSettings, advertiseData, advertiseCallback)
            Log.d(TAG, "Started Bluetooth LE advertising")
        }

        awaitClose {
            if (isAdvertising && ActivityCompat.checkSelfPermission(
                    context,
                    Manifest.permission.BLUETOOTH_ADVERTISE
                ) == PackageManager.PERMISSION_GRANTED
            ) {
                bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback)
                isAdvertising = false
                Log.d(TAG, "Stopped Bluetooth LE advertising")
            }
        }
    }

    fun connectToDevice(device: DiscoveredDevice): Flow<Boolean> = callbackFlow {
        val bluetoothDevice = bluetoothAdapter.getRemoteDevice(device.address)
        
        val gattCallback = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt?, status: Int, newState: Int) {
                when (newState) {
                    BluetoothProfile.STATE_CONNECTED -> {
                        Log.d(TAG, "Connected to GATT server")
                        if (ActivityCompat.checkSelfPermission(
                                context,
                                Manifest.permission.BLUETOOTH_CONNECT
                            ) == PackageManager.PERMISSION_GRANTED
                        ) {
                            gatt?.discoverServices()
                        }
                        trySend(true)
                    }
                    BluetoothProfile.STATE_DISCONNECTED -> {
                        Log.d(TAG, "Disconnected from GATT server")
                        trySend(false)
                        gatt?.close()
                    }
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt?, status: Int) {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    Log.d(TAG, "Services discovered")
                    gattClient = gatt
                    // Handle service discovery and setup characteristics
                }
            }

            override fun onCharacteristicRead(
                gatt: BluetoothGatt?,
                characteristic: BluetoothGattCharacteristic?,
                status: Int
            ) {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    characteristic?.value?.let { data ->
                        Log.d(TAG, "Characteristic read: ${data.contentToString()}")
                        // Handle received data
                    }
                }
            }

            override fun onCharacteristicWrite(
                gatt: BluetoothGatt?,
                characteristic: BluetoothGattCharacteristic?,
                status: Int
            ) {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    Log.d(TAG, "Characteristic write successful")
                }
            }
        }

        if (ActivityCompat.checkSelfPermission(
                context,
                Manifest.permission.BLUETOOTH_CONNECT
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            gattClient = bluetoothDevice.connectGatt(context, false, gattCallback)
        }

        awaitClose {
            if (ActivityCompat.checkSelfPermission(
                    context,
                    Manifest.permission.BLUETOOTH_CONNECT
                ) == PackageManager.PERMISSION_GRANTED
            ) {
                gattClient?.disconnect()
                gattClient?.close()
                gattClient = null
            }
        }
    }

    private fun determineDeviceType(device: BluetoothDevice): DiscoveredDevice.DeviceType {
        return try {
            if (ActivityCompat.checkSelfPermission(
                    context,
                    Manifest.permission.BLUETOOTH_CONNECT
                ) == PackageManager.PERMISSION_GRANTED
            ) {
                when (device.type) {
                    BluetoothDevice.DEVICE_TYPE_LE -> DiscoveredDevice.DeviceType.PHONE
                    BluetoothDevice.DEVICE_TYPE_CLASSIC -> DiscoveredDevice.DeviceType.LAPTOP
                    BluetoothDevice.DEVICE_TYPE_DUAL -> DiscoveredDevice.DeviceType.TABLET
                    else -> DiscoveredDevice.DeviceType.UNKNOWN
                }
            } else {
                DiscoveredDevice.DeviceType.UNKNOWN
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error determining device type", e)
            DiscoveredDevice.DeviceType.UNKNOWN
        }
    }

    fun stopAllOperations() {
        if (ActivityCompat.checkSelfPermission(
                context,
                Manifest.permission.BLUETOOTH_SCAN
            ) == PackageManager.PERMISSION_GRANTED && isScanning
        ) {
            bluetoothLeScanner?.stopScan(scanCallback)
            isScanning = false
        }

        if (ActivityCompat.checkSelfPermission(
                context,
                Manifest.permission.BLUETOOTH_ADVERTISE
            ) == PackageManager.PERMISSION_GRANTED && isAdvertising
        ) {
            bluetoothLeAdvertiser?.stopAdvertising(null)
            isAdvertising = false
        }

        if (ActivityCompat.checkSelfPermission(
                context,
                Manifest.permission.BLUETOOTH_CONNECT
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            gattClient?.disconnect()
            gattClient?.close()
            gattClient = null
            
            gattServer?.close()
            gattServer = null
        }
    }

    fun generateDeviceChecksum(): String {
        val deviceInfo = "${Build.MODEL}-${Build.MANUFACTURER}-${Build.SERIAL}"
        return MessageDigest.getInstance("MD5")
            .digest(deviceInfo.toByteArray())
            .joinToString("") { "%02x".format(it) }
    }
}
