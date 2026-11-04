import CantorialCore
import SwiftUI
import UIKit

@main
struct CantorialApp: App {
    init() {
        SongStore.shared.load()
        _ = Prefs.shared
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = UIColor(Palette.bg)
        appearance.titleTextAttributes = [.foregroundColor: UIColor(Palette.text)]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor(Palette.text)]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Palette.accent)
        }
    }
}

enum AppTab: CaseIterable {
    case live, train, songs, study

    var label: String {
        switch self {
        case .live: return "Ouvir"
        case .train: return "Treinar"
        case .songs: return "Músicas"
        case .study: return "Estudar"
        }
    }

    var icon: String {
        switch self {
        case .live: return "waveform"
        case .train: return "figure.mind.and.body"
        case .songs: return "music.note.list"
        case .study: return "book"
        }
    }
}

enum Route: Hashable {
    /// `lead`: lead singer's voice type for backing exercises (nil = same as the user).
    case exercise(String, VoiceType?)
    case rangeTest
    case addSong
    case practice(String)
    case article(Int)
    case settings
    case lessons
    case lesson(HarmonyMode)
    case backingLab
}

/// Minimal navigation: one tab plus a stack of pushed screens.
@Observable
final class Nav {
    var tab: AppTab = .live
    var path: [Route] = []

    func push(_ route: Route) { path.append(route) }

    func pop() {
        if !path.isEmpty { path.removeLast() }
    }

    func replace(_ route: Route) {
        var p = path
        if !p.isEmpty { p.removeLast() }
        p.append(route)
        path = p
    }
}

struct RootView: View {
    @State var nav = Nav()

    var body: some View {
        NavigationStack(path: $nav.path) {
            VStack(spacing: 0) {
                Group {
                    switch nav.tab {
                    case .live: LiveScreen()
                    case .train: TrainScreen()
                    case .songs: SongsScreen()
                    case .study: StudyScreen()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                BottomBar(tab: $nav.tab)
            }
            .background(Palette.bg.ignoresSafeArea())
            .navigationDestination(for: Route.self) { route in
                destination(route)
                    .background(Palette.bg.ignoresSafeArea())
                    .toolbarBackground(Palette.bg, for: .navigationBar)
            }
        }
        .environment(nav)
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case let .exercise(id, lead): ExerciseScreen(id: id, lead: lead)
        case .rangeTest: RangeTestScreen()
        case .addSong: AddSongScreen()
        case let .practice(id): PracticeScreen(id: id)
        case let .article(index): ArticleScreen(index: index)
        case .settings: SettingsScreen()
        case .lessons: LessonsScreen()
        case let .lesson(mode): LessonScreen(mode: mode)
        case .backingLab: BackingLabScreen()
        }
    }
}

private struct BottomBar: View {
    @Binding var tab: AppTab

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.line).frame(height: 0.5)
            HStack {
                ForEach(AppTab.allCases, id: \.self) { t in
                    let selected = t == tab
                    Button { tab = t } label: {
                        VStack(spacing: 4) {
                            Image(systemName: t.icon).font(.system(size: 18, weight: selected ? .semibold : .regular))
                            Text(t.label).font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(selected ? Palette.accent : Palette.muted)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 8)
        }
        .background(Palette.bg.ignoresSafeArea(edges: .bottom))
    }
}
