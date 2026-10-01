package com.example.antiattendance

import android.nfc.cardemulation.HostApduService
import android.nfc.cardemulation.PollingFrame
import android.os.Build
import android.os.Bundle

object TurnstileProbeBridge {
    var onFrames: ((List<Map<String, Any>>) -> Unit)? = null
}

/** Listens to reader polling only. It never replies with a credential. */
class TurnstileProbeService : HostApduService() {
    override fun processCommandApdu(commandApdu: ByteArray?, extras: Bundle?): ByteArray =
        byteArrayOf(0x6A, 0x82.toByte()) // File/application not found.

    override fun onDeactivated(reason: Int) = Unit

    override fun processPollingFrames(frames: MutableList<PollingFrame>) {
        if (Build.VERSION.SDK_INT < 35) return
        val result = frames.map { frame ->
            mapOf<String, Any>(
                "type" to when (frame.type) {
                    PollingFrame.POLLING_LOOP_TYPE_A -> "NFC-A"
                    PollingFrame.POLLING_LOOP_TYPE_B -> "NFC-B"
                    PollingFrame.POLLING_LOOP_TYPE_F -> "NFC-F"
                    PollingFrame.POLLING_LOOP_TYPE_ON -> "Field on"
                    PollingFrame.POLLING_LOOP_TYPE_OFF -> "Field off"
                    else -> "Unknown"
                },
                "data" to frame.data.joinToString(" ") { "%02X".format(it.toInt() and 0xFF) },
                "timestampUs" to frame.timestamp,
                "gain" to frame.vendorSpecificGain,
            )
        }
        TurnstileProbeBridge.onFrames?.invoke(result)
    }
}
