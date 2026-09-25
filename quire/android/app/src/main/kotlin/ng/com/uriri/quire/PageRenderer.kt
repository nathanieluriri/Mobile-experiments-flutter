package ng.com.uriri.quire

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.Executors

/**
 * Draws PDF pages with the renderer Android ships, so a page is shown in its
 * own fonts rather than set again in the app's.
 *
 * PdfRenderer allows one page open at a time and is not safe across threads,
 * so every call runs on one worker thread, in order, and answers on the main
 * thread. A document handed over as bytes is written to the cache directory,
 * because PdfRenderer reads only from a seekable file, and that copy is
 * deleted when the document is closed.
 */
class PageRenderer(context: Context, messenger: BinaryMessenger) {
    private val cache = File(context.cacheDir, "pages")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val open = HashMap<Int, Held>()
    private var next = 1

    private class Held(
        val renderer: PdfRenderer,
        val descriptor: ParcelFileDescriptor,
        val copy: File?,
    )

    init {
        cache.deleteRecursively()
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            worker.execute { answer(call, result) }
        }
    }

    private fun answer(call: MethodCall, result: MethodChannel.Result) {
        try {
            val reply: Any? = when (call.method) {
                "open" -> open(call)
                "render" -> render(call)
                "close" -> close(call.argument<Int>("id"))
                else -> {
                    main.post { result.notImplemented() }
                    return
                }
            }
            main.post { result.success(reply) }
        } catch (error: Throwable) {
            // A file PdfRenderer cannot read, or one under a password, is
            // drawn by the app instead, so every failure is only a refusal.
            main.post { result.error("unreadable", error.message, null) }
        }
    }

    private fun open(call: MethodCall): Map<String, Any> {
        val path = call.argument<String>("path")
        var copy: File? = null
        val file = if (path != null) {
            File(path)
        } else {
            val bytes = call.argument<ByteArray>("bytes")
                ?: throw IllegalArgumentException("nothing to open")
            cache.mkdirs()
            copy = File(cache, "${System.nanoTime()}.pdf").apply { writeBytes(bytes) }
            copy
        }
        val descriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
        val renderer = try {
            PdfRenderer(descriptor)
        } catch (error: Throwable) {
            descriptor.close()
            copy?.delete()
            throw error
        }
        val id = next++
        open[id] = Held(renderer, descriptor, copy)
        return mapOf("id" to id, "pages" to renderer.pageCount)
    }

    private fun render(call: MethodCall): Map<String, Any> {
        val held = open[call.argument<Int>("id")]
            ?: throw IllegalStateException("not open")
        val index = call.argument<Int>("page") ?: 0
        val width = call.argument<Int>("width") ?: 0
        val height = call.argument<Int>("height") ?: 0
        require(width > 0 && height > 0 && width.toLong() * height <= MAX_PIXELS)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        try {
            // PdfRenderer leaves what a page does not paint transparent, and
            // paper is white.
            bitmap.eraseColor(Color.WHITE)
            held.renderer.openPage(index).use { page ->
                // With no transform the page is fitted to the bitmap, crop box,
                // rotation and all, and the bitmap already has its shape.
                page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            }
            val pixels = ByteBuffer.allocate(bitmap.byteCount)
            bitmap.copyPixelsToBuffer(pixels)
            return mapOf("width" to width, "height" to height, "pixels" to pixels.array())
        } finally {
            bitmap.recycle()
        }
    }

    private fun close(id: Int?): Any? {
        val held = open.remove(id) ?: return null
        held.renderer.close()
        held.descriptor.close()
        held.copy?.delete()
        return null
    }

    private companion object {
        const val CHANNEL = "ng.com.uriri.quire/pages"
        const val MAX_PIXELS = 4096L * 4096L
    }
}
