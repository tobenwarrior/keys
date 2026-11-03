#if os(macOS)
import AppKit
import KeysCore
import SwiftUI

enum Theme {
    static let bg = Color(red: 28.0 / 255, green: 28.0 / 255, blue: 28.0 / 255)
    static let text = Color(red: 217.0 / 255, green: 210.0 / 255, blue: 200.0 / 255)
    static let muted = Color(red: 156.0 / 255, green: 163.0 / 255, blue: 175.0 / 255)
    static let line = Color(red: 42.0 / 255, green: 42.0 / 255, blue: 42.0 / 255)
    static let accent = Color(red: 107.0 / 255, green: 76.0 / 255, blue: 117.0 / 255)
}

struct PopoverView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("keys")
                .font(mono(13, weight: .medium))
                .foregroundStyle(Theme.text)

            row("Sound") {
                plainButton(model.settings.muted ? "Off" : "On") {
                    model.toggleMute()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Volume")
                        .font(mono(12))
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Text("\(Int((model.settings.volume * 100).rounded()))%")
                        .font(mono(12))
                        .foregroundStyle(Theme.text)
                }
                Slider(
                    value: Binding(
                        get: { model.settings.volume },
                        set: { model.setVolume($0) }
                    ),
                    in: 0...1
                )
                .tint(Theme.accent)
            }

            packPicker("Keyboard", packs: model.keyboardPacks, selection: model.settings.keyboardPackId) {
                model.selectKeyboard($0)
            }
            packPicker("Mouse", packs: model.mousePacks, selection: model.settings.mousePackId) {
                model.selectMouse($0)
            }

            permission(
                title: "Input Monitoring",
                granted: model.inputOn,
                action: { model.allowInput() }
            )
            permission(
                title: "Accessibility",
                granted: model.accessOn,
                action: { model.allowAccess() }
            )

            Text("After allowing Input Monitoring, quit keys and open it again.")
                .font(mono(11))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            if let problem = model.problem {
                Text(problem)
                    .font(mono(11))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                plainButton("Packs folder") { model.openPacksFolder() }
                plainButton("Reload") { model.reload() }
                Spacer()
                plainButton("Quit") { model.quit() }
            }
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
    }

    private func packPicker(
        _ title: String,
        packs: [SoundPack],
        selection: String,
        choose: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(mono(12))
                .foregroundStyle(Theme.muted)
            if packs.isEmpty {
                Text("No packs found")
                    .font(mono(12))
                    .foregroundStyle(Theme.text)
            } else {
                Picker(title, selection: Binding(get: { selection }, set: choose)) {
                    ForEach(packs, id: \.id) { pack in
                        Text(pack.name).tag(pack.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .font(mono(12))
                .tint(Theme.text)
            }
        }
    }

    private func permission(title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(mono(12))
                    .foregroundStyle(Theme.muted)
                Text(granted ? "On" : "Off")
                    .font(mono(12))
                    .foregroundStyle(Theme.text)
            }
            Spacer()
            if !granted {
                plainButton("Allow") { action() }
            }
        }
    }

    private func row<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(title)
                .font(mono(12))
                .foregroundStyle(Theme.muted)
            Spacer()
            control()
        }
    }

    private func plainButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(mono(12))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(lineWidth: 1)
                    .foregroundStyle(Theme.line)
            )
    }

    private func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
#endif
