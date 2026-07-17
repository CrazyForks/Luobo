package com.devid.musly

import android.os.Build
import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Enable edge-to-edge: content draws behind system bars
        WindowCompat.setDecorFitsSystemWindows(window, false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        flutterEngine.plugins.add(AndroidAutoPlugin)
        
        flutterEngine.plugins.add(AndroidSystemPlugin)
        
        flutterEngine.plugins.add(BluetoothAvrcpPlugin)
        
        flutterEngine.plugins.add(SamsungIntegrationPlugin)
        
        // Register lyrics plugin for lock screen lyrics support
        LyricsPlugin.registerWith(flutterEngine)

        // Register pitch plugin for ExoPlayer pitch control
        PitchPlugin.registerWith(flutterEngine)

        // Register Dolby Atmos plugin for device-capability detection
        DolbyAtmosPlugin.registerWith(flutterEngine, this)
    }
}
