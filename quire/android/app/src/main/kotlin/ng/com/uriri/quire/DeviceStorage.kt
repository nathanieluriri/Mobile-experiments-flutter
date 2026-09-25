package ng.com.uriri.quire

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Folders on the phone the reader has handed to quire, through the Storage
 * Access Framework.
 *
 * The reader picks a folder once and the grant is kept, so quire can list,
 * read and make folders inside it from then on without holding any storage
 * permission at all, and without asking Play for all files access. Nothing
 * outside a granted folder can be reached from here.
 */
class DeviceStorage(private val activity: Activity, messenger: BinaryMessenger) {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var picking: MethodChannel.Result? = null

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "adopt") {
                adopt(result)
            } else {
                worker.execute { answer(call, result) }
            }
        }
    }

    private fun answer(call: MethodCall, result: MethodChannel.Result) {
        try {
            val reply: Any? = when (call.method) {
                "list" -> list(call)
                "makeFolder" -> makeFolder(call)
                "read" -> read(call)
                "release" -> release(call)
                "granted" -> granted()
                else -> {
                    main.post { result.notImplemented() }
                    return
                }
            }
            main.post { result.success(reply) }
        } catch (gone: SecurityException) {
            main.post { result.error("gone", gone.message, null) }
        } catch (gone: java.io.FileNotFoundException) {
            main.post { result.error("gone", gone.message, null) }
        } catch (error: Throwable) {
            main.post { result.error("failed", error.message, null) }
        }
    }

    /** Asks the reader for a folder, starting in Downloads where it can. */
    private fun adopt(result: MethodChannel.Result) {
        if (picking != null) {
            result.error("busy", "already choosing a folder", null)
            return
        }
        picking = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                putExtra(
                    DocumentsContract.EXTRA_INITIAL_URI,
                    DocumentsContract.buildDocumentUri(EXTERNAL, "primary:Download"),
                )
            }
        }
        try {
            activity.startActivityForResult(intent, REQUEST)
        } catch (error: Throwable) {
            picking = null
            result.error("failed", error.message, null)
        }
    }

    /** The picker's answer, handed on from the activity. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST) return false
        val result = picking ?: return true
        picking = null
        val tree = data?.data
        if (resultCode != Activity.RESULT_OK || tree == null) {
            result.success(null)
            return true
        }
        worker.execute {
            try {
                activity.contentResolver.takePersistableUriPermission(
                    tree,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
                val root = DocumentsContract.buildDocumentUriUsingTree(
                    tree,
                    DocumentsContract.getTreeDocumentId(tree),
                )
                val name = nameOf(root) ?: tree.lastPathSegment ?: "Folder"
                main.post {
                    result.success(mapOf("tree" to tree.toString(), "name" to name))
                }
            } catch (error: Throwable) {
                main.post { result.error("failed", error.message, null) }
            }
        }
        return true
    }

    private fun treeOf(call: MethodCall): Uri {
        val tree = Uri.parse(call.argument<String>("tree") ?: throw SecurityException("no tree"))
        val held = activity.contentResolver.persistedUriPermissions.any {
            it.uri == tree && it.isReadPermission
        }
        if (!held) throw SecurityException("the grant for this folder has gone")
        return tree
    }

    /** What is directly inside a folder of a granted tree. */
    private fun list(call: MethodCall): List<Map<String, Any?>> {
        val tree = treeOf(call)
        val parent = call.argument<String>("document")
            ?: DocumentsContract.getTreeDocumentId(tree)
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parent)
        val out = ArrayList<Map<String, Any?>>()
        activity.contentResolver.query(
            children,
            arrayOf(
                Document.COLUMN_DOCUMENT_ID,
                Document.COLUMN_DISPLAY_NAME,
                Document.COLUMN_MIME_TYPE,
                Document.COLUMN_SIZE,
                Document.COLUMN_LAST_MODIFIED,
            ),
            null,
            null,
            null,
        )?.use { rows ->
            while (rows.moveToNext()) {
                val id = rows.getString(0) ?: continue
                out.add(
                    mapOf(
                        "document" to id,
                        "uri" to DocumentsContract.buildDocumentUriUsingTree(tree, id).toString(),
                        "name" to (rows.getString(1) ?: id),
                        "folder" to (rows.getString(2) == Document.MIME_TYPE_DIR),
                        "size" to (if (rows.isNull(3)) 0L else rows.getLong(3)),
                        "modified" to (if (rows.isNull(4)) 0L else rows.getLong(4)),
                    ),
                )
            }
        } ?: throw java.io.FileNotFoundException("the folder is not there")
        return out
    }

    /** Makes a folder on the phone, inside a granted tree. */
    private fun makeFolder(call: MethodCall): Map<String, Any?> {
        val tree = treeOf(call)
        val parent = call.argument<String>("document")
            ?: DocumentsContract.getTreeDocumentId(tree)
        val name = call.argument<String>("name") ?: throw IllegalArgumentException("no name")
        val parentUri = DocumentsContract.buildDocumentUriUsingTree(tree, parent)
        val made = DocumentsContract.createDocument(
            activity.contentResolver,
            parentUri,
            Document.MIME_TYPE_DIR,
            name,
        ) ?: throw IllegalStateException("the phone would not make the folder")
        return mapOf(
            "document" to DocumentsContract.getDocumentId(made),
            "uri" to made.toString(),
            "name" to (nameOf(made) ?: name),
            "folder" to true,
            "size" to 0L,
            "modified" to System.currentTimeMillis(),
        )
    }

    /** The bytes of one document, which the reader reads like any other. */
    private fun read(call: MethodCall): ByteArray {
        val uri = Uri.parse(call.argument<String>("uri") ?: throw IllegalArgumentException("no uri"))
        activity.contentResolver.openInputStream(uri).use { stream ->
            return stream?.readBytes() ?: throw java.io.FileNotFoundException("unreadable")
        }
    }

    private fun release(call: MethodCall): Any? {
        val tree = Uri.parse(call.argument<String>("tree") ?: return null)
        try {
            activity.contentResolver.releasePersistableUriPermission(
                tree,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        } catch (ignored: SecurityException) {
            // Already gone.
        }
        return null
    }

    private fun granted(): List<String> =
        activity.contentResolver.persistedUriPermissions.map { it.uri.toString() }

    private fun nameOf(document: Uri): String? =
        activity.contentResolver.query(
            document,
            arrayOf(Document.COLUMN_DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { if (it.moveToFirst()) it.getString(0) else null }

    private companion object {
        const val CHANNEL = "ng.com.uriri.quire/storage"
        const val REQUEST = 4721
        const val EXTERNAL = "com.android.externalstorage.documents"
    }
}
