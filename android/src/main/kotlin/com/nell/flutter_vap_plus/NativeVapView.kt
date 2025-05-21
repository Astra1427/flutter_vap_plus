package com.nell.flutter_vap_plus

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import android.util.LruCache
import android.view.View
import com.tencent.qgame.animplayer.AnimConfig
import com.tencent.qgame.animplayer.AnimView
import com.tencent.qgame.animplayer.inter.IAnimListener
import com.tencent.qgame.animplayer.util.ScaleType
import com.tencent.qgame.animplayer.inter.IFetchResource
import com.tencent.qgame.animplayer.mix.Resource
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import java.io.File

/**
 * Native Android view for displaying VAP animations.
 *
 * This class embeds `com.tencent.qgame.animplayer.AnimView` (the VAP player)
 * as a Flutter PlatformView. It handles communication with the Flutter side
 * via a [MethodChannel] and manages the lifecycle and events of the [AnimView].
 *
 * @param binaryMessenger The [BinaryMessenger] for setting up the method channel.
 * @param context The Android [Context].
 * @param id The unique identifier for this platform view instance.
 * @param creationParams Parameters passed from Flutter during view creation,
 *                       such as 'scaleType'.
 */
internal class NativeVapView(
    binaryMessenger: BinaryMessenger,
    context: Context,
    id: Int,
    private val creationParams: Map<String?, Any?>?
) : MethodChannel.MethodCallHandler, PlatformView {

    private val mContext: Context = context
    /** The underlying native VAP animation player view from Tencent QGame. */
    private val vapView: AnimView = AnimView(context)
    private val channel: MethodChannel =
        MethodChannel(binaryMessenger, "flutter_vap_controller_${id}")

    /**
     * CoroutineScope for launching asynchronous tasks, primarily for invoking
     * method channel calls on the main thread.
     * Using `Dispatchers.Main.immediate` to ensure UI-related calls are timely.
     */
    private var myScope: CoroutineScope? =
        CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    /**
     * Image cache for [FetchResources].
     * Initialized once and passed to FetchResources.
     */
    private val imageCache: LruCache<String, Bitmap>

    init {
        // Set this class as the handler for method calls from Flutter.
        channel.setMethodCallHandler(this)

        // Initialize LruCache
        val maxMemory = (Runtime.getRuntime().maxMemory() / 1024).toInt()
        val cacheSize = maxMemory / 8 // Use 1/8th of the available memory for this cache.
        imageCache = object : LruCache<String, Bitmap>(cacheSize) {
            override fun sizeOf(key: String, bitmap: Bitmap): Int {
                // The cache size will be measured in kilobytes rather than number of items.
                return bitmap.byteCount / 1024
            }
        }
    }

    /**
     * Called when the Flutter view is attached to the Android view hierarchy.
     * This is where initial setup of the [vapView] occurs, such as setting
     * the scale type and animation listeners.
     *
     * @param flutterView The Flutter [View] that this platform view is attached to.
     */
    override fun onFlutterViewAttached(flutterView: View) {
        super.onFlutterViewAttached(flutterView)

        // Set the scale type for the animation (e.g., FIT_CENTER, CENTER_CROP).
        // Defaults to FIT_CENTER if not specified in creationParams.
        vapView.setScaleType(
            ScaleType.valueOf(
                (creationParams?.get("scaleType") ?: "FIT_CENTER").toString()
            )
        )

        // Set up the listener for animation events from AnimView.
        vapView.setAnimListener(object : IAnimListener {
            /**
             * Called when the animation fails to play.
             * @param errorType The type of error.
             * @param errorMsg A descriptive error message.
             */
            override fun onFailed(errorType: Int, errorMsg: String?) {
                val errorDetails = mapOf(
                    "errorCode" to "ANDROID_PLAYER_ERROR",
                    "nativeErrorCode" to errorType.toString(),
                    "errorMessage" to (errorMsg ?: "Unknown error on Android during playback.")
                )
                Log.e("NativeVapView", "Animation failed: $errorDetails")
                myScope?.launch {
                    channel.invokeMethod("onFailed", errorDetails)
                }
            }

            /** Called when the animation playback completes successfully. */
            override fun onVideoComplete() {
                Log.d("NativeVapView", "Animation completed.")
                myScope?.launch {
                    channel.invokeMethod("onComplete", null) // Argument can be null if not needed by Dart side
                }
            }

            /**
             * Called when the animation view is destroyed.
             * This might be triggered by the AnimView itself.
             */
            override fun onVideoDestroy() {
                Log.d("NativeVapView", "Animation view destroyed.")
                myScope?.launch {
                    // Consider if "onDestroy" is an event Flutter side needs to act on.
                    // Usually, dispose() handles cleanup from Flutter's perspective.
                    channel.invokeMethod("onDestroy", null)
                }
            }

            /**
             * Called for each frame rendered by the animation.
             * @param frameIndex The index of the current frame.
             * @param config The [AnimConfig] for the current frame, may contain dynamic elements.
             */
            override fun onVideoRender(frameIndex: Int, config: AnimConfig?) {
                // This event can be frequent. Uncomment if frame-by-frame updates are needed by Flutter.
                // Log.v("NativeVapView", "Rendering frame: $frameIndex")
                // myScope?.launch {
                //     channel.invokeMethod("onRender", mapOf("frameIndex" to frameIndex))
                // }
            }

            /** Called when the animation playback starts. */
            override fun onVideoStart() {
                Log.d("NativeVapView", "Animation started.")
                myScope?.launch {
                    channel.invokeMethod("onStart", null) // Argument can be null if not needed
                }
            }
        })
    }

    /** Returns the native [AnimView] to be embedded in the Flutter widget tree. */
    override fun getView(): View {
        return vapView
    }

    /**
     * Called when the platform view is disposed.
     * Clean up resources here, such as clearing the method call handler
     * and stopping any ongoing animations or coroutines.
     */
    override fun dispose() {
        Log.d("NativeVapView", "Disposing NativeVapView.")
        channel.setMethodCallHandler(null)

        // Ensure AnimView operations are on the main thread if they interact with the view state directly.
        // Most Android View methods should be called on the main thread.
        // vapView.stopPlay() is likely safe here.
        vapView.stopPlay()

        // vapView.release() should also ideally be on the main thread unless documented otherwise.
        // If release() is a heavy operation, the library might internally handle threading
        // or expect it to be called from a specific thread. Assuming main thread for now.
        vapView.release()

        // Cancel the coroutine scope to stop any ongoing background tasks started by this view.
        myScope?.cancel() // Cancels the SupervisorJob and all its children.
        myScope = null
        Log.d("NativeVapVew", "NativeVapView disposed and scope cancelled.")
    }

    /**
     * Handles method calls received from the Flutter side (VapController).
     *
     * @param call The [MethodCall] object containing the method name and arguments.
     * @param result The [MethodChannel.Result] to send back the outcome of the call.
     */
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        Log.d("NativeVapView", "Method call received: ${call.method}")
        when (call.method) {
            "playPath" -> {
                val path = call.argument<String>("path")
                if (path != null && File(path).exists()) {
                    vapView.startPlay(File(path))
                    result.success(null)
                } else {
                    Log.e("NativeVapView", "playPath: Path is null or file does not exist ($path)")
                    result.error("INVALID_ARGUMENT", "Path is null or file does not exist", path)
                }
            }
            "playAsset" -> {
                val assetName = call.argument<String>("asset")
                if (assetName != null) {
                    // Assets in Flutter are typically accessed via "flutter_assets/" prefix for native.
                    val assetFilePath = "flutter_assets/$assetName"
                    try {
                        // Check if asset exists by trying to open an InputStream
                        mContext.assets.open(assetFilePath).close()
                        vapView.startPlay(mContext.assets, assetFilePath)
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e("NativeVapView", "playAsset: Asset not found or error opening ($assetFilePath)", e)
                        result.error("ASSET_NOT_FOUND", "Asset '$assetName' not found or cannot be opened.", e.localizedMessage)
                    }
                } else {
                    Log.e("NativeVapView", "playAsset: Asset name is null")
                    result.error("INVALID_ARGUMENT", "Asset name is null", null)
                }
            }
            "stop" -> {
                vapView.stopPlay()
                result.success(null)
            }
            "setFetchResource" -> {
                val rawJson = call.arguments<String>() // Expecting a JSON string array
                if (rawJson != null) {
                    val resourceList: List<FetchResourceModel> = parseJsonToFetchResourceModelList(rawJson)
                    // Pass the initialized imageCache to FetchResources
                    vapView.setFetchResource(FetchResources(mContext, resourceList, imageCache, myScope))
                    result.success(null)
                } else {
                    Log.e("NativeVapView", "setFetchResource: JSON argument is null")
                    result.error("INVALID_ARGUMENT", "Resource JSON string is null", null)
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    /**
     * Parses a JSON string representation of a list of resource models.
     * @param rawJson The JSON string.
     * @return A list of [FetchResourceModel]. Returns an empty list if parsing fails.
     */
    private fun parseJsonToFetchResourceModelList(rawJson: String): List<FetchResourceModel> {
        val list = mutableListOf<FetchResourceModel>()
        try {
            val jsonArray = JSONArray(rawJson)
            for (i in 0 until jsonArray.length()) {
                val jsonObject = jsonArray.getJSONObject(i)
                val tag = jsonObject.getString("tag")
                val resource = jsonObject.getString("resource")
                // Assuming type is implicitly known or handled by AnimView based on tag usage
                list.add(FetchResourceModel(tag, resource))
            }
        } catch (e: Exception) {
            Log.e("NativeVapView", "JSON parsing error for FetchResourceModel list", e)
            return emptyList()
        }
        return list
    }
}

/**
 * Implementation of [IFetchResource] for the VAP [AnimView].
 * This class is responsible for providing dynamic resources (images and text)
 * to the animation during playback based on tags defined in the VAP file.
 *
 * @param context The Android [Context], used for operations like decoding Bitmaps if needed from URIs.
 * @param resources A list of [FetchResourceModel] defining the available dynamic resources.
 */
internal class FetchResources(
    private val context: Context,
    private val resources: List<FetchResourceModel>,
    private val imageCache: LruCache<String, Bitmap>,
    private val scope: CoroutineScope? // Scope from NativeVapView for managing coroutines
) : IFetchResource {

    private val TAG = "FetchResources"

    /**
     * Called by [AnimView] when it needs an image for a specific resource tag.
     * Attempts to fetch from cache first, then loads from file on a background thread.
     * @param resource The [Resource] object containing metadata like the tag.
     * @param result A callback function to provide the loaded [Bitmap] or null if not found/failed.
     */
    override fun fetchImage(resource: Resource, result: (Bitmap?) -> Unit) {
        val model = resources.firstOrNull { it.tag == resource.tag }
        if (model == null) {
            Log.w(TAG, "No resource model found for tag: ${resource.tag}")
            result(null)
            return
        }

        val imagePath = model.resource
        // Try to get the image from cache
        val cachedBitmap = imageCache.get(imagePath)
        if (cachedBitmap != null) {
            Log.d(TAG, "Cache hit for image tag '${resource.tag}' path: $imagePath")
            result(cachedBitmap)
            return
        }

        Log.d(TAG, "Cache miss. Loading image for tag '${resource.tag}' from path: $imagePath")
        // Image not in cache, load from file using a coroutine on IO dispatcher
        (scope ?: CoroutineScope(Dispatchers.IO)).launch { // Use provided scope or a new one
            try {
                val bitmap = BitmapFactory.decodeFile(imagePath)
                if (bitmap != null) {
                    // Store in cache if successfully loaded
                    // Ensure that if the scope is a new one, this operation completes.
                    // If it's a shared scope, it should be fine.
                    synchronized(imageCache) { // LruCache is not thread-safe for concurrent writes
                        imageCache.put(imagePath, bitmap)
                    }
                    Log.d(TAG, "Loaded and cached image for tag '${resource.tag}' from path: $imagePath")
                } else {
                    Log.e(TAG, "Failed to decode image for tag '${resource.tag}' from path: $imagePath")
                }
                // The result callback should be safe to call from this thread if AnimView handles it.
                // If AnimView expects callbacks on the main thread, use:
                // withContext(Dispatchers.Main) { result(bitmap) }
                result(bitmap)
            } catch (e: Exception) {
                Log.e(TAG, "Error loading image for tag '${resource.tag}': ${e.localizedMessage}", e)
                result(null)
            }
        }
    }

    /**
     * Called by [AnimView] when it needs text for a specific resource tag.
     * @param resource The [Resource] object containing metadata like the tag.
     * @param result A callback function to provide the text [String] or null if not found.
     */
    override fun fetchText(resource: Resource, result: (String?) -> Unit) {
        val model = resources.firstOrNull { it.tag == resource.tag }
        if (model != null) {
            Log.d(TAG, "Fetching text for tag '${resource.tag}': ${model.resource}")
            result(model.resource) // Assuming model.resource is the text string
        } else {
            Log.w(TAG, "No text resource found for tag: ${resource.tag}")
            result(null)
        }
    }

    /**
     * Called by [AnimView] when it no longer needs certain resources, allowing for cleanup.
     * This is important for recycling Bitmaps to free up memory.
     * Note: LruCache handles eviction, but AnimView might request explicit release.
     * If items are removed from LruCache, their bitmaps are recycled via entryRemoved.
     * @param resources A list of [Resource] objects that can be released.
     */
    override fun releaseResource(resources: List<Resource>) {
        Log.d(TAG, "Releasing ${resources.size} resources requested by AnimView.")
        resources.forEach { res ->
            // If the bitmap is managed by LruCache, removing it from the cache
            // will trigger its recycling if configured in LruCache.evict().
            // However, AnimView is explicitly asking to release this resource.
            // We should ensure it's removed from cache AND recycled if not already.
            val bitmapToRemove = imageCache.get(res.srcId) // Assuming srcId or similar maps to the key used for cache
            if (bitmapToRemove != null && bitmapToRemove == res.bitmap) {
                 synchronized(imageCache) {
                    // Important: Use the correct key that was used to put the bitmap into the cache.
                    // This example assumes res.srcId or a similar property holds that key.
                    // If res.tag was used, and it's unique per image path, that might be it.
                    // For now, we don't have a direct key from 'Resource' to our cache key (imagePath).
                    // This part needs careful mapping if we want to remove from cache here.
                    // A simpler LruCache eviction strategy (size-based) might be more robust
                    // than explicit removal here unless keys are perfectly mapped.
                 }
            }

            // Regardless of cache, if AnimView provides a bitmap and asks to release, recycle it.
            if (res.bitmap != null && !res.bitmap.isRecycled) {
                Log.d(TAG, "Recycling bitmap for tag: ${res.tag} (explicitly by AnimView)")
                res.bitmap.recycle()
            }
        }
    }
}

/**
 * Data model for dynamic resources used in VAP animations.
 *
 * @property tag The identifier tag for the resource, as defined in the VAP animation file.
 *               This tag is used by the native player to match this resource data
 *               with a specific placeholder in the animation.
 * @property resource The actual resource content. This can be a local file path for an image
 *                    or a string for text content. The native player will interpret this
 *                    based on the type of placeholder associated with the [tag] in the animation.
 */
internal class FetchResourceModel(
    val tag: String,
    val resource: String,
) {
    override fun toString(): String {
        return "FetchResourceModel(tag='$tag', resource='$resource')"
    }
}