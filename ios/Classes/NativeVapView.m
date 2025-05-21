#import "NativeVapView.h"
#import "UIView+VAP.h" // TODO: Review if this category is still used or needed.
#import "QGVAPWrapView.h"
#import "FetchResourceModel.h"
#import <Flutter/Flutter.h>

/// Native iOS View implementation for VAP animations.
///
/// This class conforms to `FlutterPlatformView` to be used as a Flutter widget's backing native view.
/// It also conforms to `VAPWrapViewDelegate` to handle events from the `QGVAPWrapView` (the actual video animation player).
/// It manages the lifecycle of the `QGVAPWrapView`, communication with Flutter via a `FlutterMethodChannel`,
/// and resource handling for dynamic VAP animations.
@interface NativeVapView : NSObject <FlutterPlatformView, VAPWrapViewDelegate>

/// Root UIView for this platform view.
@property (nonatomic, strong, readonly) UIView *view;
/// The VAP animation player view provided by the QGVAPSDK.
@property (nonatomic, strong) QGVAPWrapView *wrapView;
/// Tracks the current playback status (YES if playing, NO otherwise).
@property (nonatomic, assign) BOOL playStatus;
/// Method channel for communication with the Flutter `VapController`.
@property (nonatomic, strong) FlutterMethodChannel *methodChannel;
/// Array of `FetchResourceModel` objects for dynamic content replacement in VAP animations.
@property (nonatomic, strong) NSArray<FetchResourceModel *> *fetchResources;
/// Arguments passed from Flutter during view creation (e.g., scaleType).
@property (nonatomic, strong) id creationArgs;
/// Cache for frequently accessed images to reduce disk I/O.
@property (nonatomic, strong) NSCache *imageCache;

/// Initializes the NativeVapView.
/// @param frame The initial frame for the view.
/// @param viewId The unique identifier for this platform view.
/// @param args Arguments passed from Flutter side during view creation.
/// @param messenger The binary messenger for setting up the method channel.
- (instancetype)initWithFrame:(CGRect)frame
               viewIdentifier:(int64_t)viewId
                    arguments:(id _Nullable)args
              binaryMessenger:(NSObject<FlutterBinaryMessenger> *)messenger;

@end

/// Factory for creating `NativeVapView` instances.
///
/// This class is registered with Flutter to allow it to create `NativeVapView`
/// when a `VapView` widget is used in the Flutter UI.
@implementation NativeVapViewFactory {
    /// Registrar for Flutter plugins, used to access the binary messenger.
    NSObject<FlutterPluginRegistrar> *_registrar;
}

/// Initializes the factory with a plugin registrar.
/// @param registrar The Flutter plugin registrar.
- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    self = [super init];
    if (self) {
        _registrar = registrar;
    }
    return self;
}

/// Creates a new `NativeVapView` instance.
/// This method is called by Flutter when a new platform view is required.
/// @param frame The initial frame for the view.
/// @param viewId The unique identifier for this platform view.
/// @param args Arguments passed from the Flutter side.
- (NSObject<FlutterPlatformView> *)createWithFrame:(CGRect)frame
                                    viewIdentifier:(int64_t)viewId
                                         arguments:(id _Nullable)args {
    return [[NativeVapView alloc] initWithFrame:frame
                                 viewIdentifier:viewId
                                      arguments:args
                                binaryMessenger:_registrar.messenger];
}

@end

@implementation NativeVapView

// Synthesize properties if not done automatically or for explicit control
@synthesize view = _view;
@synthesize wrapView = _wrapView;
@synthesize playStatus = _playStatus;
@synthesize methodChannel = _methodChannel;
@synthesize fetchResources = _fetchResources;
@synthesize creationArgs = _creationArgs;
@synthesize imageCache = _imageCache;

