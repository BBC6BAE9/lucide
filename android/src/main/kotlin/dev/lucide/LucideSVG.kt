package dev.lucide

import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.util.Xml
import androidx.compose.ui.graphics.asAndroidPath
import androidx.compose.ui.graphics.vector.PathParser
import java.io.IOException
import org.xmlpull.v1.XmlPullParser
import org.xmlpull.v1.XmlPullParserException

enum class LucideSVGError {
    malformedDocument, notSVG, invalidViewBox, invalidPathData, tooManyElements,
}

class LucideSVGException internal constructor(
    val error: LucideSVGError,
    val element: Int? = null,
    cause: Throwable? = null,
) : IOException(error.name, cause)

/** Parses the same SVG subset as the Swift package. */
object LucideSVG {
    const val maximumElementCount = 512
    private val separators = Regex("[,\\s]+")

    fun parse(data: ByteArray): LucideGlyph {
        try {
            val parser = Xml.newPullParser().apply {
                setFeature(XmlPullParser.FEATURE_PROCESS_DOCDECL, false)
                setInput(data.inputStream(), null)
            }
            return parseDocument(parser)
        } catch (error: XmlPullParserException) {
            throw LucideSVGException(LucideSVGError.malformedDocument, cause = error)
        }
    }

    private fun parseDocument(parser: XmlPullParser): LucideGlyph {
        var root: Root? = null
        val paints = mutableListOf<SvgPaint>()
        val fill = Path()
        val stroke = Path()
        var skippedDepth = 0
        var elements = 0

        while (true) {
            when (parser.nextToken()) {
                XmlPullParser.END_DOCUMENT -> break
                XmlPullParser.DOCDECL -> throw LucideSVGException(LucideSVGError.malformedDocument)
                XmlPullParser.END_TAG -> {
                    if (skippedDepth > 0) skippedDepth-- else paints.removeAt(paints.lastIndex)
                }
                XmlPullParser.START_TAG -> {
                    if (skippedDepth > 0 || (root == null && parser.name != "svg")) {
                        skippedDepth++
                        continue
                    }
                    val paint = (paints.lastOrNull() ?: SvgPaint()).inheriting(parser)
                    when (parser.name) {
                        "svg" -> {
                            if (root != null) {
                                skippedDepth = 1
                                continue
                            }
                            root = Root(parser)
                        }
                        "g" -> Unit
                        "path", "circle", "ellipse", "rect", "line", "polyline", "polygon" -> {
                            if (elements >= maximumElementCount) {
                                throw LucideSVGException(LucideSVGError.tooManyElements)
                            }
                            val path = try {
                                shape(parser)
                            } catch (error: IllegalArgumentException) {
                                throw LucideSVGException(LucideSVGError.invalidPathData, elements, error)
                            } catch (error: IndexOutOfBoundsException) {
                                throw LucideSVGException(LucideSVGError.invalidPathData, elements, error)
                            }
                            if (!path.isEmpty) {
                                if (paint.fill != "none") fill.addPath(path)
                                if (paint.stroke != "none") stroke.addPath(path)
                                elements++
                            }
                        }
                        else -> {
                            skippedDepth = 1
                            continue
                        }
                    }
                    paints.add(paint)
                }
            }
        }

        val style = root ?: throw LucideSVGException(LucideSVGError.notSVG)
        return LucideGlyph(style.viewBox, style.strokeWidth, style.cap, style.join, fill, stroke)
    }

    private class Root(parser: XmlPullParser) {
        val viewBox = viewBox(parser)
        val strokeWidth = parser.number("stroke-width") ?: 1f
        val cap = when (parser.attr("stroke-linecap")) {
            "round" -> Paint.Cap.ROUND
            "square" -> Paint.Cap.SQUARE
            else -> Paint.Cap.BUTT
        }
        val join = when (parser.attr("stroke-linejoin")) {
            "round" -> Paint.Join.ROUND
            "bevel" -> Paint.Join.BEVEL
            else -> Paint.Join.MITER
        }
    }

    private data class SvgPaint(val fill: String = "black", val stroke: String = "none") {
        fun inheriting(parser: XmlPullParser) = SvgPaint(
            parser.attr("fill")?.trim() ?: fill,
            parser.attr("stroke")?.trim() ?: stroke,
        )
    }

    private fun shape(parser: XmlPullParser): Path {
        fun value(name: String) = parser.number(name) ?: 0f

        if (parser.name == "path") {
            return PathParser().parsePathString(parser.attr("d").orEmpty()).toPath().asAndroidPath()
        }

        return Path().apply {
            when (parser.name) {
                "circle", "ellipse" -> {
                    val radius = parser.number("r") ?: 0f
                    val rx = if (parser.name == "circle") radius else value("rx")
                    val ry = if (parser.name == "circle") radius else value("ry")
                    val x = value("cx")
                    val y = value("cy")
                    if (rx > 0 && ry > 0) addOval(x - rx, y - ry, x + rx, y + ry, Path.Direction.CW)
                }
                "rect" -> {
                    val x = value("x")
                    val y = value("y")
                    val width = value("width")
                    val height = value("height")
                    val rx = parser.number("rx")
                    val ry = parser.number("ry")
                    if (width > 0 && height > 0) {
                        val horizontal = (rx ?: ry ?: 0f).coerceIn(0f, width / 2)
                        val vertical = (ry ?: rx ?: 0f).coerceIn(0f, height / 2)
                        addRoundRect(x, y, x + width, y + height, horizontal, vertical, Path.Direction.CW)
                    }
                }
                "line" -> {
                    moveTo(value("x1"), value("y1"))
                    lineTo(value("x2"), value("y2"))
                }
                "polyline", "polygon" -> {
                    val points = numbers(parser.attr("points").orEmpty())
                    if (points.size >= 4) {
                        moveTo(points[0], points[1])
                        for (index in 2 until points.lastIndex step 2) {
                            lineTo(points[index], points[index + 1])
                        }
                        if (parser.name == "polygon") close()
                    }
                }
            }
        }
    }

    private fun viewBox(parser: XmlPullParser): RectF {
        val box = try {
            parser.attr("viewBox")?.let(::numbers)
                ?: listOf(0f, 0f, parser.number("width") ?: 24f, parser.number("height") ?: 24f)
        } catch (error: IllegalArgumentException) {
            throw LucideSVGException(LucideSVGError.invalidViewBox, cause = error)
        }
        if (box.size != 4 || box[2] <= 0 || box[3] <= 0) {
            throw LucideSVGException(LucideSVGError.invalidViewBox)
        }
        val rect = RectF(box[0], box[1], box[0] + box[2], box[1] + box[3])
        if (!rect.right.isFinite() || !rect.bottom.isFinite() || rect.isEmpty) {
            throw LucideSVGException(LucideSVGError.invalidViewBox)
        }
        return rect
    }

    private fun numbers(text: String): List<Float> =
        text.trim().split(separators).filter(String::isNotEmpty).map {
            requireNotNull(it.toFloatOrNull()?.takeIf(Float::isFinite))
        }

    private fun XmlPullParser.attr(name: String): String? = getAttributeValue(null, name)

    private fun XmlPullParser.number(name: String): Float? =
        attr(name)?.trim()?.removeSuffix("px")?.toFloatOrNull()?.takeIf(Float::isFinite)
}
