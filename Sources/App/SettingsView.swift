import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var pluginHost: PluginHost
    @ObservedObject var appUpdater: AppUpdater
    @ObservedObject var menuBarIconSettings: MenuBarIconSettings

    var body: some View {
        TabView(selection: $pluginHost.selectedSettingsDestination) {
            GeneralSettingsView(
                pluginHost: pluginHost,
                menuBarIconSettings: menuBarIconSettings
            )
                .tag(SettingsDestination.general)
                .tabItem {
                    Label("通用", systemImage: "gearshape")
                }

            PluginConfigurationSettingsView(pluginHost: pluginHost)
                .tag(SettingsDestination.pluginConfiguration)
                .tabItem {
                    Label("功能", systemImage: "slider.horizontal.3")
                }

            AboutSettingsView(appUpdater: appUpdater)
                .tag(SettingsDestination.about)
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
        }
        .frame(minWidth: 720, maxWidth: .infinity, minHeight: 480, maxHeight: .infinity)
    }
}

private struct PermissionSettingsRow: View {
    let card: PluginPermissionCard
    let statusColor: Color
    let onAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: card.statusSystemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(card.title)
                        .font(.system(size: 12, weight: .semibold))

                    Text(card.statusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(statusColor)
                }

                Text(card.description)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let footnote = card.footnote {
                    Text(footnote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(card.buttonTitle, action: onAction)
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var pluginHost: PluginHost
    @ObservedObject var menuBarIconSettings: MenuBarIconSettings
    @AppStorage(AppAppearancePreference.userDefaultsKey) private var appearancePreferenceRawValue = AppAppearancePreference.system.rawValue

    var body: some View {
        Form {
            Section {
                AppearanceSettingsRow(selection: appearancePreferenceBinding)
            } header: {
                Text("外观")
            }

            Section {
                MenuBarIconSettingsView(iconSettings: menuBarIconSettings)
            } header: {
                Text("状态栏图标")
            }

            Section {
                FeatureManagementTableView(
                    items: pluginHost.featureManagementItems,
                    onVisibilityChange: { pluginID, isVisible in
                        pluginHost.setFeatureVisibility(isVisible, for: pluginID)
                    },
                    onMove: { pluginID, targetOffset in
                        pluginHost.moveFeatureManagementItem(id: pluginID, toOffset: targetOffset)
                    }
                )
                .frame(height: featureManagementListHeight)
            } header: {
                Text("功能列表")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            pluginHost.refreshAll()
        }
    }

    private var featureManagementListHeight: CGFloat {
        FeatureManagementTableView.preferredHeight(for: pluginHost.featureManagementItems.count)
    }

    private var appearancePreferenceBinding: Binding<AppAppearancePreference> {
        Binding {
            AppAppearancePreference(rawValue: appearancePreferenceRawValue) ?? .system
        } set: { preference in
            appearancePreferenceRawValue = preference.rawValue
            preference.apply()
        }
    }
}

private struct AppearanceSettingsRow: View {
    @Binding var selection: AppAppearancePreference

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))

                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text("应用外观")
                    .font(.system(size: 13, weight: .semibold))

                Text("自动跟随系统，也可以固定为深色或浅色。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker("外观", selection: $selection) {
                ForEach(AppAppearancePreference.allCases) { preference in
                    Text(preference.title)
                        .tag(preference)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
        }
        .frame(minHeight: 38)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .help("设置应用外观")
    }
}

private struct PluginConfigurationSettingsView: View {
    @ObservedObject var pluginHost: PluginHost

    var body: some View {
        HStack(spacing: 0) {
            PluginConfigurationSidebar(
                items: pluginHost.pluginConfigurationItems,
                selectedID: $pluginHost.selectedPluginConfigurationID
            )
            .frame(width: 210)

            Rectangle()
                .fill(SettingsStyle.separator)
                .frame(width: 1)

            PluginConfigurationDetailPane(
                pluginHost: pluginHost,
                item: selectedItem
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(SettingsStyle.windowBackground)
        .onAppear {
            pluginHost.refreshAll()
        }
    }

    private var selectedItem: PluginConfigurationItem? {
        guard let selectedID = pluginHost.selectedPluginConfigurationID else {
            return pluginHost.pluginConfigurationItems.first
        }

        return pluginHost.pluginConfigurationItems.first(where: { $0.id == selectedID })
            ?? pluginHost.pluginConfigurationItems.first
    }
}

private struct PluginConfigurationSidebar: View {
    let items: [PluginConfigurationItem]
    @Binding var selectedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(items) { item in
                        Button {
                            selectedID = item.id
                        } label: {
                            PluginConfigurationSidebarRow(
                                item: item,
                                isSelected: selectedID == item.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 14)
                .padding(.bottom, 14)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(SettingsStyle.sidebarBackground)
    }
}

private struct PluginConfigurationSidebarRow: View {
    let item: PluginConfigurationItem
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : item.iconTint)
                .frame(width: 18, height: 18)

            Text(item.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowBackground)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { isHovered = $0 }
        .help(item.title)
    }

    private var rowBackground: Color {
        if isSelected {
            return SettingsStyle.sidebarSelectionBackground
        }

        return isHovered ? SettingsStyle.sidebarHoverBackground : .clear
    }
}

private struct PluginConfigurationDetailPane: View {
    @ObservedObject var pluginHost: PluginHost
    let item: PluginConfigurationItem?

