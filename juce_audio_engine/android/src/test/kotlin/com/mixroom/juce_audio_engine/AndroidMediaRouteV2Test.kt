package com.mixroom.juce_audio_engine

import android.media.AudioDeviceInfo
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class AndroidMediaRouteV2Test {
  private fun endpoint(id: Int, type: Int) =
    AndroidRouteEndpointV2(id, type, "device-$id", 2)

  private fun validStream(deviceId: Int) = AndroidOboeOutputFactsV2(
    available = true,
    running = true,
    routedDeviceId = deviceId,
    sampleRateHz = 48000,
    bufferFrames = 1024,
    bufferCapacityFrames = 1920,
    framesPerBurst = 240,
    audioBackend = "AAudio",
    performanceMode = "None",
    sharingMode = "Shared",
  )

  @Test
  fun api33UsesOneExactMediaRoute() {
    val route = AndroidMediaRouteResolverV2.resolve(
      apiLevel = 33,
      bluetoothA2dpActive = true,
      bluetoothScoActive = false,
      mediaDevices = listOf(endpoint(17, AudioDeviceInfo.TYPE_BLUETOOTH_A2DP)),
      outputDevices = emptyList(),
    )

    assertEquals("ok", route.diagnosticCode)
    assertEquals(17, route.endpoint?.id)
    assertTrue(route.isBluetooth)
  }

  @Test
  fun api33RejectsAmbiguousAndScoRoutes() {
    val ambiguous = AndroidMediaRouteResolverV2.resolve(
      33,
      true,
      false,
      listOf(
        endpoint(17, AudioDeviceInfo.TYPE_BLUETOOTH_A2DP),
        endpoint(18, AudioDeviceInfo.TYPE_BLUETOOTH_A2DP),
      ),
      emptyList(),
    )
    val sco = AndroidMediaRouteResolverV2.resolve(
      33,
      false,
      true,
      listOf(endpoint(19, AudioDeviceInfo.TYPE_BLUETOOTH_SCO)),
      emptyList(),
    )

    assertEquals("bluetooth_route_unverified", ambiguous.diagnosticCode)
    assertEquals("bluetooth_duplex_forbidden", sco.diagnosticCode)
  }

  @Test
  fun api29To32RequiresOneActiveA2dpEndpoint() {
    val valid = AndroidMediaRouteResolverV2.resolve(
      32,
      true,
      false,
      emptyList(),
      listOf(endpoint(7, AudioDeviceInfo.TYPE_BLUETOOTH_A2DP)),
    )
    val duplicate = AndroidMediaRouteResolverV2.resolve(
      32,
      true,
      false,
      emptyList(),
      listOf(
        endpoint(7, AudioDeviceInfo.TYPE_BLUETOOTH_A2DP),
        endpoint(8, AudioDeviceInfo.TYPE_BLUETOOTH_A2DP),
      ),
    )

    assertEquals("ok", valid.diagnosticCode)
    assertEquals("bluetooth_route_unverified", duplicate.diagnosticCode)
  }

  @Test
  fun bleAndUnknownTypesRemainDistinct() {
    val ble = AndroidMediaRouteResolverV2.resolve(
      33,
      false,
      false,
      listOf(endpoint(4, AudioDeviceInfo.TYPE_BLE_SPEAKER)),
      emptyList(),
    )
    val unknown = AndroidMediaRouteResolverV2.resolve(
      33,
      false,
      false,
      listOf(endpoint(5, 999)),
      emptyList(),
    )

    assertEquals(AndroidRouteKindV2.BLUETOOTH_LE, ble.endpoint?.kind)
    assertTrue(ble.isBluetooth)
    assertEquals(AndroidRouteKindV2.UNKNOWN, unknown.endpoint?.kind)
    assertFalse(unknown.isBluetooth)

    val ambiguousBluetooth = AndroidMediaRouteResolverV2.resolve(
      33,
      true,
      false,
      listOf(endpoint(5, 999)),
      emptyList(),
    )
    assertEquals("bluetooth_route_unverified", ambiguousBluetooth.diagnosticCode)
  }

  @Test
  fun bluetoothStartupRequiresExactRouteAndAcceptedStreamFacts() {
    val expected = endpoint(17, AudioDeviceInfo.TYPE_BLUETOOTH_A2DP)
    val actual = AndroidMediaRouteResolutionV2(expected, "ok")

    assertEquals(
      "ok",
      AndroidBluetoothStartupValidatorV2.validate(expected, actual, validStream(17)),
    )
    assertEquals(
      "route_unstable",
      AndroidBluetoothStartupValidatorV2.validate(
        expected,
        AndroidMediaRouteResolutionV2(
          endpoint(18, AudioDeviceInfo.TYPE_BLUETOOTH_A2DP),
          "ok",
        ),
        validStream(17),
      ),
    )
    assertEquals(
      "bluetooth_route_unverified",
      AndroidBluetoothStartupValidatorV2.validate(expected, actual, validStream(18)),
    )
  }

  @Test
  fun bluetoothStartupRejectsUnstableBackendFacts() {
    val expected = endpoint(17, AudioDeviceInfo.TYPE_BLUETOOTH_A2DP)
    val actual = AndroidMediaRouteResolutionV2(expected, "ok")
    val invalid = listOf(
      validStream(17).copy(running = false),
      validStream(17).copy(sampleRateHz = 0),
      validStream(17).copy(bufferFrames = 0),
      validStream(17).copy(bufferCapacityFrames = 0),
      validStream(17).copy(framesPerBurst = 0),
      validStream(17).copy(audioBackend = "OpenSLES"),
      validStream(17).copy(performanceMode = "LowLatency"),
      validStream(17).copy(sharingMode = "Exclusive"),
    )

    for (stream in invalid) {
      assertEquals(
        "actual_state_unavailable",
        AndroidBluetoothStartupValidatorV2.validate(expected, actual, stream),
      )
    }
  }

  @Test
  fun liveTransitionAcceptsExactBluetoothMediaRoute() {
    val endpoint = endpoint(17, AudioDeviceInfo.TYPE_BLUETOOTH_A2DP)
    val route = AndroidMediaRouteResolutionV2(endpoint, "ok")

    assertEquals(
      "ok",
      AndroidLiveRouteValidatorV2.validate(
        route,
        route,
        endpoint,
        validStream(17),
      ),
    )
  }

  @Test
  fun liveTransitionAcceptsVerifiedSystemDefaultSpeaker() {
    val expected = AndroidMediaRouteResolutionV2(null, "ok")
    val speaker = endpoint(3, AudioDeviceInfo.TYPE_BUILTIN_SPEAKER)

    assertEquals(
      "ok",
      AndroidLiveRouteValidatorV2.validate(
        expected,
        expected,
        speaker,
        validStream(3),
      ),
    )
  }

  @Test
  fun liveTransitionRejectsRouteChangesAndDuplexRoutes() {
    val bluetooth = endpoint(17, AudioDeviceInfo.TYPE_BLUETOOTH_A2DP)
    val changed = endpoint(18, AudioDeviceInfo.TYPE_BLUETOOTH_A2DP)
    val sco = endpoint(19, AudioDeviceInfo.TYPE_BLUETOOTH_SCO)

    assertEquals(
      "route_unstable",
      AndroidLiveRouteValidatorV2.validate(
        AndroidMediaRouteResolutionV2(bluetooth, "ok"),
        AndroidMediaRouteResolutionV2(changed, "ok"),
        changed,
        validStream(18),
      ),
    )
    assertEquals(
      "bluetooth_duplex_forbidden",
      AndroidLiveRouteValidatorV2.validate(
        AndroidMediaRouteResolutionV2(sco, "ok"),
        AndroidMediaRouteResolutionV2(sco, "ok"),
        sco,
        validStream(19),
      ),
    )
  }

  @Test
  fun liveTransitionRejectsUnusableStreamAndBluetoothLowLatencyMode() {
    val bluetooth = endpoint(17, AudioDeviceInfo.TYPE_BLUETOOTH_A2DP)
    val route = AndroidMediaRouteResolutionV2(bluetooth, "ok")

    assertEquals(
      "actual_state_unavailable",
      AndroidLiveRouteValidatorV2.validate(
        route,
        route,
        bluetooth,
        validStream(17).copy(running = false),
      ),
    )
    assertEquals(
      "actual_state_unavailable",
      AndroidLiveRouteValidatorV2.validate(
        route,
        route,
        bluetooth,
        validStream(17).copy(performanceMode = "LowLatency"),
      ),
    )
  }
}
