import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';

/// Controls a VAP (Video Animation Player) view.
///
/// This controller is responsible for interacting with the native VAP player,
/// allowing for playback control, resource management, and event handling.
/// It communicates with the native side using a [MethodChannel].
class VapController {
  late final MethodChannel _methodChannel;

  /// The unique identifier for the platform view this controller manages.
  final int viewId;

  /// An optional callback function that is invoked when events are received from the native VAP player.
  ///
  /// Events can include playback status changes (e.g., "onComplete", "onFailed") or other custom events.
  /// The `event` parameter is a string identifying the event type, and `arguments` can be any dynamic data
  /// associated with the event.
  final void Function(dynamic event, dynamic arguments)? onEvent;

  /// Creates a [VapController].
  ///
  /// Requires a [viewId] to associate with the specific platform view and an optional [onEvent] callback.
  VapController({
    required this.viewId,
    this.onEvent,
  }) {
    _methodChannel = MethodChannel('flutter_vap_controller_$viewId');
    _methodChannel.setMethodCallHandler(_onMethodCallHandler);
  }

  /// A completer that resolves when the current playback completes or fails.
  /// This is used internally to manage the asynchronous nature of playback.
  Completer<void>? _playCompleter;

  /// Plays a VAP animation from a specified [source].
  ///
  /// This is a generic play method used by more specific methods like [playPath] and [playAsset].
  ///
  /// - [source]: The resource identifier (e.g., file path or asset key).
  /// - [playMethod]: The native method name to invoke for playing (e.g., "playPath", "playAsset").
  /// - [playArg]: The argument key for the source (e.g., "path", "asset").
  /// - [fetchResources]: A list of [FetchResourceModel] to provide dynamic resources (images/text)
  ///   to the animation during playback. This is crucial for animations that support dynamic content replacement.
  ///
  /// **Important:** The fusion animation parameters (dynamic resources via [fetchResources])
  /// must be set *before* calling play. Otherwise, the fusion animation features might not work correctly.
  ///
  /// Returns a [Future] that completes when the animation finishes playing or errors out.
  /// The future will also error if the playback times out (20 seconds).
  Future<void> play(
      {required String source,
      required String playMethod,
      required String playArg,
      List<FetchResourceModel> fetchResources = const []}) async {
    try {
      _playCompleter = Completer<void>();
      // It's crucial to set the fusion animation parameters (dynamic resources) *before* starting playback.
      // Failure to do so may result in the fusion animation not working as expected.
      await setFetchResources(fetchResources);

      await _methodChannel.invokeMethod(playMethod, {playArg: source});

      return _playCompleter!.future.timeout(const Duration(seconds: 20),
          onTimeout: () {
        if (_playCompleter?.isCompleted == true) return;
        _playCompleter
            ?.completeError(TimeoutException("VAP playback timed out after 20 seconds."));
      });
    } catch (e, s) {
      // Ensure the completer is resolved even if an error occurs during the setup phase.
      if (_playCompleter?.isCompleted == false) {
        _playCompleter?.completeError(e, s);
      } else {
        // If completer is already completed, rethrow to avoid hiding the original error.
        rethrow;
      }
    }
  }

  /// Plays a VAP animation from a file path.
  ///
  /// - [path]: The absolute file path to the VAP animation file.
  /// - [fetchResources]: Optional list of [FetchResourceModel] for dynamic content.
  ///
  /// Returns a [Future] that completes when the animation finishes or errors.
  Future<void> playPath(String path,
      {List<FetchResourceModel> fetchResources = const []}) {
    return play(
        source: path,
        playMethod: 'playPath',
        playArg: 'path',
        fetchResources: fetchResources);
  }

