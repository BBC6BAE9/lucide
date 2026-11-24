package dev.lucide

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import kotlin.math.ceil
import kotlin.math.min

/** Resolution-independent geometry in SVG viewBox coordinates. */
class LucideGlyph internal constructor(
    private val bounds: RectF,
    val strokeWidth: Float,
    val lineCap: Paint.Cap,
    val lineJoin: Paint.Join,
    private val fill: Path,
    private val stroke: Path,
) {
    enum class Part { fill, stroke }

    val viewBox: RectF get() = RectF(bounds)

    fun scale(rect: RectF): Float =
        min(rect.width() / bounds.width(), rect.height() / bounds.height())

    fun lineWidth(strokeWidth: Float? = null, absolute: Boolean = false, rect: RectF): Float {
        val width = strokeWidth ?: this.strokeWidth
        return if (absolute) width else width * scale(rect)
    }

    fun path(part: Part, rect: RectF): Path {
        val source = when (part) {
            Part.fill -> fill
            Part.stroke -> stroke
        }
        val transform = Matrix().apply {
            setRectToRect(bounds, rect, Matrix.ScaleToFit.CENTER)
        }
        return Path().also { source.transform(transform, it) }
    }

    /** Rasterizes the glyph in black on a transparent bitmap suitable for tinting. */
    fun image(
        pointSize: Float = 24f,
        strokeWidth: Float? = null,
        absoluteStrokeWidth: Boolean = false,
        scale: Float = 3f,
    ): Bitmap? {
        val pixels = ceil(pointSize * scale)
        if (!pixels.isFinite() || pixels < 1 || scale <= 0f) return null

        val bitmap = Bitmap.createBitmap(pixels.toInt(), pixels.toInt(), Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.scale(scale, scale)
        draw(canvas, RectF(0f, 0f, pointSize, pointSize), Color.BLACK, strokeWidth, absoluteStrokeWidth)
        return bitmap
    }

    internal fun draw(canvas: Canvas, rect: RectF, color: Int, strokeWidth: Float?, absolute: Boolean) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
        if (!fill.isEmpty) canvas.drawPath(path(Part.fill, rect), paint)
        val width = lineWidth(strokeWidth, absolute, rect)
        if (!stroke.isEmpty && width.isFinite() && width > 0f) {
            paint.style = Paint.Style.STROKE
            paint.strokeCap = lineCap
            paint.strokeJoin = lineJoin
            paint.strokeWidth = width
            canvas.drawPath(path(Part.stroke, rect), paint)
        }
    }
}
