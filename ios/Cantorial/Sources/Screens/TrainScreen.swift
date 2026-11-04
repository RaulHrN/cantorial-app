import CantorialCore
import SwiftUI

struct TrainScreen: View {
    @Environment(Nav.self) var nav
    var prefs = Prefs.shared

    var body: some View {
        let naming = prefs.naming
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Panel {
                    Caps("Dica do dia", color: Palette.accent)
                    Text(Content.tipOfTheDay()).font(Typo.body).foregroundStyle(Palette.text).padding(.top, 6)
                }
                HStack(spacing: 12) {
                    Panel(action: { nav.push(.lessons) }) {
                        Caps("Aprender", color: Palette.accent)
                        Text("Tipos de segunda voz").font(Typo.label).foregroundStyle(Palette.text).padding(.top, 6)
                        Text("8 tipos, do básico ao avançado").font(Typo.small).foregroundStyle(Palette.muted)
                    }
                    Panel(action: { nav.push(.backingLab) }) {
                        Caps("Laboratório", color: Palette.accent)
                        Text("Backing vocal").font(Typo.label).foregroundStyle(Palette.text).padding(.top, 6)
                        Text("Conforme a voz do regente").font(Typo.small).foregroundStyle(Palette.muted)
                    }
                }
                Panel {
                    Caps("Sua extensão")
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(NoteNames.full(prefs.rangeLow, naming)) – \(NoteNames.full(prefs.rangeHigh, naming))")
                                .font(Typo.heading)
                                .foregroundStyle(Palette.text)
                            Text(prefs.rangeMeasured ? prefs.voiceType.label : "Padrão, ainda não medida")
                                .font(Typo.small)
                                .foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        PillButton(prefs.rangeMeasured ? "Refazer" : "Medir", primary: !prefs.rangeMeasured) { nav.push(.rangeTest) }
                            .frame(width: 120)
                    }
                    .padding(.top, 6)
                }
                ForEach(Content.categories, id: \.self) { category in
                    SectionTitle(category)
                    ForEach(Content.exercises.filter { $0.category == category }) { ex in
                        ListRow(title: ex.title, subtitle: ex.summary, trailing: "\(ex.minutes) min") {
                            nav.push(.exercise(ex.id, nil))
                        }
                    }
                }
            }
            .padding(.horizontal, screenPadding)
            .padding(.bottom, 24)
        }
        .navigationTitle("Treinar")
    }
}

struct SongsScreen: View {
    @Environment(Nav.self) var nav
    var store = SongStore.shared
    var prefs = Prefs.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if store.loaded && store.songs.isEmpty {
                    Panel {
                        Text("Segunda voz e backing vocal").font(Typo.heading).foregroundStyle(Palette.text)
                        Text("Adicione uma música e o Cantorial separa a voz do instrumental, encontra a melodia, descobre o tom e escreve a segunda voz ou o backing vocal para a sua voz. Depois é só ouvir, cantar junto e acompanhar a afinação.")
                            .font(Typo.small)
                            .foregroundStyle(Palette.muted)
                            .padding(.top, 8)
                        VStack(alignment: .leading, spacing: 6) {
                            Bullet(text: "Arquivo de áudio: a música completa; o app isola o que é cantado.")
                            Bullet(text: "Cantando: você canta a melodia e o app transcreve.")
                            Bullet(text: "Digitando: escreva as notas, como \"Dó Ré Mi:2\".")
                        }
                        .padding(.top, 12)
                        PillButton("Adicionar música", icon: "plus") { nav.push(.addSong) }.padding(.top, 16)
                    }
                }
                ForEach(store.songs) { song in
                    ListRow(
                        title: song.title,
                        subtitle: song.key.label(prefs.naming) + " · " + (song.backingMode ? "Backing: \(song.backingStyle.label)" : song.mode.label),
                        trailing: formatTime(Float(song.durationMs))
                    ) { nav.push(.practice(song.id)) }
                }
            }
            .padding(.horizontal, screenPadding)
            .padding(.bottom, 24)
        }
        .navigationTitle("Músicas")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                IconButton(icon: "plus", label: "Adicionar música") { nav.push(.addSong) }
            }
        }
    }
}

