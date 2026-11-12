package com.raulhrn.vox.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.raulhrn.vox.audio.MicEngine
import com.raulhrn.vox.core.Chords
import com.raulhrn.vox.core.Cifra
import com.raulhrn.vox.core.Setlist
import com.raulhrn.vox.data.CifraStore
import com.raulhrn.vox.data.Prefs
import com.raulhrn.vox.ui.Chip
import com.raulhrn.vox.ui.Hairline
import com.raulhrn.vox.ui.Header
import com.raulhrn.vox.ui.IconBtn
import com.raulhrn.vox.ui.ListRow
import com.raulhrn.vox.ui.Nav
import com.raulhrn.vox.ui.Panel
import com.raulhrn.vox.ui.RoundButton
import com.raulhrn.vox.ui.Route
import com.raulhrn.vox.ui.ScreenPadding
import com.raulhrn.vox.ui.Section
import com.raulhrn.vox.ui.Vox
import com.raulhrn.vox.ui.VoxButton
import com.raulhrn.vox.ui.VoxIcons
import com.raulhrn.vox.ui.VoxType
import com.raulhrn.vox.ui.fieldColors
import java.util.UUID

/** "Artista · Tom G", with whatever is known. */
private fun cifraSubtitle(cifra: Cifra): String {
    val key = Chords.keyOf(cifra.text, cifra.transpose)?.let { "Tom " + Chords.keyName(it) }
    return listOfNotNull(cifra.artist.ifBlank { null }, key).joinToString(" · ")
}

private fun countLabel(n: Int): String = if (n == 1) "1 cifra" else "$n cifras"

@Composable
fun CifrasScreen(nav: Nav) {
    val c = Vox.colors
    LazyColumn(Modifier.fillMaxSize().padding(horizontal = ScreenPadding)) {
        item {
            Header("Cifras") {
                IconBtn(VoxIcons.Add, "Adicionar cifra", { nav.push(Route.CifraEdit(null)) })
            }
        }
        if (CifraStore.loaded.value && CifraStore.cifras.isEmpty()) {
            item {
                Panel {
                    Text("Suas cifras, no seu tom", style = VoxType.heading, color = c.text)
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "Guarde as cifras das músicas que você toca e canta, mude o tom com um toque e monte listas " +
                            "para se apresentar: ao terminar uma música, um botão leva direto à próxima.",
                        style = VoxType.small,
                        color = c.muted,
                    )
                    Spacer(Modifier.height(16.dp))
                    VoxButton("Adicionar cifra", { nav.push(Route.CifraEdit(null)) }, Modifier.fillMaxWidth(), icon = VoxIcons.Add)
                }
            }
        }
        item { Section("Listas de apresentação") }
        items(CifraStore.setlists, key = { "l-" + it.id }) { list ->
            ListRow(list.name, countLabel(list.items.size)) { nav.push(Route.SetlistEdit(list.id)) }
        }
        item {
            Spacer(Modifier.height(8.dp))
            VoxButton(
                "Nova lista",
                {
                    val list = Setlist(UUID.randomUUID().toString(), "Nova lista", emptyList(), System.currentTimeMillis())
                    CifraStore.upsertSetlist(list)
                    nav.push(Route.SetlistEdit(list.id))
                },
                Modifier.fillMaxWidth(),
                icon = VoxIcons.Add,
                primary = false,
            )
        }
        if (CifraStore.cifras.isNotEmpty()) {
            item { Section("Minhas cifras") }
            items(CifraStore.cifras, key = { "c-" + it.id }) { cifra ->
                val subtitle = remember(cifra) { cifraSubtitle(cifra) }
                ListRow(cifra.title, subtitle.ifEmpty { null }) { nav.push(Route.CifraView(cifra.id)) }
            }
        }
        item { Spacer(Modifier.height(24.dp)) }
    }
}

