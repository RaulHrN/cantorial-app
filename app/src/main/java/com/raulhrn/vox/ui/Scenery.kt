package com.raulhrn.vox.ui

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke

/**
 * The illustration behind the main screens: a pale sun over misty mountains, the ruin of a
 * classical colonnade on the left and a red maple growing from a rock on the right. Drawn with
 * a few paths in the theme colours, so it costs no image memory and follows light and dark.
 */
@Composable
fun Scenery(modifier: Modifier = Modifier) {
    val c = Vox.colors
    Canvas(modifier.clipToBounds()) {
        val w = size.width
        val h = size.height
        val ink = c.text

        // Sun.
        drawCircle(
            Color(0xFFD9916B).copy(alpha = if (c.dark) 0.20f else 0.34f),
            radius = h * 0.25f,
            center = Offset(w * 0.40f, h * 0.36f),
        )

        // Mountains, far to near.
        ridge(ink.copy(alpha = if (c.dark) 0.05f else 0.07f), 0f, 0.58f, 0.14f, 0.44f, 0.28f, 0.56f, 0.44f, 0.26f, 0.58f, 0.50f, 0.72f, 0.36f, 0.88f, 0.54f, 1f, 0.42f)
        ridge(ink.copy(alpha = if (c.dark) 0.06f else 0.09f), 0f, 0.74f, 0.16f, 0.60f, 0.30f, 0.70f, 0.46f, 0.52f, 0.62f, 0.68f, 0.80f, 0.56f, 1f, 0.70f)
        ridge(ink.copy(alpha = if (c.dark) 0.07f else 0.10f), 0f, 0.86f, 0.22f, 0.76f, 0.44f, 0.84f, 0.66f, 0.74f, 0.84f, 0.84f, 1f, 0.80f)

        colonnade(ink.copy(alpha = if (c.dark) 0.10f else 0.13f), c.bg.copy(alpha = 0.55f))
        maple(
            rock = if (c.dark) Color(0xFF2F3026) else Color(0xFFCDBFA6),
            trunk = if (c.dark) Color(0xFF55463A) else Color(0xFF4A372B),
            leaf = c.leaf,
            leafLight = if (c.dark) Color(0xFFDD7450) else Color(0xFFCB5B3C),
        )

        // Fade into the page.
        drawRect(
            Brush.verticalGradient(0.50f to Color.Transparent, 1f to c.bg),
            size = Size(w, h),
        )
    }
}

/** A soft mountain silhouette through points given as x, y fractions of the canvas. */
private fun DrawScope.ridge(color: Color, vararg p: Float) {
    val w = size.width
    val h = size.height
    val path = Path()
    path.moveTo(0f, h)
    path.lineTo(p[0] * w, p[1] * h)
    var i = 2
    while (i < p.size - 2) {
        val x = p[i] * w
        val y = p[i + 1] * h
        val nx = p[i + 2] * w
        val ny = p[i + 3] * h
        path.quadraticBezierTo(x, y, (x + nx) / 2f, (y + ny) / 2f)
        i += 2
    }
    path.lineTo(p[p.size - 2] * w, p[p.size - 1] * h)
    path.lineTo(w, h)
    path.close()
    drawPath(path, color)
}