    var body: some View {
        Group {
            if let item {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        PluginConfigurationHeader(item: item)

                        if !item.settingsCards.isEmpty {
                            PluginSettingsCardSection(
                                pluginHost: pluginHost,
                                cards: item.settingsCards
                            )
                        }

                        if !item.permissionCards.isEmpty {
                            PluginPermissionCardSection(
                                pluginHost: pluginHost,
                                cards: item.permissionCards
                            )
                        }

                        if !item.shortcutItems.isEmpty {
                            PluginShortcutSection(pluginHost: pluginHost, items: item.shortcutItems)
                        }

                        if item.hasCustomConfiguration {
                            pluginHost.pluginConfigurationViewItem(for: item.pluginID).content
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(SettingsStyle.contentBackground)
            } else {
                ContentUnavailableView(
                    "暂无可配置功能",
                    systemImage: "slider.horizontal.3",
                    description: Text("当插件提供权限、快捷键或自定义设置后，会显示在这里。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(SettingsStyle.contentBackground)
    }
}

private struct PluginConfigurationHeader: View {
    let item: PluginConfigurationItem

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(item.iconTint.opacity(0.14))

                Image(systemName: item.iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(item.iconTint)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 20, weight: .semibold))

                Text(item.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 2)
    }
}

private struct PluginSettingsCardSection: View {
    @ObservedObject var pluginHost: PluginHost
    let cards: [PluginSettingsCard]

    var body: some View {
        PluginConfigurationSection(title: "设置", systemImage: "switch.2") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    PluginSettingsCardRow(
                        card: card,
                        statusColor: statusColor(for: card.statusTone),
                        onAction: {
                            if let actionID = card.actionID {
                                pluginHost.performSettingsAction(pluginID: card.pluginID, actionID: actionID)
                            }
                        }
                    )

                    if index < cards.count - 1 {
                        SettingsSectionDivider()
                    }
                }
            }
        }
    }
}

private struct PluginSettingsCardRow: View {
    let card: PluginSettingsCard
    let statusColor: Color
    let onAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.title)
                        .font(.system(size: 14, weight: .semibold))

                    Text(card.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Label {
                    Text(card.statusText)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: card.statusSystemImage)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(statusColor)
            }

            if let footnote = card.footnote {
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let buttonTitle = card.buttonTitle, card.actionID != nil {
                HStack {
                    Spacer()

                    Button(buttonTitle, action: onAction)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(16)
    }
}

private struct PluginPermissionCardSection: View {
    @ObservedObject var pluginHost: PluginHost
    let cards: [PluginPermissionCard]

    var body: some View {
        PluginConfigurationSection(title: "权限", systemImage: "lock.shield") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    PermissionSettingsRow(
                        card: card,
                        statusColor: statusColor(for: card.statusTone),
                        onAction: {
                            pluginHost.performPermissionAction(
                                pluginID: card.pluginID,
                                permissionID: card.permissionID
                            )
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    if index < cards.count - 1 {
                        SettingsSectionDivider()
                    }
                }
            }
        }
    }
}

private struct PluginShortcutSection: View {
    @ObservedObject var pluginHost: PluginHost
    let items: [ShortcutSettingsItem]

    var body: some View {
        PluginConfigurationSection(title: "快捷键", systemImage: "command") {
            VStack(alignment: .leading, spacing: 0) {
                ShortcutSettingsRowsView(pluginHost: pluginHost, items: items)
            }
        }
    }
}

private struct PluginConfigurationSection<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(SettingsStyle.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(SettingsStyle.cardBorder, lineWidth: 1)
                )
        }
    }
}

private struct SettingsSectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(SettingsStyle.separator)
            .frame(height: 1)
            .padding(.horizontal, 16)
    }
}

private func statusColor(for tone: PluginStatusTone) -> Color {
    switch tone {
    case .neutral:
        return .secondary
    case .positive:
        return .green
    case .caution:
        return .orange
    }
}

struct AboutSettingsView: View {
    @StateObject private var updateViewModel: AboutUpdateViewModel

    init(appUpdater: AppUpdater) {
        _updateViewModel = StateObject(
            wrappedValue: AboutUpdateViewModel(updater: appUpdater)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 28)

            AppIconPreview()

            Text(AppMetadata.appName)
                .font(.system(size: 22, weight: .bold))
                .padding(.top, 18)

            Text("版本 \(AppMetadata.versionDescription)")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            AboutUpdateCard(viewModel: updateViewModel)
                .padding(.top, 28)
                .frame(maxWidth: 420)

            Text(AppMetadata.aboutDescription)
                .font(.title3)
                .lineLimit(nil)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)
                .padding(.top, 28)

            VStack(spacing: 0) {
                Link(AppMetadata.repositoryDisplayName, destination: AppMetadata.repositoryURL)
                    .font(.title3)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 28)

            Spacer(minLength: 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 40)
        .padding(.vertical, 28)
    }
}

private struct AboutUpdateCard: View {
    private enum Layout {
        static let verticalSpacing: CGFloat = 12
        static let statusMinHeight: CGFloat = 16
    }

    @ObservedObject var viewModel: AboutUpdateViewModel

    var body: some View {
        VStack(spacing: Layout.verticalSpacing) {
            Button(viewModel.primaryButtonTitle) {
                Task {
                    await viewModel.performPrimaryAction()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isPrimaryButtonDisabled)

            Text(statusText ?? " ")
                .font(.footnote)
                .foregroundStyle(viewModel.statusColor)
                .lineLimit(nil)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: Layout.statusMinHeight, alignment: .top)
                .opacity(statusText == nil ? 0 : 1)
        }
        .frame(maxWidth: .infinity)
    }

    private var statusText: String? {
        switch viewModel.state {
        case .idle:
            return nil
        default:
            return viewModel.statusDetail ?? viewModel.statusHeadline
        }
    }
}

private struct AppIconPreview: View {
    var body: some View {
        Group {
            if let appIcon = AppMetadata.appIcon {
                Image(nsImage: appIcon)
                    .resizable()
            } else {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(12)
                    .foregroundStyle(.secondary)
                    .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