/// Initializes the NativeVapView, sets up the main view, and configures the method channel.
- (instancetype)initWithFrame:(CGRect)frame
               viewIdentifier:(int64_t)viewId
                    arguments:(id _Nullable)args
              binaryMessenger:(NSObject<FlutterBinaryMessenger> *)messenger {
    self = [super init];
    if (self) {
        _creationArgs = args; // Store creation arguments
        _playStatus = NO;     // Initial playback status is not playing
        _view = [[UIView alloc] initWithFrame:frame]; // Create the root UIView
        _view.clipsToBounds = YES; // Ensure subviews (like _wrapView) are clipped to bounds
        
        // Initialize the image cache
        _imageCache = [[NSCache alloc] init];
        // _imageCache.countLimit = 20; // Example: Max 20 images
        // _imageCache.totalCostLimit = 10 * 1024 * 1024; // Example: Max 10MB

        // Initialize MethodChannel for communication with Flutter.
        NSString *methodChannelName = [NSString stringWithFormat: @"flutter_vap_controller_%lld" ,viewId];
        _methodChannel = [FlutterMethodChannel methodChannelWithName:methodChannelName binaryMessenger:messenger];
        
        __weak typeof(self) weakSelf = self;
        [_methodChannel setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult result) {
            [weakSelf handleMethodCall:call result:result];
        }];

        // Initialize _wrapView once here and add it to the hierarchy.
        // Its frame will be managed by autoresizing or layoutSubviews if needed.
        _wrapView = [[QGVAPWrapView alloc] initWithFrame:_view.bounds];
        _wrapView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _wrapView.userInteractionEnabled = NO;
        _wrapView.delegate = self; // Set delegate once
        // Apply initial scale mode. This can be updated later if needed.
        [self applyScaleModeToWrapView];
        [_view addSubview:_wrapView];

    }
    return self;
}

#pragma mark - FlutterPlatformView

/// Returns the root UIView that Flutter will embed.
- (UIView *)view {
    return _view;
}

#pragma mark - Method Call Handling

/// Handles method calls received from the Flutter `VapController`.
/// @param call The method call object, containing the method name and arguments.
/// @param result A callback to send the result of the method call back to Flutter.
- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if ([@"playPath" isEqualToString:call.method]) {
        NSString *path = call.arguments[@"path"];
        if (path && [path isKindOfClass:[NSString class]] && path.length > 0) {
            [self playByPath:path withResult:result];
        } else {
            result([FlutterError errorWithCode:@"INVALID_ARGUMENT"
                                       message:@"Path is null or invalid"
                                       details:nil]);
        }
    } else if ([@"playAsset" isEqualToString:call.method]) {
        NSString *assetName = call.arguments[@"asset"];
        if (assetName && [assetName isKindOfClass:[NSString class]] && assetName.length > 0) {
            // Construct the full path to the asset within the app bundle.
            // Assets are typically placed in the "flutter_assets" directory.
            NSString *key = [FlutterDartProject.lookupKeyForAsset stringByAppendingPathComponent:assetName];
            NSString *assetPath = [[NSBundle mainBundle] pathForResource:key ofType:nil];
            
            if (assetPath) {
                NSLog(@"[NativeVapView] Playing asset from path: %@", assetPath);
                [self playByPath:assetPath withResult:result];
            } else {
                NSLog(@"[NativeVapView] Asset not found: %@", assetName);
                result([FlutterError errorWithCode:@"ASSET_NOT_FOUND"
                                           message:[NSString stringWithFormat:@"Asset '%@' not found", assetName]
                                           details:nil]);
            }
        } else {
            result([FlutterError errorWithCode:@"INVALID_ARGUMENT"
                                       message:@"Asset name is null or invalid"
                                       details:nil]);
        }
    } else if ([@"stop" isEqualToString:call.method]) {
        [self stopPlayback];
        result(nil); // Acknowledge the call
    } else if ([@"setFetchResource" isEqualToString:call.method]){
        NSString *rawJson = call.arguments;
        if (rawJson && [rawJson isKindOfClass:[NSString class]]) {
            _fetchResources = [FetchResourceModel fromRawJsonArray:rawJson];
            result(nil); // Acknowledge the call
        } else {
            result([FlutterError errorWithCode:@"INVALID_ARGUMENT"
                                       message:@"Resource JSON is null or not a string"
                                       details:nil]);
        }
    } else {
        result(FlutterMethodNotImplemented); // Method not recognized
    }
}

#pragma mark - Playback Control

