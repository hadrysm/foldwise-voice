import AppKit
import SwiftUI

struct ModelsCombinedPane: View {
    @ObservedObject var model: SettingsModel
    @State private var inspectedID: ModelsRowID?
    @State private var pendingDestructiveAction: ModelsDestructiveAction?
    @State private var previousPolishRowIDs: [ModelsRowID] = []

    private var projection: ModelsWorkspaceProjection {
        ModelsWorkspaceProjection.make(
            asrSnapshot: model.asrSnapshot,
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
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(presentation.sections, id: \.id) { section in
                    familySection(section, inspectedID: presentation.inspector?.id)
                }
            }
            .padding(18)
        }
        .background(Theme.sidebarBackground.opacity(0.46))
    }

    private func familySection(
        _ section: ModelsFamilyPresentation,
        inspectedID: ModelsRowID?
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            familyHeading(section)
            columnHeaders
            if let placeholder = section.placeholder {
                familyPlaceholder(
                    placeholder,
                    family: section.id,
                    isInspected: inspectedID == .polishPlaceholder
                )
            }
            ForEach(section.rows, id: \.id) { row in
                ledgerRow(row, isInspected: row.id == inspectedID)
            }
        }
    }

    private func familyPlaceholder(
        _ placeholder: ModelsFamilyPlaceholder,
        family: ModelsFamilyID,
        isInspected: Bool
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
                    .strokeBorder(Theme.hairline)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(family != .polish || placeholder.showsProgress)
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
        isInspected: Bool
    ) -> some View {
        Button {
            inspectedID = row.id
        } label: {
            if row.kind == .utility {
                utilityLedgerRow(row, isInspected: isInspected)
            } else {
                modelLedgerRow(row, isInspected: isInspected)
            }
        }
        .buttonStyle(.plain)
        .help(row.accessibilityLabel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityAddTraits(isInspected ? .isSelected : [])
    }

    private func modelLedgerRow(
        _ row: ModelsRowPresentation,
        isInspected: Bool
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
            rating(row.speed)
            rating(row.quality)
            ledgerState(row)
        }
        .modelsLedgerRowChrome(isInspected: isInspected)
    }

    private func utilityLedgerRow(
        _ row: ModelsRowPresentation,
        isInspected: Bool
    ) -> some View {
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
            if row.progress != nil || !row.state.isEmpty {
                ledgerState(row)
            }
        }
        .modelsLedgerRowChrome(isInspected: isInspected)
    }

    @ViewBuilder
    private func ledgerState(_ row: ModelsRowPresentation) -> some View {
        if let progress = row.progress {
            VStack(alignment: .trailing, spacing: 2) {
                if let fraction = progress.fraction {
                    ProgressView(value: fraction)
                        .frame(width: 64)
                } else {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text(progress.compactState)
                    .font(Theme.ui(8.5, .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 64, alignment: .trailing)
        } else {
            Text(row.state)
                .font(Theme.ui(8.5, .semibold))
                .foregroundStyle(
                    row.isSavedASRSelection
                        ? AnyShapeStyle(Theme.accent)
                        : AnyShapeStyle(Theme.textSecondary)
                )
                .lineLimit(1)
                .frame(width: 64, alignment: .trailing)
        }
    }

    private func rating(_ rating: ModelsRating) -> some View {
        Text(rating.displayText)
            .font(Theme.ui(9.5, .medium))
            .foregroundStyle(
                rating == .notRated
                    ? AnyShapeStyle(Theme.textTertiary)
                    : AnyShapeStyle(Theme.textSecondary)
            )
            .frame(width: 42, alignment: .center)
            .accessibilityLabel(rating.accessibilityText)
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
                inspectorProgress(progress)
            } else if let presentation {
                primaryAction(
                    presentation.primaryAction,
                    disabledReason: presentation.managementDisabledReason
                )
            }
            Spacer()
            if presentation?.progress == nil,
               let action = presentation?.destructiveAction {
                destructiveMenu(
                    action,
                    disabledReason: presentation?.managementDisabledReason
                )
            }
        }
        .padding(.horizontal, 26)
        .frame(minHeight: 58)
        .background(Theme.windowBackground)
    }

    private func inspectorProgress(_ progress: ModelsProgressPresentation) -> some View {
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
        .font(Theme.ui(10.5, .medium))
        .foregroundStyle(Theme.textSecondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(progress.label), \(progress.status)")
    }

    @ViewBuilder
    private func primaryAction(
        _ action: ModelsPrimaryAction,
        disabledReason: String?
    ) -> some View {
        switch action {
        case .selected:
            Label("Selected", systemImage: "checkmark.circle.fill")
                .font(Theme.ui(10.5, .semibold))
                .foregroundStyle(Theme.accent)
        case let .selectASR(id):
            Button("Select") { model.onSelectASRModel?(id) }
                .buttonStyle(.borderedProminent)
        case let .downloadASR(id):
            Button("Download") { model.onDownloadASRModel?(id) }
                .buttonStyle(.borderedProminent)
        case .installed:
            Label("Installed", systemImage: "checkmark.circle")
                .font(Theme.ui(10.5, .semibold))
                .foregroundStyle(Theme.textSecondary)
        case let .installPolish(name):
            Button("Install") { model.onInstallModel?(name) }
                .buttonStyle(.borderedProminent)
                .disabled(disabledReason != nil)
                .help(disabledReason ?? "Install \(name)")
                .accessibilityHint(disabledReason ?? "")
        case .installCustomPolish:
            Button("Install") { model.onInstallCustomModel?() }
                .buttonStyle(.borderedProminent)
                .disabled(disabledReason != nil)
                .help(disabledReason ?? "Install the entered Ollama model")
                .accessibilityHint(disabledReason ?? "")
        case .retryPolish:
            Button("Retry") { model.onRefreshModels?() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func destructiveMenu(
        _ action: ModelsDestructiveAction,
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
    }

    private func reconcileInspection(with presentation: ModelsWorkspaceProjection) {
        if inspectedID != presentation.inspector?.id {
            inspectedID = presentation.inspector?.id
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

    private func perform(_ action: ModelsDestructiveAction) {
        switch action.command {
        case let .deleteASR(id): model.onDeleteASRModel?(id)
        case let .uninstallPolish(name): model.onDeleteModel?(name)
        }
    }
}

private extension View {
    func modelsLedgerRowChrome(isInspected: Bool) -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isInspected ? Theme.activeNavBackground : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(isInspected ? Theme.hairline : Color.clear)
            }
            .contentShape(Rectangle())
    }
}

private struct ModelsNativeSplit<Leading: View, Trailing: View>: NSViewControllerRepresentable {
    let leading: Leading
    let trailing: Trailing

    func makeNSViewController(context _: Context) -> NSSplitViewController {
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
