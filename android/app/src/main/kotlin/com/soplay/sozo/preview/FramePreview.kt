package com.soplay.sozo.preview

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.util.Log
import java.io.ByteArrayOutputStream

/**
 * On-device seek-preview frame generator (like CloudStream's PreviewGenerator).
 *
 * Many providers (all CloudStream ones) don't ship VTT/storyboard thumbnails, so
 * we sample frames straight from the video with MediaMetadataRetriever and hand
 * single JPEG frames to the Flutter player to show while scrubbing. Works well
 * for progressive MP4 (most HubCloud/DriveSeed links); HLS frame extraction is
 * best-effort and may return null (the player then shows no preview — graceful).
 *
 * One retriever is kept open per playing URL; `frame()` is cheap-ish and called
 * with bucketed positions + cached on the Flutter side.
 */
object FramePreview {
    private const val TAG = "FramePreview"
    private var retriever: MediaMetadataRetriever? = null
    private var openUrl: String? = null

    @Synchronized
    fun open(url: String, headers: Map<String, String>) {
        if (openUrl == url && retriever != null) return
        close()
        try {
            val r = MediaMetadataRetriever()
            if (headers.isEmpty()) r.setDataSource(url) else r.setDataSource(url, headers)
            retriever = r
            openUrl = url
        } catch (t: Throwable) {
            Log.e(TAG, "open failed: ${t.message}")
            retriever = null; openUrl = null
        }
    }

    /** JPEG bytes of the frame nearest [positionMs], scaled to ~ [maxW]px wide. */
    @Synchronized
    fun frame(positionMs: Long, maxW: Int = 240): ByteArray? {
        val r = retriever ?: return null
        return try {
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
        }
    }

    private fun scaleTo(bmp: Bitmap, maxW: Int): Bitmap {
        if (bmp.width <= maxW || bmp.width == 0) return bmp
        val h = (bmp.height.toLong() * maxW / bmp.width).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(bmp, maxW, h, true)
    }

    @Synchronized
    fun close() {
        try { retriever?.release() } catch (_: Throwable) {}
        retriever = null; openUrl = null
    }
}