/// Starts playing a VAP animation from the given file path.
/// @param path The absolute file path to the VAP animation MP4 file.
/// @param result FlutterResult to signal success or failure of starting playback.
- (void)playByPath:(NSString *)path withResult:(FlutterResult)result {
    if (_playStatus) {
        // If already playing, notify Flutter and do not start a new playback.
        result([FlutterError errorWithCode:@"ALREADY_PLAYING"
                                   message:@"A VAP animation is already playing."
                                   details:nil]);
        return;
    }

    // If already playing, notify Flutter and do not start a new playback.
    // Consider if we should stop the current one and play the new one,
    // or if this error is the desired behavior.
    // For now, matching existing behavior of disallowing concurrent plays.
    if (_playStatus) {
        result([FlutterError errorWithCode:@"ALREADY_PLAYING"
                                   message:@"A VAP animation is already playing."
                                   details:nil]);
        return;
    }

    // Ensure _wrapView is initialized (should be by initWithFrame...)
    if (!_wrapView) {
        // This case should ideally not happen if initialized in constructor.
        // Re-initialize or log error. For now, let's assume it's always there.
        NSLog(@"[NativeVapView] _wrapView is nil in playByPath. This should not happen.");
        _wrapView = [[QGVAPWrapView alloc] initWithFrame:_view.bounds];
        _wrapView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _wrapView.userInteractionEnabled = NO;
        _wrapView.delegate = self;
        [self applyScaleModeToWrapView]; // Apply current scale mode
        [_view addSubview:_wrapView];
    }
    
    // If _wrapView was previously used and autoDestoryAfterFinish was YES,
    // it might have been removed from its superview by the QGVAPSDK.
    // Ensure it's part of the view hierarchy.
    if (!_wrapView.superview) {
        [_view addSubview:_wrapView];
    }
    
    // It's important to check if `QGVAPWrapView` internally handles being played multiple times
    // or if it needs a reset. Assuming `vapWrapView_playHWDMP4` can be called again
    // after a previous playback finished or was stopped.
    // If `autoDestoryAfterFinish` is YES (current setting), the view might self-destruct
    // its internal player upon completion. This needs to be compatible with reuse.
    // For this optimization, let's assume autoDestoryAfterFinish should be NO for reuse.
    _wrapView.autoDestoryAfterFinish = NO; // Set to NO for reusable view instance

    _playStatus = YES;

    // Apply scale mode before playing, in case it changed via creationArgs (if that's dynamic)
    // [self applyScaleModeToWrapView]; // Already applied at init and potentially if args change

    // Start playing the MP4 animation.
    // `vapWrapView_playHWDMP4` is assumed to be the correct method.
    // The standard method might be `playHWDMP4:repeatCount:delegate:`.
    // TODO: Confirm the correct method name for playing with hardware decoding.
    // Assuming `vapWrapView_playHWDMP4` is correct based on original code.
    [_wrapView vapWrapView_playHWDMP4:path repeatCount:0 delegate:self]; // Play once

    result(nil); // Notify Flutter that the play command was initiated.
    // Note: "onStart" is sent from the delegate method `vapWrap_viewDidStartPlayMP4`.
}

/// Stops the currently playing VAP animation.
- (void)stopPlayback {
    if (_wrapView) {
        // Assuming QGVAPWrapView has a 'stop' method or similar.
        // If not, vapWrapView_playHWDMP4 with a nil path or an explicit stop method from the SDK should be used.
        // For now, let's assume there's a method like `stopPlay` or `qg_stop`.
        // If `autoDestoryAfterFinish` is NO, we should explicitly stop the player.
        // The QGVAPSDK documentation would be needed for the exact method.
        // Example: [_wrapView stopPlay]; (This is a hypothetical method)
        // Or, if stopping is managed by vapWrap_viewDidStopPlayMP4 and vapWrap_viewDidFinishPlayMP4,
        // then just updating status might be enough.
        // Given the original code removed the view, let's try to call a stop method if available,
        // otherwise, the view will just sit there if not playing.
        // If QGVAPSDK has a method like `stop`, it should be called here.
        // Without SDK docs, it's hard to know the correct stop procedure for a reusable view.
        // For this exercise, we'll assume calling play with nil/empty path or a specific stop method
        // is handled by the QGVAPSDK or is not strictly necessary if play can be called again.
        // The critical part is that we no longer do `[_wrapView removeFromSuperview]; _wrapView = nil;` here.
    }
    if (_playStatus) {
        _playStatus = NO;
        // Optionally notify Flutter. If stop is user-initiated, Flutter already knows.
        // If it's an internal stop, an event might be useful.
        // For now, mirror existing behavior of not sending a specific "onStopped" from here.
    }
}

