package com.example.music_app

import android.app.Activity
import android.app.RecoverableSecurityException
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

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
                    "import" -> importAudio(
                        call.argument<String>("path") ?: "",
                        call.argument<String>("name") ?: "musique.m4a",
                        call.argument<String>("title") ?: "musique",
                        call.argument<String>("mime") ?: "audio/mp4",
                        result
                    )
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

    private fun importAudio(
        path: String,
        name: String,
        title: String,
        mime: String,
        result: MethodChannel.Result
    ) {
        try {
            val src = File(path)
            if (Build.VERSION.SDK_INT >= 29) {
                val values = ContentValues().apply {
                    put(MediaStore.Audio.Media.DISPLAY_NAME, name)
                    put(MediaStore.Audio.Media.TITLE, title)
                    put(MediaStore.Audio.Media.MIME_TYPE, mime)
                    put(MediaStore.Audio.Media.RELATIVE_PATH, "Music/PahaeMusic")
                    put(MediaStore.Audio.Media.IS_MUSIC, 1)
                    put(MediaStore.Audio.Media.IS_PENDING, 1)
                }
                val uri = contentResolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, values)
                    ?: throw Exception("insertion impossible")
                contentResolver.openOutputStream(uri)?.use { out ->
                    src.inputStream().use { it.copyTo(out) }
                } ?: throw Exception("écriture impossible")
                val done = ContentValues().apply { put(MediaStore.Audio.Media.IS_PENDING, 0) }
                contentResolver.update(uri, done, null, null)
                result.success(uri.toString())
            } else {
                val dir = File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC),
                    "PahaeMusic"
                )
                dir.mkdirs()
                val dest = File(dir, name)
                src.copyTo(dest, true)
                MediaScannerConnection.scanFile(this, arrayOf(dest.absolutePath), arrayOf(mime), null)
                result.success(dest.absolutePath)
            }
            src.delete()
        } catch (e: Exception) {
            result.error("import", e.toString(), null)
        }
    }

    private var deleteIds: List<Long> = emptyList()

    private fun uriOf(id: Long): Uri =
        ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id)

    private fun exists(id: Long): Boolean = try {
        contentResolver.query(uriOf(id), arrayOf(MediaStore.Audio.Media._ID), null, null, null)
            ?.use { it.count > 0 } ?: false
    } catch (e: Exception) {
        false
    }

    private fun finishDelete(cancelled: Boolean) {
        val gone = ArrayList<Long>()
        val failed = ArrayList<Long>()
        for (id in deleteIds) {
            if (!cancelled && exists(id)) {
                try {
                    contentResolver.delete(uriOf(id), null, null)
                } catch (e: Exception) {
                }
            }
            if (exists(id)) failed.add(id) else gone.add(id)
        }
        pending?.success(mapOf("deleted" to gone, "failed" to failed, "cancelled" to cancelled))
        pending = null
    }

    private fun delete(ids: List<Number>, result: MethodChannel.Result) {
        try {
            deleteIds = ids.map { it.toLong() }
            val uris = deleteIds.map { uriOf(it) }
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
                finishDelete(false)
                return
            }
        }
        finishDelete(false)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 4711) {
            finishDelete(resultCode != Activity.RESULT_OK)
        } else if (requestCode == 4712) {
            if (resultCode == Activity.RESULT_OK) {
                deleteFrom(legacyIndex)
            } else {
                finishDelete(true)
            }
        }
    }
}
