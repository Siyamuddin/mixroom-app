package com.mixroom.juce_audio_engine

import android.media.AudioManager
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class AndroidLegacyScoRouteV2Test {
  @Test
  fun apiFamilySelectsOnePrivateRoutingAdapter() {
    assertEquals(
      AndroidBluetoothRouteSelectionModeV2.LEGACY_SCO,
      AndroidBluetoothRouteSelectionModeV2.forApiLevel(29),
    )
    assertEquals(
      AndroidBluetoothRouteSelectionModeV2.LEGACY_SCO,
      AndroidBluetoothRouteSelectionModeV2.forApiLevel(30),
    )
    assertEquals(
      AndroidBluetoothRouteSelectionModeV2.COMMUNICATION_DEVICE,
      AndroidBluetoothRouteSelectionModeV2.forApiLevel(31),
    )
  }

  @Test
  fun stickyConnectedStateAcquiresWithoutWaitingForAnotherTransition() {
    val state = AndroidLegacyScoStateV2()

    assertEquals(
      AndroidLegacyScoEventV2.ACQUIRED,
      state.beginAcquisition(AudioManager.SCO_AUDIO_STATE_CONNECTED),
    )
    state.markRequestStarted()
    assertTrue(state.isConnected())
    assertTrue(state.claimStopRequest())
    assertFalse(state.claimStopRequest())
  }

  @Test
  fun disconnectedStickyStateIsIgnoredUntilARealConnectionAttemptChangesState() {
    val state = AndroidLegacyScoStateV2()

    assertEquals(
      AndroidLegacyScoEventV2.NONE,
      state.beginAcquisition(AudioManager.SCO_AUDIO_STATE_DISCONNECTED),
    )
    assertEquals(
      AndroidLegacyScoEventV2.NONE,
      state.observe(AudioManager.SCO_AUDIO_STATE_DISCONNECTED),
    )
    assertEquals(
      AndroidLegacyScoEventV2.NONE,
      state.observe(AudioManager.SCO_AUDIO_STATE_CONNECTING),
    )
    assertEquals(
      AndroidLegacyScoEventV2.ACQUIRED,
      state.observe(AudioManager.SCO_AUDIO_STATE_CONNECTED),
    )
    assertTrue(state.isConnected())
  }

  @Test
  fun connectingThenDisconnectedFailsAcquisitionWithoutClaimingPhysicalLoss() {
    val state = AndroidLegacyScoStateV2()

    state.beginAcquisition(AudioManager.SCO_AUDIO_STATE_DISCONNECTED)
    state.markRequestStarted()
    state.observe(AudioManager.SCO_AUDIO_STATE_CONNECTING)
    assertEquals(
      AndroidLegacyScoEventV2.ACQUISITION_FAILED,
      state.observe(AudioManager.SCO_AUDIO_STATE_DISCONNECTED),
    )
    assertFalse(state.isConnected())
    assertFalse(state.beginRelease())
  }

  @Test
  fun disconnectAfterAcquisitionIsTerminalUntilCleanupClaimsRelease() {
    val state = AndroidLegacyScoStateV2()

    state.beginAcquisition(AudioManager.SCO_AUDIO_STATE_DISCONNECTED)
    state.markRequestStarted()
    state.observe(AudioManager.SCO_AUDIO_STATE_CONNECTING)
    state.observe(AudioManager.SCO_AUDIO_STATE_CONNECTED)
    assertEquals(
      AndroidLegacyScoEventV2.TERMINAL_LOSS,
      state.observe(AudioManager.SCO_AUDIO_STATE_DISCONNECTED),
    )
  }

  @Test
  fun expectedReleaseOwnsOneDisconnectedEvent() {
    val state = AndroidLegacyScoStateV2()

    state.beginAcquisition(AudioManager.SCO_AUDIO_STATE_CONNECTED)
    state.markRequestStarted()
    assertTrue(state.beginRelease())
    assertEquals(
      AndroidLegacyScoEventV2.RELEASED,
      state.observe(AudioManager.SCO_AUDIO_STATE_DISCONNECTED),
    )
    assertEquals(
      AndroidLegacyScoEventV2.NONE,
      state.observe(AudioManager.SCO_AUDIO_STATE_DISCONNECTED),
    )
  }

  @Test
  fun cancellationDuringConnectingOwnsReleaseAndIgnoresLateConnectedState() {
    val state = AndroidLegacyScoStateV2()

    state.beginAcquisition(AudioManager.SCO_AUDIO_STATE_DISCONNECTED)
    state.markRequestStarted()
    state.observe(AudioManager.SCO_AUDIO_STATE_CONNECTING)
    assertTrue(state.beginRelease())
    assertEquals(
      AndroidLegacyScoEventV2.NONE,
      state.observe(AudioManager.SCO_AUDIO_STATE_CONNECTED),
    )
    assertEquals(
      AndroidLegacyScoEventV2.RELEASED,
      state.observe(AudioManager.SCO_AUDIO_STATE_DISCONNECTED),
    )
    assertTrue(state.claimStopRequest())
    assertFalse(state.claimStopRequest())
  }
}