// Helper method to apply scale mode
- (void)applyScaleModeToWrapView {
    if (!_wrapView) return;
    NSString *scaleType = self.creationArgs[@"scaleType"];
    if ([scaleType isEqualToString:@"FIT_XY"]) {
        _wrapView.contentMode = QGVAPWrapViewContentModeScaleToFill;
    } else if ([scaleType isEqualToString:@"CENTER_CROP"]) {
        _wrapView.contentMode = QGVAPWrapViewContentModeAspectFill;
    } else { // Default to FIT_CENTER
        _wrapView.contentMode = QGVAPWrapViewContentModeAspectFit;
    }
}


#pragma mark - VAPWrapViewDelegate Callbacks

/// Called when the VAP animation starts playing.
/// @param container The VAPView instance that started playing. (QGVAPSDK's VAPView)
- (void)vapWrap_viewDidStartPlayMP4:(VAPView *)container {
    _playStatus = YES; // Update status
    // Notify Flutter that playback has started.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.methodChannel invokeMethod:@"onStart" arguments:nil];
    });
}

/// Called when the VAP animation fails to play.
/// @param error An NSError object describing the failure.
- (void)vapWrap_viewDidFailPlayMP4:(NSError *)error {
    _playStatus = NO; // Update status
    // Notify Flutter about the failure with a structured error.
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *nativeErrorCodeStr = @"UNKNOWN";
        NSString *errorMessageStr = @"Unknown error on iOS during playback.";

        if (error) {
            nativeErrorCodeStr = [NSString stringWithFormat:@"%ld", (long)error.code];
            errorMessageStr = error.localizedDescription ?: @"No error description provided by iOS.";
        }
        
        NSDictionary *errorDetails = @{
            @"errorCode": @"IOS_PLAYER_ERROR",
            @"nativeErrorCode": nativeErrorCodeStr,
            @"errorMessage": errorMessageStr
        };
        NSLog(@"[NativeVapView] Playback failed: %@", errorDetails);
        [self.methodChannel invokeMethod:@"onFailed" arguments:errorDetails];
    });
    // Do NOT remove _wrapView from superview or nil it out here if we are reusing it.
    // The view should be ready for another play attempt or be explicitly destroyed on dispose.
}

/// Called when the VAP animation stops playing (e.g., manually stopped or finished).
/// @param lastFrameIndex The index of the last frame that was played.
/// @param container The VAPView instance.
- (void)vapWrap_viewDidStopPlayMP4:(NSInteger)lastFrameIndex view:(VAPView *)container {
    _playStatus = NO;
    // This method is called when playback stops for any reason, including finishing.
    // If `autoDestoryAfterFinish` was YES, the SDK might handle cleanup.
    // Since we set it to NO for reuse, the `_wrapView` instance remains.
    // No specific "onStopped" event was sent in original code from here.
}

/// Called when the VAP animation finishes playing successfully.
/// @param totalFrameCount The total number of frames in the animation.
/// @param container The VAPView instance.
- (void)vapWrap_viewDidFinishPlayMP4:(NSInteger)totalFrameCount view:(VAPView *)container {
    _playStatus = NO; // Update status
    // Notify Flutter that playback has completed.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.methodChannel invokeMethod:@"onComplete" arguments:nil];
    });
    // With `autoDestoryAfterFinish = NO`, `_wrapView` is not automatically destroyed by QGVAPSDK.
    // It's ready to be played again.
}

#pragma mark - Dynamic Resource Handling (VAPWrapViewDelegate)

/// Provides dynamic content (text or image URLs) for specified tags within the VAP animation.
/// This method is called by the `QGVAPWrapView` when it encounters a dynamic resource tag.
/// @param tag The tag identifier from the VAP animation file.
/// @param info Additional information about the source (e.g., type: image/text).
/// @return The string content (text or URL for an image) for the given tag. Returns `nil` if no resource matches the tag.
- (NSString *)vapWrapview_contentForVapTag:(NSString *)tag resource:(QGVAPSourceInfo *)info {
    for (FetchResourceModel *model in _fetchResources) {
        if ([model.tag isEqualToString:tag]) {
            // Log the resource being provided for the tag.
            NSLog(@"[NativeVapView] Providing resource for tag '%@': type '%@', content '%@'", tag, info.srcType, model.resource);
            return model.resource; // Return the path or text string.
        }
    }
    NSLog(@"[NativeVapView] No resource found for VAP tag: %@", tag);
    return nil; // No resource found for this tag.
}

