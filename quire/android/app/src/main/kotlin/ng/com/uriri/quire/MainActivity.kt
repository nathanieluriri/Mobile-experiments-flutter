package ng.com.uriri.quire

import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Hands documents opened from outside the app over to the Dart side, and lets
 * it hold the screen awake.
 *
 * Two ways in and they are different. A cold start has the intent waiting
 * before Dart is up, so the path is held until Dart asks for it. A warm open
 * arrives at any moment, and is pushed straight across.
 *
 * The content uri a launcher sends is readable only through the resolver and
 * only for as long as the grant lasts, so it is copied into the cache
 * directory here and it is that copy's path that goes over. The Dart side
 * imports it and the copy stops mattering.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var screen: MethodChannel? = null

    /** The document a cold start arrived with, waiting for Dart to ask. */
    private var pending: String? = null

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        val messenger = engine.dartExecutor.binaryMessenger
        channel = MethodChannel(messenger, CHANNEL).also { open ->
            open.setMethodCallHandler { call, result ->
                if (call.method == INITIAL) {
                    result.success(pending)
                    pending = null
                } else {
                    result.notImplemented()
                }
            }
        }
        screen = MethodChannel(messenger, SCREEN).also { hold ->
            hold.setMethodCallHandler { call, result ->
                if (call.method == HOLD) {
                    setScreenHeld(call.arguments == true)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    /**
     * Keeps the screen on, or lets it go again.
     *
     * A presentation is a stretch of minutes with no touches in it, which is
     * exactly what the phone reads as nobody being there. Without this the
     * screen dims and then locks part way through a slide, in front of whoever
     * is watching. It is a window flag rather than a wake lock so that it
     * cannot outlive the window: quire has no business keeping a phone awake
     * once it is no longer the thing on the screen.
     */
    private fun setScreenHeld(held: Boolean) {
        if (held) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        pending = copyOf(intent)
    }

    override fun onNewIntent(next: Intent) {
        super.onNewIntent(next)
        val path = copyOf(next) ?: return
        val open = channel
        if (open == null) {
            pending = path
            return
        }
        open.invokeMethod(OPENED, path)
    }

    /**
     * The document [intent] carries, copied somewhere this app can read it
     * later, or null when it carries none.
     */
    private fun copyOf(intent: Intent?): String? {
        val uri = when (intent?.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> intent.getParcelableExtra(Intent.EXTRA_STREAM)
            // Only the first. The app opens one document at a time, and
            // quietly dropping the rest is better than opening a pile of
            // windows nobody asked for.
            Intent.ACTION_SEND_MULTIPLE ->
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                    ?.firstOrNull()
            else -> null
        } ?: return null
        return try {
            copyIn(uri)
        } catch (error: Exception) {
            null
        }
    }

    private fun copyIn(uri: Uri): String? {
        val resolver = contentResolver
        val name = nameOf(resolver, uri) ?: return null
        val into = File(cacheDir, "incoming").apply { mkdirs() }
        val file = File(into, "${System.currentTimeMillis()}_$name")
        resolver.openInputStream(uri).use { source ->
            if (source == null) return null
            file.outputStream().use { sink -> source.copyTo(sink) }
        }
        return file.absolutePath
    }

    /**
     * What the document is called, which is the only thing that says what kind
     * of file it is once it has been copied out of its uri.
     */
    private fun nameOf(resolver: ContentResolver, uri: Uri): String? {
        if (uri.scheme == ContentResolver.SCHEME_FILE) {
            return uri.lastPathSegment
        }
        resolver.query(uri, null, null, null, null)?.use { row ->
            val at = row.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (at >= 0 && row.moveToFirst()) return row.getString(at)
        }
        return uri.lastPathSegment
    }

    private companion object {
        const val CHANNEL = "ng.com.uriri.quire/incoming"
        const val INITIAL = "getInitialFile"
        const val OPENED = "opened"
        const val SCREEN = "ng.com.uriri.quire/screen"
        const val HOLD = "hold"
    }
}
