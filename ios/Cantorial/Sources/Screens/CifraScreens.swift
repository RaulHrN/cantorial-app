import CantorialCore
import SwiftUI
import UIKit

/// "Artista · Tom G", with whatever is known.
private func cifraSubtitle(_ cifra: Cifra) -> String? {
    var parts: [String] = []
    if !cifra.artist.isEmpty { parts.append(cifra.artist) }
    if let key = Chords.keyOf(cifra.text, cifra.transpose) { parts.append("Tom " + Chords.keyName(key)) }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}

private func countLabel(_ n: Int) -> String { n == 1 ? "1 cifra" : "\(n) cifras" }

struct CifrasScreen: View {
    @Environment(Nav.self) var nav
    var store = SheetStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if store.loaded && store.cifras.isEmpty {
                    Panel {
                        Text("Suas cifras, no seu tom").font(Typo.heading).foregroundStyle(Palette.text)
                        Text("Guarde as cifras das músicas que você toca e canta, mude o tom com um toque e monte listas para se apresentar: ao terminar uma música, um botão leva direto à próxima.")
                            .font(Typo.small)
                            .foregroundStyle(Palette.muted)
                            .padding(.top, 8)
                        PillButton("Adicionar cifra", icon: "plus") { nav.push(.cifraEdit(nil)) }.padding(.top, 16)
                    }
                }
                SectionTitle("Listas de apresentação")
                ForEach(store.setlists) { list in
                    ListRow(title: list.name, subtitle: countLabel(list.items.count)) { nav.push(.setlist(list.id)) }
                }
                PillButton("Nova lista", icon: "plus", primary: false) {
                    let list = Setlist(id: UUID().uuidString, name: "Nova lista", items: [])
                    store.upsertSetlist(list)
                    nav.push(.setlist(list.id))
                }
                .padding(.top, 8)
                if !store.cifras.isEmpty {
                    SectionTitle("Minhas cifras")
                    ForEach(store.cifras) { cifra in
                        ListRow(title: cifra.title, subtitle: cifraSubtitle(cifra)) { nav.push(.cifraView(cifra.id, nil, 0)) }
                    }
                }
            }
            .padding(.horizontal, screenPadding)
            .padding(.bottom, 24)
        }
        .navigationTitle("Cifras")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                IconButton(icon: "plus", label: "Adicionar cifra") { nav.push(.cifraEdit(nil)) }
            }
        }
    }
}

private let exampleSheet = [
    "Tom: C",
    "",
    "C                G",
    "Parabéns pra você",
    "G7               C",
    "Nesta data querida",
    "C7           F",
    "Muitas felicidades",
    "C       G7      C",
    "Muitos anos de vida",
].joined(separator: "\n")

struct CifraEditScreen: View {
    let id: String?
    @Environment(Nav.self) var nav
    @State var title = ""
    @State var artist = ""
    @State var text = ""
    @State var loadedFields = false
    @State var confirmDelete = false