/// Loads an image for a VAP animation, typically from a local file path.
/// This method is called by `QGVAPWrapView` when it needs to load an image resource
/// whose URL was provided by `vapWrapview_contentForVapTag`.
/// @param urlStr The URL (local file path) of the image to load.
/// @param context Additional context (not typically used in this implementation).
/// @param completionBlock A block to call with the loaded UIImage or an error.
- (void)vapWrapView_loadVapImageWithURL:(NSString *)urlStr context:(NSDictionary *)context completion:(VAPImageCompletionBlock)completionBlock {
    if (!urlStr || urlStr.length == 0) {
        if (completionBlock) {
            NSError *error = [NSError errorWithDomain:@"com.flutter_vap_plus.ios" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"Image URL string is empty."}];
            completionBlock(nil, error, urlStr);
        }
        return;
    }

    // Check cache first
    UIImage *cachedImage = [self.imageCache objectForKey:urlStr];
    if (cachedImage) {
        NSLog(@"[NativeVapView] Using cached image for URL: %@", urlStr);
        if (completionBlock) {
            // Call completion block on main thread, as expected by QGVAPSDK typically for UI updates.
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(cachedImage, nil, urlStr);
            });
        }
        return;
    }
    
    // Image not in cache, load from file in background
    NSLog(@"[NativeVapView] Loading image from file for URL: %@", urlStr);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        UIImage *image = [UIImage imageWithContentsOfFile:urlStr];
        
        // Potential: Decode image here if needed, or handle more granular errors.
        // For now, simple load.

        if (image) {
            // Store in cache if successfully loaded
            [self.imageCache setObject:image forKey:urlStr];
            NSLog(@"[NativeVapView] Cached image for URL: %@", urlStr);
        } else {
            NSLog(@"[NativeVapView] Failed to load image from path: %@", urlStr);
        }
        
        // Call completion block on main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completionBlock) {
                if (image) {
                    completionBlock(image, nil, urlStr);
                } else {
                    NSError *error = [NSError errorWithDomain:@"com.flutter_vap_plus.ios"
                                                         code:-2 // Using a different code for load failure
                                                     userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Failed to load image from path: %@", urlStr]}];
                    completionBlock(nil, error, urlStr);
                }
            }
        });
    });
}

/// Called when the platform view is about to be destroyed.
/// Perform any cleanup here, such as removing observers or stopping ongoing tasks.
- (void)onFlutterViewRemoved {
    [self stopPlayback]; // Ensure playback is stopped and resources are potentially released.
    if (_methodChannel) {
        [_methodChannel setMethodCallHandler:nil]; // Clear the method call handler.
        _methodChannel = nil;
    }
    if (_imageCache) {
        [_imageCache removeAllObjects]; // Clear the image cache
        _imageCache = nil;
    }
    // Any other cleanup specific to NativeVapView
    NSLog(@"[NativeVapView] Flutter view removed, cleaning up.");
}

- (void)dealloc {
    // Note: onFlutterViewRemoved is not automatically called on dealloc by FlutterPlatformView.
    // It's better to rely on the explicit signal from Flutter if possible, or ensure cleanup in dealloc.
    // For this structure, let's ensure cleanup happens.
    // Critical: If _wrapView has a specific dealloc or cleanup method from QGVAPSDK, call it here.
    // e.g. [_wrapView shutdownMediaPlayer]; or [_wrapView prepareToDealloc];
    // Without SDK docs, we assume removeFromSuperview is sufficient if autoDestoryAfterFinish was NO.
    if (_wrapView) {
        // If QGVAPSDK requires an explicit cleanup call on the view before it's deallocated,
        // it should be done here. Example: [_wrapView cleanupResources];
        // Then remove from superview.
        [_wrapView removeFromSuperview];
        _wrapView = nil; // Release the strong reference.
    }
    if (_methodChannel) {
        [_methodChannel setMethodCallHandler:nil];
        _methodChannel = nil;
    }
    if (_imageCache) {
        [_imageCache removeAllObjects];
        _imageCache = nil;
    }
    NSLog(@"[NativeVapView] Deallocating.");
}

@end