struct StudyScreen: View {
    @Environment(Nav.self) var nav

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(Content.studies.enumerated()), id: \.offset) { i, a in
                    ListRow(title: a.title, subtitle: a.summary) { nav.push(.article(i)) }
                }
            }
            .padding(.horizontal, screenPadding)
            .padding(.bottom, 24)
        }
        .navigationTitle("Estudar")
    }
}

struct ArticleScreen: View {
    let index: Int

    var body: some View {
        let article = index < Content.studies.count ? Content.studies[index] : nil
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let article {
                    Text(article.summary).font(Typo.heading).foregroundStyle(Palette.muted).padding(.bottom, 12)
                    ForEach(Array(article.body.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                        if line.trimmingCharacters(in: .whitespaces).isEmpty {
                            Spacer().frame(height: 10)
                        } else if line.hasPrefix("# ") {
                            Text(String(line.dropFirst(2))).font(Typo.heading).foregroundStyle(Palette.text).padding(.top, 14).padding(.bottom, 6)
                        } else if line.hasPrefix("- ") {
                            Bullet(text: String(line.dropFirst(2)), font: Typo.body).padding(.vertical, 4)
                        } else {
                            Text(line).font(Typo.body).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, screenPadding)
            .padding(.bottom, 32)
        }
        .navigationTitle(article?.title ?? "Estudo")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SettingsScreen: View {
    @Environment(Nav.self) var nav
    var prefs = Prefs.shared

    var body: some View {
        @Bindable var p = prefs
        let naming = prefs.naming
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    SectionTitle("Nomes das notas")
                    ChoiceGrid(items: Naming.allCases, columns: 2, selected: { $0 == naming }, label: { $0 == .solfege ? "Dó Ré Mi" : "C D E" }, onSelect: { prefs.naming = $0 })
                    SectionTitle("Afinação")
                    StepperRow(label: "Lá central (A4)", value: "\(Int(prefs.a4.rounded())) Hz", detail: "O padrão é 440 Hz", minus: { prefs.a4 -= 1 }, plus: { prefs.a4 += 1 })
                }
                Group {
                    SectionTitle("Microfone")
                    Text("Sensibilidade").font(Typo.body).foregroundStyle(Palette.text)
                    Text("Aumente se o app não ouvir cantos suaves; diminua se captar ruído do ambiente.").font(Typo.small).foregroundStyle(Palette.muted)
                    Slider(value: $p.sensitivity, in: 0...1).tint(Palette.accent)
                }
                SectionTitle("Extensão vocal")
                StepperRow(
                    label: "Nota mais grave", value: NoteNames.full(prefs.rangeLow, naming),
                    minus: { prefs.setRange(prefs.rangeLow - 1, prefs.rangeHigh, measured: prefs.rangeMeasured) },
                    plus: { prefs.setRange(prefs.rangeLow + 1, prefs.rangeHigh, measured: prefs.rangeMeasured) }
                )
                StepperRow(
                    label: "Nota mais aguda", value: NoteNames.full(prefs.rangeHigh, naming), detail: prefs.voiceType.label,
                    minus: { prefs.setRange(prefs.rangeLow, prefs.rangeHigh - 1, measured: prefs.rangeMeasured) },
                    plus: { prefs.setRange(prefs.rangeLow, prefs.rangeHigh + 1, measured: prefs.rangeMeasured) }
                )
                PillButton("Medir com o teste de extensão", primary: false) { nav.push(.rangeTest) }.padding(.top, 8)

                SectionTitle("Sobre")
                Text("Cantorial: afinador vocal, exercícios, segunda voz e backing vocal. Tudo roda no seu iPhone: o app não usa a internet e o som do microfone nunca é gravado nem enviado.")
                    .font(Typo.small)
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, screenPadding)
            .padding(.bottom, 32)
        }
        .navigationTitle("Ajustes")
        .navigationBarTitleDisplayMode(.inline)
    }
}
