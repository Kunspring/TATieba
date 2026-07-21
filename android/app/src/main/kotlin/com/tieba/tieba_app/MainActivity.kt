package com.tieba.tieba_app

import android.os.Bundle
import android.os.SystemClock
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {

    private var volumeEventSink: EventChannel.EventSink? = null
    private var pendingVolumeDown = false
    private var lastVolumeDownUptime = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        window.setBackgroundDrawableResource(R.drawable.launch_background)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "tieba_app/native_glass",
                NativeGlassViewFactory(this),
            )
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "tieba_app/volume_down",
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    volumeEventSink = events
                    if (pendingVolumeDown && events != null) {
                        events.success("down")
                        pendingVolumeDown = false
                    }
                }

                override fun onCancel(arguments: Any?) {
                    volumeEventSink = null
                }
            },
        )
    }

    private fun emitVolumeDown(): Boolean {
        val uptime = SystemClock.uptimeMillis()
        if (uptime - lastVolumeDownUptime < 320) {
            return true
        }
        lastVolumeDownUptime = uptime

        val sink = volumeEventSink
        if (sink != null) {
            sink.success("down")
            pendingVolumeDown = false
            return true
        }
        pendingVolumeDown = true
        return false
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN &&
            event.action == KeyEvent.ACTION_DOWN
        ) {
            emitVolumeDown()
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            emitVolumeDown()
            return true
        }
        return super.onKeyDown(keyCode, event)
    }
}
