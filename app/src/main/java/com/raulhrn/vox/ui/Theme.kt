package com.raulhrn.vox.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

@Immutable
data class VoxColors(
    val bg: Color,
    val surface: Color,
    val surface2: Color,
    val line: Color,
    val text: Color,
    val muted: Color,
    val faint: Color,
    /** Sage green: what you sing, highlights, chords, good pitch. */
    val accent: Color,
    val onAccent: Color,
    /** Deep olive: main buttons. */
    val primary: Color,
    val onPrimary: Color,
    /** Sand: the lead melody (regente). */
    val melody: Color,
    /** Mauve: other harmony / backing parts. */
    val rose: Color,
    val warn: Color,
    val bad: Color,
    /** Terracotta of the maple leaves in the illustrations. */
    val leaf: Color,
    val dark: Boolean,
)

// Classical palette: parchment or dark olive ink, sage and deep olive greens, sand, ochre and
// the terracotta red of the maple in the illustrations.
private val Dark = VoxColors(
    bg = Color(0xFF1B1C16),
    surface = Color(0xFF25261E),
    surface2 = Color(0xFF323327),
    line = Color(0xFF414234),
    text = Color(0xFFEFE6D6),
    muted = Color(0xFFAAA28C),
    faint = Color(0xFF6C6857),
    accent = Color(0xFFA9BC85),
    onAccent = Color(0xFF1B2412),
    primary = Color(0xFF5B6D47),
    onPrimary = Color(0xFFF4ECDD),
    melody = Color(0xFFD6C2A0),
    rose = Color(0xFFB392B8),
    warn = Color(0xFFDBA845),
    bad = Color(0xFFD9694A),
    leaf = Color(0xFFC9573B),
    dark = true,
)

private val Light = VoxColors(
    bg = Color(0xFFF2EADC),
    surface = Color(0xFFE8DDCA),
    surface2 = Color(0xFFDCD0BA),
    line = Color(0xFFCDBFA6),
    text = Color(0xFF26271D),
    muted = Color(0xFF6F6853),
    faint = Color(0xFFAA9F87),
    accent = Color(0xFF58713B),
    onAccent = Color(0xFFF4ECDD),
    primary = Color(0xFF34422D),
    onPrimary = Color(0xFFF4ECDD),
    melody = Color(0xFF8F7655),
    rose = Color(0xFF84608A),
    warn = Color(0xFFB0751A),
    bad = Color(0xFFB2452B),
    leaf = Color(0xFFB8452C),
    dark = false,
)

val LocalVox = staticCompositionLocalOf { Dark }

object Vox {
    val colors: VoxColors
        @Composable @ReadOnlyComposable
        get() = LocalVox.current
}

/** Serif type throughout, like engraved sheet music. */
object VoxType {
    private val serif = FontFamily.Serif
    val display = TextStyle(fontFamily = serif, fontSize = 104.sp, fontWeight = FontWeight.Normal, letterSpacing = (-3).sp, lineHeight = 108.sp)
    val title = TextStyle(fontFamily = serif, fontSize = 30.sp, fontWeight = FontWeight.Normal, letterSpacing = (-0.3).sp)
    val heading = TextStyle(fontFamily = serif, fontSize = 19.sp, fontWeight = FontWeight.Medium)
    val body = TextStyle(fontFamily = serif, fontSize = 16.sp, lineHeight = 24.sp)
    val label = TextStyle(fontFamily = serif, fontSize = 15.sp, fontWeight = FontWeight.Medium)
    val small = TextStyle(fontFamily = serif, fontSize = 13.5.sp, lineHeight = 19.sp)
    val caps = TextStyle(fontFamily = serif, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 1.4.sp)
}

@Composable
fun VoxTheme(content: @Composable () -> Unit) {
    val c = if (isSystemInDarkTheme()) Dark else Light
    val scheme = if (c.dark) {
        darkColorScheme(
            primary = c.primary, onPrimary = c.onPrimary, background = c.bg, onBackground = c.text,
            surface = c.surface, onSurface = c.text, surfaceVariant = c.surface2, onSurfaceVariant = c.muted,
            outline = c.line, secondary = c.melody,
        )
    } else {
        lightColorScheme(
            primary = c.primary, onPrimary = c.onPrimary, background = c.bg, onBackground = c.text,
            surface = c.surface, onSurface = c.text, surfaceVariant = c.surface2, onSurfaceVariant = c.muted,
            outline = c.line, secondary = c.melody,
        )
    }
    CompositionLocalProvider(LocalVox provides c) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}
