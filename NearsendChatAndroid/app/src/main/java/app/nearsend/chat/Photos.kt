package app.nearsend.chat

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.net.Uri
import android.os.Build
import androidx.exifinterface.media.ExifInterface
import java.io.ByteArrayOutputStream

/** Makes a picture small enough for Bluetooth: resized, re-encoded as WebP (which also drops the camera metadata, GPS included). */
object Photos {
    private const val MAX_BYTES = 40_000
    private val SIZES = listOf(800, 640, 512, 400, 320)
    private val QUALITIES = listOf(60, 45, 30)

    /** WebP bytes of at most about 40 KB, or null if the picture cannot be read. Slow: call it off the main thread. */
    fun compress(ctx: Context, uri: Uri): ByteArray? = runCatching {
        val cr = ctx.contentResolver
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        cr.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= 1600) sample *= 2
        var bmp = cr.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample }) } ?: return null
        val rotation = cr.openInputStream(uri)?.use { s ->
            when (ExifInterface(s).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90f; ExifInterface.ORIENTATION_ROTATE_180 -> 180f; ExifInterface.ORIENTATION_ROTATE_270 -> 270f; else -> 0f
            }
        } ?: 0f
        if (rotation != 0f) bmp = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, Matrix().apply { postRotate(rotation) }, true)
        var best: ByteArray? = null
        for (size in SIZES) {
            val scale = minOf(1f, size.toFloat() / maxOf(bmp.width, bmp.height))
            val scaled = if (scale < 1f) Bitmap.createScaledBitmap(bmp, (bmp.width * scale).toInt().coerceAtLeast(1), (bmp.height * scale).toInt().coerceAtLeast(1), true) else bmp
            for (q in QUALITIES) {
                val out = ByteArrayOutputStream()
                @Suppress("DEPRECATION")
                scaled.compress(if (Build.VERSION.SDK_INT >= 30) Bitmap.CompressFormat.WEBP_LOSSY else Bitmap.CompressFormat.WEBP, q, out)
                best = out.toByteArray()
                if (best.size <= MAX_BYTES) return best
            }
        }
        best?.takeIf { it.size <= 48_000 }
    }.getOrNull()
}
