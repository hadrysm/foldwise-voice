import AppKit
import SwiftUI

struct PermissionRecoveryGuide: View {
    @ObservedObject var model: SettingsModel

    private var state: PermissionRecoveryWorkflow.State {
        model.permissionRecovery
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    Text("Restore FoldWise Voice permissions")
                        .font(Theme.display)
                        .tracking(Theme.displayTracking)
                        .foregroundStyle(Theme.textPrimary)
                }
                Text(
                    "A new signed app identity needs fresh macOS permission grants. "
                        + "Microphone and Accessibility restore full Dictation capability."
                )
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)

            EmberHairline(axis: .horizontal)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    permissionRow(
                        permission: .microphone,
                        title: "Microphone",
                        detail: "Records your voice while a Dictation session is active.",
                        status: microphoneStatus,
                        requestTitle: state.snapshot.microphone == .notDetermined
                            ? "Allow Microphone"
                            : nil
                    )
                    permissionRow(
                        permission: .accessibility,
                        title: "Accessibility",
                        detail: "Pastes completed text and enables global shortcuts.",
                        status: state.snapshot.accessibilityGranted ? "Granted" : "Missing",
                        requestTitle: state.snapshot.accessibilityGranted
                            ? nil
                            : "Request Access"
                    )

                    if !state.snapshot.accessibilityGranted {
                        VStack(alignment: .leading, spacing: 8) {
                            EmberSectionLabel(
                                "Prefer not to grant Accessibility?",
                                symbolName: "keyboard"
                            )
                            Text(
                                "Input Monitoring can restore global shortcuts only. "
                                    + "Completed text will stay on the clipboard for ⌘V."
                            )
                            .font(Theme.ui(10.5))
                            .foregroundStyle(Theme.textSecondary)
                            permissionRow(
                                permission: .inputMonitoring,
                                title: "Input Monitoring",
                                detail: "Optional clipboard-only shortcut fallback.",
                                status: state.snapshot.inputMonitoringGranted
                                    ? "Granted"
                                    : "Optional shortcut fallback",
                                requestTitle: state.snapshot.inputMonitoringGranted
                                    ? nil
                                    : "Request Access"
                            )
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(24)
            }

            EmberHairline(axis: .horizontal)

            HStack {
                Text("The guide closes automatically after full recovery.")
                    .font(Theme.ui(10.5))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Button("Not now") {
                    model.onDismissPermissionRecovery?()
                }
                .buttonStyle(EmberButtonStyle(kind: .quiet))
                .accessibilityIdentifier("permission-recovery.dismiss")
            }
            .padding(18)
        }
        .frame(width: 620, height: 560)
        .background(Theme.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("permission-recovery.guide")
    }

    private var microphoneStatus: String {
        switch state.snapshot.microphone {
        case .authorized:
            "Granted"
        case .notDetermined:
            "Not requested"
        case .denied, .restricted:
            "Missing"
        }
    }

    private func permissionRow(
        permission: PermissionKind,
        title: String,
        detail: String,
        status: String,
        requestTitle: String?
    ) -> some View {
        let identifier = identifierComponent(permission)
        let granted = state.snapshot.isGranted(permission)
        return EmberSurface(level: .raised) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: granted
                        ? "checkmark.circle.fill"
                        : "exclamationmark.triangle.fill")
                        .foregroundStyle(granted ? Theme.success : Theme.warning)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(Theme.ui(12.5, .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(detail)
                            .font(Theme.ui(10))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 12)
                    Text(status)
                        .font(Theme.compactData)
                        .foregroundStyle(granted ? Theme.success : Theme.warning)
                        .accessibilityIdentifier(
                            "permission-recovery.\(identifier).status"
                        )
                        .accessibilityValue(status)
                    if let requestTitle {
                        Button(requestTitle) {
                            model.onRequestPermission?(permission)
                        }
                        .buttonStyle(EmberButtonStyle(kind: .primary))
                        .accessibilityIdentifier(
                            "permission-recovery.\(identifier).request"
                        )
                    }
                    if !granted {
                        Button("Open Settings…") {
                            model.onOpenPermissionSettings?(permission)
                        }
                        .buttonStyle(EmberButtonStyle(kind: .quiet))
                        .accessibilityIdentifier(
                            "permission-recovery.\(identifier).settings"
                        )
                    }
                }
                if state.staleGuidance.contains(permission) {
                    Text(staleGuidance(for: permission))
                        .font(Theme.ui(10))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(
                            "permission-recovery.\(identifier).stale"
                        )
                }
            }
            .padding(14)
        }
        .accessibilityElement(children: .contain)
    }

    private func identifierComponent(_ permission: PermissionKind) -> String {
        switch permission {
        case .microphone:
            "microphone"
        case .accessibility:
            "accessibility"
        case .inputMonitoring:
            "input-monitoring"
        }
    }

    private func staleGuidance(for permission: PermissionKind) -> String {
        let pane = switch permission {
        case .microphone:
            "Microphone"
        case .accessibility:
            "Accessibility"
        case .inputMonitoring:
            "Input Monitoring"
        }
        return "Still missing? In \(pane), remove an enabled-looking old FoldWise "
            + "Voice row, add the installed app from Applications, and enable it again."
    }
}

struct SignalLedgerSection<Content: View>: View {
    let title: String
    let symbolName: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EmberSectionLabel(title, symbolName: symbolName)
                .padding(.leading, 4)
            EmberSurface {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SignalLedgerRow<Trailing: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.ui(12.5, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(Theme.ui(10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }
}

struct SignalLedgerDivider: View {
    var body: some View {
        EmberHairline(axis: .horizontal)
            .padding(.leading, 12)
    }
}

struct SignalLedgerFeedback: View {
    let kind: EmberStatusKind
    let title: String
    var detail: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        EmberStatusNotice(
            kind: kind,
            title: title,
            detail: detail,
            ingressWidth: Theme.selectionIngressWidth,
            actionTitle: actionTitle,
            action: action
        )
        .padding(.trailing, 10)
        .frame(minHeight: 44)
        .background(Theme.raised)
        .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius))
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }
}

struct Keycap: View {
    let text: String
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        Text(text)
            .font(Theme.mono(11.5, .semibold))
            .foregroundStyle(Theme.textPrimary)
            .frame(minWidth: 14)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.controlRadius)
                    .strokeBorder(
                        Theme.essentialBorderColor(increaseContrast: usesStrongBoundary),
                        lineWidth: Theme.essentialBorderWidth(
                            increaseContrast: usesStrongBoundary
                        )
                    )
            )
    }

    private var usesStrongBoundary: Bool {
        colorSchemeContrast == .increased
    }
}

struct RatingDots: View {
    let label: String
    let value: Int // of 5
    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(Theme.ui(10)).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 2.5) {
                ForEach(0 ..< 5, id: \.self) { i in
                    Circle()
                        .fill(i < value ? Theme.textSecondary : Theme.border)
                        .frame(width: 4.5, height: 4.5)
                }
            }
        }
    }
}
