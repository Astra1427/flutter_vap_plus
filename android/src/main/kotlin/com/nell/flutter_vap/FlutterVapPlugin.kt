package com.nell.flutter_vap

import androidx.annotation.NonNull

import io.flutter.embedding.engine.plugins.FlutterPlugin

class FlutterVapPlugin : FlutterPlugin {

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        flutterPluginBinding.platformViewRegistry.registerViewFactory(
            "flutter_vap",
            NativeVapViewFactory(flutterPluginBinding.binaryMessenger)
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    }
}