@Composable
fun CifraEditScreen(nav: Nav, id: String?) {
    val c = Vox.colors
    val existing = remember(id) { id?.let { CifraStore.find(it) } }
    var title by remember { mutableStateOf(existing?.title ?: "") }
    var artist by remember { mutableStateOf(existing?.artist ?: "") }
    var text by remember { mutableStateOf(existing?.text ?: "") }
    var confirmDelete by remember { mutableStateOf(false) }

    fun save() {
        val cifra = Cifra(
            id = existing?.id ?: UUID.randomUUID().toString(),
            title = title.trim().ifBlank { "Sem título" },
            artist = artist.trim(),
            text = text.trimEnd(),
            transpose = existing?.transpose ?: 0,
            createdAt = existing?.createdAt ?: System.currentTimeMillis(),
        )
        CifraStore.upsert(cifra)
        if (existing == null) nav.replace(Route.CifraView(cifra.id)) else nav.pop()
    }

    Column(Modifier.fillMaxSize().padding(horizontal = ScreenPadding)) {
        Header(if (existing == null) "Nova cifra" else "Editar cifra", onBack = { nav.pop() }) {
            if (existing != null) IconBtn(VoxIcons.Delete, "Excluir", { confirmDelete = true })
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            if (confirmDelete && existing != null) {
                Panel {
                    Text("Excluir \"${existing.title}\"? Ela também sai das listas.", style = VoxType.body, color = c.text)
                    Spacer(Modifier.height(10.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        VoxButton("Cancelar", { confirmDelete = false }, Modifier.weight(1f), primary = false)
                        VoxButton("Excluir", {
                            CifraStore.delete(existing.id)
                            // Leave the editor and the sheet that no longer exists.
                            nav.pop()
                            if (nav.stack.lastOrNull() is Route.CifraView) nav.pop()
                        }, Modifier.weight(1f))
                    }
                }
                Spacer(Modifier.height(12.dp))
            }
            OutlinedTextField(
                value = title,
                onValueChange = { title = it },
                label = { Text("Nome da música") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                colors = fieldColors(),
            )
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(
                value = artist,
                onValueChange = { artist = it },
                label = { Text("Artista (opcional)") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                colors = fieldColors(),
            )
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                label = { Text("Cifra") },
                minLines = 12,
                textStyle = TextStyle(fontFamily = FontFamily.Monospace, fontSize = 14.sp, lineHeight = 20.sp),
                modifier = Modifier.fillMaxWidth(),
                colors = fieldColors(),
            )
            Spacer(Modifier.height(8.dp))
            Text(
                "Cole ou digite a cifra com os acordes na linha de cima da letra, como nos sites de cifras. " +
                    "Também funciona com os acordes entre colchetes no meio da letra: [C]Parabéns pra vo[G]cê.",
                style = VoxType.small,
                color = c.muted,
            )
            Text(
                "Inserir exemplo",
                style = VoxType.label,
                color = c.accent,
                modifier = Modifier
                    .clickable {
                        if (title.isBlank()) title = "Parabéns pra você"
                        text = EXAMPLE
                    }
                    .padding(vertical = 8.dp),
            )
            Spacer(Modifier.height(8.dp))
        }
        VoxButton("Salvar", { save() }, Modifier.fillMaxWidth(), enabled = text.isNotBlank())
        Spacer(Modifier.height(12.dp))
    }
}

private const val EXAMPLE =
    "Tom: C\n\n" +
        "C                G\n" +
        "Parabéns pra você\n" +
        "G7               C\n" +
        "Nesta data querida\n" +
        "C7           F\n" +
        "Muitas felicidades\n" +
        "C       G7      C\n" +
        "Muitos anos de vida"

/** The sheet as monospaced text with the chords picked out in [chord] colour. */
private fun highlight(text: String, chord: Color): AnnotatedString = buildAnnotatedString {
    val style = SpanStyle(color = chord, fontWeight = FontWeight.Bold)
    var start = 0
    for (line in text.split('\n')) {
        append(line)
        for (span in Chords.spans(line)) addStyle(style, start + span.first, start + span.last + 1)
        append('\n')
        start += line.length + 1
    }
}

@Composable
fun CifraViewScreen(nav: Nav, id: String, setlistId: String?, index: Int) {
    val c = Vox.colors
    val cifra = CifraStore.find(id)
    val setlist = setlistId?.let { CifraStore.findSetlist(it) }

    // The phone must not sleep in the middle of a song.
    val view = LocalView.current
    DisposableEffect(view) {
        view.keepScreenOn = true
        onDispose { view.keepScreenOn = MicEngine.active }
    }

    Column(Modifier.fillMaxSize().padding(horizontal = ScreenPadding)) {
        if (cifra == null) {
            Header("Cifra", onBack = { nav.pop() })
            Text(
                if (CifraStore.loaded.value) "Cifra não encontrada." else "Carregando…",
                style = VoxType.body,
                color = c.muted,
            )
            return@Column
        }
        Header(cifra.title, onBack = { nav.pop() }, subtitle = cifra.artist.ifBlank { null }) {
            IconBtn(VoxIcons.Edit, "Editar", { nav.push(Route.CifraEdit(cifra.id)) })
        }

        val original = remember(cifra.text) { Chords.keyOf(cifra.text) }
        val key = remember(cifra.text, cifra.transpose) { Chords.keyOf(cifra.text, cifra.transpose) }
        fun shift(by: Int) = CifraStore.upsert(cifra.copy(transpose = (cifra.transpose + by) % 12))

        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("TOM", style = VoxType.caps, color = c.muted)
                Row(verticalAlignment = Alignment.Bottom) {
                    Text(key?.let { Chords.keyName(it) } ?: "—", style = VoxType.title, color = c.text)
                    if (cifra.transpose != 0 && original != null) {
                        Text(
                            "original ${Chords.keyName(original)}",
                            style = VoxType.small,
                            color = c.accent,
                            modifier = Modifier.clickable { CifraStore.upsert(cifra.copy(transpose = 0)) }.padding(start = 10.dp, bottom = 6.dp, end = 6.dp),
                        )
                    }
                }
            }
            RoundButton(VoxIcons.Remove, "Meio tom abaixo", { shift(-1) }, size = 40.dp, primary = false)
            Text(
                if (cifra.transpose > 0) "+${cifra.transpose}" else "${cifra.transpose}",
                style = VoxType.label,
                color = c.text,
                textAlign = TextAlign.Center,
                modifier = Modifier.width(40.dp),
            )
            RoundButton(VoxIcons.Add, "Meio tom acima", { shift(1) }, size = 40.dp, primary = false)
            Spacer(Modifier.width(12.dp))
            Chip("A−", false, { Prefs.cifraSize -= 1f })
            Spacer(Modifier.width(6.dp))
            Chip("A+", false, { Prefs.cifraSize += 1f })
        }
        Spacer(Modifier.height(8.dp))
        Hairline()

        val shown = remember(cifra.text, cifra.transpose, c.accent) { highlight(Chords.transpose(cifra.text, cifra.transpose), c.accent) }
        val size = Prefs.cifraSize
        Box(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).horizontalScroll(rememberScrollState())) {
            Text(
                shown,
                style = TextStyle(fontFamily = FontFamily.Monospace, fontSize = size.sp, lineHeight = (size * 1.5f).sp),
                color = c.text,
                softWrap = false,
                modifier = Modifier.padding(top = 12.dp, bottom = 32.dp),
            )
        }

        if (setlist != null) {
            val items = setlist.items
            val next = items.getOrNull(index + 1)?.let { CifraStore.find(it) }
            Hairline()
            Row(Modifier.fillMaxWidth().padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                if (index > 0) {
                    RoundButton(
                        VoxIcons.Prev,
                        "Cifra anterior",
                        { nav.replace(Route.CifraView(items[index - 1], setlist.id, index - 1)) },
                        size = 56.dp,
                        primary = false,
                    )
                    Spacer(Modifier.width(10.dp))
                }
                if (next != null) {
                    NextButton(
                        caption = "PRÓXIMA  ·  ${index + 2} de ${items.size}",
                        title = next.title,
                        modifier = Modifier.weight(1f),
                    ) { nav.replace(Route.CifraView(next.id, setlist.id, index + 1)) }
                } else {
                    VoxButton("Fim da lista · voltar", { nav.pop() }, Modifier.weight(1f).heightIn(min = 56.dp), primary = false)
                }
            }
        }
    }
}

