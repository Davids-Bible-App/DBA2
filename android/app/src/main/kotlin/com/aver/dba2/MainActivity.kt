package com.aver.dba2

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.provider.DocumentsContract
import android.view.WindowManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.concurrent.thread
import android.system.Os
import android.system.OsConstants


class MainActivity : AudioServiceActivity() {
    private val backupRequest = 4711
    private var pendingResult: MethodChannel.Result? = null
    private var pendingSource: String? = null
    private var serverPid = 0


    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != backupRequest) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingResult
        val src = pendingSource
        pendingResult = null
        pendingSource = null
        if (result == null || src == null) return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(false) // user cancelled
            return
        }
        thread {
            try {
                contentResolver.openOutputStream(uri, "w")!!.use { out ->
                    File(src).inputStream().use { it.copyTo(out, 1 shl 20) }
                }
                runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                try { DocumentsContract.deleteDocument(contentResolver, uri) } catch (_: Exception) {}
                runOnUiThread { result.error("copy_failed", e.message ?: "Copy failed", null) }
            }
        }
    }

    override fun onDestroy() {
        // isFinishing is false for rotation etc., so only a real close stops the server.
        if (isFinishing && serverPid > 0) {
            try { Os.kill(serverPid, OsConstants.SIGTERM) } catch (_: Exception) {}
        }
        super.onDestroy()
    }


    // ONE configureFlutterEngine, registering all three channels.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

                // 1. Bible AI: where the bundled llama-server lives + its running pid
        MethodChannel(messenger, "bible_ai/engine")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "serverPath" -> {
                        val f = File(applicationInfo.nativeLibraryDir, "libllama_server.so")
                        result.success(if (f.exists()) f.absolutePath else null)
                    }
                    "setServerPid" -> {
                        serverPid = call.arguments as? Int ?: 0
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }


        // 2. Bible AI: save a model backup via the system file picker
        MethodChannel(messenger, "bible_ai/backup")
            .setMethodCallHandler { call, result ->
                if (call.method != "exportFile") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingResult != null) {
                    result.error("busy", "Another save is already in progress.", null)
                    return@setMethodCallHandler
                }
                pendingResult = result
                pendingSource = call.argument<String>("path")
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "application/octet-stream"
                    putExtra(Intent.EXTRA_TITLE, call.argument<String>("name"))
                }
                startActivityForResult(intent, backupRequest)
            }

        // 3. Your existing app: draw under the camera cutout
        MethodChannel(messenger, "app/cutout")
            .setMethodCallHandler { call, result ->
                if (call.method == "setDrawUnderCutout") {
                    val enable = call.arguments as? Boolean ?: false
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        val attrs = window.attributes
                        attrs.layoutInDisplayCutoutMode = if (enable) {
                            WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                        } else {
                            WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_DEFAULT
                        }
                        window.attributes = attrs
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}