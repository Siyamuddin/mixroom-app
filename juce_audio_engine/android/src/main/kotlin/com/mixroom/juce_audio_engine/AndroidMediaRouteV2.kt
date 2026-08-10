package com.mixroom.juce_audio_engine

import android.media.AudioDeviceInfo

internal enum class AndroidRouteKindV2(val wireValue: String) {
  BUILT_IN("builtIn"),
  WIRED("wired"),
  EXTERNAL("external"),
  BLUETOOTH_MEDIA("bluetoothMedia"),
  BLUETOOTH_DUPLEX("bluetoothDuplex"),
  BLUETOOTH_LE("bluetoothLe"),
  UNKNOWN("unknown"),
}

internal data class AndroidRouteEndpointV2(
  val id: Int,
  val type: Int,
  val name: String,
  val channelCount: Int?,
) {
  val kind: AndroidRouteKindV2 get() = classifyAndroidRouteKindV2(type)
  val fingerprint: String get() = "$id:$type"
}

internal data class AndroidMediaRouteResolutionV2(
  val endpoint: AndroidRouteEndpointV2?,
  val diagnosticCode: String,
) {
  val isBluetooth: Boolean
    get() = endpoint?.kind == AndroidRouteKindV2.BLUETOOTH_MEDIA ||
      endpoint?.kind == AndroidRouteKindV2.BLUETOOTH_LE
}

internal data class AndroidOboeOutputFactsV2(
  val available: Boolean,
  val running: Boolean,
  val routedDeviceId: Int?,
  val sampleRateHz: Int?,
  val bufferFrames: Int?,
  val bufferCapacityFrames: Int?,
  val framesPerBurst: Int?,
  val audioBackend: String?,
  val performanceMode: String?,
  val sharingMode: String?,
) {
  companion object {
    fun fromMap(map: Map<String, Any>) = AndroidOboeOutputFactsV2(
      available = map["available"] == true,
      running = map["running"] == true,
      routedDeviceId = (map["routedDeviceId"] as? Number)?.toInt(),
      sampleRateHz = (map["sampleRateHz"] as? Number)?.toInt(),
      bufferFrames = (map["bufferFrames"] as? Number)?.toInt(),
      bufferCapacityFrames = (map["bufferCapacityFrames"] as? Number)?.toInt(),
      framesPerBurst = (map["framesPerBurst"] as? Number)?.toInt(),
      audioBackend = map["audioBackend"]?.toString(),
      performanceMode = map["performanceMode"]?.toString(),
      sharingMode = map["sharingMode"]?.toString(),
    )
  }
}

internal fun classifyAndroidRouteKindV2(type: Int): AndroidRouteKindV2 = when (type) {
  AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
  AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
  AudioDeviceInfo.TYPE_BUILTIN_SPEAKER_SAFE -> AndroidRouteKindV2.BUILT_IN
  AudioDeviceInfo.TYPE_WIRED_HEADSET,
  AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
  AudioDeviceInfo.TYPE_LINE_ANALOG,
  AudioDeviceInfo.TYPE_LINE_DIGITAL,
  AudioDeviceInfo.TYPE_AUX_LINE -> AndroidRouteKindV2.WIRED
  AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> AndroidRouteKindV2.BLUETOOTH_MEDIA
  AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> AndroidRouteKindV2.BLUETOOTH_DUPLEX
  AudioDeviceInfo.TYPE_BLE_HEADSET,
  AudioDeviceInfo.TYPE_BLE_SPEAKER,
  AudioDeviceInfo.TYPE_BLE_BROADCAST -> AndroidRouteKindV2.BLUETOOTH_LE
  AudioDeviceInfo.TYPE_USB_DEVICE,
  AudioDeviceInfo.TYPE_USB_ACCESSORY,
  AudioDeviceInfo.TYPE_USB_HEADSET,
  AudioDeviceInfo.TYPE_DOCK,
  AudioDeviceInfo.TYPE_HDMI,
  AudioDeviceInfo.TYPE_HDMI_ARC,
  AudioDeviceInfo.TYPE_HDMI_EARC -> AndroidRouteKindV2.EXTERNAL
  else -> AndroidRouteKindV2.UNKNOWN
}

