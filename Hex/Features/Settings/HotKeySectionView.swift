import ComposableArchitecture
import HexCore
import Inject
import SwiftUI

struct HotKeySectionView: View {
    @ObserveInjection var inject
    @Bindable var store: StoreOf<SettingsFeature>

    var body: some View {
        Section("Hot Key") {
            VStack(spacing: 12) {
                ForEach(Array(store.hexSettings.hotkeys.enumerated()), id: \.offset) { index, hotKey in
                    hotKeyRow(index: index, hotKey: hotKey)
                }

                if store.isAddingHotKey {
                    HStack(spacing: 8) {
                        HotKeyView(modifiers: store.currentModifiers, key: nil, isActive: true)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                store.send(.cancelSettingHotKey)
                            }
                    }
                } else if !store.isSettingHotKey {
                    Button {
                        store.send(.addHotKey)
                    } label: {
                        Label("Add Hot Key", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            let hasKeyBasedHotKey = store.hexSettings.hotkeys.contains { $0.key != nil }
            let hasModifierOnlyHotKey = store.hexSettings.hotkeys.contains { $0.key == nil && !$0.modifiers.isEmpty }

            Label {
                Toggle(
                    "Enable double-tap lock",
                    isOn: Binding(
                        get: { store.hexSettings.doubleTapLockEnabled },
                        set: { store.send(.setDoubleTapLockEnabled($0)) }
                    )
                )
            } icon: {
                Image(systemName: "hand.tap")
            }

            // Double-tap only mode applies to key+modifier combinations.
            if hasKeyBasedHotKey {
                Label {
                    Toggle(
                        "Use double-tap only",
                        isOn: Binding(
                            get: { store.hexSettings.useDoubleTapOnly },
                            set: { store.send(.setUseDoubleTapOnly($0)) }
                        )
                    )
                        .disabled(!store.hexSettings.doubleTapLockEnabled)
                } icon: {
                    Image(systemName: "hand.tap.fill")
                }
            }

            // Minimum key time (for modifier-only shortcuts)
            if hasModifierOnlyHotKey {
                Label {
                    Slider(
                        value: Binding(
                            get: { store.hexSettings.minimumKeyTime },
                            set: { store.send(.setMinimumKeyTime($0)) }
                        ),
                        in: 0.0 ... 2.0,
                        step: 0.1
                    ) {
                        Text("Ignore below \(store.hexSettings.minimumKeyTime, specifier: "%.1f")s")
                    }
                } icon: {
                    Image(systemName: "clock")
                }
            }
        }
        .enableInjection()
    }

    @ViewBuilder
    private func hotKeyRow(index: Int, hotKey: HotKey) -> some View {
        let isCapturingThis = store.isSettingHotKey && !store.isAddingHotKey && store.settingHotKeyIndex == index
        let key = isCapturingThis ? nil : hotKey.key
        let modifiers = isCapturingThis ? store.currentModifiers : hotKey.modifiers

        VStack(spacing: 12) {
            HStack(spacing: 8) {
                HotKeyView(modifiers: modifiers, key: key, isActive: isCapturingThis)
                    .animation(.spring(), value: key)
                    .animation(.spring(), value: modifiers)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.send(.startSettingHotKey(index: index))
                    }

                if store.hexSettings.hotkeys.count > 1, !isCapturingThis {
                    Button(role: .destructive) {
                        store.send(.removeHotKey(index))
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove hot key")
                }
            }

            if !store.isSettingHotKey,
               hotKey.key == nil,
               !hotKey.modifiers.isEmpty {
                ModifierSideControls(
                    modifiers: hotKey.modifiers,
                    onSelect: { kind, side in
                        store.send(.setModifierSide(index: index, kind: kind, side: side))
                    }
                )
                .transition(.opacity)
            }
        }
    }
}

private struct ModifierSideControls: View {
    @ObserveInjection var inject
    var modifiers: Modifiers
    var onSelect: (Modifier.Kind, Modifier.Side) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(modifiers.kinds, id: \.self) { kind in
                if kind.supportsSideSelection {
                    let binding = Binding<Modifier.Side>(
                        get: { modifiers.side(for: kind) ?? .either },
                        set: { onSelect(kind, $0) }
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(kind.symbol) \(kind.displayName)")
                            .settingsCaption()

                        Picker("Modifier side", selection: binding) {
                            ForEach(Modifier.Side.allCases, id: \.self) { side in
                                Text(side.displayName)
                                    .tag(side)
                                    .disabled(!kind.supportsSideSelection && side != .either)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
        }
        .enableInjection()
    }
}
