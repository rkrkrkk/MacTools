import AppKit
import SwiftUI

struct MenuBarContent: View {
    private struct DeferredPanelSwitchAction {
        let pluginID: String
        let isOn: Bool
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    @ObservedObject var pluginHost: PluginHost
    @State private var deferredPanelSwitchAction: DeferredPanelSwitchAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 8) {
                ForEach(pluginHost.panelItems) { item in
                    FeatureRowView(
                        item: item,
                        isOn: Binding(
                            get: { pluginHost.isSwitchOn(for: item.id) },
                            set: { newValue in
                                handlePanelSwitchChange(newValue, for: item)
                            }
                        )
                    )
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )

            Divider()
                .padding(.horizontal, 2)

            VStack(spacing: 0) {
                Button {
                    presentSettings()
                } label: {
                    MenuActionRowLabel(title: "设置", systemImage: "gearshape")
                }
                .buttonStyle(.plain)

                Divider()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    MenuActionRowLabel(title: "退出", systemImage: "power", bottomPadding: 0)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onReceive(pluginHost.$settingsPresentationRequestCount.dropFirst()) { _ in
            presentSettings()
        }
        .onDisappear {
            flushDeferredPanelSwitchActionIfNeeded()
        }
    }

    private func presentSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "settings")
        dismiss()
    }

    private func handlePanelSwitchChange(_ newValue: Bool, for item: PluginPanelItem) {
        switch item.menuActionBehavior {
        case .keepPresented:
            pluginHost.setSwitchValue(newValue, for: item.id)
        case .dismissBeforeHandling:
            deferredPanelSwitchAction = DeferredPanelSwitchAction(
                pluginID: item.id,
                isOn: newValue
            )
            dismiss()
        }
    }

    private func flushDeferredPanelSwitchActionIfNeeded() {
        guard let deferredPanelSwitchAction else {
            return
        }

        self.deferredPanelSwitchAction = nil
        pluginHost.setSwitchValue(
            deferredPanelSwitchAction.isOn,
            for: deferredPanelSwitchAction.pluginID
        )
    }
}

struct FeatureRowView: View {
    let item: PluginPanelItem
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(item.iconTint.opacity(0.14))

                Image(systemName: item.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(item.iconTint)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Text(item.description)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(item.helpText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            switch item.controlStyle {
            case .switch:
                Toggle(String(), isOn: $isOn)
                    .labelsHidden()
                    .controlSize(.small)
                    .toggleStyle(.switch)
                    .disabled(!item.isEnabled)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.white.opacity(0.001))
        )
        .contentShape(Rectangle())
        .help(item.helpText)
    }
}

private struct MenuActionRowLabel: View {
    let title: String
    let systemImage: String
    var topPadding: CGFloat = 10
    var bottomPadding: CGFloat = 10

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .contentShape(Rectangle())
    }
}