/** Two fluted columns carrying a broken entablature. */
private fun DrawScope.colonnade(color: Color, flute: Color) {
    val h = size.height
    val cw = h * 0.105f
    val top = h * 0.20f
    val x0 = h * 0.10f
    val gap = cw * 2.05f
    for (k in 0..1) {
        val x = x0 + k * gap
        // Abacus and capital.
        drawRect(color, Offset(x - cw * 0.22f, top), Size(cw * 1.44f, h * 0.022f))
        drawRect(color, Offset(x - cw * 0.10f, top + h * 0.022f), Size(cw * 1.20f, h * 0.024f))
        // Shaft and flutes.
        drawRect(color, Offset(x, top + h * 0.046f), Size(cw, h - top - h * 0.046f))
        for (f in 1..3) {
            val fx = x + cw * f / 4f
            drawLine(flute, Offset(fx, top + h * 0.06f), Offset(fx, h), strokeWidth = cw * 0.05f)
        }
    }
    // Entablature: an architrave and a cornice that breaks off past the second column.
    val beam = Path()
    val left = x0 - cw * 0.34f
    val right = x0 + gap + cw * 1.50f
    beam.moveTo(left, top)
    beam.lineTo(left, top - h * 0.085f)
    beam.lineTo(right - cw * 0.50f, top - h * 0.085f)
    beam.lineTo(right - cw * 0.34f, top - h * 0.052f)
    beam.lineTo(right - cw * 0.10f, top - h * 0.040f)
    beam.lineTo(right, top)
    beam.close()
    drawPath(beam, color)
    drawRect(color, Offset(left - cw * 0.16f, top - h * 0.110f), Size(gap + cw * 0.9f, h * 0.025f))
}

/** A windswept maple on a rock: dark trunk, layered pads of red leaves. */
private fun DrawScope.maple(rock: Color, trunk: Color, leaf: Color, leafLight: Color) {
    val w = size.width
    val h = size.height
    fun x(f: Float) = w - (1f - f) * h * 1.9f // anchored to the right edge, scaled by the height
    fun y(f: Float) = (f + 0.10f) * h // a little lower, clear of the buttons in the header

    val cliff = Path()
    cliff.moveTo(x(0.52f), y(1f))
    cliff.quadraticBezierTo(x(0.60f), y(0.86f), x(0.70f), y(0.84f))
    cliff.quadraticBezierTo(x(0.80f), y(0.76f), x(0.88f), y(0.80f))
    cliff.quadraticBezierTo(x(0.95f), y(0.72f), x(1.02f), y(0.74f))
    cliff.lineTo(x(1.02f), y(1f))
    cliff.close()
    drawPath(cliff, rock)

    fun limb(width: Float, vararg p: Float) {
        val path = Path()
        path.moveTo(x(p[0]), y(p[1]))
        path.cubicTo(x(p[2]), y(p[3]), x(p[4]), y(p[5]), x(p[6]), y(p[7]))
        drawPath(path, trunk, style = Stroke(width = h * width, cap = StrokeCap.Round))
    }
    limb(0.034f, 0.84f, 0.80f, 0.80f, 0.66f, 0.90f, 0.58f, 0.82f, 0.46f)
    limb(0.022f, 0.82f, 0.46f, 0.78f, 0.38f, 0.72f, 0.38f, 0.66f, 0.33f)
    limb(0.018f, 0.84f, 0.56f, 0.92f, 0.50f, 0.94f, 0.44f, 0.97f, 0.38f)
    limb(0.014f, 0.80f, 0.42f, 0.84f, 0.34f, 0.86f, 0.30f, 0.84f, 0.22f)
    limb(0.012f, 0.83f, 0.62f, 0.76f, 0.58f, 0.72f, 0.60f, 0.68f, 0.56f)

    fun pad(cx: Float, cy: Float, r: Float, light: Boolean) {
        for (k in -2..2) {
            val lift = (2 - kotlin.math.abs(k)) * r * 0.16f
            drawCircle(
                (if ((k + 2) % 2 == 0 == light) leafLight else leaf).copy(alpha = 0.92f),
                radius = h * r * (0.42f - kotlin.math.abs(k) * 0.05f),
                center = Offset(x(cx) + k * h * r * 0.42f, y(cy) - h * lift),
            )
        }
    }
    pad(0.66f, 0.31f, 0.17f, false)
    pad(0.84f, 0.20f, 0.19f, true)
    pad(0.97f, 0.35f, 0.16f, false)
    pad(0.78f, 0.38f, 0.14f, true)
    pad(0.68f, 0.54f, 0.11f, false)
    pad(0.90f, 0.47f, 0.10f, true)
}
