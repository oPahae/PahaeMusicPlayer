package com.example.music_app

import android.app.Activity
import android.app.RecoverableSecurityException
import android.content.ContentUris
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var pending: MethodChannel.Result? = null
    private var legacyUris: List<Uri> = emptyList()
    private var legacyIndex = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "music/scan")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ping" -> result.success("2")
                    "songs" -> songs(result)
                    "delete" -> delete(call.argument<List<Number>>("ids") ?: emptyList(), result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun songs(result: MethodChannel.Result) {
        try {
            val list = ArrayList<Map<String, Any?>>()
            val proj = arrayOf(
                MediaStore.Audio.Media.DATA,
                MediaStore.Audio.Media.TITLE,
                MediaStore.Audio.Media._ID,
                MediaStore.Audio.Media.DATE_ADDED
            )
            val sel = "${MediaStore.Audio.Media.IS_RINGTONE} = 0 AND " +
                "${MediaStore.Audio.Media.IS_NOTIFICATION} = 0 AND " +
                "${MediaStore.Audio.Media.IS_ALARM} = 0 AND " +
                "${MediaStore.Audio.Media.DURATION} > 30000 AND " +
                "${MediaStore.Audio.Media.DATA} NOT LIKE '%WhatsApp%'"
            contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                proj,
                sel,
                null,
                null
            )?.use { c ->
                while (c.moveToNext()) {
                    val path = c.getString(0) ?: continue
                    list.add(
                        mapOf(
                            "path" to path,
                            "title" to c.getString(1),
                            "id" to c.getLong(2),
                            "added" to c.getLong(3)
                        )
                    )
                }
            }
            result.success(list)
        } catch (e: Exception) {
            result.error("scan", e.message, null)
        }
    }

    private fun delete(ids: List<Number>, result: MethodChannel.Result) {
        try {
            val uris = ids.map {
                ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, it.toLong())
            }
            pending = result
            if (Build.VERSION.SDK_INT >= 30) {
                val pi = MediaStore.createDeleteRequest(contentResolver, uris)
                startIntentSenderForResult(pi.intentSender, 4711, null, 0, 0, 0)
            } else {
                legacyUris = uris
                deleteFrom(0)
            }
        } catch (e: Exception) {
            pending = null
            result.error("delete", e.toString(), null)
        }
    }

    private fun deleteFrom(start: Int) {
        var i = start
        while (i < legacyUris.size) {
            try {
                contentResolver.delete(legacyUris[i], null, null)
                i++
            } catch (e: SecurityException) {
                if (Build.VERSION.SDK_INT >= 29 && e is RecoverableSecurityException) {
                    legacyIndex = i
                    startIntentSenderForResult(
                        e.userAction.actionIntent.intentSender, 4712, null, 0, 0, 0
                    )
                    return
                }
                pending?.error("delete", e.toString(), null)
                pending = null
                return
            }
        }
        pending?.success(true)
        pending = null
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 4711) {
            pending?.success(resultCode == Activity.RESULT_OK)
            pending = null
        } else if (requestCode == 4712) {
            if (resultCode == Activity.RESULT_OK) {
                deleteFrom(legacyIndex)
            } else {
                pending?.success(false)
                pending = null
            }
        }
    }
}
