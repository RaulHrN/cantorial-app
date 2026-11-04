import CantorialCore
import SwiftUI

/// Small all-caps label above a group of controls.
struct Caps: View {
    let text: String
    var color: Color = Palette.muted

    init(_ text: String, color: Color = Palette.muted) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased()).font(Typo.caps).tracking(1.2).foregroundStyle(color)
    }
}

struct SectionTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Caps(text).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 22).padding(.bottom, 8)
    }
}

/// Rounded surface for grouped content; tappable when `action` is set.
struct Panel<Content: View>: View {
    var action: (() -> Void)?
    @ViewBuilder var content: Content

    init(action: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.action = action
        self.content = content()
    }

    var body: some View {
        let box = VStack(alignment: .leading, spacing: 0) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        if let action {
            Button(action: action) { box }.buttonStyle(.plain)
        } else {
            box
        }
    }
}

struct Bullet: View {
    let text: String
    var marker = "•"
    var font: Font = Typo.small

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(marker).font(font).foregroundStyle(Palette.accent).frame(width: 14, alignment: .leading)
            Text(text).font(font).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ListRow: View {
    let title: String
    var subtitle: String?
    var trailing: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Typo.body).foregroundStyle(Palette.text)
                    if let subtitle {
                        Text(subtitle).font(Typo.small).foregroundStyle(Palette.muted).lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                if let trailing { Text(trailing).font(Typo.small).foregroundStyle(Palette.muted) }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.faint)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 0.5) }
    }
}

/// Full-width pill button. Primary = amber, otherwise outlined.
struct PillButton: View {
    let title: String
    var icon: String?
    var primary = true
    var enabled = true
    let action: () -> Void

    init(_ title: String, icon: String? = nil, primary: Bool = true, enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.primary = primary
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon) }
                Text(title).font(Typo.label)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(primary ? Palette.onAccent : Palette.text)
            .background(
                Capsule().fill(primary ? Palette.accent : Color.clear)
            )
            .overlay(Capsule().stroke(primary ? Color.clear : Palette.line, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

/// Round icon button for transport controls.
struct RoundButton: View {
    let icon: String
    let label: String
    var size: CGFloat = 64
    var primary = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.36, weight: .semibold))
                .frame(width: size, height: size)
                .foregroundStyle(primary ? Palette.onAccent : Palette.text)
                .background(Circle().fill(primary ? Palette.accent : Palette.surface2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct IconButton: View {
    let icon: String
    let label: String
    var tint: Color = Palette.text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 19, weight: .medium)).foregroundStyle(tint).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct Chip: View {
    let text: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(Typo.label)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .foregroundStyle(selected ? Palette.onAccent : Palette.text)
                .background(Capsule().fill(selected ? Palette.accent : Palette.surface2))
        }
        .buttonStyle(.plain)
    }
}

/// Grid of mutually exclusive choices.
struct ChoiceGrid<T: Hashable>: View {
    let items: [T]
    var columns: Int
    let selected: (T) -> Bool
    let label: (T) -> String
    let onSelect: (T) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: max(1, columns)), spacing: 8) {
            ForEach(items, id: \.self) { item in
                let on = selected(item)
                Button { onSelect(item) } label: {
                    Text(label(item))
                        .font(Typo.label)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .padding(.horizontal, 4)
                        .foregroundStyle(on ? Palette.onAccent : Palette.text)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? Palette.accent : Palette.surface2))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct StepperRow: View {
    let label: String
    let value: String
    var detail: String?
    let minus: () -> Void
    let plus: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(Typo.body).foregroundStyle(Palette.text)
                if let detail { Text(detail).font(Typo.small).foregroundStyle(Palette.muted) }
            }
            Spacer()
            IconButton(icon: "minus", label: "Menos", action: minus)
            Text(value).font(Typo.label).foregroundStyle(Palette.text).frame(minWidth: 64)
            IconButton(icon: "plus", label: "Mais", action: plus)
        }
        .padding(.vertical, 6)
    }
}

struct ToggleRow: View {
    let label: String
    @Binding var isOn: Bool
    var detail: String?

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(Typo.body).foregroundStyle(Palette.text)
                if let detail { Text(detail).font(Typo.small).foregroundStyle(Palette.muted) }
            }
        }
        .tint(Palette.accent)
        .padding(.vertical, 6)
    }
}

/// Text link in accent colour.
struct LinkText: View {
    let text: String
    var color: Color = Palette.accent
    let action: () -> Void

    init(_ text: String, color: Color = Palette.accent, action: @escaping () -> Void) {
        self.text = text
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(text).font(Typo.label).foregroundStyle(color).padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

/// Thin progress bar.
struct ProgressLine: View {
    let value: Float

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.surface2)
                Capsule().fill(Palette.accent).frame(width: g.size.width * CGFloat(min(max(value, 0), 1)))
            }
        }
        .frame(height: 4)
    }
}
