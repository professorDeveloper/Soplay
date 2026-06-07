package com.soplay.sozo.preview

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.util.Log
import java.io.ByteArrayOutputStream
import java.util.concurrent.locks.ReentrantLock

/**
 * On-device seek-preview frame generator (like CloudStream's PreviewGenerator).
 *
 * Many providers (all CloudStream ones) don't ship VTT/storyboard thumbnails, so
 * we sample frames straight from the video with MediaMetadataRetriever and hand
 * single JPEG frames to the Flutter player to show while scrubbing. Works well
 * for progressive MP4 (most HubCloud/DriveSeed links); HLS frame extraction is
 * best-effort and may return null (the player then shows no preview — graceful).
 *
 * Concurrency: `open()` does the slow network `setDataSource`, so it holds the
 * lock; `frame()` uses `tryLock` and bails out (null) instead of blocking — that
 * way the MethodChannel call never hangs while a source is still opening (the
 * old `@Synchronized` version froze the preview spinner forever here).
 */
object FramePreview {
    private const val TAG = "FramePreview"
    private val lock = ReentrantLock()
    private var retriever: MediaMetadataRetriever? = null
    private var openUrl: String? = null

    fun open(url: String, headers: Map<String, String>) {
        if (openUrl == url && retriever != null) return
        lock.lock()
        try {
            closeLocked()
            val r = MediaMetadataRetriever()
            if (headers.isEmpty()) r.setDataSource(url) else r.setDataSource(url, headers)
            retriever = r
            openUrl = url
        } catch (t: Throwable) {
            Log.e(TAG, "open failed: ${t.message}")
            retriever = null; openUrl = null
        } finally {
            lock.unlock()
        }
    }

    /** JPEG bytes of the frame nearest [positionMs], scaled to ~ [maxW]px wide. */
    fun frame(positionMs: Long, maxW: Int = 240): ByteArray? {
        // Don't block while a (slow) open() is in progress — return null so the
        // channel call returns immediately and the UI shows its fallback.
        if (!lock.tryLock()) return null
        return try {
            val r = retriever ?: return null
            val bmp = r.getFrameAtTime(positionMs * 1000L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                ?: return null
            val scaled = scaleTo(bmp, maxW)
            val out = ByteArrayOutputStream()
            scaled.compress(Bitmap.CompressFormat.JPEG, 70, out)
            if (scaled !== bmp) scaled.recycle()
            bmp.recycle()
            out.toByteArray()
        } catch (t: Throwable) {
            Log.e(TAG, "frame failed: ${t.message}"); null
        } finally {
            lock.unlock()
        }
    }

    private fun scaleTo(bmp: Bitmap, maxW: Int): Bitmap {
        if (bmp.width <= maxW || bmp.width == 0) return bmp
        val h = (bmp.height.toLong() * maxW / bmp.width).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(bmp, maxW, h, true)
    }

    fun close() {
        lock.lock()
        try { closeLocked() } finally { lock.unlock() }
    }

    private fun closeLocked() {
        try { retriever?.release() } catch (_: Throwable) {}
        retriever = null; openUrl = null
    }
}
