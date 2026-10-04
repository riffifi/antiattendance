package com.example.antiattendance

/** Foreground-only test queue. Credentials never leave process memory. */
internal object PassQueue {
    data class Pass(val accountId: String, val number: Long, val expiresAt: Long)
    private var passes: List<Pass> = emptyList()
    private var index = 0
    private var responded = false
    private var advanceAt = 0L
    private var intervalMillis = 60_000L
    internal var elapsedTime: () -> Long = { android.os.SystemClock.elapsedRealtime() }
    internal var wallTime: () -> Long = { System.currentTimeMillis() }
    var armed = false
        private set

    fun start(values: List<Pass>, intervalSeconds: Int) {
        require(intervalSeconds in 1..300)
        require(values.isNotEmpty() && values.size <= 100)
        require(values.all { it.number > 0 && it.expiresAt > wallTime() })
        passes = values.toList()
        index = 0
        responded = false
        advanceAt = 0L
        intervalMillis = intervalSeconds * 1000L
        armed = true
    }

    fun stop() {
        passes = emptyList()
        index = 0
        responded = false
        advanceAt = 0L
        armed = false
    }

    fun response(command: ByteArray?): ByteArray {
        advanceIfDue()
        val pass = passes.getOrNull(index)
        if (!armed || pass == null || pass.expiresAt <= wallTime()) {
            return byteArrayOf(0x69, 0x85.toByte())
        }
        if (command == null || command.size < 4) return byteArrayOf(0x67, 0x00)
        // Pin the same pass throughout the cooldown. Pulse 2.1.0
        // responds with the identifier to all commands routed to its AID.
        responded = true
        if (advanceAt == 0L) advanceAt = elapsedTime() + intervalMillis
        return encode(pass.number)
    }

    fun deactivate() {
        // Link loss does not prove admission. Keep the current pass through
        // the configured gate cooldown, including repeated taps.
        advanceIfDue()
    }

    private fun advanceIfDue() {
        if (armed && advanceAt != 0L && elapsedTime() >= advanceAt) {
            index++
            responded = false
            advanceAt = 0L
            if (index >= passes.size) armed = false
        }
    }

    fun status(): Map<String, Any?> {
        advanceIfDue()
        return mapOf(
        "armed" to armed,
        "presented" to index + if (responded) 1 else 0,
        "total" to passes.size,
        "accountId" to passes.getOrNull(index)?.accountId,
        "responded" to responded,
        "remainingMillis" to if (advanceAt == 0L) 0L else (advanceAt - elapsedTime()).coerceAtLeast(0L),
        "expired" to (passes.getOrNull(index)?.expiresAt?.let { it <= wallTime() } ?: false),
    )
    }

    fun encode(number: Long): ByteArray {
        require(number > 0)
        var value = number
        val bytes = ArrayList<Byte>()
        do {
            bytes.add((value and 0xff).toByte())
            value = value ushr 8
        } while (value != 0L)
        bytes.add(0x90.toByte())
        bytes.add(0x00)
        return bytes.toByteArray()
    }
}
