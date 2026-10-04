package com.example.antiattendance

import android.nfc.cardemulation.HostApduService
import android.nfc.NfcAdapter
import android.nfc.cardemulation.CardEmulation
import android.content.ComponentName
import android.os.Bundle

class DigitalPassService : HostApduService() {
    override fun onCreate() {
        super.onCreate()
        // Dynamic registrations can survive process death; a newly created
        // process has no credentials and must release any stale campus route.
        if (!PassQueue.armed) {
            try {
                NfcAdapter.getDefaultAdapter(this)?.let {
                    CardEmulation.getInstance(it).removeAidsForService(
                        ComponentName(this, DigitalPassService::class.java), CardEmulation.CATEGORY_OTHER,
                    )
                }
            } catch (_: Exception) { }
        }
    }
    override fun processCommandApdu(commandApdu: ByteArray?, extras: Bundle?): ByteArray =
        PassQueue.response(commandApdu)

    override fun onDeactivated(reason: Int) = PassQueue.deactivate()
}
