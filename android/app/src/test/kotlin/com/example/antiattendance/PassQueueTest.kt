package com.example.antiattendance

import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class PassQueueTest {
    private var elapsed = 1000L
    private var wall = 1000L
    private val command = byteArrayOf(0x00, 0xa4.toByte(), 0x04, 0x00)

    @Before fun setup() {
        PassQueue.stop()
        PassQueue.elapsedTime = { elapsed }
        PassQueue.wallTime = { wall }
    }

    @After fun cleanup() {
        PassQueue.stop()
        PassQueue.elapsedTime = { android.os.SystemClock.elapsedRealtime() }
        PassQueue.wallTime = { System.currentTimeMillis() }
    }

    @Test fun protocolIsVariableLengthLittleEndian() {
        assertArrayEquals(byteArrayOf(0x01, 0x90.toByte(), 0x00), PassQueue.encode(1))
        assertArrayEquals(byteArrayOf(0xbc.toByte(), 0x0a, 0x90.toByte(), 0x00), PassQueue.encode(0xabc))
        assertArrayEquals(byteArrayOf(0xff.toByte(), 0xff.toByte(), 0x90.toByte(), 0x00), PassQueue.encode(65535))
        assertEquals(10, PassQueue.encode(Long.MAX_VALUE).size)
    }

    @Test fun advancesAutomaticallyOnlyAfterResponseAndDelay() {
        PassQueue.start(listOf(PassQueue.Pass("a", 123, 999999), PassQueue.Pass("self", 456, 999999)), 60)
        elapsed += 120000
        assertEquals("a", PassQueue.status()["accountId"])
        assertArrayEquals(PassQueue.encode(123), PassQueue.response(command))
        PassQueue.deactivate()
        elapsed += 59999
        assertEquals("a", PassQueue.status()["accountId"])
        assertArrayEquals(PassQueue.encode(123), PassQueue.response(command))
        elapsed++
        assertEquals("self", PassQueue.status()["accountId"])
        assertArrayEquals(PassQueue.encode(456), PassQueue.response(command))
        elapsed += 60000
        assertEquals(false, PassQueue.status()["armed"])
        assertEquals(2, PassQueue.status()["presented"])
        assertArrayEquals(byteArrayOf(0x69, 0x85.toByte()), PassQueue.response(command))
    }

    @Test fun expiryAndStopPreventCredentialPresentation() {
        PassQueue.start(listOf(PassQueue.Pass("a", 123, 2000)), 1)
        wall = 2000
        assertArrayEquals(byteArrayOf(0x69, 0x85.toByte()), PassQueue.response(command))
        assertEquals(true, PassQueue.status()["expired"])
        assertEquals(0, PassQueue.status()["presented"])
        PassQueue.stop()
        assertEquals(0, PassQueue.status()["total"])
        assertArrayEquals(byteArrayOf(0x69, 0x85.toByte()), PassQueue.response(command))
    }
}
