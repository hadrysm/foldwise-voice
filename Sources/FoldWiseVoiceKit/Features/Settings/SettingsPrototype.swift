#if DEBUG
    // PROTOTYPE — throw away after issue #151 resolves.
    // Three variants of Input and Appearance in the existing Settings pane,
    // switchable from a floating bar at the bottom of the app window.

    import AppKit
    import SwiftUI

    enum SettingsPrototypeEnvironment {
        static var isEnabled: Bool {
            ProcessInfo.processInfo.environment["FOLDWISE_SETTINGS_PROTOTYPE"] == "1"
        }
    }

    private enum SettingsPrototypeVariant: String, CaseIterable, Identifiable {
        case nativeRows = "A"
        case deviceRoster = "B"
        case currentChoice = "C"

        var id: String {
            rawValue
        }

        var name: String {
            switch self {
            case .nativeRows: "Native rows"
            case .deviceRoster: "Device roster"
            case .currentChoice: "Current choice"
            }
        }
    }

    private enum SettingsPrototypeScenario: String, CaseIterable, Identifiable {
        case systemDefault
        case connectedPreferred
        case disconnectedPreferred
        case restoredPreferred
        case deferredSwitch

        var id: String {
            rawValue
        }

        var name: String {
            switch self {
            case .systemDefault: "System Default"
            case .connectedPreferred: "Connected preferred"
            case .disconnectedPreferred: "Temporary fallback"
            case .restoredPreferred: "Preferred restored"
            case .deferredSwitch: "Deferred switch"
            }
        }
    }

    private enum PrototypeAppearance: String, CaseIterable, Identifiable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"

        var id: String {
            rawValue
        }

        var icon: String {
            switch self {
            case .system: "circle.lefthalf.filled"
            case .light: "sun.max"
            case .dark: "moon"
            }
        }
    }

    private struct PrototypeInputDevice: Identifiable, Equatable {
        let id: String
        let name: String
        let detail: String
        var isConnected: Bool

        static let system = PrototypeInputDevice(
            id: "system",
            name: "System Default",
            detail: "Studio Display Microphone",
            isConnected: true
        )
        static let studio = PrototypeInputDevice(
            id: "studio",
            name: "Studio Display Microphone",
            detail: "Connected",
            isConnected: true
        )
        static let macBook = PrototypeInputDevice(
            id: "macbook",
            name: "MacBook Pro Microphone",
            detail: "Connected",
            isConnected: true
        )
        static let shure = PrototypeInputDevice(
            id: "shure",
            name: "Shure MV7",
            detail: "USB",
            isConnected: true
        )
    }

    private struct SettingsPrototypeState {
        var preferredInputID = PrototypeInputDevice.system.id
        var activeInputID = PrototypeInputDevice.system.id
        var disconnectedInputIDs: Set<String> = []
        var pendingInputID: String?
        var isDictating = false
        var showsRestoredStatus = false
        var appearance: PrototypeAppearance = .system
        var simulatedSystemAppearance: ColorScheme = .light

        var devices: [PrototypeInputDevice] {
            [
                .system,
                .studio,
                .macBook,
                PrototypeInputDevice(
                    id: PrototypeInputDevice.shure.id,
                    name: PrototypeInputDevice.shure.name,
                    detail: disconnectedInputIDs.contains(PrototypeInputDevice.shure.id)
                        ? "Not connected"
                        : PrototypeInputDevice.shure.detail,
                    isConnected: !disconnectedInputIDs.contains(PrototypeInputDevice.shure.id)
                ),
            ]
        }

        var preferredDevice: PrototypeInputDevice {
            devices.first { $0.id == preferredInputID } ?? .system
        }

        var activeDevice: PrototypeInputDevice {
            devices.first { $0.id == activeInputID } ?? .system
        }

        var pendingDevice: PrototypeInputDevice? {
            guard let pendingInputID else { return nil }
            return devices.first { $0.id == pendingInputID }
        }

        var activeInputName: String {
            activeInputID == PrototypeInputDevice.system.id
                ? PrototypeInputDevice.system.detail
                : activeDevice.name
        }

        var effectiveColorScheme: ColorScheme {
            switch appearance {
            case .system: simulatedSystemAppearance
            case .light: .light
            case .dark: .dark
            }
        }

        var inputStatus: String? {
            if let pendingDevice {
                return "Using \(activeInputName) for this Dictation session. "
                    + "\(pendingDevice.name) will be used next."
            }
            if preferredInputID != PrototypeInputDevice.system.id,
               disconnectedInputIDs.contains(preferredInputID) {
                return "\(preferredDevice.name) is unavailable. Using the system default "
                    + "until it reconnects."
            }
            if showsRestoredStatus {
                return "Shure MV7 reconnected and is in use again."
            }
            return nil
        }

        mutating func apply(_ scenario: SettingsPrototypeScenario) {
            switch scenario {
            case .systemDefault:
                preferredInputID = PrototypeInputDevice.system.id
                activeInputID = PrototypeInputDevice.system.id
                disconnectedInputIDs = []
                pendingInputID = nil
                isDictating = false
                showsRestoredStatus = false
            case .connectedPreferred:
                preferredInputID = PrototypeInputDevice.shure.id
                activeInputID = PrototypeInputDevice.shure.id
                disconnectedInputIDs = []
                pendingInputID = nil
                isDictating = false
                showsRestoredStatus = false
            case .disconnectedPreferred:
                preferredInputID = PrototypeInputDevice.shure.id
                activeInputID = PrototypeInputDevice.system.id
                disconnectedInputIDs = [PrototypeInputDevice.shure.id]
                pendingInputID = nil
                isDictating = false
                showsRestoredStatus = false
            case .restoredPreferred:
                preferredInputID = PrototypeInputDevice.shure.id
                activeInputID = PrototypeInputDevice.shure.id
                disconnectedInputIDs = []
                pendingInputID = nil
                isDictating = false
                showsRestoredStatus = true
            case .deferredSwitch:
                preferredInputID = PrototypeInputDevice.macBook.id
                activeInputID = PrototypeInputDevice.studio.id
                disconnectedInputIDs = []
                pendingInputID = PrototypeInputDevice.macBook.id
                isDictating = true
                showsRestoredStatus = false
            }
        }

        mutating func selectInput(_ id: String) {
            preferredInputID = id
            showsRestoredStatus = false
            if isDictating {
                pendingInputID = id
            } else if disconnectedInputIDs.contains(id) {
                activeInputID = PrototypeInputDevice.system.id
                pendingInputID = nil
            } else {
                activeInputID = id
                pendingInputID = nil
            }
        }
    }

    struct SettingsPrototypeHost: View {
        @State private var variant: SettingsPrototypeVariant = .nativeRows
        @State private var scenario: SettingsPrototypeScenario = .systemDefault
        @State private var state = SettingsPrototypeState()
        @State private var keyMonitor: Any?

        var body: some View {
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Settings")
                                .font(Theme.pageTitle)
                                .kerning(-0.56)
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.bottom, 4)
                            variantView(contentWidth: geometry.size.width - Theme.contentPadding * 2)
                        }
                        .padding(.horizontal, Theme.contentPadding)
                        .padding(.top, Theme.contentPadding)
                        .padding(.bottom, 92)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    switcher
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                }
            }
            .background(Theme.windowBackground)
            .preferredColorScheme(state.effectiveColorScheme)
            .onChange(of: scenario) { _, scenario in
                state.apply(scenario)
            }
            .onAppear { installKeyMonitor() }
            .onDisappear { removeKeyMonitor() }
        }

        @ViewBuilder
        private func variantView(contentWidth: CGFloat) -> some View {
            switch variant {
            case .nativeRows:
                SettingsPrototypeNativeRows(state: $state, contentWidth: contentWidth)
            case .deviceRoster:
                SettingsPrototypeDeviceRoster(state: $state, contentWidth: contentWidth)
            case .currentChoice:
                SettingsPrototypeCurrentChoice(state: $state, contentWidth: contentWidth)
            }
        }

        private var switcher: some View {
            HStack(spacing: 10) {
                Button { cycleVariant(by: -1) } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Previous prototype variant")

                Text("\(variant.rawValue) — \(variant.name)")
                    .font(Theme.ui(12, .semibold))
                    .frame(minWidth: 126)

                Button { cycleVariant(by: 1) } label: {
                    Image(systemName: "chevron.right")
                }
                .accessibilityLabel("Next prototype variant")

                Divider().frame(height: 22)

                Picker("Scenario", selection: $scenario) {
                    ForEach(SettingsPrototypeScenario.allCases) { scenario in
                        Text(scenario.name).tag(scenario)
                    }
                }
                .labelsHidden()
                .frame(width: 154)
                .accessibilityLabel("Input scenario")

                Button {
                    state.simulatedSystemAppearance =
                        state.simulatedSystemAppearance == .light ? .dark : .light
                } label: {
                    Label(
                        state.simulatedSystemAppearance == .light ? "macOS Light" : "macOS Dark",
                        systemImage: state.simulatedSystemAppearance == .light ? "sun.max" : "moon"
                    )
                }
                .accessibilityLabel("Toggle simulated macOS appearance")
            }
            .buttonStyle(.borderless)
            .font(Theme.ui(12))
            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(
                Color(nsColor: .labelColor),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .shadow(color: .black.opacity(0.24), radius: 12, y: 4)
            .fixedSize()
        }

        private func cycleVariant(by offset: Int) {
            let variants = SettingsPrototypeVariant.allCases
            guard let index = variants.firstIndex(of: variant) else { return }
            variant = variants[(index + offset + variants.count) % variants.count]
        }

        private func installKeyMonitor() {
            guard keyMonitor == nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.window?.firstResponder is NSTextView
                    || event.window?.firstResponder is NSTextField {
                    return event
                }
                switch event.keyCode {
                case 123:
                    cycleVariant(by: -1)
                    return nil
                case 124:
                    cycleVariant(by: 1)
                    return nil
                default:
                    return event
                }
            }
        }

        private func removeKeyMonitor() {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
    }

    private struct SettingsPrototypeNativeRows: View {
        @Binding var state: SettingsPrototypeState
        let contentWidth: CGFloat

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("Keyboard shortcuts")
                placeholderKeyboardCard

                sectionHeader("Input")
                Card {
                    responsiveRow(
                        title: "Input device",
                        subtitle: inputSubtitle
                    ) {
                        inputPicker
                    }
                }
                if let status = state.inputStatus { PrototypeStatus(text: status) }

                sectionHeader("Sound")
                soundCard

                sectionHeader("Appearance")
                Card {
                    responsiveRow(
                        title: "Appearance",
                        subtitle: appearanceSubtitle
                    ) {
                        appearancePicker.frame(width: 210)
                    }
                }

                sectionHeader("Updates")
                updatesCard
                PrototypeFocusOrder(
                    items: ["Input device", "Pause other audio", "System", "Light", "Dark"]
                )
            }
        }

        private var inputSubtitle: String {
            state.preferredInputID == PrototypeInputDevice.system.id
                ? "Follows the microphone selected in macOS"
                : "FoldWise remembers this device if it disconnects"
        }

        private var appearanceSubtitle: String {
            state.appearance == .system
                ? "Follows the live macOS appearance"
                : "Overrides macOS across the main window and Badge"
        }

        private var inputPicker: some View {
            Picker(
                "Input device",
                selection: Binding(
                    get: { state.preferredInputID },
                    set: { state.selectInput($0) }
                )
            ) {
                ForEach(state.devices) { device in
                    Text(deviceLabel(device)).tag(device.id)
                }
            }
            .labelsHidden()
            .frame(width: 240)
        }

        private var appearancePicker: some View {
            Picker("Appearance", selection: $state.appearance) {
                ForEach(PrototypeAppearance.allCases) { appearance in
                    Text(appearance.rawValue).tag(appearance)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }

        @ViewBuilder
        private func responsiveRow(
            title: String,
            subtitle: String,
            @ViewBuilder trailing: () -> some View
        ) -> some View {
            if contentWidth < 650 {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(Theme.ui(13, .semibold)).foregroundStyle(Theme.textPrimary)
                        Text(subtitle).font(Theme.ui(11)).foregroundStyle(Theme.textSecondary)
                    }
                    trailing()
                }
                .padding(14)
            } else {
                CardRow(title: title, subtitle: subtitle) { trailing() }
            }
        }
    }

    private struct SettingsPrototypeDeviceRoster: View {
        @Binding var state: SettingsPrototypeState
        let contentWidth: CGFloat

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("Keyboard shortcuts")
                placeholderKeyboardCard

                sectionHeader("Input")
                Card {
                    ForEach(Array(state.devices.enumerated()), id: \.element.id) { index, device in
                        if index > 0 { Divider().padding(.leading, 14) }
                        deviceRow(device)
                    }
                }
                if let status = state.inputStatus { PrototypeStatus(text: status) }

                sectionHeader("Sound")
                soundCard

                sectionHeader("Appearance")
                if contentWidth < 650 {
                    VStack(spacing: 8) { appearanceChoices }
                } else {
                    HStack(spacing: 8) { appearanceChoices }
                }

                sectionHeader("Updates")
                updatesCard
                PrototypeFocusOrder(
                    items: [
                        "System Default", "Studio Display Microphone",
                        "MacBook Pro Microphone", "Shure MV7", "Pause other audio",
                        "System", "Light", "Dark",
                    ]
                )
            }
        }

        private func deviceRow(_ device: PrototypeInputDevice) -> some View {
            Button { state.selectInput(device.id) } label: {
                HStack(spacing: 12) {
                    Image(systemName: device.id == "system" ? "arrow.triangle.2.circlepath" : "mic")
                        .foregroundStyle(device.isConnected ? Theme.textSecondary : Theme.textFaint)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                            .font(Theme.ui(13, .semibold))
                            .foregroundStyle(device.isConnected ? Theme.textPrimary : Theme.textFaint)
                        Text(device.detail)
                            .font(Theme.ui(11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    if state.preferredInputID == device.id, !device.isConnected {
                        Text("Preferred")
                            .font(Theme.ui(10, .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    Image(systemName: state.preferredInputID == device.id ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(
                            state.preferredInputID == device.id
                                ? AnyShapeStyle(Theme.accent)
                                : AnyShapeStyle(Theme.textTertiary)
                        )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        private var appearanceChoices: some View {
            ForEach(PrototypeAppearance.allCases) { appearance in
                Button { state.appearance = appearance } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: appearance.icon)
                                .font(.system(size: 16, weight: .medium))
                            Spacer()
                            Image(
                                systemName: state.appearance == appearance
                                    ? "checkmark.circle.fill"
                                    : "circle"
                            )
                        }
                        Text(appearance.rawValue).font(Theme.ui(13, .semibold))
                        Text(appearanceDescription(appearance))
                            .font(Theme.ui(10.5))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
                    .background(
                        state.appearance == appearance
                            ? Theme.activeNavBackground
                            : Theme.cardBackground,
                        in: RoundedRectangle(cornerRadius: Theme.cardRadius)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cardRadius)
                            .strokeBorder(
                                state.appearance == appearance ? Theme.accent : Theme.hairline,
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private struct SettingsPrototypeCurrentChoice: View {
        @Binding var state: SettingsPrototypeState
        let contentWidth: CGFloat

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("Keyboard shortcuts")
                placeholderKeyboardCard

                sectionHeader("Input")
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 24, height: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Using \(state.activeInputName)")
                                    .font(Theme.ui(14, .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                preferredSummary
                            }
                            Spacer(minLength: 12)
                            inputMenu
                        }
                        if let status = state.inputStatus {
                            Divider()
                            Label(status, systemImage: inputStatusIcon)
                                .font(Theme.ui(11))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .padding(14)
                }

                sectionHeader("Sound")
                soundCard

                sectionHeader("Appearance")
                Card {
                    if contentWidth < 650 {
                        VStack(alignment: .leading, spacing: 12) {
                            appearanceSummary
                            appearanceMenu
                        }
                        .padding(14)
                    } else {
                        HStack(spacing: 16) {
                            appearanceSummary
                            Spacer()
                            appearanceMenu
                        }
                        .padding(14)
                    }
                }

                sectionHeader("Updates")
                updatesCard
                PrototypeFocusOrder(
                    items: ["Choose input device", "Pause other audio", "Choose appearance"]
                )
            }
        }

        private var preferredSummary: some View {
            Group {
                if state.preferredInputID == PrototypeInputDevice.system.id {
                    Text("Follows System Default")
                } else if state.activeInputID != state.preferredInputID {
                    Text("Preferred: \(state.preferredDevice.name)")
                } else {
                    Text("Preferred device")
                }
            }
            .font(Theme.ui(11))
            .foregroundStyle(Theme.textSecondary)
        }

        private var inputMenu: some View {
            Menu {
                ForEach(state.devices) { device in
                    Button {
                        state.selectInput(device.id)
                    } label: {
                        if state.preferredInputID == device.id {
                            Label(deviceLabel(device), systemImage: "checkmark")
                        } else {
                            Text(deviceLabel(device))
                        }
                    }
                }
            } label: {
                Text("Choose…")
            }
            .controlSize(.small)
            .accessibilityLabel("Choose input device")
        }

        private var appearanceSummary: some View {
            HStack(spacing: 12) {
                Image(systemName: state.appearance.icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(state.appearance.rawValue) appearance")
                        .font(Theme.ui(14, .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(appearanceDescription(state.appearance))
                        .font(Theme.ui(11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }

        private var appearanceMenu: some View {
            Picker("Appearance", selection: $state.appearance) {
                ForEach(PrototypeAppearance.allCases) { appearance in
                    Text(appearance.rawValue).tag(appearance)
                }
            }
            .labelsHidden()
            .frame(width: 120)
            .accessibilityLabel("Choose appearance")
        }

        private var inputStatusIcon: String {
            state.pendingInputID == nil ? "arrow.triangle.2.circlepath" : "clock"
        }
    }

    private struct PrototypeStatus: View {
        let text: String

        var body: some View {
            Label(text, systemImage: "info.circle.fill")
                .font(Theme.ui(11))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 4)
        }
    }

    private struct PrototypeFocusOrder: View {
        let items: [String]

        var body: some View {
            Text("Focus order: " + items.joined(separator: " → "))
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textFaint)
                .padding(.top, 2)
        }
    }

    private var placeholderKeyboardCard: some View {
        Card {
            CardRow(title: "Push to Talk", subtitle: "Hold to record, release when done") {
                Keycap(text: "right ⌥")
            }
            Divider().padding(.leading, 14)
            CardRow(title: "Toggle Recording", subtitle: "Starts and stops dictation") {
                Text("Click to set")
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var soundCard: some View {
        Card {
            CardRow(
                title: "Pause other audio",
                subtitle: "Pause music and mute system audio while dictating"
            ) {
                Toggle("", isOn: .constant(true))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
    }

    private var updatesCard: some View {
        Card {
            CardRow(title: "Updates", subtitle: "Version \(AppInfo.version)") {
                Button("Check for Updates") {}
                    .controlSize(.small)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func deviceLabel(_ device: PrototypeInputDevice) -> String {
        device.isConnected ? device.name : "\(device.name) — Not connected"
    }

    private func appearanceDescription(_ appearance: PrototypeAppearance) -> String {
        switch appearance {
        case .system: "Follows macOS as it changes"
        case .light: "Always uses the light appearance"
        case .dark: "Always uses the dark appearance"
        }
    }
#endif
