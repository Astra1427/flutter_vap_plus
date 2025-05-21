package com.nell.flutter_vap_plus

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Factory for creating [NativeVapView] instances.
 *
 * This class is registered with the Flutter plugin framework to enable the embedding
 * of native Android VAP views (`NativeVapView`) within the Flutter widget tree.
 * It utilizes a [BinaryMessenger] to facilitate communication between the Dart
 * side (Flutter) and the native Android side (Kotlin/Java).
 *
 * @param binaryMessenger The [BinaryMessenger] used for communication between
 *                        Flutter and the native platform view. This is typically
 *                        obtained from the Flutter plugin registrar.
 */
class NativeVapViewFactory(
    private val binaryMessenger: BinaryMessenger // Made private as it's only used internally
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    // Property mBinaryMessenger was redundant as it's passed via constructor and can be private.

    /**
     * Creates a new [NativeVapView] instance.
     *
     * This method is called by the Flutter framework when a VAP widget is added to the UI.
     * It instantiates a [NativeVapView], passing necessary parameters for its initialization.
     *
     * @param context The Android [Context] for the view. This is typically the application
     *                or activity context where the Flutter view is running.
     * @param viewId The unique identifier for the platform view. This ID is used to
     *               correlate the native view with its Flutter widget counterpart.
     * @param args Arguments passed from the Dart side during the creation of the VAP widget.
     *             These arguments are expected to be a [Map] (e.g., containing 'scaleType')
     *             and are cast to `Map<String?, Any?>?`.
     * @return A new instance of [NativeVapView].
     */
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        // Cast the arguments passed from Flutter to the expected Map type.
        // These parameters (e.g., scaleType) are used by NativeVapView for its setup.
        val creationParams = args as? Map<String?, Any?>
        return NativeVapView(binaryMessenger, context, viewId, creationParams)
    }
}