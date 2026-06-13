package com.soplay.sozo.preview

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
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
 * Speed: `open()` warms the decoder up front (extracts one frame so codec-init is
 * paid off the user's scrub path), `getScaledFrameAtTime` decodes straight to the
 * preview size instead of decoding full-res then downscaling, and a small cache
 * holds the warm frame plus any frames the Dart side prefetches around the scrub
 * head — so repeated/neighbouring scrubs return instantly.
 *
 * Concurrency: `open()` does the slow network `setDataSource`, so it holds the
 * lock; `frame()` uses `tryLock` and bails out (null) instead of blocking — that
 * way the MethodChannel call never hangs while a source is still opening. The
 * cache has its own monitor so the fast-path read never waits on a slow open.
 */
object FramePreview {
    private const val TAG = "FramePreview"
    private const val MAX_W = 240
    private const val CACHE_CAP = 64

    private val lock = ReentrantLock()
    private var retriever: MediaMetadataRetriever? = null
    private var openUrl: String? = null

    // Bounded LRU of bucketed-position -> JPEG bytes. Guarded by its own monitor
    // (not [lock]) so a scrub can read a cached frame while a slow open() is still
    // holding [lock]. access-order = true → least-recently-used is evicted first.
    private val cache = object : LinkedHashMap<Long, ByteArray>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: Map.Entry<Long, ByteArray>): Boolean =
            size > CACHE_CAP
    }

    private fun cacheGet(key: Long): ByteArray? = synchronized(cache) { cache[key] }
    private fun cachePut(key: Long, value: ByteArray) = synchronized(cache) { cache[key] = value }

    /**
     * Open [url] for frame extraction. When [warmMs] >= 0, immediately extract the
     * frame at that position: this pays the one-time decoder/codec init cost here
     * (during the backgrounded open, not on the user's first scrub) and caches the
     * result so the first scrub at the start position is instant.
     */
    fun open(url: String, headers: Map<String, String>, warmMs: Long = -1L) {
        if (openUrl == url && retriever != null) return
        lock.lock()
        try {
            closeLocked()
            val r = MediaMetadataRetriever()
            if (headers.isEmpty()) r.setDataSource(url) else r.setDataSource(url, headers)
            retriever = r
            openUrl = url
            if (warmMs >= 0) extractLocked(r, warmMs)?.let { cachePut(warmMs, it) }
        } catch (t: Throwable) {
            Log.e(TAG, "open failed: ${t.message}")
            retriever = null; openUrl = null
        } finally {
            lock.unlock()
        }
    }

    /** JPEG bytes of the frame nearest [positionMs], scaled to ~ [maxW]px wide. */
    fun frame(positionMs: Long, maxW: Int = MAX_W): ByteArray? {
        cacheGet(positionMs)?.let { return it }
        // Don't block while a (slow) open() is in progress — return null so the
        // channel call returns immediately and the UI shows its fallback.
        if (!lock.tryLock()) return null
        return try {
            val r = retriever ?: return null
            val bytes = extractLocked(r, positionMs, maxW)
            if (bytes != null) cachePut(positionMs, bytes)
            bytes
        } catch (t: Throwable) {
            Log.e(TAG, "frame failed: ${t.message}"); null
        } finally {
            lock.unlock()
        }
    }

    /** Extract + JPEG-encode one frame. Caller must hold [lock]. */
    private fun extractLocked(
        r: MediaMetadataRetriever,
        positionMs: Long,
        maxW: Int = MAX_W,
    ): ByteArray? {
        val timeUs = positionMs * 1000L
        // getScaledFrameAtTime (API 27+) decodes directly at the target size — far
        // cheaper than decoding a full 1080p frame then downscaling it ourselves.
        val bmp = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            r.getScaledFrameAtTime(
                timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, maxW, maxW,
            )
        } else {
            r.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
        } ?: return null
        val scaled = scaleTo(bmp, maxW)
        val out = ByteArrayOutputStream()
        scaled.compress(Bitmap.CompressFormat.JPEG, 70, out)
        if (scaled !== bmp) scaled.recycle()
        bmp.recycle()
        return out.toByteArray()
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
        synchronized(cache) { cache.clear() }
    }
}
