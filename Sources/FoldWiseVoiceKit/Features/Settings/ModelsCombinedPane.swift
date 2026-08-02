import AppKit
import SwiftUI

struct ModelsWorkspaceProjectionInput {
    let asrSnapshot: ASRModelLifecycleSnapshot?
    let asrFailures: ModelsASRFailures
    let polishState: ModelsPolishState
    let modes: [Mode]
    let inspectedID: ModelsRowID?
    let previousPolishRowIDs: [ModelsRowID]
}

typealias ModelsWorkspaceProjector =
    (ModelsWorkspaceProjectionInput) -> ModelsWorkspaceProjection

struct ModelsCombinedPane: View {
    let interface: ModelsPaneInterface
    private let project: ModelsWorkspaceProjector
    @State private var inspectedID: ModelsRowID?
    @State private var pendingDestructiveAction: ModelsDestructiveAction?
    @State private var previousPolishRowIDs: [ModelsRowID] = []
    @State private var inspectionOrigin: ModelsInspectionOrigin = .keyboard
    @FocusState private var focusedControl: ModelsFocusTarget?
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    init(
        interface: ModelsPaneInterface,
        project: @escaping ModelsWorkspaceProjector = { input in
            ModelsWorkspaceProjection.make(
                asrSnapshot: input.asrSnapshot,
                asrFailures: input.asrFailures,
                polishState: input.polishState,
                modes: input.modes,
                inspectedID: input.inspectedID,
                previousPolishRowIDs: input.previousPolishRowIDs
            )
        }
    ) {
        self.interface = interface
        self.project = project
    }

    private var projection: ModelsWorkspaceProjection {
        project(ModelsWorkspaceProjectionInput(
            asrSnapshot: interface.asrSnapshot,
            asrFailures: interface.asrFailures,
            polishState: interface.polishState,
            modes: interface.modes,
            inspectedID: interface.requestedPolishInspection.map(ModelsRowID.polish)
                ?? inspectedID,
            previousPolishRowIDs: previousPolishRowIDs
        ))
    }

