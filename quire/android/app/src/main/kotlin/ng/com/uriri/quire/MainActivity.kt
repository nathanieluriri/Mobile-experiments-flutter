package ng.com.uriri.quire

import android.annotation.TargetApi
import android.content.ContentResolver
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Rect
import android.graphics.RectF
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.view.View
import android.view.WindowManager
import android.window.SplashScreenView
import java.nio.ByteBuffer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Hands documents opened from outside the app over to the Dart side, lets it
 * hold the screen awake, and hands the launch splash over to its first frame.
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
    private var arrival: MethodChannel? = null

    /** True from launch until Android 12's splash has been dealt with. */
    private var splashUp = false

    /** True once the system has given the app its splash to hand over. */
    private var handing = false

    /** Whether Dart has had its first chance to say how the bars should be. */
    private var resumedOnce = false

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
        arrival = MethodChannel(messenger, ARRIVAL)
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
        reachTheEdges()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            splashUp = true
            splashScreen.setOnExitAnimationListener { splash -> handOver(splash) }
        }
        pending = copyOf(intent)
    }

    /**
     * Tells Dart, before its first frame, that Android owns the splash.
     *
     * It is the one thing the first frame cannot wait to be told: on Android
     * 12 and later the splash may have no mark at all, so the first frame is
     * drawn bare until the splash has said what it showed.
     */
    override fun getDartEntrypointArgs(): List<String>? {
        val given = super.getDartEntrypointArgs() ?: emptyList()
        return if (splashUp) given + HANDS_OVER else given
    }

    /**
     * Android 12's splash without an icon, and a relaunch with no splash at
     * all, never reach the exit listener. Whatever is up is bare ground then,
     * so once the first frame has been up long enough for the listener to
     * have come, Dart is told so and lifts off quietly.
     */
    override fun onFlutterUiDisplayed() {
        super.onFlutterUiDisplayed()
        if (!splashUp || handing) return
        window.decorView.postDelayed({
            if (splashUp && !handing) {
                splashUp = false
                arrival?.invokeMethod(
                    PLACE,
                    mapOf("showedMark" to false, "showedName" to false),
                )
                arrival?.invokeMethod(GONE, null)
            }
        }, BARE_AFTER_MS)
    }

    override fun onPostResume() {
        super.onPostResume()
        // The engine puts its own system ui flags back on every resume, and
        // below Android 11 those flags are what lets the app under the
        // navigation bar. The first time, Dart has not yet asked for edge to
        // edge, so the first frame would be laid out short of the splash it
        // replaces. Below Android 10 the engine never honours edge to edge,
        // so every later resume would bring the app back short as well.
        if (!resumedOnce || Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            resumedOnce = true
            reachTheEdges()
        }
    }

    /**
     * Lays the app out under both system bars, as the splash is.
     *
     * The splash covers the whole screen and centres the mark on it. An app
     * that stopped above the navigation bar would centre its first frame a
     * few points higher, and the mark would jump as one gave way to the other.
     */
    @Suppress("DEPRECATION")
    private fun reachTheEdges() {
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isStatusBarContrastEnforced = false
            window.isNavigationBarContrastEnforced = false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
        } else {
            // Added to the engine's flags rather than put in their place, so
            // a presentation's hidden bars stay hidden.
            window.decorView.systemUiVisibility =
                window.decorView.systemUiVisibility or
                    View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                    View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
        }
    }

    /**
     * Hands Android 12's splash over to the first frame.
     *
     * The system has kept its splash up until the first frame was drawn, and
     * gives it to the app to take away. Before it goes, Dart is sent the
     * splash's mark and name exactly as they are on the screen: their pixels,
     * where they sit, and where the mark's ink is. The system draws its icon
     * from a small bitmap scaled up, so it is a shade softer than a vector
     * would be, and a first frame that drew the vector would sharpen in front
     * of the reader. Only once Dart says a frame of those same pixels is up
     * does the splash go, from over an identical picture.
     */
    @TargetApi(Build.VERSION_CODES.S)
    private fun handOver(splash: SplashScreenView) {
        if (!splashUp) {
            // The listener came after Dart was told there was no splash to
            // wait for, and the app under it has moved on. It goes softly
            // rather than being cut away.
            splash.animate()
                .alpha(0f)
                .setDuration(LATE_FADE_MS)
                .withEndAction { splash.remove() }
                .start()
            return
        }
        handing = true
        val channel = arrival
        val flutter = findViewById<View>(FLUTTER_VIEW_ID)
        var finished = false
        val finish = Runnable {
            if (!finished) {
                finished = true
                splash.remove()
                splashUp = false
                channel?.invokeMethod(GONE, null)
            }
        }
        if (channel == null || flutter == null) {
            finish.run()
            return
        }
        val origin = IntArray(2).also { flutter.getLocationInWindow(it) }
        val density = resources.displayMetrics.density
        fun inFlutter(rect: RectF) = listOf(
            (rect.left - origin[0]) / density,
            (rect.top - origin[1]) / density,
            (rect.right - origin[0]) / density,
            (rect.bottom - origin[1]) / density,
        )
        val report = HashMap<String, Any>()
        val icon = splash.iconView
        report["showedMark"] = icon != null
        if (icon != null) {
            snapshotOf(icon)?.let { shot ->
                val at = windowRectOf(icon)
                inkIn(shot)?.let { ink ->
                    ink.offset(at.left, at.top)
                    report["mark"] = inFlutter(ink)
                }
                report["markPixels"] = pixelsOf(shot)
                report["markPixelsSize"] = listOf(shot.width, shot.height)
                report["markPixelsRect"] = inFlutter(at)
                shot.recycle()
            }
        }
        val name = brandingOf(splash, icon)
        report["showedName"] = name != null
        if (name != null) {
            val at = windowRectOf(name)
            report["name"] = inFlutter(at)
            snapshotOf(name)?.let { shot ->
                report["namePixels"] = pixelsOf(shot)
                report["namePixelsSize"] = listOf(shot.width, shot.height)
                shot.recycle()
            }
        }
        channel.invokeMethod(PLACE, report, object : MethodChannel.Result {
            override fun success(result: Any?) = finish.run()
            override fun error(code: String, message: String?, details: Any?) =
                finish.run()
            override fun notImplemented() = finish.run()
        })
        // A Dart side that never answers must not leave the splash up.
        splash.postDelayed(finish, HANDOVER_LIMIT_MS)
    }

    /** [view] drawn as it is on the screen, or null if it has no size. */
    private fun snapshotOf(view: View): Bitmap? {
        if (view.width <= 0 || view.height <= 0) return null
        val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
        view.draw(Canvas(bitmap))
        return bitmap
    }

    /** Where [view] is in the window, in pixels. */
    private fun windowRectOf(view: View): RectF {
        val at = IntArray(2).also { view.getLocationInWindow(it) }
        return RectF(
            at[0].toFloat(),
            at[1].toFloat(),
            (at[0] + view.width).toFloat(),
            (at[1] + view.height).toFloat(),
        )
    }

    /**
     * The rect of [shot] that its drawing covers at least half of a pixel of.
     * This is the mark as it is actually on the screen, whatever size the
     * system gave its view and however it scaled the drawable in it.
     */
    private fun inkIn(shot: Bitmap): RectF? {
        val width = shot.width
        val height = shot.height
        val pixels = IntArray(width * height)
        shot.getPixels(pixels, 0, width, 0, 0, width, height)
        var left = width
        var top = height
        var right = -1
        var bottom = -1
        for (y in 0 until height) {
            for (x in 0 until width) {
                if (pixels[y * width + x] ushr 24 >= 128) {
                    if (x < left) left = x
                    if (x > right) right = x
                    if (y < top) top = y
                    if (y > bottom) bottom = y
                }
            }
        }
        if (right < 0) return null
        return RectF(Rect(left, top, right + 1, bottom + 1))
    }

    /** [shot]'s pixels as premultiplied RGBA, which is how Dart takes them. */
    private fun pixelsOf(shot: Bitmap): ByteArray {
        val buffer = ByteBuffer.allocate(shot.byteCount)
        shot.copyPixelsToBuffer(buffer)
        return buffer.array()
    }

    /** The branding view, if the splash showed one. */
    private fun brandingOf(splash: SplashScreenView, icon: View?): View? {
        for (i in 0 until splash.childCount) {
            val child = splash.getChildAt(i)
            if (child === icon || child.visibility != View.VISIBLE) continue
            if (child.background == null || child.width <= 0) continue
            return child
        }
        return null
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
        const val ARRIVAL = "ng.com.uriri.quire/arrival"
        const val HANDS_OVER = "handsOver"
        const val PLACE = "place"
        const val GONE = "gone"
        const val HANDOVER_LIMIT_MS = 600L
        const val BARE_AFTER_MS = 300L
        const val LATE_FADE_MS = 200L
    }
}
