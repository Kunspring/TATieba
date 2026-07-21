package com.tieba.tieba_app

import android.app.Activity
import android.content.Context
import android.graphics.drawable.ColorDrawable
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import eightbitlab.com.blurview.BlurView
import io.flutter.plugin.platform.PlatformView

class NativeGlassPlatformView(
    private val activity: Activity,
    context: Context,
    creationParams: Map<String, Any?>?,
) : PlatformView {
    private val container = FrameLayout(context)
    private val blurView = BlurView(context)

    init {
        val sigma = (creationParams?.get("sigma") as? Number)?.toDouble() ?: 30.0
        val radius = (sigma * 0.55).toFloat().coerceIn(6f, 25f)

        val decorView = activity.window.decorView as ViewGroup
        val rootView = decorView.findViewById<ViewGroup>(android.R.id.content)

        blurView.setupWith(rootView)
            .setFrameClearDrawable(
                activity.window.decorView.background ?: ColorDrawable(0x00000000),
            )
            .setBlurRadius(radius)
            .setBlurAutoUpdate(true)

        container.addView(
            blurView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
    }

    override fun getView(): View = container

    override fun dispose() {
        blurView.setBlurAutoUpdate(false)
    }
}
