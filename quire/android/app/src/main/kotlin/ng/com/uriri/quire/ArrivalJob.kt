package ng.com.uriri.quire

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobParameters
import android.app.job.JobService
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.pdf.PdfRenderer
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import org.json.JSONArray

/**
 * Looks in the folders quire was handed for documents that were not there the
 * last time, and says so.
 *
 * The first look at a folder only learns what is in it, so handing over a
 * Downloads folder with years in it is not answered with years of notices.
 */
class ArrivalJob : JobService() {
    override fun onStartJob(params: JobParameters): Boolean {
        Thread {
            try {
                look(this)
            } catch (ignored: Throwable) {
                // A folder that cannot be read this time is looked at again
                // next time; nothing here is worth a crash in the background.
            }
            jobFinished(params, false)
        }.start()
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean = true

    companion object {
        private const val SEEN = "seen:"
        private const val CHANNEL = "new_documents_v1"
        private const val MOST_AT_ONCE = 3
        private const val SEEN_LIMIT = 4000
        private const val DEPTH = 2
        private val READS = setOf("pdf", "docx", "xlsx", "pptx", "csv", "tsv", "md", "markdown", "txt")

        private class Found(val uri: Uri, val name: String, val modified: Long)

        fun look(context: Context) {
            val prefs = context.getSharedPreferences(ArrivalNotices.PREFS, Context.MODE_PRIVATE)
            val trees = JSONArray(prefs.getString(ArrivalNotices.TREES, "[]") ?: "[]")
            val granted = context.contentResolver.persistedUriPermissions.map { it.uri }.toSet()
            val arrived = ArrayList<Found>()
            for (i in 0 until trees.length()) {
                val tree = Uri.parse(trees.getString(i))
                if (tree !in granted) continue
                val found = ArrayList<Found>()
                walk(context.contentResolver, tree, DocumentsContract.getTreeDocumentId(tree), 0, found)
                val key = SEEN + tree
                val first = !prefs.contains(key)
                val seen = prefs.getStringSet(key, emptySet())!!.toMutableSet()
                for (doc in found) {
                    if (seen.add(doc.uri.toString()) && !first) arrived.add(doc)
                }
                val kept = if (seen.size > SEEN_LIMIT) {
                    found.map { it.uri.toString() }.toMutableSet()
                } else {
                    seen
                }
                prefs.edit().putStringSet(key, kept).apply()
            }
            if (arrived.isEmpty() || !allowed(context)) return
            arrived.sortByDescending { it.modified }
            for (doc in arrived.take(MOST_AT_ONCE)) notify(context, doc)
        }

        private fun walk(
            resolver: ContentResolver,
            tree: Uri,
            parent: String,
            depth: Int,
            out: MutableList<Found>,
        ) {
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parent)
            resolver.query(
                children,
                arrayOf(
                    Document.COLUMN_DOCUMENT_ID,
                    Document.COLUMN_DISPLAY_NAME,
                    Document.COLUMN_MIME_TYPE,
                    Document.COLUMN_LAST_MODIFIED,
                ),
                null,
                null,
                null,
            )?.use { rows ->
                while (rows.moveToNext()) {
                    val id = rows.getString(0) ?: continue
                    val name = rows.getString(1) ?: continue
                    if (rows.getString(2) == Document.MIME_TYPE_DIR) {
                        if (depth < DEPTH) walk(resolver, tree, id, depth + 1, out)
                        continue
                    }
                    if (name.substringAfterLast('.', "").lowercase() !in READS) continue
                    val modified = if (rows.isNull(3)) 0L else rows.getLong(3)
                    out.add(Found(DocumentsContract.buildDocumentUriUsingTree(tree, id), name, modified))
                }
            }
        }

        private fun allowed(context: Context): Boolean =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED

        /** The next line Dart dealt, or, for a PDF, how many pages it has. */
        private fun lineFor(context: Context, doc: Found): String {
            val prefs = context.getSharedPreferences(ArrivalNotices.PREFS, Context.MODE_PRIVATE)
            if (doc.name.lowercase().endsWith(".pdf")) {
                val pages = pagesOf(context, doc.uri)
                val counted = JSONArray(prefs.getString(ArrivalNotices.PDF_LINES, "[]") ?: "[]")
                if (pages in 1..counted.length()) return counted.getString(pages - 1)
            }
            val lines = JSONArray(prefs.getString(ArrivalNotices.LINES, "[]") ?: "[]")
            if (lines.length() == 0) return FALLBACK
            val line = lines.getString(0)
            val rest = JSONArray()
            for (i in 1 until lines.length()) rest.put(lines.getString(i))
            prefs.edit()
                .putString(ArrivalNotices.LINES, rest.toString())
                .putInt(ArrivalNotices.USED, prefs.getInt(ArrivalNotices.USED, 0) + 1)
                .apply()
            return line
        }

        private fun pagesOf(context: Context, uri: Uri): Int = try {
            context.contentResolver.openFileDescriptor(uri, "r")?.use { descriptor ->
                PdfRenderer(descriptor).use { it.pageCount }
            } ?: 0
        } catch (ignored: Throwable) {
            0
        }

        private fun notify(context: Context, doc: Found) {
            val manager = context.getSystemService(NotificationManager::class.java)
            channel(context, manager)
            val id = doc.uri.toString().hashCode()
            val title = doc.name.substringBeforeLast('.')
            val line = lineFor(context, doc)
            val open = PendingIntent.getActivity(
                context,
                id,
                Intent(context, MainActivity::class.java).apply {
                    action = MainActivity.OPEN_DEVICE
                    putExtra(MainActivity.DEVICE_URI, doc.uri.toString())
                    putExtra(MainActivity.DEVICE_NAME, doc.name)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val later = PendingIntent.getBroadcast(
                context,
                id,
                Intent(context, NoticeDismissed::class.java).putExtra(NoticeDismissed.ID, id),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CHANNEL)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context).setPriority(Notification.PRIORITY_HIGH)
            }
            val notice = builder
                // The small icon is tinted by the phone and loses its colour,
                // so it is the mark's silhouette alone. The full mark is the
                // large icon, which is what shows when the notice is opened.
                .setSmallIcon(R.drawable.ic_stat_quire)
                .setLargeIcon(markOf(context))
                .setContentTitle(title)
                .setContentText(line)
                .setStyle(Notification.BigTextStyle().bigText(line))
                .setContentIntent(open)
                .setAutoCancel(true)
                .addAction(Notification.Action.Builder(null, "Open", open).build())
                .addAction(Notification.Action.Builder(null, "Not now", later).build())
                .build()
            manager.notify(id, notice)
        }

        /**
         * The one channel these notices go through. A channel's sound and
         * importance are fixed when it is made, so a change to either needs a
         * new id, which is why this one is numbered.
         */
        private fun channel(context: Context, manager: NotificationManager) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            if (manager.getNotificationChannel(CHANNEL) != null) return
            val sound = Uri.parse(
                "${ContentResolver.SCHEME_ANDROID_RESOURCE}://${context.packageName}/${R.raw.quire_knock}",
            )
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "New documents", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "A document has arrived in a folder quire reads."
                    setSound(
                        sound,
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build(),
                    )
                },
            )
        }

        private fun markOf(context: Context): Bitmap? {
            val drawable = context.getDrawable(R.mipmap.ic_launcher) ?: return null
            val size = (64 * context.resources.displayMetrics.density).toInt()
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            drawable.setBounds(0, 0, size, size)
            drawable.draw(Canvas(bitmap))
            return bitmap
        }

        private const val FALLBACK = "Just downloaded. Open it in quire?"
    }
}
