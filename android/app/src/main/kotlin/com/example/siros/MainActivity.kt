package com.example.siros

import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.os.Build
import android.os.ParcelUuid
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.siros/ble"
    private var pendingAdvertiseResult: MethodChannel.Result? = null
    private var pendingResponseResult: MethodChannel.Result? = null
    private var pendingSendResult: MethodChannel.Result? = null
    private var gattServer: BluetoothGattServer? = null
    private var advertiser: android.bluetooth.le.BluetoothLeAdvertiser? = null
    private var advertiseCallback: AdvertiseCallback? = null
    private var connectedDevice: BluetoothDevice? = null
    private var mtu = 517
    private var identValue: ByteArray? = null

    private val SERVER2CLIENT_UUID = UUID.fromString("00000005-a123-48ce-896b-4c76973373e6")
    private val CLIENT2SERVER_UUID = UUID.fromString("00000006-a123-48ce-896b-4c76973373e6")
    private val STATE_UUID         = UUID.fromString("00000007-a123-48ce-896b-4c76973373e6")
    private val IDENT_UUID         = UUID.fromString("00000008-a123-48ce-896b-4c76973373e6")
    private val CCC_UUID           = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

    private var incomingBuffer = mutableListOf<Byte>()
    private var serviceUuid: UUID? = null
    private var pendingSessionEstablishment: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "advertiseAndWait" -> {
                        val uuid = call.argument<String>("uuid")!!
                        val eReaderKeyCose = call.argument<ByteArray>("eReaderKeyCose")
                            ?: (call.argument<List<Int>>("eReaderKeyCose")
                                ?.map { it.toByte() }?.toByteArray()) ?: byteArrayOf()
                        advertiseAndWait(uuid, eReaderKeyCose, result)
                    }
                    "sendData" -> {
                        val data = call.argument<ByteArray>("data")
                            ?: (call.argument<List<Int>>("data")
                                ?.map { it.toByte() }?.toByteArray()) ?: byteArrayOf()
                        pendingSessionEstablishment = data
                        pendingSendResult = result
                        android.util.Log.i("BLEADV",
                            "SessionEstablishment ready (${data.size} bytes), waiting for START...")
                    }
                    "waitForResponse" -> {
                        pendingResponseResult = result
                        android.util.Log.i("BLEADV", "Waiting for DeviceResponse...")
                    }
                    "stopAdvertise" -> {
                        stopAdvertise()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ── IDENT helpers ─────────────────────────────────────────────────────────

    private fun cborBstr(bytes: ByteArray): ByteArray {
        val len = bytes.size
        return when {
            len < 24 -> byteArrayOf((0x40 or len).toByte()) + bytes
            len < 256 -> byteArrayOf(0x58.toByte(), len.toByte()) + bytes
            else -> byteArrayOf(
                0x59.toByte(),
                (len shr 8).toByte(),
                (len and 0xff).toByte()
            ) + bytes
        }
    }

    // ikm = Cbor.encode(Tagged(24, Bstr(eReaderKeyCose)))
    // = #6.24(bstr(eReaderKeyCose))
    // = 0xd8 0x18 + cborBstr(eReaderKeyCose)
    private fun buildIdentIkm(eReaderKeyCose: ByteArray): ByteArray {
        return byteArrayOf(0xd8.toByte(), 0x18.toByte()) + cborBstr(eReaderKeyCose)
    }

    // HKDF with salt=zeros(32), matching multipaz Hkdf.deriveKey(salt=null)
    private fun hkdfDerive(ikm: ByteArray, infoStr: String, length: Int): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        // Extract: PRK = HMAC(salt=zeros(32), IKM)
        mac.init(SecretKeySpec(ByteArray(32), "HmacSHA256"))
        val prk = mac.doFinal(ikm)
        // Expand: OKM = HMAC(PRK, info || 0x01)
        mac.init(SecretKeySpec(prk, "HmacSHA256"))
        val infoBytes = infoStr.toByteArray(Charsets.UTF_8) + byteArrayOf(0x01)
        val okm = mac.doFinal(infoBytes)
        return okm.copyOf(length)
    }

    private fun computeIdentValue(eReaderKeyCose: ByteArray): ByteArray {
        android.util.Log.i("BLEADV", "received eReaderKeyCose (${eReaderKeyCose.size}b): ${eReaderKeyCose.joinToString("") { (it.toInt() and 0xff).toString(16).padStart(2,'0') }}")
        val ikm = buildIdentIkm(eReaderKeyCose)
        val ident = hkdfDerive(ikm, "BLEIdent", 16)
        android.util.Log.i("BLEADV",
            "eReaderKeyCose (${eReaderKeyCose.size}b): ${eReaderKeyCose.joinToString("") { (it.toInt() and 0xff).toString(16).padStart(2, '0') }}")
        android.util.Log.i("BLEADV",
            "ikm (${ikm.size}b): ${ikm.joinToString("") { (it.toInt() and 0xff).toString(16).padStart(2, '0') }}")
        android.util.Log.i("BLEADV",
            "IDENT: ${ident.joinToString("") { (it.toInt() and 0xff).toString(16).padStart(2, '0') }}")
        return ident
    }

    // ── Reset ─────────────────────────────────────────────────────────────────

    private fun fullReset() {
        incomingBuffer.clear()
        pendingResponseResult = null
        pendingSessionEstablishment = null
        pendingSendResult = null
        android.util.Log.i("BLEADV", "Buffer reset")
    }

    // ── Send SessionEstablishment ─────────────────────────────────────────────

    private fun flushPendingData() {
        val data = pendingSessionEstablishment ?: return
        val device = connectedDevice ?: return
        pendingSessionEstablishment = null

        android.util.Log.i("BLEADV", "Sending SessionEstablishment after 1000ms delay...")

        Thread {
            Thread.sleep(1000)

            val service = gattServer?.getService(serviceUuid!!) ?: return@Thread
            val stateChar = service.getCharacteristic(STATE_UUID) ?: return@Thread

            try {
                val maxChunk = mtu - 4
                var offset = 0
                while (offset < data.size) {
                    val end = minOf(offset + maxChunk, data.size)
                    val isLast = end == data.size
                    val chunk = ByteArray(end - offset + 1)
                    chunk[0] = if (isLast) 0x00 else 0x01
                    data.copyInto(chunk, 1, offset, end)

                    android.util.Log.i("BLEADV",
                        "Sending chunk ${if (isLast) "LAST" else "MORE"}: ${chunk.size} bytes")

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        gattServer?.notifyCharacteristicChanged(device, stateChar, false, chunk)
                    } else {
                        @Suppress("DEPRECATION")
                        stateChar.value = chunk
                        @Suppress("DEPRECATION")
                        gattServer?.notifyCharacteristicChanged(device, stateChar, false)
                    }
                    Thread.sleep(50)
                    offset = end
                }
                android.util.Log.i("BLEADV", "Sent ${data.size} bytes on STATE char")
                runOnUiThread {
                    pendingSendResult?.success(null)
                    pendingSendResult = null
                }
            } catch (e: Exception) {
                android.util.Log.e("BLEADV", "Send failed: ${e.message}")
                runOnUiThread {
                    pendingSendResult?.error("SEND_FAILED", e.message, null)
                    pendingSendResult = null
                }
            }
        }.start()
    }

    // ── Advertise ─────────────────────────────────────────────────────────────

    private fun advertiseAndWait(
        uuid: String,
        eReaderKeyCose: ByteArray,
        result: MethodChannel.Result
    ) {
        stopAdvertise()
        fullReset()
        pendingAdvertiseResult = result
        serviceUuid = UUID.fromString(uuid)

        // Compute BLEIdent from eReaderKeyCose
        identValue = computeIdentValue(eReaderKeyCose)

        val bluetoothManager = getSystemService(BluetoothManager::class.java)
        val serviceParcelUuid = ParcelUuid(serviceUuid!!)

        android.util.Log.i("BLEADV", "Starting GATT server UUID: $uuid")

        gattServer = bluetoothManager.openGattServer(this,
            object : BluetoothGattServerCallback() {

                override fun onConnectionStateChange(
                    device: BluetoothDevice, status: Int, newState: Int
                ) {
                    android.util.Log.i("BLEADV",
                        "Connection: ${device.address} status=$status newState=$newState")
                    if (newState == BluetoothProfile.STATE_CONNECTED) {
                        android.util.Log.i("BLEADV", "✅ Wallet connected: ${device.address}")
                        fullReset()
                        connectedDevice = device
                        stopAdvertising()
                        val r = pendingAdvertiseResult
                        pendingAdvertiseResult = null
                        runOnUiThread { r?.success(device.address) }
                    } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                        android.util.Log.i("BLEADV", "Wallet disconnected")
                        fullReset()
                        connectedDevice = null
                    }
                }

                override fun onMtuChanged(device: BluetoothDevice, mtu: Int) {
                    android.util.Log.i("BLEADV", "MTU: $mtu")
                    this@MainActivity.mtu = mtu
                }

                override fun onServiceAdded(status: Int, service: BluetoothGattService) {
                    android.util.Log.i("BLEADV", "Service added status=$status")
                    startAdvertising(serviceParcelUuid)
                }

                override fun onCharacteristicReadRequest(
                    device: BluetoothDevice, requestId: Int, offset: Int,
                    characteristic: BluetoothGattCharacteristic
                ) {
                    android.util.Log.i("BLEADV", "Read: ${characteristic.uuid}")
                    val response = if (characteristic.uuid == IDENT_UUID) {
                        identValue ?: byteArrayOf()
                    } else {
                        byteArrayOf()
                    }
                    android.util.Log.i("BLEADV",
                        "Responding IDENT ${response.size}b: ${
                            response.joinToString("") {
                                (it.toInt() and 0xff).toString(16).padStart(2, '0')
                            }
                        }")
                    gattServer?.sendResponse(device, requestId,
                        android.bluetooth.BluetoothGatt.GATT_SUCCESS, 0, response)
                }

                override fun onCharacteristicWriteRequest(
                    device: BluetoothDevice, requestId: Int,
                    characteristic: BluetoothGattCharacteristic,
                    preparedWrite: Boolean, responseNeeded: Boolean,
                    offset: Int, value: ByteArray
                ) {
                    android.util.Log.i("BLEADV",
                        "Write ${characteristic.uuid}: ${value.size} bytes")

                    if (responseNeeded) {
                        gattServer?.sendResponse(device, requestId,
                            android.bluetooth.BluetoothGatt.GATT_SUCCESS, 0, null)
                    }

                    when (characteristic.uuid) {
                        SERVER2CLIENT_UUID -> {
                            android.util.Log.i("BLEADV", "START signal from wallet!")
                            flushPendingData()
                        }
                        CLIENT2SERVER_UUID -> {
                            if (value.isEmpty()) return
                            val isLast = value[0].toInt() == 0x00
                            incomingBuffer.addAll(value.drop(1))
                            if (isLast) {
                                val message = incomingBuffer.toByteArray()
                                incomingBuffer.clear()
                                android.util.Log.i("BLEADV",
                                    "Complete DeviceResponse: ${message.size} bytes")
                                val r = pendingResponseResult
                                pendingResponseResult = null
                                runOnUiThread { r?.success(message) }
                            }
                        }
                    }
                }

                override fun onDescriptorWriteRequest(
                    device: BluetoothDevice, requestId: Int,
                    descriptor: BluetoothGattDescriptor,
                    preparedWrite: Boolean, responseNeeded: Boolean,
                    offset: Int, value: ByteArray
                ) {
                    android.util.Log.i("BLEADV",
                        "Descriptor write ${descriptor.characteristic.uuid}")
                    if (responseNeeded) {
                        gattServer?.sendResponse(device, requestId,
                            android.bluetooth.BluetoothGatt.GATT_SUCCESS, 0, null)
                    }
                }

                override fun onNotificationSent(device: BluetoothDevice, status: Int) {
                    android.util.Log.i("BLEADV", "Notification sent status=$status")
                }
            })

        val service = BluetoothGattService(serviceUuid!!,
            BluetoothGattService.SERVICE_TYPE_PRIMARY)

        // SERVER2CLIENT (00000005): wallet subscribes + sends START
        val s2cChar = BluetoothGattCharacteristic(SERVER2CLIENT_UUID,
            BluetoothGattCharacteristic.PROPERTY_NOTIFY or
                    BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
            BluetoothGattCharacteristic.PERMISSION_WRITE)
        s2cChar.addDescriptor(
            BluetoothGattDescriptor(CCC_UUID, BluetoothGattDescriptor.PERMISSION_WRITE))
        service.addCharacteristic(s2cChar)

        // CLIENT2SERVER (00000006): wallet sends DeviceResponse
        val c2sChar = BluetoothGattCharacteristic(CLIENT2SERVER_UUID,
            BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
            BluetoothGattCharacteristic.PERMISSION_WRITE)
        service.addCharacteristic(c2sChar)

        // STATE (00000007): we send SessionEstablishment here
        val stateChar = BluetoothGattCharacteristic(STATE_UUID,
            BluetoothGattCharacteristic.PROPERTY_NOTIFY or
                    BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
            BluetoothGattCharacteristic.PERMISSION_WRITE)
        stateChar.addDescriptor(
            BluetoothGattDescriptor(CCC_UUID, BluetoothGattDescriptor.PERMISSION_WRITE))
        service.addCharacteristic(stateChar)

        // IDENT (00000008): wallet reads to verify identity
        val identChar = BluetoothGattCharacteristic(IDENT_UUID,
            BluetoothGattCharacteristic.PROPERTY_READ,
            BluetoothGattCharacteristic.PERMISSION_READ)
        service.addCharacteristic(identChar)

        gattServer?.addService(service)
    }

    private fun startAdvertising(serviceUuid: ParcelUuid) {
        val bluetoothManager = getSystemService(BluetoothManager::class.java)
        advertiser = bluetoothManager.adapter.bluetoothLeAdvertiser
        if (advertiser == null) {
            android.util.Log.e("BLEADV", "No advertiser")
            return
        }
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)
            .setTimeout(0)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .build()
        val data = AdvertiseData.Builder()
            .setIncludeTxPowerLevel(false)
            .addServiceUuid(serviceUuid)
            .build()
        advertiseCallback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                android.util.Log.i("BLEADV", "✅ Advertising started!")
            }
            override fun onStartFailure(errorCode: Int) {
                android.util.Log.e("BLEADV", "Advertising failed: $errorCode")
                val r = pendingAdvertiseResult
                pendingAdvertiseResult = null
                runOnUiThread {
                    r?.error("ADV_FAILED", "Advertising failed: $errorCode", null)
                }
            }
        }
        advertiser?.startAdvertising(settings, data, advertiseCallback!!)
        android.util.Log.i("BLEADV", "Advertising UUID: ${serviceUuid.uuid}")
    }

    private fun stopAdvertising() {
        advertiseCallback?.let {
            advertiser?.stopAdvertising(it)
            advertiseCallback = null
        }
    }

    private fun stopAdvertise() {
        stopAdvertising()
        gattServer?.close()
        gattServer = null
        pendingAdvertiseResult = null
        connectedDevice = null
        fullReset()
    }

    override fun onDestroy() {
        stopAdvertise()
        super.onDestroy()
    }
}