/** The big button at the bottom of a sheet that jumps to the next one of the setlist. */
@Composable
private fun NextButton(caption: String, title: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val c = Vox.colors
    Row(
        modifier
            .heightIn(min = 60.dp)
            .clip(RoundedCornerShape(18.dp))
            .background(c.primary)
            .clickable(onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(caption, style = VoxType.caps, color = c.onPrimary.copy(alpha = 0.7f))
            Text(title, style = VoxType.heading, color = c.onPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Icon(VoxIcons.Next, null, tint = c.onPrimary, modifier = Modifier.size(26.dp))
    }
}

@Composable
fun SetlistScreen(nav: Nav, id: String) {
    val c = Vox.colors
    val list = CifraStore.findSetlist(id)
    var name by remember(id) { mutableStateOf(list?.name ?: "") }
    var adding by remember(id) { mutableStateOf(list?.items?.isEmpty() ?: false) }
    var confirmDelete by remember { mutableStateOf(false) }

    Column(Modifier.fillMaxSize().padding(horizontal = ScreenPadding)) {
        if (list == null) {
            Header("Lista", onBack = { nav.pop() })
            Text(
                if (CifraStore.loaded.value) "Lista não encontrada." else "Carregando…",
                style = VoxType.body,
                color = c.muted,
            )
            return@Column
        }
        Header("Lista de apresentação", onBack = { nav.pop() }, subtitle = countLabel(list.items.size)) {
            IconBtn(VoxIcons.Delete, "Excluir lista", { confirmDelete = true })
        }

        fun update(items: List<String>) = CifraStore.upsertSetlist(list.copy(items = items))
        fun move(from: Int, to: Int) {
            if (to !in list.items.indices) return
            val items = list.items.toMutableList()
            items.add(to, items.removeAt(from))
            update(items)
        }

        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            if (confirmDelete) {
                Panel {
                    Text("Excluir a lista \"${list.name}\"? As cifras continuam guardadas.", style = VoxType.body, color = c.text)
                    Spacer(Modifier.height(10.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        VoxButton("Cancelar", { confirmDelete = false }, Modifier.weight(1f), primary = false)
                        VoxButton("Excluir", {
                            CifraStore.deleteSetlist(list.id)
                            nav.pop()
                        }, Modifier.weight(1f))
                    }
                }
                Spacer(Modifier.height(12.dp))
            }
            OutlinedTextField(
                value = name,
                onValueChange = {
                    name = it
                    CifraStore.upsertSetlist(list.copy(name = it.trim().ifBlank { "Lista" }))
                },
                label = { Text("Nome da lista") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                colors = fieldColors(),
            )
            Section("Ordem das músicas")
            if (list.items.isEmpty()) {
                Text("A lista está vazia. Escolha as cifras abaixo, na ordem em que vai tocar.", style = VoxType.small, color = c.muted)
            }
            list.items.forEachIndexed { i, itemId ->
                val cifra = CifraStore.find(itemId)
                Row(
                    Modifier.fillMaxWidth().clickable { nav.push(Route.CifraView(itemId, list.id, i)) }.padding(vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("${i + 1}", style = VoxType.heading, color = c.accent, modifier = Modifier.width(30.dp))
                    Column(Modifier.weight(1f)) {
                        Text(cifra?.title ?: "Cifra apagada", style = VoxType.body, color = c.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        val subtitle = cifra?.let { cifraSubtitle(it) }.orEmpty()
                        if (subtitle.isNotEmpty()) Text(subtitle, style = VoxType.small, color = c.muted, maxLines = 1)
                    }
                    IconBtn(VoxIcons.Up, "Subir", { move(i, i - 1) }, tint = if (i > 0) c.text else c.faint)
                    IconBtn(VoxIcons.Down, "Descer", { move(i, i + 1) }, tint = if (i < list.items.lastIndex) c.text else c.faint)
                    IconBtn(VoxIcons.Close, "Tirar da lista", { update(list.items.filterIndexed { k, _ -> k != i }) }, tint = c.muted)
                }
                Hairline()
            }

            Spacer(Modifier.height(12.dp))
            val available = CifraStore.cifras.filter { it.id !in list.items }
            if (adding) {
                Section("Adicionar à lista")
                when {
                    CifraStore.cifras.isEmpty() -> {
                        Text("Você ainda não guardou nenhuma cifra.", style = VoxType.small, color = c.muted)
                        Spacer(Modifier.height(8.dp))
                        VoxButton("Criar cifra", { nav.push(Route.CifraEdit(null)) }, Modifier.fillMaxWidth(), icon = VoxIcons.Add, primary = false)
                    }
                    available.isEmpty() -> Text("Todas as suas cifras já estão na lista.", style = VoxType.small, color = c.muted)
                    else -> for (cifra in available) {
                        Row(
                            Modifier.fillMaxWidth().clickable { update(list.items + cifra.id) }.padding(vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(VoxIcons.Add, null, tint = c.accent, modifier = Modifier.size(20.dp))
                            Spacer(Modifier.width(12.dp))
                            Column(Modifier.weight(1f)) {
                                Text(cifra.title, style = VoxType.body, color = c.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                val subtitle = cifraSubtitle(cifra)
                                if (subtitle.isNotEmpty()) Text(subtitle, style = VoxType.small, color = c.muted, maxLines = 1)
                            }
                        }
                    }
                }
            } else {
                VoxButton("Adicionar cifras", { adding = true }, Modifier.fillMaxWidth(), icon = VoxIcons.Add, primary = false)
            }
            Spacer(Modifier.height(16.dp))
        }
        VoxButton(
            "Começar apresentação",
            { nav.push(Route.CifraView(list.items.first(), list.id, 0)) },
            Modifier.fillMaxWidth(),
            icon = VoxIcons.Play,
            enabled = list.items.isNotEmpty(),
        )
        Spacer(Modifier.height(12.dp))
    }
}
