import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'vap_controller.dart';
import 'vap_view.dart';

/// Android-specific implementation for the VAP (Video Animation Player) view.
///
/// This widget uses an [AndroidView] to embed the native Android VAP player
/// into the Flutter widget tree. It's responsible for setting up the
/// communication channel and passing creation parameters to the native view.
class VapViewForAndroid extends StatelessWidget {
  /// Callback invoked when the native Android view and its [VapController] are ready.
  final void Function(VapController controller) onControllerCreated;

  /// Defines how the VAP animation should be scaled to fit the view on Android.
  final VapScaleFit fit;

  /// Optional callback for receiving events from the native Android VAP player.
  final void Function(dynamic event, dynamic arguments)? onEvent;

  /// Optional callback for handling errors from the AndroidView.
  /// Note: This is for platform view specific errors, not VAP playback errors typically.
  final void Function(Object error)? onError;

  /// Creates an instance of [VapViewForAndroid].
  ///
  /// - [onControllerCreated]: Required callback for when the [VapController] is initialized.
  /// - [fit]: Scaling mode for the animation.
  /// - [onEvent]: Optional callback for native player events.
  /// - [onError]: Optional callback for platform view errors.
  const VapViewForAndroid({
    super.key, // Added key for consistency, though not strictly required by original code
    required this.onControllerCreated,
    required this.fit,
    this.onEvent,
    this.onError,
  });

  @override
  Widget build(BuildContext context) {
    // Parameters to be passed to the native Android view during its creation.
    // 'scaleType' corresponds to the VapScaleFit enum.
    final Map<String, dynamic> creationParams = <String, dynamic>{
      'scaleType': fit.name // Convert enum to string for native side
    };

    return AndroidView(
      // Unique identifier for the view type, registered on the native side.
      viewType: "flutter_vap",
      layoutDirection: TextDirection.ltr,
      creationParams: creationParams,
      creationParamsCodec: const StandardMessageCodec(), // Standard codec for params.
      // This callback is invoked when the native Android view has been created.
      // The `viewId` is essential for establishing the MethodChannel communication
      // with this specific native view instance.
      onPlatformViewCreated: (viewId) {
        // The Future.delayed was removed in a previous step.
        // If issues arise with view initialization, a more robust solution
        // like a native-to-Dart readiness signal would be preferable to reintroducing a delay.
        onControllerCreated(VapController(
          viewId: viewId,
          onEvent: onEvent,
        ));
      },
      // It's good practice to handle potential errors during view creation or operation.
      // However, the original code for VapViewForAndroid had an `onError` parameter in its constructor
      // but didn't pass it to the AndroidView. If this `onError` is intended for the AndroidView,
      // it should be assigned here. For now, matching original behavior.
      // Example: `onError: (error) { onError?.call(error); },`
    );
  }
}
