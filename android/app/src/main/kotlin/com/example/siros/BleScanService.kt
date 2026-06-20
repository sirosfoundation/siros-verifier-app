package com.example.siros

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Intent
import android.os.Binder
import android.os.IBinder
import android.os.ParcelUuid
import java.util.UUID

class BleScanService : Service() {
    companion object {
        const val CHANNEL_ID = "ble_scan_channel"
        var onDeviceFound: ((String) -> Unit)? = null
        var onScanFailed: ((Int) -> Unit)? = null
    }

    private val binder = LocalBinder()
    private var scanCallback: ScanCallback? = null

    inner class LocalBinder : Binder() {
        fun getService(): BleScanService = this@BleScanService
    }

    override fun onBind(intent: Intent): IBinder = binder

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        val notification = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("mDL Verifier")
            .setContentText("Scanning for wallet...")
            .setSmallIcon(android.R.drawable.ic_menu_search)
            .build()
        startForeground(1, notification)
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "BLE Scan",
            NotificationManager.IMPORTANCE_LOW
        )
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    fun startScan(serviceUuid: String) {
        val targetUuid = UUID.fromString(serviceUuid)
        val bluetoothManager = getSystemService(BluetoothManager::class.java)

        scanCallback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, scanResult: ScanResult) {
                val uuids = scanResult.scanRecord?.serviceUuids
                val mac = scanResult.device.address
                android.util.Log.i("BLESCAN_SVC",
                    "Device: $mac uuids:$uuids")
                val hasUuid = uuids?.any { it.uuid == targetUuid } == true
                if (hasUuid) {
                    android.util.Log.i("BLESCAN_SVC", "*** MATCHED: $mac ***")
                    bluetoothManager.adapter.bluetoothLeScanner.stopScan(this)
                    onDeviceFound?.invoke(mac)
                }
            }
            override fun onScanFailed(errorCode: Int) {
                android.util.Log.e("BLESCAN_SVC", "Scan failed: $errorCode")
                onScanFailed?.invoke(errorCode)
            }
        }

        val filter = ScanFilter.Builder()
            .setServiceUuid(ParcelUuid(targetUuid))
            .build()
        val settings = ScanSettings.Builder()
            .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

        bluetoothManager.adapter.bluetoothLeScanner.startScan(
            listOf(filter), settings, scanCallback!!
        )
        android.util.Log.i("BLESCAN_SVC", "Scan started for $serviceUuid")
    }

    fun stopScan() {
        val bluetoothManager = getSystemService(BluetoothManager::class.java)
        scanCallback?.let {
            bluetoothManager.adapter.bluetoothLeScanner?.stopScan(it)
            scanCallback = null
        }
    }

    override fun onDestroy() {
        stopScan()
        super.onDestroy()
    }
}