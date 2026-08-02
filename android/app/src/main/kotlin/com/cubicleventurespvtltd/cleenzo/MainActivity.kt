package com.cubicleventurespvtltd.cleenzoapp

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.cubicleventurespvtltd.cleenzoapp/back"
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
    }

    // Some OEM ROMs (observed on ColorOS) fail to forward the standard
    // Flutter back-dispatch pipeline (engine -> WidgetsBinding ->
    // PopScope) even though onBackPressed() is genuinely invoked here.
    // So we bypass that pipeline entirely: notify Dart directly via
    // MethodChannel and let Dart decide what to do. We deliberately do
    // NOT call super.onBackPressed() — Dart is fully in control now.
    @Deprecated("Deprecated in Java, intentionally used for reliable OEM back handling")
    override fun onBackPressed() {
        channel?.invokeMethod("backPressed", null)
    }
}