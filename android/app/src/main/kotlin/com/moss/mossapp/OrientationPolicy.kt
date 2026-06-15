package com.mixroom.mixroomapp

import android.app.Activity
import android.content.pm.ActivityInfo
import android.content.res.Configuration

internal object OrientationPolicy {
  private const val TABLET_SMALLEST_WIDTH_DP = 600

  fun apply(activity: Activity) {
    val smallestWidthDp = activity.resources.configuration.smallestScreenWidthDp
    val isTablet =
      smallestWidthDp != Configuration.SMALLEST_SCREEN_WIDTH_DP_UNDEFINED &&
        smallestWidthDp >= TABLET_SMALLEST_WIDTH_DP

    activity.requestedOrientation = if (isTablet) {
      ActivityInfo.SCREEN_ORIENTATION_USER_LANDSCAPE
    } else {
      ActivityInfo.SCREEN_ORIENTATION_USER_PORTRAIT
    }
  }
}
