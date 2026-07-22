import AppKit
import SwiftUI

struct ModelsCombinedPane: View {
    @ObservedObject var model: SettingsModel
    @State private var inspectedID: ModelsRowID?
    @State private var pendingDestructiveAction: ModelsDestructiveAction?
    @State private var previousPolishRowIDs: [ModelsRowID] = []
    @FocusState private var focusedControl: ModelsFocusTarget?

    private var projection: ModelsWorkspaceProjection {
        ModelsWorkspaceProjection.make(
            asrSnapshot: model.asrSnapshot,
            asrFailures: model.asrFailures,
            polishState: model.polishModelsState,
            modes: model.modes,
            inspectedID: model.requestedPolishInspection.map(ModelsRowID.polish) ?? inspectedID,
            previousPolishRowIDs: previousPolishRowIDs
        )
    }

    var body: some View {
        let presentation = projection
        VStack(spacing: 0) {
            header
            Divider()
            ModelsNativeSplit(
                leading: ledger(presentation),
                trailing: inspector(presentation.inspector)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.windowBackground)
        .onAppear { reconcileInspection(with: presentation) }
        .onChange(of: presentation) { _, updated in
            reconcileInspection(with: updated)
        }
        .onChange(of: model.asrSnapshot) { previous, current in
            applyASRFocusTransition(from: previous, to: current)
            announceASRTransition(from: previous, to: current)
        }
        .onChange(of: model.polishModelsState) { previous, current in
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
                .font(Theme.pageTitle)
                .kerning(-0.56)
                .foregroundStyle(Theme.textPrimary)
            Text("Compare what runs each stage, then manage its local data.")
                .font(Theme.ui(12))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, Theme.contentPadding)
        .padding(.top, Theme.contentPadding)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
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
            .background(Theme.sidebarBackground.opacity(0.46))
            .focusable(!presentation.ledgerRowIDs.isEmpty)
            .focused(
                $focusedControl,
                equals: presentation.inspector.map { .ledgerInspection($0.id) } ?? .ledger
            )
            .onMoveCommand { direction in
                moveInspection(direction, in: presentation, scrollProxy: scrollProxy)
            }
            .onChange(of: presentation.inspector?.id) { previous, current in
                guard previous != current, let current else { return }
                scrollProxy.scrollTo(current, anchor: .center)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Models comparison ledger")
            .accessibilityValue(presentation.inspector?.name ?? "No model selected")
        }
    }

    private func familySection(
        _ section: ModelsFamilyPresentation,
        inspectedID: ModelsRowID?
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            familyHeading(section)
            columnHeaders
            if let notice = section.recoveryNotice {
                Label(notice.message, systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(Theme.ui(10.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 7))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(Theme.hairline)
                    }
            }
            if let placeholder = section.placeholder {
                familyPlaceholder(
                    placeholder,
                    family: section.id,
                    isInspected: inspectedID == .polishPlaceholder,
                    isKeyboardFocused: focusedControl == .ledgerInspection(.polishPlaceholder)
                )
            }
            ForEach(section.rows, id: \.id) { row in
                ledgerRow(
                    row,
                    isInspected: row.id == inspectedID,
                    isKeyboardFocused: focusedControl == .ledgerInspection(row.id)
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
            .padding(.horizontal, 10)
            .frame(minHeight: 42)
            .background(
                isInspected ? Theme.activeNavBackground : Theme.cardBackground,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(
                        isKeyboardFocused ? Theme.accent : Theme.hairline,
                        lineWidth: isKeyboardFocused ? 2 : 1
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                .kerning(1.1)
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .frame(maxWidth: .infinity)
            .help(row.accessibilityLabel)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.accessibilityLabel)
            .accessibilityValue(row.progress?.accessibilityValue ?? "")
            .accessibilityAddTraits(isInspected ? .isSelected : [])
            if showsInlineCancel {
                ledgerState(row)
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
                }
                Text(row.fit)
                    .font(Theme.ui(9))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.size)
                .font(Theme.ui(9.5, .medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .frame(width: 42, alignment: .trailing)
            rating(row.speed, isHighlighted: isHighlighted)
            rating(row.quality, isHighlighted: isHighlighted)
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
                Button { model.onCancelASROperation?() } label: {
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
                    .font(Theme.ui(8.5, .semibold))
                    .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
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
                .font(Theme.ui(8.5, .semibold))
                .foregroundStyle(Theme.textSecondary)
            }
        } else if !row.state.isEmpty {
            Text(row.state)
                .font(Theme.ui(8.5, .semibold))
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

    private func rating(
        _ rating: ModelsRating,
        isHighlighted: Bool
    ) -> some View {
        Group {
            switch rating {
            case let .rated(value):
                let activeColor = isHighlighted ? Theme.accent : Theme.textSecondary
                HStack(spacing: 2) {
                    ForEach(1 ... 5, id: \.self) { mark in
                        Capsule()
                            .fill(mark <= value ? activeColor : Theme.hairline)
                            .frame(width: 5, height: 10)
                    }
                }
            case .notRated:
                Text("—")
                    .font(Theme.ui(9.5, .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(width: 42, height: 14, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rating.accessibilityText)
        .help(rating.accessibilityText)
    }

    private func inspector(_ presentation: ModelsInspectorPresentation?) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                if let presentation {
                    inspectorBody(presentation)
                } else {
                    neutralInspector
                }
            }
            Divider()
            inspectorFooter(presentation)
        }
        .background(Theme.windowBackground)
    }

    private func inspectorBody(_ presentation: ModelsInspectorPresentation) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text(presentation.familyLabel.uppercased())
                    .font(Theme.sectionLabel)
                    .kerning(1.1)
                    .foregroundStyle(Theme.textTertiary)
                Text(presentation.name)
                    .font(Theme.ui(19, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(presentation.fit)
                    .font(Theme.ui(11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Label(presentation.status, systemImage: presentation.primaryAction.statusSymbol)
                    .font(Theme.ui(10, .semibold))
                    .foregroundStyle(Theme.textSecondary)
                if let explanation = presentation.statusExplanation {
                    Text(explanation)
                        .font(Theme.ui(11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let description = presentation.description, !description.isEmpty {
                Text(description)
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if presentation.showsInstallByNameForm {
                TextField("model:tag", text: $model.customModel)
                    .textFieldStyle(.roundedBorder)
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
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(presentation.semanticLabel.uppercased())
                    .font(Theme.sectionLabel)
                    .kerning(1.1)
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

    private var neutralInspector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MODEL DETAILS")
                .font(Theme.sectionLabel)
                .kerning(1.1)
                .foregroundStyle(Theme.textTertiary)
            Text("Checking local model information…")
                .font(Theme.ui(12))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(26)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inspectorFooter(_ presentation: ModelsInspectorPresentation?) -> some View {
        HStack(spacing: 10) {
            if let progress = presentation?.progress {
                inspectorProgress(progress, id: presentation?.id)
            } else if let presentation {
                primaryAction(
                    presentation.primaryAction,
                    id: presentation.id,
                    disabledReason: presentation.managementDisabledReason
                )
            }
            Spacer()
            if let presentation,
               presentation.progress == nil,
               let action = presentation.destructiveAction {
                destructiveMenu(
                    action,
                    id: presentation.id,
                    disabledReason: presentation.managementDisabledReason
                )
            }
        }
        .padding(.horizontal, 26)
        .frame(minHeight: 58)
        .background(Theme.windowBackground)
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
                Button("Cancel") { model.onCancelASROperation?() }
                    .controlSize(.small)
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
            Label("Selected", systemImage: "checkmark.circle.fill")
                .font(Theme.ui(10.5, .semibold))
                .foregroundStyle(Theme.accent)
                .focusable()
                .focused($focusedControl, equals: .inspectorPrimary(id))
        case let .selectASR(modelID):
            asrActionButton(
                "Select",
                modelID: modelID,
                help: "Select this ASR model",
                disabledReason: disabledReason
            ) { model.onSelectASRModel?(modelID) }
        case let .downloadASR(modelID):
            asrActionButton(
                "Download",
                modelID: modelID,
                help: "Download this ASR model",
                disabledReason: disabledReason
            ) { model.onDownloadASRModel?(modelID) }
        case let .downloadAgainASR(modelID):
            asrActionButton(
                "Download again",
                modelID: modelID,
                help: "Download this saved ASR model again",
                disabledReason: disabledReason
            ) { model.onDownloadASRModel?(modelID) }
        case .retryASRBootstrap:
            Button("Retry") { model.onRetryASRBootstrap?() }
                .buttonStyle(.borderedProminent)
                .focused($focusedControl, equals: .inspectorPrimary(id))
        case .installed:
            Label("Installed", systemImage: "checkmark.circle")
                .font(Theme.ui(10.5, .semibold))
                .foregroundStyle(Theme.textSecondary)
                .focusable()
                .focused($focusedControl, equals: .inspectorPrimary(id))
        case let .installPolish(name):
            Button("Install") { model.onInstallModel?(name) }
                .buttonStyle(.borderedProminent)
                .disabled(disabledReason != nil)
                .help(disabledReason ?? "Install \(name)")
                .accessibilityHint(disabledReason ?? "")
                .focused($focusedControl, equals: .inspectorPrimary(id))
        case .installCustomPolish:
            Button("Install") { model.onInstallCustomModel?() }
                .buttonStyle(.borderedProminent)
                .disabled(disabledReason != nil)
                .help(disabledReason ?? "Install the entered Ollama model")
                .accessibilityHint(disabledReason ?? "")
                .focused($focusedControl, equals: .inspectorPrimary(id))
        case .retryPolish:
            Button("Retry") { model.onRefreshModels?() }
                .buttonStyle(.borderedProminent)
                .focused($focusedControl, equals: .inspectorPrimary(id))
        }
    }

    private func asrActionButton(
        _ title: String,
        modelID: String,
        help: String,
        disabledReason: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
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
        .buttonStyle(.plain)
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
        if let requested = model.requestedPolishInspection,
           presentation.inspector?.id == .polish(requested) {
            model.requestedPolishInspection = nil
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
        case let .deleteASR(id): model.onDeleteASRModel?(id)
        case let .uninstallPolish(name): model.onDeleteModel?(name)
        }
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

private extension View {
    func modelsLedgerRowChrome(
        isInspected: Bool,
        isKeyboardFocused: Bool
    ) -> some View {
        let borderColor: Color = if isKeyboardFocused {
            Theme.accent
        } else if isInspected {
            Theme.hairline
        } else {
            .clear
        }

        return padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isInspected ? Theme.activeNavBackground : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(
                        borderColor,
                        lineWidth: isKeyboardFocused ? 2 : 1
                    )
            }
            .contentShape(Rectangle())
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