internal object AndroidMediaRouteResolverV2 {
  fun resolve(
    apiLevel: Int,
    bluetoothA2dpActive: Boolean,
    bluetoothScoActive: Boolean,
    mediaDevices: List<AndroidRouteEndpointV2>,
    outputDevices: List<AndroidRouteEndpointV2>,
  ): AndroidMediaRouteResolutionV2 {
    if (apiLevel >= 33) {
      val unique = mediaDevices.distinctBy { it.id }
      if (unique.size != 1) {
        return AndroidMediaRouteResolutionV2(null, "bluetooth_route_unverified")
      }
      val endpoint = unique.single()
      return when (endpoint.kind) {
        AndroidRouteKindV2.BLUETOOTH_DUPLEX ->
          AndroidMediaRouteResolutionV2(endpoint, "bluetooth_duplex_forbidden")
        AndroidRouteKindV2.UNKNOWN ->
          if (bluetoothA2dpActive) {
            AndroidMediaRouteResolutionV2(endpoint, "bluetooth_route_unverified")
          } else {
            AndroidMediaRouteResolutionV2(endpoint, "ok")
          }
        else -> AndroidMediaRouteResolutionV2(endpoint, "ok")
      }
    }

    if (bluetoothScoActive) {
      val sco = outputDevices.firstOrNull { it.kind == AndroidRouteKindV2.BLUETOOTH_DUPLEX }
      return AndroidMediaRouteResolutionV2(sco, "bluetooth_duplex_forbidden")
    }
    if (!bluetoothA2dpActive) return AndroidMediaRouteResolutionV2(null, "ok")
    val a2dp = outputDevices
      .filter { it.kind == AndroidRouteKindV2.BLUETOOTH_MEDIA }
      .distinctBy { it.id }
    return if (a2dp.size == 1) {
      AndroidMediaRouteResolutionV2(a2dp.single(), "ok")
    } else {
      AndroidMediaRouteResolutionV2(null, "bluetooth_route_unverified")
    }
  }
}

internal object AndroidBluetoothStartupValidatorV2 {
  fun validate(
    expected: AndroidRouteEndpointV2,
    actual: AndroidMediaRouteResolutionV2,
    stream: AndroidOboeOutputFactsV2,
  ): String {
    if (actual.diagnosticCode != "ok" || actual.endpoint == null) {
      return actual.diagnosticCode.takeIf { it != "ok" } ?: "bluetooth_route_unverified"
    }
    if (actual.endpoint.fingerprint != expected.fingerprint) return "route_unstable"
    if (actual.endpoint.kind == AndroidRouteKindV2.BLUETOOTH_DUPLEX) {
      return "bluetooth_duplex_forbidden"
    }
    if (!stream.available || stream.routedDeviceId != expected.id) {
      return "bluetooth_route_unverified"
    }
    if (
      !stream.running ||
      (stream.sampleRateHz ?: 0) <= 0 ||
      (stream.bufferFrames ?: 0) <= 0 ||
      (stream.bufferCapacityFrames ?: 0) <= 0 ||
      (stream.framesPerBurst ?: 0) <= 0 ||
      stream.audioBackend != "AAudio" ||
      stream.performanceMode != "None" ||
      stream.sharingMode != "Shared"
    ) {
      return "actual_state_unavailable"
    }
    return "ok"
  }
}

internal object AndroidLiveRouteValidatorV2 {
  fun validate(
    expected: AndroidMediaRouteResolutionV2,
    actual: AndroidMediaRouteResolutionV2,
    actualEndpoint: AndroidRouteEndpointV2?,
    stream: AndroidOboeOutputFactsV2,
  ): String {
    if (expected.diagnosticCode != "ok") return expected.diagnosticCode
    if (actual.diagnosticCode != "ok") return actual.diagnosticCode
    if (
      !stream.available ||
      !stream.running ||
      (stream.routedDeviceId ?: 0) <= 0 ||
      (stream.sampleRateHz ?: 0) <= 0 ||
      (stream.bufferFrames ?: 0) <= 0 ||
      (stream.bufferCapacityFrames ?: 0) <= 0 ||
      (stream.framesPerBurst ?: 0) <= 0 ||
      stream.audioBackend != "AAudio" ||
      stream.sharingMode != "Shared"
    ) {
      return "actual_state_unavailable"
    }

    val expectedEndpoint = expected.endpoint
    if (expectedEndpoint != null) {
      val actualResolved = actual.endpoint ?: return "route_unstable"
      if (
        actualResolved.fingerprint != expectedEndpoint.fingerprint ||
        stream.routedDeviceId != expectedEndpoint.id
      ) {
        return "route_unstable"
      }
      if (expectedEndpoint.kind == AndroidRouteKindV2.BLUETOOTH_DUPLEX) {
        return "bluetooth_duplex_forbidden"
      }
      if (
        expected.isBluetooth &&
        stream.performanceMode != "None"
      ) {
        return "actual_state_unavailable"
      }
      return "ok"
    }

    val routedEndpoint = actualEndpoint ?: return "actual_state_unavailable"
    if (stream.routedDeviceId != routedEndpoint.id) return "route_unstable"
    return when (routedEndpoint.kind) {
      AndroidRouteKindV2.BLUETOOTH_DUPLEX -> "bluetooth_duplex_forbidden"
      AndroidRouteKindV2.BLUETOOTH_MEDIA,
      AndroidRouteKindV2.BLUETOOTH_LE -> "route_unstable"
      else -> "ok"
    }
  }
}
