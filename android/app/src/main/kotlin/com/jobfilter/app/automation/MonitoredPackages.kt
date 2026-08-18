package com.jobfilter.app.automation

/**
 * Official public package identifiers for the two supported driver apps.
 * Kept as the single source of truth on the native side (mirrors
 * PlatformType.androidPackageName in Dart) so accessibility_service_config.xml,
 * [JobAccessibilityService], and any future package-visibility checks never
 * drift apart.
 */
object MonitoredPackages {
    const val UBER_DRIVER = "com.ubercab.driver"
    const val BOLT_DRIVER = "ee.mtakso.driver"

    val ANDROID_PACKAGE_NAMES: Set<String> = setOf(UBER_DRIVER, BOLT_DRIVER)
}
