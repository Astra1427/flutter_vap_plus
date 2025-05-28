package com.nell.flutter_vap_plus

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import android.view.View
import com.tencent.qgame.animplayer.AnimConfig
import com.tencent.qgame.animplayer.AnimView
import com.tencent.qgame.animplayer.Constant
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
import org.json.JSONArray
import java.io.File

internal class NativeVapView(
    binaryMessenger: BinaryMessenger,
    context: Context,
    id: Int,
    private val creationParams: Map<String?, Any?>?
) : MethodChannel.MethodCallHandler, PlatformView {

    private val mContext: Context = context
    private val vapView: AnimView = AnimView(context)
    private val channel: MethodChannel =
        MethodChannel(binaryMessenger, "flutter_vap_controller_${id}")


    // 创建一个 CoroutineScope
    private var myScope: CoroutineScope? =
        CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate) // 或者 Dispatchers.Default/I // O

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onFlutterViewAttached(flutterView: View) {
        super.onFlutterViewAttached(flutterView)

        /// 循环播放
        val repeatCount = creationParams?.get("repeatCount") as Int
        if (repeatCount == -1) {
            vapView.setLoop(Int.MAX_VALUE)
        }
        else {
            vapView.setLoop(repeatCount)
        }

        vapView.enableVersion1(true)

        vapView.setVideoMode(Constant.VIDEO_MODE_SPLIT_HORIZONTAL_REVERSE)

        vapView.setScaleType(
            ScaleType.valueOf(
                (creationParams?.get("scaleType") ?: "FIT_CENTER").toString()
            )
        )
        vapView.setAnimListener(object : IAnimListener {
            override fun onFailed(errorType: Int, errorMsg: String?) {
                val errorInfo = mapOf(
                    "status" to "failure",
                    "errorType" to errorType,
                    "errorMsg" to (errorMsg ?: "unknown error")
                )
                Log.d("TAG", "Anim onFailed: $errorInfo")
                myScope?.launch {
                    channel.invokeMethod(
                        "onFailed",
                        errorInfo
                    )
                }

            }

            override fun onVideoComplete() {
//                myScope?.launch {
//                    eventSink?.success(mapOf("status" to "complete"))
//                }
                myScope?.launch {
                    channel.invokeMethod(
                        "onComplete",
                        mapOf("status" to "complete")
                    )
                }

            }

            override fun onVideoDestroy() {
                // Handle video destroy if necessary
                myScope?.launch {
                    channel.invokeMethod(
                        "onDestroy",
                        mapOf("status" to "destroy")
                    )
                }
            }

            override fun onVideoRender(frameIndex: Int, config: AnimConfig?) {
                // Handle video render if necessary
//                myScope?.launch {
//                    channel.invokeMethod(
//                        "onRender",
//                        mapOf(
//                            "status" to "render",
//                            "frameIndex" to frameIndex,
////                    "config" to config
//                        )
//                    )
//                }
            }

            override fun onVideoStart() {
                // Handle video start if necessary
                myScope?.launch {
                    channel.invokeMethod("onStart", mapOf("status" to "start"))
                }
            }
        })

    }

    override fun getView(): View {
        return vapView
    }

    override fun dispose() {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        Log.d("TAG", "onMethodCall: ${call.method}")
        when (call.method) {
            "playPath" -> {
                val path = call.argument<String>("path")
                if (path != null) {
                    vapView.startPlay(File(path))
                    result.success(null)

                } else {
                    result.error("INVALID_ARGUMENT", "Path is null", null)
                }
            }

            "playAsset" -> {
                val asset = call.argument<String>("asset")
                if (asset != null) {
                    vapView.startPlay(mContext.assets, "flutter_assets/$asset")
                    result.success(null)
                } else {
                    result.error("INVALID_ARGUMENT", "Asset is null", null)
                }
            }

            "stop" -> {
                vapView.stopPlay()
                result.success(null)
            }

            "setFetchResource" -> {
                val rawJson = call.arguments.toString()
                val list: List<FetchResourceModel> = parseJsonToFetchResourceModelList(rawJson)

                vapView.setFetchResource(
                    fetchResource = FetchResources(
                        resources = list
                    )
                )
                result.success(null);
            }

            else -> {
                result.notImplemented()
            }
        }
    }


    private fun parseJsonToFetchResourceModelList(rawJson: String): List<FetchResourceModel> {
        val list = mutableListOf<FetchResourceModel>()
        try {
            val jsonArray = JSONArray(rawJson)
            for (i in 0 until jsonArray.length()) {
                val jsonObject = jsonArray.getJSONObject(i)
                val tag = jsonObject.getString("tag")
                val resource = jsonObject.getString("resource")

                val resourceModel = FetchResourceModel(tag,resource)
                list.add(resourceModel)
            }
        } catch (e: Exception) {
            println("JSON parsing error: ${e.message}")
            e.printStackTrace()
            return emptyList()
        }
        return list
    }
}


internal class FetchResources(
    private val resources: List<FetchResourceModel>
) : IFetchResource {


    override fun fetchImage(resource: Resource, result: (Bitmap?) -> Unit) {
        Log.d("TAG", "fetchResource: fetchImage ${resource.tag} -- $resources")
        resources.firstOrNull {
            it.tag == resource.tag
        }?.let {
            Log.d("TAG", "fetchImage: result ${it.resource}")
            result(BitmapFactory.decodeFile(it.resource))
        } ?: result(null)
    }

    override fun fetchText(resource: Resource, result: (String?) -> Unit) {
        Log.d("TAG", "fetchResource: fetchText ${resource.tag}")

        result(
            resources.firstOrNull {
                it.tag == resource.tag
            }?.resource
        )

    }

    override fun releaseResource(resources: List<Resource>) {
        resources.forEach {
            it.bitmap?.recycle()
        }
    }
}

internal class FetchResourceModel(
    /// vap资源文件中预设的tag
    val tag: String,
    /// 图片本地路径或者文本字符串
    val resource: String,


) {
    override fun toString(): String {
        return mapOf(
            "tag" to tag,
            "resource" to resource
        ).toString()
    }
}