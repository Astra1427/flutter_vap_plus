package com.nell.flutter_vap_plus

import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * The main plugin class for the `flutter_vap_plus` package on Android.
 *
 * This class is responsible for registering the native components of the plugin
 * with the Flutter engine. Specifically, it registers the [NativeVapViewFactory],
 * which allows Flutter to create and display native VAP (Video Animation Player) views.
 */
class FlutterVapPlugin : FlutterPlugin {

    /**
     * Called when the plugin is attached to a Flutter engine.
     *
     * This is the point where the plugin should initialize itself and register
     * any native components it provides. For `flutter_vap_plus`, this involves
     * registering the [NativeVapViewFactory] with Flutter's platform view registry.
     * This allows Flutter widgets (like `VapView`) to create instances of the
     * native Android VAP view.
     *
     * @param flutterPluginBinding Provides access to application context, binary messenger,
     *                             and other essential components from the Flutter engine.
     */
    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        // Register the NativeVapViewFactory with the platform view registry.
        // The viewType "flutter_vap" must match the string used on the Dart side
        // when creating an AndroidView/UiKitView for the VAP player.
        flutterPluginBinding.platformViewRegistry.registerViewFactory(
            "flutter_vap", // This is the unique identifier for the VAP platform view type.
            NativeVapViewFactory(flutterPluginBinding.binaryMessenger)
        )
    }

    /**
     * Called when the plugin is detached from a Flutter engine.
     *
     * This is the point where the plugin should clean up any resources it has allocated.
     * For `flutter_vap_plus`, there are no explicit resources to release in this method,
     * as the primary responsibility is the registration of the view factory.
     * Individual [NativeVapView] instances handle their own lifecycle and resource cleanup
     * via their `dispose` method.
     *
     * @param binding Provides access to components from the Flutter engine, similar to
     *                [onAttachedToEngine]. Not used in this implementation for cleanup.
     */
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // No specific cleanup required here for this plugin.
        // The platform view factory will be unregistered automatically by the engine.
    }
}
