package com.mixroom.juce_audio_engine
import kotlin.test.*

class AndroidCaptureLifecycleV2Test {
  private class Native : AndroidCaptureNativeV2 {
    var active = false
    var monitor = true
    var target = 3
    var epoch = 42L
    var startResult = true
    var throwStart = false
    var throwStop = false
    var stopResult = true
    var onStart: () -> Unit = {}
    var onStop: () -> Unit = {}
    val calls = mutableListOf<String>()
    override fun isRecording() = active
    override fun start(path: String, channelStart: Int, channelCount: Int): Boolean {
      calls += "start:$channelStart:$channelCount"
      active = startResult
      onStart()
      if (throwStart) throw IllegalStateException("writer")
      return startResult
    }
    override fun stop(preserveMonitoring: Boolean): Map<String, Any> {
      calls += "stop:$preserveMonitoring"
      if (throwStop) throw IllegalStateException("writer")
      active = false
      if (!preserveMonitoring) { monitor = false; epoch++ }
      onStop()
      return mapOf("success" to stopResult, "diagnosticCode" to if (stopResult) "ok" else "writer_finalize_failed", "acceptedSamples" to 128L)
    }
    override fun discard(preserveMonitoring: Boolean) {
      calls += "discard:$preserveMonitoring"
      active = false
      if (!preserveMonitoring) { monitor = false; epoch++ }
    }
  }
  private fun AndroidCaptureLifecycleV2.begin(
    channel: Int = 2, count: Int = 2, preserve: Boolean = true,
    valid: () -> Boolean = { true }, cancelled: () -> Boolean = { false },
  ) = start("take.wav", 2, 2, channel, count, preserve, valid, cancelled)

  @Test fun repeatedTakesPreserveMonitoringTargetAndEpoch() {
    val native = Native()
    val lifecycle = AndroidCaptureLifecycleV2(native)
    repeat(3) {
      assertTrue(lifecycle.begin())
      assertFalse(lifecycle.begin(), "duplicate start")
      assertEquals(true, lifecycle.stop(true) { true }["success"])
      assertTrue(native.monitor)
      assertEquals(3, native.target)
      assertEquals(42L, native.epoch)
    }
    assertEquals(listOf("start:2:2", "stop:true", "start:2:2", "stop:true", "start:2:2", "stop:true"), native.calls)
  }
  @Test fun mismatchedChannelsAndCancelledAdmissionDoNotTouchNative() {
    val native = Native()
    val lifecycle = AndroidCaptureLifecycleV2(native)
    assertFalse(lifecycle.begin(channel = 1))
    assertFalse(lifecycle.begin(count = 1))
    assertFalse(lifecycle.begin(cancelled = { true })); assertFalse(lifecycle.begin(valid = { false }))
    assertTrue(native.calls.isEmpty())
    assertTrue(native.monitor)
  }
  @Test fun cancellationDuringStartDiscardsOnlyCapture() {
    val native = Native(); var cancelled = false; native.onStart = { cancelled = true }
    assertFalse(AndroidCaptureLifecycleV2(native).begin(cancelled = { cancelled }))
    assertEquals(listOf("start:2:2", "discard:true"), native.calls)
    assertFalse(native.active)
    assertTrue(native.monitor)
  }
  @Test fun staleStartCannotPublishCapture() {
    val native = Native()
    var current = true
    native.onStart = { current = false; native.monitor = false; native.epoch++ }
    assertFalse(AndroidCaptureLifecycleV2(native).begin(valid = { current }))
    assertFalse(native.active)
    assertFalse(native.monitor)
    assertEquals(43L, native.epoch)
  }
  @Test fun writerFailureLeavesMonitorUsableForNextTake() {
    val native = Native()
    val lifecycle = AndroidCaptureLifecycleV2(native)
    native.startResult = false
    assertFalse(lifecycle.begin())
    native.startResult = true
    native.throwStart = true
    assertFalse(lifecycle.begin())
    assertFalse(native.active)
    assertTrue(native.monitor)
    native.throwStart = false
    assertTrue(lifecycle.begin())
    native.throwStop = true
    assertEquals(false, lifecycle.stop(true) { true }["success"])
    assertFalse(native.active)
    assertTrue(native.monitor)
    native.throwStop = false
    assertTrue(lifecycle.begin())
    assertEquals(true, lifecycle.stop(true) { true }["success"])
  }
  @Test fun routeInvalidationDuringStopCannotPublishOrReactivate() {
    val native = Native()
    val lifecycle = AndroidCaptureLifecycleV2(native)
    var current = true
    assertTrue(lifecycle.begin())
    native.onStop = { current = false; native.monitor = false; native.epoch++ }
    val result = lifecycle.stop(true) { current }
    assertEquals(false, result["success"])
    assertEquals("route_unstable", result["diagnosticCode"])
    assertFalse(native.monitor)
    assertEquals(43L, native.epoch)
  }
  @Test fun staleStopDoesNotTouchReplacementCapture() {
    val native = Native()
    native.active = true
    assertEquals(false, AndroidCaptureLifecycleV2(native).stop(true) { false }["success"])
    assertTrue(native.active)
    assertTrue(native.calls.isEmpty())
  }
  @Test fun recordingOnlyRetainsItsExistingCleanup() {
    val native = Native()
    native.monitor = false
    val lifecycle = AndroidCaptureLifecycleV2(native)
    assertTrue(lifecycle.begin(preserve = false))
    assertEquals(true, lifecycle.stop(false) { true }["success"])
    assertEquals(listOf("start:2:2", "stop:false"), native.calls)
    assertFalse(native.monitor)
  }

  @Test fun finalizationFailureReportPreservesMonitorAndAllowsNextTake() {
    val native = Native()
    val lifecycle = AndroidCaptureLifecycleV2(native)
    assertTrue(lifecycle.begin())
    native.stopResult = false
    assertEquals(false, lifecycle.stop(true) { true }["success"])
    assertTrue(native.monitor)
    assertEquals(42L, native.epoch)
    native.stopResult = true
    assertTrue(lifecycle.begin())
    assertEquals(true, lifecycle.stop(true) { true }["success"])
  }

  @Test fun monoCaptureCanShareAnOwnedChannelWithoutRetargeting() {
    val native = Native()
    val lifecycle = AndroidCaptureLifecycleV2(native)
    assertTrue(lifecycle.start("mono.wav", 1, 1, 1, 1, true, { true }, { false }))
    assertEquals(true, lifecycle.stop(true) { true }["success"])
    assertEquals(listOf("start:1:1", "stop:true"), native.calls)
    assertEquals(3, native.target)
    assertEquals(42L, native.epoch)
  }
}
