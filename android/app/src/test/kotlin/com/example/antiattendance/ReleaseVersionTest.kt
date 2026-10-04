package com.example.antiattendance

import org.junit.Assert.*
import org.junit.Test

class ReleaseVersionTest {
    @Test fun comparesVersionsAndBuilds() {
        assertTrue(ReleaseVersion.isNewer("v1.3.0", "1.2.13", 11))
        assertTrue(ReleaseVersion.isNewer("v1.2.13+12", "1.2.13", 11))
        assertFalse(ReleaseVersion.isNewer("v1.2.13", "1.2.13", 11))
        assertFalse(ReleaseVersion.isNewer("v1.2.13+11", "1.2.13", 11))
        assertFalse(ReleaseVersion.isNewer("v1.2.0", "1.2.13", 11))
        assertFalse(ReleaseVersion.isNewer("nightly", "1.2.13", 11))
        assertFalse(ReleaseVersion.isNewer("v99999999999999999999.0.0", "1.2.13", 11))
    }
}
