package dev.lucideremote

import android.graphics.RectF
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.material3.LocalContentColor
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import java.io.IOException

val LocalLucidePipeline = compositionLocalOf<LucidePipeline?> { null }

/** Draws a vector icon and reserves the same layout space while it loads. */
@Composable
fun LucideIcon(
    name: LucideName,
    size: Dp = 24.dp,
    strokeWidth: Float? = null,
    absoluteStrokeWidth: Boolean = false,
    modifier: Modifier = Modifier,
    tint: Color = LocalContentColor.current,
    pipeline: LucidePipeline = LocalLucidePipeline.current ?: LucidePipeline.shared(LocalContext.current),
) {
    var glyph by remember(name, pipeline) { mutableStateOf(pipeline.localGlyph(name)) }
    LaunchedEffect(name, pipeline) {
        if (glyph == null) {
            glyph = try {
                pipeline.glyph(name)
            } catch (_: IOException) {
                null
            }
        }
    }

    Canvas(modifier.size(size)) {
        val current = glyph ?: return@Canvas
        val width = if (absoluteStrokeWidth) {
            (strokeWidth ?: current.strokeWidth).dp.toPx()
        } else {
            strokeWidth
        }
        drawIntoCanvas { canvas ->
            current.draw(
                canvas.nativeCanvas,
                RectF(0f, 0f, this.size.width, this.size.height),
                tint.toArgb(),
                width,
                absoluteStrokeWidth,
            )
        }
    }
}
