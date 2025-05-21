import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_vap_plus/flutter_vap_plus.dart';
import 'package:flutter_vap_plus/vap_view_for_android.dart';
import 'package:flutter_vap_plus/vap_view_for_ios.dart';

/// A Flutter widget that displays a VAP (Video Animation Player) animation.
///
/// This widget acts as a bridge to native VAP player implementations on Android and iOS.
/// It handles platform-specific view creation and provides a unified API
/// through the [VapController].
class VapView extends StatefulWidget {
  /// Callback invoked when the native platform view and its associated [VapController] are created.
  ///
  /// This controller can be used to manage playback (play, stop), set dynamic resources, etc.
  final void Function(VapController controller) onControllerCreated;

  /// Defines how the VAP animation should be scaled to fit the view.
  ///
  /// Defaults to [VapScaleFit.FIT_CENTER].
  final VapScaleFit fit;

  /// Optional callback for receiving events from the native VAP player.
  ///
  /// Events can include playback status changes (e.g., completion, failure) or other custom events
  /// defined by the native player.
  /// The `event` parameter is a string identifying the event, and `arguments` can contain
  /// additional data related to the event.
  final void Function(dynamic event, dynamic arguments)? onEvent;

  /// Creates a [VapView] widget.
  ///
  /// - [key]: Optional widget key.
  /// - [onControllerCreated]: Required callback for when the [VapController] is ready.
  /// - [fit]: Scaling mode for the animation. Defaults to [VapScaleFit.FIT_CENTER].
  /// - [onEvent]: Optional callback for native player events.
  const VapView({
    super.key,
    required this.onControllerCreated,
    this.fit = VapScaleFit.FIT_CENTER,
    this.onEvent,
  });

  @override
  State<VapView> createState() => _VapViewState();
}

class _VapViewState extends State<VapView> {
  /// Internal reference to the VapController.
  /// Used to call dispose on the controller when the widget is disposed.
  VapController? _internalController;

  @override
  Widget build(BuildContext context) {
    // Conditionally render the appropriate platform-specific VAP view.
    if (Platform.isAndroid) {
      return VapViewForAndroid(
        onControllerCreated: _onPlatformControllerCreated,
        fit: widget.fit,
        onEvent: widget.onEvent,
      );
    } else if (Platform.isIOS) {
      return VapViewForIos(
        onControllerCreated: _onPlatformControllerCreated,
        fit: widget.fit,
        onEvent: widget.onEvent,
      );
    }
    // Return an empty container if the platform is not supported.
    // This could be enhanced to show a message or a placeholder.
    return Container(
      child: const Text("VAP view is not supported on this platform."),
    );
  }

  /// Internal callback that receives the [VapController] from the platform-specific view.
  ///
  /// It stores the controller for later disposal and then calls the user-provided
  /// [widget.onControllerCreated] callback.
  void _onPlatformControllerCreated(VapController controller) {
    _internalController = controller;
    widget.onControllerCreated(controller);
  }

  @override
  void dispose() {
    // Dispose the VapController to release its resources (e.g., MethodChannel handler).
    _internalController?.dispose();
    super.dispose();
  }
}

/// Defines how the VAP animation content should be scaled to fit the bounds of the [VapView].
enum VapScaleFit {
  /// Scale the X and Y axes independently so that the animation matches the view's bounds exactly.
  /// This may change the aspect ratio of the animation.
  FIT_XY,

  /// Scale the animation to fit within the view's bounds while maintaining its aspect ratio.
  /// The animation will be centered within the view. At least one dimension (width or height)
  /// will fit exactly, and the other dimension will be smaller than or equal to the view's bounds.
  FIT_CENTER,

  /// Scale the animation to fill the view's bounds while maintaining its aspect ratio.
  /// The animation will be centered. If the aspect ratio of the animation does not match
  /// the aspect ratio of the view, then some portion of the animation may be cropped.
  CENTER_CROP,
}