    var body: some View {
        let presentation = projection
        VStack(spacing: 0) {
            header
            EmberHairline(axis: .horizontal)
            ModelsNativeSplit(
                leading: ledger(presentation),
                trailing: inspector(presentation.inspector)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
        .onAppear { reconcileInspection(with: presentation) }
        .onChange(of: presentation) { _, updated in
            reconcileInspection(with: updated)
        }
        .onChange(of: focusedControl) { previous, current in
            inspectionOrigin = .afterFocusMove(
                from: previous,
                to: current,
                existing: inspectionOrigin
            )
        }
        .onChange(of: interface.requestedPolishInspection) { _, current in
            // A Mode deep-linking into the ledger moves the inspection for the
            // user, so the row it names still has to be scrolled into view.
            if current != nil {
                inspectionOrigin = .keyboard
            }
        }
        .onChange(of: interface.asrSnapshot) { previous, current in
            applyASRFocusTransition(from: previous, to: current)
            announceASRTransition(from: previous, to: current)
        }
        .onChange(of: interface.polishState) { previous, current in
            applyPolishFocusTransition(from: previous, to: current)
            announce(
                ModelsPolishAnnouncementTransition.resolve(from: previous, to: current)
            )
        }
        .alert(
            pendingDestructiveAction?.confirmationTitle ?? "Remove model?",
            isPresented: Binding(
                get: { pendingDestructiveAction != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDestructiveAction = nil
                    }
                }
            ),
            presenting: pendingDestructiveAction
        ) { action in
            Button(action.confirmationButtonTitle, role: .destructive) {
                perform(action)
            }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text(action.confirmationMessage)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Models")
                .font(Theme.display)
                .tracking(Theme.displayTracking)
                .foregroundStyle(Theme.textPrimary)
            Text("Compare what runs each Stage, then manage its local data.")
                .font(Theme.ui(12))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, destinationPadding)
        .padding(.top, destinationPadding)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var destinationPadding: CGFloat {
        ThemeLayoutPolicy.destinationPadding(windowWidth: interface.windowWidth)
    }

    private func ledger(_ presentation: ModelsWorkspaceProjection) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(presentation.sections, id: \.id) { section in
                        familySection(section, inspectedID: presentation.inspector?.id)
                    }
                }
                .padding(18)
            }
            .background(Theme.canvas)
            .focusable(!presentation.ledgerRowIDs.isEmpty)
            .focusEffectDisabled()
            .focused(
                $focusedControl,
                equals: presentation.inspector.map { .ledgerInspection($0.id) } ?? .ledger
            )
            .onMoveCommand { direction in
                moveInspection(direction, in: presentation, scrollProxy: scrollProxy)
            }
            .onChange(of: presentation.inspector?.id) { previous, current in
                guard previous != current, let current else { return }
                // A click lands on a row the user can already see, so centring
                // it just yanks the ledger out from under the pointer — and
                // once the row sits past the halfway mark the centre clamps to
                // the very bottom of the list. Only an inspection the app moved
                // on its own has to be brought into view.
                guard inspectionOrigin != .pointer else { return }
                scrollProxy.scrollTo(current, anchor: .center)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Models comparison ledger")
            .accessibilityValue(presentation.inspector?.name ?? "No model selected")
        }
    }

    private func showsFocusRing(for id: ModelsRowID) -> Bool {
        inspectionOrigin.showsFocusRing(for: id, focus: focusedControl)
    }

    private func familySection(
        _ section: ModelsFamilyPresentation,
        inspectedID: ModelsRowID?
    ) -> some View {
        VStack(alignment: .leading, spacing: ModelsLedgerRowMetrics.interRowSpacing) {
            familyHeading(section)
            columnHeaders
            if let notice = section.recoveryNotice {
                EmberSurface(level: .raised) {
                    Label(
                        notice.message,
                        systemImage: "arrow.trianglehead.2.clockwise.rotate.90"
                    )
                    .font(Theme.ui(10.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let placeholder = section.placeholder {
                familyPlaceholder(
                    placeholder,
                    family: section.id,
                    isInspected: inspectedID == .polishPlaceholder,
                    isKeyboardFocused: showsFocusRing(for: .polishPlaceholder)
                )
            }
            ForEach(section.rows, id: \.id) { row in
                ledgerRow(
                    row,
                    isInspected: row.id == inspectedID,
                    isKeyboardFocused: showsFocusRing(for: row.id)
                )
            }
        }
    }

    private func familyPlaceholder(
        _ placeholder: ModelsFamilyPlaceholder,
        family: ModelsFamilyID,
        isInspected: Bool,
        isKeyboardFocused: Bool
    ) -> some View {
        Button {
            if family == .polish {
                inspectionOrigin = .pointer
                inspectedID = .polishPlaceholder
            }
        } label: {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .opacity(placeholder.showsProgress ? 1 : 0)
                Text(placeholder.text)
                    .font(Theme.ui(11))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, ModelsLedgerRowMetrics.horizontalInset)
            .frame(minHeight: 42)
            .background {
                ModelsTraceRowChrome(
                    isInspected: isInspected,
                    isHighlighted: isInspected,
                    isKeyboardFocused: isKeyboardFocused,
                    increaseContrast: usesStrongBoundary
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(EmberPlainButtonStyle(cornerRadius: Theme.controlRadius))
        .focusable(false)
        .disabled(family != .polish || placeholder.showsProgress)
        .id(ModelsRowID.polishPlaceholder)
        .accessibilityLabel(placeholder.text)
    }

    private func familyHeading(_ section: ModelsFamilyPresentation) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: section.id == .speechRecognition ? "waveform" : "wand.and.stars")
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
            Text(section.title.uppercased())
                .font(Theme.sectionLabel)
                .tracking(Theme.sectionTracking)
                .foregroundStyle(Theme.textTertiary)
            Text("—")
                .font(Theme.ui(9.5, .medium))
                .foregroundStyle(Theme.textTertiary)
            Text(section.semanticLabel)
                .font(Theme.ui(9.5, .medium))
                .foregroundStyle(
                    section.id == .speechRecognition
                        ? AnyShapeStyle(Theme.accent)
                        : AnyShapeStyle(Theme.textSecondary)
                )
            Spacer()
        }
        .padding(.leading, 4)
    }

    private var columnHeaders: some View {
        HStack(spacing: 8) {
            Text("MODEL / FIT").frame(maxWidth: .infinity, alignment: .leading)
            Text("SIZE").frame(width: 42, alignment: .trailing)
            Text("SPEED").frame(width: 42, alignment: .center)
            Text("QUALITY").frame(width: 42, alignment: .center)
            Text("STATE").frame(width: 64, alignment: .trailing)
        }
        .font(Theme.ui(8.5, .bold))
        .kerning(0.45)
        .foregroundStyle(Theme.textTertiary)
        .padding(.horizontal, 10)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .accessibilityHidden(true)
    }

    private func ledgerRow(
        _ row: ModelsRowPresentation,
        isInspected: Bool,
        isKeyboardFocused: Bool
    ) -> some View {
        let showsInlineCancel = row.progress?.allowsCancellation == true
        return HStack(spacing: 8) {
            Button {
                inspectionOrigin = .pointer
                inspectedID = row.id
            } label: {
                HStack(spacing: 8) {
                    if row.kind == .utility {
                        utilityLedgerRow(row)
                    } else {
                        modelLedgerRow(row, isHighlighted: isInspected)
                    }
                    if !showsInlineCancel {
                        ledgerState(row)
                    }
                }
                // The card's padding belongs to the button, not to the chrome
                // around it — otherwise the visible card is wider and taller
                // than the thing that answers a click.
                .padding(.leading, ModelsLedgerRowMetrics.horizontalInset)
                .padding(
                    .trailing,
                    showsInlineCancel ? 0 : ModelsLedgerRowMetrics.horizontalInset
                )
                .padding(.vertical, ModelsLedgerRowMetrics.verticalInset)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(EmberPlainButtonStyle(cornerRadius: Theme.controlRadius))
            .focusable(false)
            .frame(maxWidth: .infinity)
            .help(row.accessibilityLabel)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.accessibilityLabel)
            .accessibilityValue(
                ModelsRowAccessibility.value(
                    isInspected: isInspected,
                    progressValue: row.progress?.accessibilityValue
                )
            )
            if showsInlineCancel {
                ledgerState(row)
                    .padding(.trailing, ModelsLedgerRowMetrics.horizontalInset)
                    .padding(.vertical, ModelsLedgerRowMetrics.verticalInset)
            }
        }
        .modelsLedgerRowChrome(
            isInspected: isInspected,
            isKeyboardFocused: isKeyboardFocused
        )
        .id(row.id)
    }

    private func modelLedgerRow(
        _ row: ModelsRowPresentation,
        isHighlighted: Bool
    ) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if row.isSavedASRSelection {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.accent)
                            .accessibilityHidden(true)
                    }
                    Text(row.name)
                        .font(Theme.ui(11.5, .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if row.isStreaming {
                        ModelsLiveChip()
                    }
                }
                Text(row.fit)
                    .font(Theme.ui(9))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.size)
                .font(Theme.compactData)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .frame(width: 42, alignment: .trailing)
            ModelsRatingMeter(rating: row.speed, isHighlighted: isHighlighted)
                .frame(width: 42, height: 14)
            ModelsRatingMeter(rating: row.quality, isHighlighted: isHighlighted)
                .frame(width: 42, height: 14)
        }
        .contentShape(Rectangle())
    }

    private func utilityLedgerRow(_ row: ModelsRowPresentation) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle")
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name)
                    .font(Theme.ui(11.5, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(row.fit)
                    .font(Theme.ui(9))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func ledgerState(_ row: ModelsRowPresentation) -> some View {
        if let progress = row.progress {
            if progress.allowsCancellation {
                Button { interface.cancelASROperation() } label: {
                    VStack(alignment: .trailing, spacing: 2) {
                        if let fraction = progress.fraction {
                            ProgressView(value: fraction)
                                .frame(width: 64)
                            Text("\(Int(fraction * 100))% · Cancel")
                        } else {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .controlSize(.mini)
                                Text("Cancel")
                            }
                        }
                    }
                    .font(Theme.compactData)
                    .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(EmberPlainButtonStyle())
                .frame(width: 64, alignment: .trailing)
                .focused($focusedControl, equals: .inlineCancel(row.id))
                .help("Cancel \(progress.label.lowercased())")
                .accessibilityLabel("Cancel \(progress.label.lowercased()) for \(row.name)")
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    if let fraction = progress.fraction {
                        ProgressView(value: fraction)
                            .frame(width: 64)
                    } else {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    Text(progress.compactState)
                }
                .frame(width: 64, alignment: .trailing)
                .accessibilityHidden(true)
                .font(Theme.compactData)
                .foregroundStyle(Theme.textSecondary)
            }
        } else if !row.state.isEmpty {
            Text(row.state)
                .font(Theme.compactData)
                .foregroundStyle(
                    row.isSavedASRSelection
                        ? AnyShapeStyle(Theme.accent)
                        : AnyShapeStyle(Theme.textSecondary)
                )
                .lineLimit(1)
                .frame(width: 64, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    private func inspector(_ presentation: ModelsInspectorPresentation?) -> some View {
        ScrollView {
            if let presentation {
                inspectorBody(presentation)
            } else {
                neutralInspector
            }
        }
        .background(Theme.surface)
    }

    private func inspectorBody(_ presentation: ModelsInspectorPresentation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ModelsTraceInspectorHeader(isInspected: true) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(presentation.familyLabel.uppercased())
                        .font(Theme.sectionLabel)
                        .tracking(Theme.sectionTracking)
                        .foregroundStyle(Theme.textTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(presentation.name)
                            .font(Theme.ui(19, .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if presentation.isStreaming {
                            ModelsLiveChip()
                        }
                    }
                    Text(presentation.fit)
                        .font(Theme.ui(11.5))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(
                            ModelsStreamingCopy.spokenFit(
                                presentation.fit,
                                isStreaming: presentation.isStreaming
                            )
                        )
                    Label(
                        presentation.status,
                        systemImage: presentation.primaryAction.statusSymbol
                    )
                    .font(Theme.compactData)
                    .foregroundStyle(Theme.textSecondary)
                    if let explanation = presentation.statusExplanation {
                        Text(explanation)
                            .font(Theme.ui(11))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 22) {
                if let description = presentation.description, !description.isEmpty {
                    Text(description)
                        .font(Theme.ui(12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if presentation.showsInstallByNameForm {
                    TextField(
                        "model:tag",
                        text: Binding(
                            get: { interface.customModel },
                            set: interface.setCustomModel
                        )
                    )
                    .font(Theme.data)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .emberControlSurface()
                    .disabled(presentation.inputDisabledReason != nil)
                    .help(
                        presentation.inputDisabledReason
                            ?? "Enter an Ollama model name in model:tag form"
                    )
                    .accessibilityLabel("Ollama model name")
                    .accessibilityHint(presentation.inputDisabledReason ?? "")
                }
                if let error = presentation.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.ui(11))
                        .foregroundStyle(Theme.error)
                        .fixedSize(horizontal: false, vertical: true)
                }
                inspectorManagement(presentation)
                VStack(alignment: .leading, spacing: 8) {
                    Text(presentation.semanticLabel.uppercased())
                        .font(Theme.sectionLabel)
                        .tracking(Theme.sectionTracking)
                        .foregroundStyle(Theme.textTertiary)
                    Text(presentation.familyExplanation)
                        .font(Theme.ui(11.5))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var neutralInspector: some View {
        ModelsTraceInspectorHeader(isInspected: false) {
            VStack(alignment: .leading, spacing: 8) {
                Text("MODEL DETAILS")
                    .font(Theme.sectionLabel)
                    .tracking(Theme.sectionTracking)
                    .foregroundStyle(Theme.textTertiary)
                Text("Checking local model information…")
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func inspectorManagement(_ presentation: ModelsInspectorPresentation) -> some View {
        HStack(spacing: 10) {
            if let progress = presentation.progress {
                inspectorProgress(progress, id: presentation.id)
            } else {
                primaryAction(
                    presentation.primaryAction,
                    id: presentation.id,
                    disabledReason: presentation.managementDisabledReason
                )
            }
            Spacer()
            if presentation.progress == nil,
               let action = presentation.destructiveAction {
                destructiveMenu(
                    action,
                    id: presentation.id,
                    disabledReason: presentation.managementDisabledReason
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func inspectorProgress(
        _ progress: ModelsProgressPresentation,
        id: ModelsRowID?
    ) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                if let fraction = progress.fraction {
                    ProgressView(value: fraction)
                        .frame(width: 110)
                    Text("\(Int(fraction * 100))% — \(progress.status)")
                } else {
                    ProgressView()
                        .controlSize(.small)
                    Text(progress.status)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(progress.label), \(progress.status)")
            .accessibilityValue(progress.accessibilityValue)
            if progress.allowsCancellation, let id {
                Button("Cancel") { interface.cancelASROperation() }
                    .buttonStyle(EmberButtonStyle(kind: .quiet))
                    .focused($focusedControl, equals: .inspectorCancel(id))
                    .accessibilityLabel("Cancel \(progress.label.lowercased())")
            }
        }
        .font(Theme.ui(10.5, .medium))
        .foregroundStyle(Theme.textSecondary)
    }

    @ViewBuilder
    private func primaryAction(
        _ action: ModelsPrimaryAction,
        id: ModelsRowID,
        disabledReason: String?
    ) -> some View {
        switch action {
        case .checking:
            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking…")
            }
            .font(Theme.ui(10.5, .medium))
            .foregroundStyle(Theme.textSecondary)
        case .selected:
            inspectorStatus(
                "Selected",
                systemImage: "checkmark.circle.fill",
                tint: Theme.accent,
                id: id
            )
        case let .selectASR(modelID):
            asrActionButton(
                "Select",
                modelID: modelID,
                help: "Select this ASR model",
                disabledReason: disabledReason
            ) { interface.selectASRModel(modelID) }
        case let .downloadASR(modelID):
            asrActionButton(
                "Download",
                modelID: modelID,
                help: "Download this ASR model",
                disabledReason: disabledReason
            ) { interface.downloadASRModel(modelID) }
        case let .downloadAgainASR(modelID):
            asrActionButton(
                "Download again",
                modelID: modelID,
                help: "Download this saved ASR model again",
                disabledReason: disabledReason
            ) { interface.downloadASRModel(modelID) }
        case .retryASRBootstrap:
            Button("Retry") { interface.retryASRBootstrap() }
                .buttonStyle(EmberButtonStyle(kind: .primary))
                .focused($focusedControl, equals: .inspectorPrimary(id))
        case .unsupportedASR:
            inspectorStatus(
                "Not supported on this Mac",
                systemImage: "slash.circle",
                tint: Theme.textSecondary,
                id: id
            )
        case .installed:
            inspectorStatus(
                "Installed",
                systemImage: "checkmark.circle",
                tint: Theme.textSecondary,
                id: id
            )
        case let .installPolish(name):
            Button("Install") { interface.installPolishModel(name) }
                .buttonStyle(EmberButtonStyle(kind: .primary))
                .disabled(disabledReason != nil)
                .help(disabledReason ?? "Install \(name)")
                .accessibilityHint(disabledReason ?? "")
                .focused($focusedControl, equals: .inspectorPrimary(id))
        case .installCustomPolish:
            Button("Install") { interface.installCustomPolishModel() }
                .buttonStyle(EmberButtonStyle(kind: .primary))
                .disabled(disabledReason != nil)
                .help(disabledReason ?? "Install the entered Ollama model")
                .accessibilityHint(disabledReason ?? "")
                .focused($focusedControl, equals: .inspectorPrimary(id))
        case .retryPolish:
            Button("Retry") { interface.refreshPolishModels() }
                .buttonStyle(EmberButtonStyle(kind: .primary))
                .focused($focusedControl, equals: .inspectorPrimary(id))
        }
    }

    /// The inspector's primary slot stays a focus stop even when the state it
    /// reports has no control to press — a finished download moves focus here,
    /// and the arrival has to be visible. Static text has nothing to press,
    /// though, so it refuses the pointer: `.focusable()` alone lets a click make
    /// a word first responder, and macOS then paints its own focus ring around
    /// it. Keyboard arrivals still show a ring, drawn the way every other
    /// control here draws one.
    private func inspectorStatus(
        _ title: String,
        systemImage: String,
        tint: Color,
        id: ModelsRowID
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(Theme.ui(10.5, .semibold))
            .foregroundStyle(tint)
            .focusable()
            .focused($focusedControl, equals: .inspectorPrimary(id))
            .focusEffectDisabled()
            .emberFocusRing(focusedControl == .inspectorPrimary(id))
            .allowsHitTesting(false)
    }

    private func asrActionButton(
        _ title: String,
        modelID: String,
        help: String,
        disabledReason: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(EmberButtonStyle(kind: .primary))
            .disabled(disabledReason != nil)
            .help(disabledReason ?? help)
            .accessibilityHint(disabledReason ?? "")
            .focused(
                $focusedControl,
                equals: .inspectorPrimary(.speechRecognition(modelID))
            )
    }

    private func destructiveMenu(
        _ action: ModelsDestructiveAction,
        id: ModelsRowID,
        disabledReason: String?
    ) -> some View {
        Menu {
            Button(action.menuTitle, role: .destructive) {
                pendingDestructiveAction = action
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(EmberPlainButtonStyle())
        .menuIndicator(.hidden)
        .controlSize(.small)
        .fixedSize()
        .disabled(disabledReason != nil)
        .help(disabledReason ?? action.menuTitle)
        .accessibilityLabel(action.accessibilityLabel)
        .accessibilityHint(disabledReason ?? "")
        .focused($focusedControl, equals: .inspectorDestructive(id))
    }

    private func reconcileInspection(with presentation: ModelsWorkspaceProjection) {
        let previousInspection = inspectedID
        if inspectedID != presentation.inspector?.id {
            inspectedID = presentation.inspector?.id
            if let previousInspection,
               focusedControl?.inspectedID == previousInspection,
               let updatedInspection = presentation.inspector?.id {
                DispatchQueue.main.async {
                    focusedControl = .inspectorPrimary(updatedInspection)
                }
            }
        }
        if let requested = interface.requestedPolishInspection,
           presentation.inspector?.id == .polish(requested) {
            interface.clearRequestedPolishInspection()
        }
        let currentPolishRowIDs = presentation.sections
            .first { $0.id == .polish }?.rows.map(\.id) ?? []
        if previousPolishRowIDs != currentPolishRowIDs {
            previousPolishRowIDs = currentPolishRowIDs
        }
    }

    private func moveInspection(
        _ direction: MoveCommandDirection,
        in presentation: ModelsWorkspaceProjection,
        scrollProxy: ScrollViewProxy
    ) {
        let navigationDirection: ModelsLedgerNavigation.Direction
        switch direction {
        case .up:
            navigationDirection = .up
        case .down:
            navigationDirection = .down
        case .left, .right:
            return
        @unknown default:
            return
        }
        let navigation = ModelsLedgerNavigation(
            rowIDs: presentation.ledgerRowIDs,
            inspectedID: presentation.inspector?.id
        )
        guard let nextID = navigation.move(navigationDirection) else { return }
        inspectionOrigin = .keyboard
        inspectedID = nextID
        focusedControl = .ledgerInspection(nextID)
        scrollProxy.scrollTo(nextID, anchor: .center)
    }

    private func applyASRFocusTransition(
        from previous: ASRModelLifecycleSnapshot?,
        to current: ASRModelLifecycleSnapshot?
    ) {
        guard let previous,
              let current,
              let currentInspection = projection.inspector?.id,
              let transition = ModelsASRFocusTransition.resolve(
                  from: previous,
                  to: current,
                  inspectedID: currentInspection
              )
        else { return }
        inspectionOrigin = .keyboard
        inspectedID = transition.inspectedID
        DispatchQueue.main.async {
            focusedControl = transition.target
        }
    }

    private func announceASRTransition(
        from previous: ASRModelLifecycleSnapshot?,
        to current: ASRModelLifecycleSnapshot?
    ) {
        guard let previous,
              let current,
              let message = ModelsASRAnnouncementTransition.resolve(
                  from: previous,
                  to: current
              )
        else { return }
        announce(message)
    }

    private func applyPolishFocusTransition(
        from previous: ModelsPolishState,
        to current: ModelsPolishState
    ) {
        guard let currentInspection = projection.inspector?.id,
              let transition = ModelsPolishFocusTransition.resolve(
                  from: previous,
                  to: current,
                  projection: projection,
                  inspectedID: currentInspection
              )
        else { return }
        inspectionOrigin = .keyboard
        inspectedID = transition.inspectedID
        DispatchQueue.main.async {
            focusedControl = transition.target
        }
    }

    private func announce(_ message: String?) {
        guard let message else { return }
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ]
        )
    }

    private func perform(_ action: ModelsDestructiveAction) {
        switch action.command {
        case let .deleteASR(id): interface.deleteASRModel(id)
        case let .uninstallPolish(name): interface.deletePolishModel(name)
        }
    }

    private var usesStrongBoundary: Bool {
        colorSchemeContrast == .increased
    }
}

private extension ModelsFocusTarget {
    var inspectedID: ModelsRowID? {
        switch self {
        case .ledger:
            nil
        case let .ledgerInspection(id), let .inlineCancel(id), let .inspectorCancel(id),
             let .inspectorPrimary(id), let .inspectorDestructive(id):
            id
        }
    }
}

struct ModelsTraceRowChrome: View {
    let isInspected: Bool
    let isHighlighted: Bool
    let isKeyboardFocused: Bool
    let increaseContrast: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.controlRadius)
            .fill(background)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.controlRadius)
                    .strokeBorder(
                        Theme.essentialBorderColor(increaseContrast: increaseContrast),
                        lineWidth: Theme.essentialBorderWidth(
                            increaseContrast: increaseContrast
                        )
                    )
            }
            .overlay(alignment: .leading) {
                EmberIngress(color: isInspected ? Theme.accent : .clear)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius))
            .emberInsetFocusRing(
                isKeyboardFocused,
                cornerRadius: Theme.controlRadius
            )
    }

    private var background: Color {
        if isInspected {
            return Theme.raised
        }
        return isHighlighted ? Theme.hover : Theme.surface
    }
}

enum ModelsRowAccessibility {
    static func value(isInspected: Bool, progressValue: String?) -> String {
        [isInspected ? "Inspected" : nil, progressValue]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

struct ModelsTraceInspectorHeader<Content: View>: View {
    let isInspected: Bool
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            EmberIngress(color: isInspected ? Theme.accent : .clear)
            content
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.raised)
        .overlay(alignment: .bottom) {
            EmberHairline(axis: .horizontal)
        }
    }
}

/// Geometry shared between a ledger row's card and the controls inside it.
///
/// The insets live on the row's own controls rather than on the card, so the
/// whole card — padding included — is a tap target. Anything that moves an
/// inset out to the card carves a dead band back out of the row.
enum ModelsLedgerRowMetrics {
    static let horizontalInset: CGFloat = 10
    static let verticalInset: CGFloat = 8
    /// The canvas gap between adjacent cards in a family stack.
    static let interRowSpacing: CGFloat = 7
}

private struct ModelsLedgerRowChrome: ViewModifier {
    let isInspected: Bool
    let isKeyboardFocused: Bool
    @State private var isHovered = false
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ModelsTraceRowChrome(
                    isInspected: isInspected,
                    isHighlighted: isHovered,
                    isKeyboardFocused: isKeyboardFocused,
                    increaseContrast: colorSchemeContrast == .increased
                )
            }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}

private extension View {
    func modelsLedgerRowChrome(
        isInspected: Bool,
        isKeyboardFocused: Bool
    ) -> some View {
        modifier(ModelsLedgerRowChrome(
            isInspected: isInspected,
            isKeyboardFocused: isKeyboardFocused
        ))
    }
}

private struct ModelsNativeSplit<Leading: View, Trailing: View>: NSViewControllerRepresentable {
    let leading: Leading
    let trailing: Trailing

    func makeNSViewController(context _: Context) -> NSSplitViewController {
        let controller = ModelsNativeSplitController.make(
            leading: leading,
            trailing: trailing
        )

        DispatchQueue.main.async { [weak controller] in
            guard let splitView = controller?.splitView else { return }
            let position = ModelsSplitGeometry.initialLedgerWidth(
                totalWidth: splitView.bounds.width,
                dividerWidth: splitView.dividerThickness
            )
            splitView.setPosition(position, ofDividerAt: 0)
        }
        return controller
    }

    func updateNSViewController(_ controller: NSSplitViewController, context _: Context) {
        guard controller.splitViewItems.count == 2,
              let leadingController = controller.splitViewItems[0].viewController
              as? NSHostingController<Leading>,
              let trailingController = controller.splitViewItems[1].viewController
              as? NSHostingController<Trailing>
        else { return }
        leadingController.rootView = leading
        trailingController.rootView = trailing
    }
}

@MainActor
enum ModelsNativeSplitController {
    static func make(
        leading: some View,
        trailing: some View
    ) -> NSSplitViewController {
        let controller = NSSplitViewController()
        controller.splitView.isVertical = true
        controller.splitView.dividerStyle = .thin

        let leadingItem = NSSplitViewItem(
            viewController: NSHostingController(rootView: leading)
        )
        leadingItem.minimumThickness = ModelsSplitGeometry.ledgerMinimum
        leadingItem.canCollapse = false
        controller.addSplitViewItem(leadingItem)

        let trailingItem = NSSplitViewItem(
            viewController: NSHostingController(rootView: trailing)
        )
        trailingItem.minimumThickness = ModelsSplitGeometry.inspectorMinimum
        trailingItem.canCollapse = false
        controller.addSplitViewItem(trailingItem)
        return controller
    }
}
