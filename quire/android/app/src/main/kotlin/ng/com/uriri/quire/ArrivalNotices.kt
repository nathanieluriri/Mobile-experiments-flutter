package ng.com.uriri.quire

import android.Manifest
import android.app.Activity
import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray

/**
 * What quire tells the phone about the notices that a document has arrived:
 * which folders to watch, and the lines to say, dealt in Dart.
 *
 * The check itself is [ArrivalJob], run by the phone's own job scheduler about
 * every quarter of an hour whether or not quire is running. Nothing sooner is
 * possible for a download another app made, so a notice comes a while after
 * the file lands, never the moment it does.
 */
class ArrivalNotices(private val activity: Activity, messenger: BinaryMessenger) {
    private var asking: MethodChannel.Result? = null

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "configure" -> {
                    val trees = call.argument<List<String>>("trees") ?: emptyList()
                    val lines = call.argument<List<String>>("lines") ?: emptyList()
                    val pdfLines = call.argument<List<String>>("pdfLines")
                    result.success(configure(activity, trees, lines, pdfLines))
                }
                "askLeave" -> askLeave(result)
                else -> result.notImplemented()
            }
        }
    }

    /** Asks for leave to post notices, where the phone asks the reader. */
    private fun askLeave(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (asking != null) {
            result.success(false)
            return
        }
        asking = result
        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST)
    }

    /** The reader's answer, handed on from the activity. */
    fun onRequestPermissionsResult(requestCode: Int, results: IntArray): Boolean {
        if (requestCode != REQUEST) return false
        val result = asking ?: return true
        asking = null
        result.success(results.isNotEmpty() && results[0] == PackageManager.PERMISSION_GRANTED)
        return true
    }

    companion object {
        const val CHANNEL = "ng.com.uriri.quire/notices"
        const val REQUEST = 4722
        const val JOB = 4723
        const val PREFS = "quire_arrivals"
        const val TREES = "trees"
        const val LINES = "lines"
        const val USED = "used"
        const val PDF_LINES = "pdfLines"
        const val PERIOD_MS = 15L * 60L * 1000L

        /**
         * Keeps what Dart said and schedules the check, or cancels it when
         * there is no folder to watch. Returns how many lines were used from
         * the last queue, and drops that many from the front of this one,
         * since both begin where the dealer stood.
         */
        fun configure(
            context: Context,
            trees: List<String>,
            lines: List<String>,
            pdfLines: List<String>?,
        ): Int {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val used = prefs.getInt(USED, 0)
            val queue = JSONArray(lines.drop(used.coerceAtMost(lines.size)))
            prefs.edit().apply {
                putString(TREES, JSONArray(trees).toString())
                putString(LINES, queue.toString())
                putInt(USED, 0)
                if (pdfLines != null) putString(PDF_LINES, JSONArray(pdfLines).toString())
                apply()
            }
            val scheduler = context.getSystemService(JobScheduler::class.java)
            if (trees.isEmpty()) {
                scheduler.cancel(JOB)
            } else if (scheduler.getPendingJob(JOB) == null) {
                scheduler.schedule(
                    JobInfo.Builder(JOB, ComponentName(context, ArrivalJob::class.java))
                        .setPeriodic(PERIOD_MS)
                        .setPersisted(true)
                        .build(),
                )
            }
            return used
        }
    }
}
