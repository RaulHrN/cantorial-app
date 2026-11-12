package com.raulhrn.vox.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.raulhrn.vox.core.HarmonyMode
import com.raulhrn.vox.core.VoiceType
import com.raulhrn.vox.ui.screens.AddSongScreen
import com.raulhrn.vox.ui.screens.BackingLabScreen
import com.raulhrn.vox.ui.screens.CifraEditScreen
import com.raulhrn.vox.ui.screens.CifraViewScreen
import com.raulhrn.vox.ui.screens.CifrasScreen
import com.raulhrn.vox.ui.screens.SetlistScreen
import com.raulhrn.vox.ui.screens.LessonScreen
import com.raulhrn.vox.ui.screens.LessonsScreen
import com.raulhrn.vox.ui.screens.ArticleScreen
import com.raulhrn.vox.ui.screens.ExerciseScreen
import com.raulhrn.vox.ui.screens.LiveScreen
import com.raulhrn.vox.ui.screens.PracticeScreen
import com.raulhrn.vox.ui.screens.RangeTestScreen
import com.raulhrn.vox.ui.screens.SettingsScreen
import com.raulhrn.vox.ui.screens.SongsScreen
import com.raulhrn.vox.ui.screens.StudyScreen
import com.raulhrn.vox.ui.screens.TrainScreen

enum class Tab(val label: String) {
    LIVE("Ouvir"),
    TRAIN("Treinar"),
    SONGS("Músicas"),
    CIFRAS("Cifras"),
    STUDY("Estudar"),
}

private fun Tab.icon(): ImageVector = when (this) {
    Tab.LIVE -> VoxIcons.Listen
    Tab.TRAIN -> VoxIcons.Train
    Tab.SONGS -> VoxIcons.Songs
    Tab.CIFRAS -> VoxIcons.Chords
    Tab.STUDY -> VoxIcons.Study
}

sealed interface Route {
    /** [lead]: lead singer's voice type for backing exercises (null = same as the user). */
    data class Exercise(val id: String, val lead: VoiceType? = null) : Route
    data object RangeTest : Route
    data object AddSong : Route
    data class Practice(val id: String) : Route
    data class Article(val index: Int) : Route
    data object Settings : Route
    data object Lessons : Route
    data class Lesson(val mode: HarmonyMode) : Route
    data object BackingLab : Route

    /** [id] null creates a new chord sheet. */
    data class CifraEdit(val id: String?) : Route

    /** [setlist] and [index] are set while going through a setlist. */
    data class CifraView(val id: String, val setlist: String? = null, val index: Int = 0) : Route
    data class SetlistEdit(val id: String) : Route
}

/** Minimal navigation: one tab plus a stack of pushed screens. */
class Nav {
    var tab by mutableStateOf(Tab.LIVE)
    val stack = mutableStateListOf<Route>()

    fun push(route: Route) {
        stack.add(route)
    }

    fun pop(): Boolean {
        if (stack.isEmpty()) return false
        stack.removeAt(stack.lastIndex)
        return true
    }

    fun replace(route: Route) {
        if (stack.isNotEmpty()) stack.removeAt(stack.lastIndex)
        stack.add(route)
    }
}

@Composable
fun VoxApp() {
    val c = Vox.colors
    val nav = remember { Nav() }
    BackHandler(enabled = nav.stack.isNotEmpty() || nav.tab != Tab.LIVE) {
        if (!nav.pop()) nav.tab = Tab.LIVE
    }
    Column(Modifier.fillMaxSize().background(c.bg).safeDrawingPadding()) {
        val top: Any = nav.stack.lastOrNull() ?: nav.tab
        Box(Modifier.weight(1f).fillMaxWidth()) {
            if (nav.stack.isEmpty()) Scenery(Modifier.fillMaxWidth().height(250.dp))
            Crossfade(targetState = top, animationSpec = tween(160), label = "screen") { screen ->
                Box(Modifier.fillMaxSize()) {
                    when (screen) {
                        Tab.LIVE -> LiveScreen(nav)
                        Tab.TRAIN -> TrainScreen(nav)
                        Tab.SONGS -> SongsScreen(nav)
                        Tab.CIFRAS -> CifrasScreen(nav)
                        Tab.STUDY -> StudyScreen(nav)
                        is Route.Exercise -> ExerciseScreen(nav, screen.id, screen.lead)
                        Route.RangeTest -> RangeTestScreen(nav)
                        Route.AddSong -> AddSongScreen(nav)
                        is Route.Practice -> PracticeScreen(nav, screen.id)
                        is Route.Article -> ArticleScreen(nav, screen.index)
                        Route.Settings -> SettingsScreen(nav)
                        Route.Lessons -> LessonsScreen(nav)
                        is Route.Lesson -> LessonScreen(nav, screen.mode)
                        Route.BackingLab -> BackingLabScreen(nav)
                        is Route.CifraEdit -> CifraEditScreen(nav, screen.id)
                        is Route.CifraView -> CifraViewScreen(nav, screen.id, screen.setlist, screen.index)
                        is Route.SetlistEdit -> SetlistScreen(nav, screen.id)
                    }
                }
            }
        }
        if (nav.stack.isEmpty()) BottomBar(nav)
    }
}

@Composable
private fun BottomBar(nav: Nav) {
    val c = Vox.colors
    Column {
        Hairline()
        Row(
            Modifier.fillMaxWidth().height(62.dp).padding(horizontal = 4.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            for (tab in Tab.entries) {
                val selected = nav.tab == tab
                Column(
                    Modifier
                        .weight(1f)
                        .clip(CircleShape)
                        .clickable { nav.tab = tab }
                        .padding(vertical = 6.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Icon(tab.icon(), null, tint = if (selected) c.text else c.faint, modifier = Modifier.size(22.dp))
                    Spacer(Modifier.height(4.dp))
                    Text(
                        tab.label,
                        style = VoxType.caps.copy(fontSize = 11.sp, letterSpacing = 0.2.sp),
                        color = if (selected) c.text else c.muted,
                        maxLines = 1,
                    )
                }
            }
        }
    }
}
