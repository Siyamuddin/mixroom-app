package com.mixroom.mixroomapp

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.enableEdgeToEdge

class SplashActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    enableEdgeToEdge()
    super.onCreate(savedInstanceState)
    setContentView(R.layout.activity_splash)

    // Forward the launch intent so deep-link metadata is preserved if present.
    val nextIntent = Intent(intent).setClass(this, MainActivity::class.java)
    nextIntent.addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION)
    startActivity(nextIntent)

    finish()
  }
}
