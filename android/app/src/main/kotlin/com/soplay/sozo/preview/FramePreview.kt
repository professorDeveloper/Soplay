package com.soplay.sozo.preview

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import android.util.Log
import java.io.ByteArrayOutputStream
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

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
 * Concurrency: `setDataSource` is a network fetch with NO timeout, so `open()`
 * runs it OUTSIDE [lock] and only swaps the finished retriever in under the lock.
 * That way `close()` — which the player calls from dispose() when the user hits
 * back — never waits on a still-opening source. [generation] invalidates a slow
 * open() that finished after a close()/newer open(), so it releases its retriever
 * instead of installing a stale one. `frame()` uses tryLock and bails out (null)
 * rather than blocking. The cache has its own monitor.
 */
object FramePreview {
    private const val TAG = "FramePreview"
    private const val MAX_W = 240
    private const val CACHE_CAP = 64

    private val lock = ReentrantLock()

    @Volatile private var retriever: MediaMetadataRetriever? = null
    @Volatile private var openUrl: String? = null

    /** Bumped by every [open] and [close]; a slow open() whose generation is stale
     *  when it finishes throws its retriever away instead of installing it. */
    private val generation = AtomicInteger(0)

    // Bounded LRU of bucketed-position -> JPEG bytes. Guarded by its own monitor
    // (not [lock]) so a scrub can read a cached frame while an open() is running.
    // access-order = true → least-recently-used is evicted first.
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

        val myGen = generation.incrementAndGet()
        // Free whatever was open before (fast — no network under the lock).
        lock.withLock { closeLocked() }

        // The slow part runs OUTSIDE [lock] so close() can never wait on it.
        val r = MediaMetadataRetriever()
        try {
            if (headers.isEmpty()) r.setDataSource(url) else r.setDataSource(url, headers)
        } catch (t: Throwable) {
            Log.e(TAG, "open failed: ${t.message}")
            releaseQuietly(r)
            return
        }

        // Superseded while we were opening (player closed, or a newer source)?
        if (generation.get() != myGen) {
            releaseQuietly(r)
            return
        }

        // [r] is still private to us here, so warming needs no lock either.
        val warm = if (warmMs >= 0) {
            try { extract(r, warmMs) } catch (t: Throwable) {
                Log.e(TAG, "warm failed: ${t.message}"); null
            }
        } else {
            null
        }

        val installed = lock.withLock {
            if (generation.get() != myGen) {
                false
            } else {
                retriever = r
                openUrl = url
                true
            }
        }
        if (!installed) {
            releaseQuietly(r)
            return
        }
        if (warm != null) cachePut(warmMs, warm)
    }

    /** JPEG bytes of the frame nearest [positionMs], scaled to ~ [maxW]px wide. */
    fun frame(positionMs: Long, maxW: Int = MAX_W): ByteArray? {
        cacheGet(positionMs)?.let { return it }
        // Don't block while another op holds the lock — return null so the channel
        // call returns immediately and the UI shows its fallback.
        if (!lock.tryLock()) return null
        return try {
            val r = retriever ?: return null
            val bytes = extract(r, positionMs, maxW)
            if (bytes != null) cachePut(positionMs, bytes)
            bytes
        } catch (t: Throwable) {
            Log.e(TAG, "frame failed: ${t.message}"); null
        } finally {
            lock.unlock()
        }
    }

    /**
     * Release the source. Invalidates any in-flight [open] (it will drop its own
     * retriever when it finishes) so this never has to wait on a network fetch.
     */
    fun close() {
        generation.incrementAndGet()
        synchronized(cache) { cache.clear() }
        lock.withLock { closeLocked() }
    }

    private fun closeLocked() {
        releaseQuietly(retriever)
        retriever = null
        openUrl = null
        synchronized(cache) { cache.clear() }
    }

    private fun releaseQuietly(r: MediaMetadataRetriever?) {
        try { r?.release() } catch (_: Throwable) {}
    }

    /** Extract + JPEG-encode one frame from [r]. */
    private fun extract(
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
}