  /// Plays a VAP animation from a Flutter asset.
  ///
  /// - [asset]: The asset path (e.g., "assets/animation.mp4").
  /// - [fetchResources]: Optional list of [FetchResourceModel] for dynamic content.
  ///
  /// Returns a [Future] that completes when the animation finishes or errors.
  Future<void> playAsset(String asset,
      {List<FetchResourceModel> fetchResources = const []}) {
    return play(
        source: asset,
        playMethod: 'playAsset',
        playArg: 'asset',
        fetchResources: fetchResources);
  }

  /// Stops the currently playing VAP animation.
  ///
  /// This method sends a 'stop' command to the native player.
  /// It does not return a future as the stop operation is typically fire-and-forget,
  /// though completion/failure events might still be received via the `onEvent` callback
  /// or the `playCompleter` if a play was in progress.
  void stop() {
    _methodChannel.invokeMethod('stop');
    // If a play was in progress, complete its completer as the stop command effectively ends it.
    // We don't complete with an error here, as 'stop' is an intentional action.
    // Consumers can listen to 'onComplete' or specific stop events if needed.
    if (_playCompleter?.isCompleted == false) {
      _playCompleter?.complete();
    }
  }

  /// Sets dynamic resources for the VAP animation.
  ///
  /// These resources (images or text) can be referenced by `tag` within the VAP animation file,
  /// allowing parts of the animation to be customized at runtime.
  ///
  /// - [resources]: A list of [FetchResourceModel] objects detailing the resources to be made available.
  ///
  /// Returns a [Future] that completes when the native side has processed the resource request.
  Future<void> setFetchResources(List<FetchResourceModel> resources) {
    return _methodChannel.invokeMethod(
        'setFetchResource',
        // Resources are JSON encoded for transport over the method channel.
        jsonEncode(resources.map((e) => e.toMap()).toList()));
  }

  /// Releases resources used by the controller.
  ///
  /// This should be called when the controller is no longer needed to prevent memory leaks
  /// and to ensure the method call handler is removed from the channel.
  void dispose() {
    _methodChannel.setMethodCallHandler(null);
    // If there's an active play completer that hasn't finished,
    // complete it to prevent any pending futures from hanging indefinitely.
    if (_playCompleter?.isCompleted == false) {
      _playCompleter?.completeError(StateError("VapController was disposed during playback."));
    }
  }

  /// Handles incoming method calls from the native platform.
  ///
  /// This method is set as the handler on the [_methodChannel].
  /// It forwards events to the [onEvent] callback and manages the [_playCompleter]
  /// based on "onComplete" and "onFailed" events from the native side.
  Future<void> _onMethodCallHandler(MethodCall call) async {
    // Forward all events to the public onEvent callback if provided.
    onEvent?.call(call.method, call.arguments);

    // Handle specific events to manage the play completer.
    switch (call.method) {
      case "onComplete":
        if (_playCompleter?.isCompleted == false) {
          _playCompleter?.complete();
        }
        break;
      case "onFailed":
        if (_playCompleter?.isCompleted == false) {
          _playCompleter?.completeError(call.arguments ?? "Unknown playback error");
        }
        break;
    }
  }
}

/// Represents a dynamic resource to be fetched and used by the VAP animation.
///
/// VAP animations can define placeholders (identified by `tag`) that can be
/// filled with images or text at runtime. This class models such a resource.
class FetchResourceModel {
  /// The identifier tag for the resource, as defined in the VAP animation file.
  ///
  /// This tag is used by the native player to match this resource data
  /// with a specific placeholder in the animation.
  final String tag;

  /// The actual resource content.
  ///
  /// This can be a local file path for an image or a string for text content.
  /// The native player will interpret this based on the type of placeholder
  /// associated with the [tag] in the animation.
  final String resource;

  /// Creates a [FetchResourceModel].
  ///
  /// - [tag]: The resource tag from the VAP animation.
  /// - [resource]: The image file path or text string.
  FetchResourceModel({required this.tag, required this.resource});

  /// Converts the model to a Map, typically for JSON encoding.
  Map<String, String> toMap() => {
        'tag': tag,
        'resource': resource,
      };
}