    var body: some View {
        let existing = id.flatMap { SheetStore.shared.find($0) }
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    field("Nome da música", $title)
                    field("Artista (opcional)", $artist)
                    TextEditor(text: $text)
                        .font(.system(size: 14, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 280)
                        .padding(10)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Text("Cole ou digite a cifra com os acordes na linha de cima da letra, como nos sites de cifras. Também funciona com os acordes entre colchetes no meio da letra: [C]Parabéns pra vo[G]cê.")
                        .font(Typo.small)
                        .foregroundStyle(Palette.muted)
                    LinkText("Inserir exemplo") {
                        if title.trimmingCharacters(in: .whitespaces).isEmpty { title = "Parabéns pra você" }
                        text = exampleSheet
                    }
                }
                .padding(.bottom, 16)
            }
            PillButton("Salvar", enabled: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { save(existing) }
                .padding(.vertical, 12)
        }
        .padding(.horizontal, screenPadding)
        .navigationTitle(id == nil ? "Nova cifra" : "Editar cifra")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if existing != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    IconButton(icon: "trash", label: "Excluir") { confirmDelete = true }
                }
            }
        }
        .confirmationDialog("Excluir esta cifra? Ela também sai das listas.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Excluir", role: .destructive) {
                if let existing { SheetStore.shared.delete(existing.id) }
                // Leave the editor and the sheet that no longer exists.
                nav.pop()
                if let last = nav.path.last, case .cifraView = last { nav.pop() }
            }
            Button("Cancelar", role: .cancel) {}
        }
        .onAppear {
            if !loadedFields, let existing {
                title = existing.title
                artist = existing.artist
                text = existing.text
            }
            loadedFields = true
        }
    }

    private func field(_ label: String, _ value: Binding<String>) -> some View {
        TextField(label, text: value)
            .font(Typo.body)
            .padding(14)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func save(_ existing: Cifra?) {
        let name = title.trimmingCharacters(in: .whitespaces)
        var body = text
        while let last = body.last, last.isWhitespace { body.removeLast() }
        let cifra = Cifra(
            id: existing?.id ?? UUID().uuidString,
            title: name.isEmpty ? "Sem título" : name,
            artist: artist.trimmingCharacters(in: .whitespaces),
            text: body,
            transpose: existing?.transpose ?? 0,
            createdAt: existing?.createdAt ?? Date()
        )
        SheetStore.shared.upsert(cifra)
        if existing == nil { nav.replace(.cifraView(cifra.id, nil, 0)) } else { nav.pop() }
    }
}

/// The sheet as monospaced text with the chords picked out in the accent colour.
private func highlight(_ text: String, size: CGFloat) -> AttributedString {
    var out = AttributedString()
    let bold = Font.system(size: size, weight: .bold, design: .monospaced)
    let lines = text.components(separatedBy: "\n")
    for (n, line) in lines.enumerated() {
        var a = AttributedString(line)
        for span in Chords.spans(line) {
            let lo = a.index(a.startIndex, offsetByCharacters: span.lowerBound)
            let hi = a.index(a.startIndex, offsetByCharacters: span.upperBound)
            a[lo..<hi].foregroundColor = Palette.accent
            a[lo..<hi].font = bold
        }
        out.append(a)
        if n < lines.count - 1 { out.append(AttributedString("\n")) }
    }
    return out
}

struct CifraViewScreen: View {
    let id: String
    let setlistId: String?
    let index: Int
    @Environment(Nav.self) var nav
    var store = SheetStore.shared
    var prefs = Prefs.shared

