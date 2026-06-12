package com.ravilesx.playit_mobile

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Storage Access Framework bridge. The app holds no storage permissions:
 * the user grants access to a single folder via the system picker and the
 * grant is persisted across reboots with takePersistableUriPermission.
 *
 * Extends AudioServiceActivity so audio_service can host the media session.
 */
class MainActivity : AudioServiceActivity() {

    private companion object {
        const val CHANNEL = "playit/saf"
        const val PICK_TREE_REQUEST = 4201
        const val MAX_WALK_DEPTH = 8
    }

    private var pendingPickResult: MethodChannel.Result? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickTree" -> pickTree(result)
                    "persistedTree" -> result.success(persistedTree())
                    "walkTree" -> {
                        val uri = call.argument<String>("uri")
                        if (uri == null) {
                            result.error("bad_args", "missing uri", null)
                        } else {
                            runInBackground(result) { walkTree(Uri.parse(uri)) }
                        }
                    }
                    "readFile" -> {
                        val uri = call.argument<String>("uri")
                        if (uri == null) {
                            result.error("bad_args", "missing uri", null)
                        } else {
                            runInBackground(result) { readFile(Uri.parse(uri)) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun runInBackground(result: MethodChannel.Result, block: () -> Any?) {
        Thread {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (e: Exception) {
                mainHandler.post { result.error("saf_error", e.message, null) }
            }
        }.start()
    }

    private fun pickTree(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("busy", "folder picker already open", null)
            return
        }
        pendingPickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
        )
        startActivityForResult(intent, PICK_TREE_REQUEST)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != PICK_TREE_REQUEST) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingPickResult ?: return
        pendingPickResult = null

        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        // Keep a single active grant: release any previously persisted tree
        contentResolver.persistedUriPermissions.forEach { perm ->
            if (perm.uri != uri) {
                try {
                    contentResolver.releasePersistableUriPermission(
                        perm.uri, Intent.FLAG_GRANT_READ_URI_PERMISSION
                    )
                } catch (_: Exception) {
                }
            }
        }
        contentResolver.takePersistableUriPermission(
            uri, Intent.FLAG_GRANT_READ_URI_PERMISSION
        )
        result.success(uri.toString())
    }

    private fun persistedTree(): String? =
        contentResolver.persistedUriPermissions
            .firstOrNull { it.isReadPermission }
            ?.uri?.toString()

    /** Flat recursive listing of all files under the tree, with paths relative to it. */
    private fun walkTree(treeUri: Uri): List<Map<String, String>> {
        val out = mutableListOf<Map<String, String>>()
        walkChildren(treeUri, DocumentsContract.getTreeDocumentId(treeUri), "", out, 0)
        return out
    }

    private fun walkChildren(
        treeUri: Uri,
        parentDocId: String,
        relPath: String,
        out: MutableList<Map<String, String>>,
        depth: Int,
    ) {
        if (depth > MAX_WALK_DEPTH) return
        val childrenUri =
            DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )
        contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val docId = cursor.getString(0) ?: continue
                val name = cursor.getString(1) ?: continue
                val mime = cursor.getString(2)
                val childRel = if (relPath.isEmpty()) name else "$relPath/$name"
                if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                    walkChildren(treeUri, docId, childRel, out, depth + 1)
                } else {
                    val fileUri =
                        DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
                    out.add(mapOf("uri" to fileUri.toString(), "relPath" to childRel))
                }
            }
        }
    }

    private fun readFile(uri: Uri): ByteArray =
        contentResolver.openInputStream(uri)?.use { it.readBytes() }
            ?: throw IllegalStateException("cannot open $uri")
}