    var body: some View {
        Group {
            if let cifra = store.find(id) {
                content(cifra)
            } else {
                Text(store.loaded ? "Cifra não encontrada." : "Carregando…").font(Typo.body).foregroundStyle(Palette.muted)
            }
        }
        .padding(.horizontal, screenPadding)
        .navigationTitle(store.find(id)?.title ?? "Cifra")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                IconButton(icon: "pencil", label: "Editar") { nav.push(.cifraEdit(id)) }
            }
        }
        // The phone must not sleep in the middle of a song.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = MicEngine.shared.active }
    }

    private func shift(_ cifra: Cifra, _ by: Int) {
        var c = cifra
        c.transpose = (cifra.transpose + by) % 12
        store.upsert(c)
    }

    @ViewBuilder
    private func content(_ cifra: Cifra) -> some View {
        let size = CGFloat(prefs.cifraSize)
        let key = Chords.keyOf(cifra.text, cifra.transpose)
        let original = Chords.keyOf(cifra.text)
        VStack(alignment: .leading, spacing: 0) {
            if !cifra.artist.isEmpty {
                Text(cifra.artist).font(Typo.small).foregroundStyle(Palette.muted).padding(.bottom, 4)
            }
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    Caps("Tom")
                    HStack(alignment: .lastTextBaseline, spacing: 10) {
                        Text(key.map(Chords.keyName) ?? "—").font(Typo.title).foregroundStyle(Palette.text)
                        if cifra.transpose != 0, let original {
                            Button {
                                var c = cifra
                                c.transpose = 0
                                store.upsert(c)
                            } label: {
                                Text("original \(Chords.keyName(original))").font(Typo.small).foregroundStyle(Palette.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Spacer()
                RoundButton(icon: "minus", label: "Meio tom abaixo", size: 40, primary: false) { shift(cifra, -1) }
                Text(cifra.transpose > 0 ? "+\(cifra.transpose)" : "\(cifra.transpose)")
                    .font(Typo.label)
                    .foregroundStyle(Palette.text)
                    .frame(width: 34)
                RoundButton(icon: "plus", label: "Meio tom acima", size: 40, primary: false) { shift(cifra, 1) }
                Chip(text: "A−", selected: false) { prefs.cifraSize -= 1 }.padding(.leading, 6)
                Chip(text: "A+", selected: false) { prefs.cifraSize += 1 }
            }
            .padding(.bottom, 8)
            Rectangle().fill(Palette.line).frame(height: 0.5)

            ScrollView(.vertical) {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(highlight(Chords.transpose(cifra.text, cifra.transpose), size: size))
                        .font(.system(size: size, design: .monospaced))
                        .lineSpacing(size * 0.35)
                        .foregroundStyle(Palette.text)
                        .fixedSize()
                        .padding(.top, 12)
                        .padding(.bottom, 32)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)

            if let setlistId, let setlist = store.findSetlist(setlistId) {
                footer(setlist)
            }
        }
    }

    @ViewBuilder
    private func footer(_ setlist: Setlist) -> some View {
        let items = setlist.items
        let next: Cifra? = index + 1 < items.count ? store.find(items[index + 1]) : nil
        Rectangle().fill(Palette.line).frame(height: 0.5)
        HStack(spacing: 10) {
            if index > 0 && index - 1 < items.count {
                RoundButton(icon: "backward.end.fill", label: "Cifra anterior", size: 56, primary: false) {
                    nav.replace(.cifraView(items[index - 1], setlist.id, index - 1))
                }
            }
            if let next {
                Button {
                    nav.replace(.cifraView(next.id, setlist.id, index + 1))
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PRÓXIMA  ·  \(index + 2) de \(items.count)")
                                .font(Typo.caps)
                                .tracking(1.2)
                                .foregroundStyle(Palette.onPrimary.opacity(0.7))
                            Text(next.title).font(Typo.heading).foregroundStyle(Palette.onPrimary).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "forward.end.fill").font(.system(size: 20)).foregroundStyle(Palette.onPrimary)
                    }
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(Palette.primary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Próxima cifra: \(next.title)")
            } else {
                PillButton("Fim da lista · voltar", primary: false) { nav.pop() }
            }
        }
        .padding(.vertical, 10)
    }
}

struct SetlistScreen: View {
    let id: String
    @Environment(Nav.self) var nav
    var store = SheetStore.shared
    @State var name = ""
    @State var loadedName = false
    @State var adding = false
    @State var confirmDelete = false

    var body: some View {
        Group {
            if let list = store.findSetlist(id) {
                content(list)
            } else {
                Text(store.loaded ? "Lista não encontrada." : "Carregando…").font(Typo.body).foregroundStyle(Palette.muted)
            }
        }
        .padding(.horizontal, screenPadding)
        .navigationTitle("Lista de apresentação")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                IconButton(icon: "trash", label: "Excluir lista") { confirmDelete = true }
            }
        }
        .confirmationDialog("Excluir esta lista? As cifras continuam guardadas.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Excluir", role: .destructive) {
                store.deleteSetlist(id)
                nav.pop()
            }
            Button("Cancelar", role: .cancel) {}
        }
        .onAppear {
            if !loadedName, let list = store.findSetlist(id) {
                name = list.name
                adding = list.items.isEmpty
                loadedName = true
            }
        }
        .onChange(of: name) { _, value in
            guard loadedName, var list = store.findSetlist(id) else { return }
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            list.name = trimmed.isEmpty ? "Lista" : trimmed
            store.upsertSetlist(list)
        }
    }

    private func update(_ list: Setlist, _ items: [String]) {
        var l = list
        l.items = items
        store.upsertSetlist(l)
    }

    private func move(_ list: Setlist, _ from: Int, _ to: Int) {
        guard to >= 0, to < list.items.count else { return }
        var items = list.items
        items.insert(items.remove(at: from), at: to)
        update(list, items)
    }

    @ViewBuilder
    private func content(_ list: Setlist) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TextField("Nome da lista", text: $name)
                        .font(Typo.body)
                        .padding(14)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    SectionTitle("Ordem das músicas")
                    if list.items.isEmpty {
                        Text("A lista está vazia. Escolha as cifras abaixo, na ordem em que vai tocar.").font(Typo.small).foregroundStyle(Palette.muted)
                    }
                    ForEach(Array(list.items.enumerated()), id: \.offset) { i, itemId in
                        row(list, i, itemId)
                    }
                    additions(list).padding(.top, 12)
                }
                .padding(.bottom, 16)
            }
            PillButton("Começar apresentação", icon: "play.fill", enabled: !list.items.isEmpty) {
                if let first = list.items.first { nav.push(.cifraView(first, list.id, 0)) }
            }
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func row(_ list: Setlist, _ i: Int, _ itemId: String) -> some View {
        let cifra = store.find(itemId)
        HStack(spacing: 0) {
            Button {
                nav.push(.cifraView(itemId, list.id, i))
            } label: {
                HStack(spacing: 0) {
                    Text("\(i + 1)").font(Typo.heading).foregroundStyle(Palette.accent).frame(width: 30, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cifra?.title ?? "Cifra apagada").font(Typo.body).foregroundStyle(Palette.text).lineLimit(1)
                        if let cifra, let subtitle = cifraSubtitle(cifra) {
                            Text(subtitle).font(Typo.small).foregroundStyle(Palette.muted).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            IconButton(icon: "chevron.up", label: "Subir", tint: i > 0 ? Palette.text : Palette.faint) { move(list, i, i - 1) }
            IconButton(icon: "chevron.down", label: "Descer", tint: i < list.items.count - 1 ? Palette.text : Palette.faint) { move(list, i, i + 1) }
            IconButton(icon: "xmark", label: "Tirar da lista", tint: Palette.muted) {
                var items = list.items
                items.remove(at: i)
                update(list, items)
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 0.5) }
    }

    @ViewBuilder
    private func additions(_ list: Setlist) -> some View {
        if adding {
            let available = store.cifras.filter { !list.items.contains($0.id) }
            SectionTitle("Adicionar à lista")
            if store.cifras.isEmpty {
                Text("Você ainda não guardou nenhuma cifra.").font(Typo.small).foregroundStyle(Palette.muted)
                PillButton("Criar cifra", icon: "plus", primary: false) { nav.push(.cifraEdit(nil)) }.padding(.top, 8)
            } else if available.isEmpty {
                Text("Todas as suas cifras já estão na lista.").font(Typo.small).foregroundStyle(Palette.muted)
            } else {
                ForEach(available) { cifra in
                    Button {
                        update(list, list.items + [cifra.id])
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus").foregroundStyle(Palette.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cifra.title).font(Typo.body).foregroundStyle(Palette.text).lineLimit(1)
                                if let subtitle = cifraSubtitle(cifra) {
                                    Text(subtitle).font(Typo.small).foregroundStyle(Palette.muted).lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            PillButton("Adicionar cifras", icon: "plus", primary: false) { adding = true }
        }
    }
}
