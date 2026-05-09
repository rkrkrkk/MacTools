import AppKit
import SwiftUI

struct MenuBarIconSettingsView: View {
    @ObservedObject var iconSettings: MenuBarIconSettings
    @State private var selectedAppearance: MenuBarIconAppearance = .light

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Picker("编辑外观", selection: $selectedAppearance) {
                ForEach(MenuBarIconAppearance.allCases) { appearance in
                    Text(appearance.title).tag(appearance)
                }
            }
            .pickerStyle(.segmented)

            HStack(alignment: .top, spacing: 18) {
                MenuBarIconPreviewPair(
                    lightImage: iconSettings.previewImage(for: .light),
                    darkImage: iconSettings.previewImage(for: .dark),
                    renderMode: iconSettings.renderMode,
                    selectedAppearance: selectedAppearance
                )
                .frame(width: 260)

                VStack(alignment: .leading, spacing: 12) {
                    MenuBarIconEditorControls(
                        iconSettings: iconSettings,
                        appearance: selectedAppearance
                    )

                    MenuBarIconBuiltInGrid(
                        iconSettings: iconSettings,
                        appearance: selectedAppearance
                    )

                    MenuBarIconRecentGrid(
                        iconSettings: iconSettings,
                        appearance: selectedAppearance
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let warningText = iconSettings.contrastReport(for: selectedAppearance).warningText {
                Label(warningText, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            if let errorMessage = iconSettings.lastErrorMessage {
                Label(errorMessage, systemImage: "xmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("状态栏图标")
                    .font(.system(size: 13, weight: .semibold))

                Text("为浅色和深色菜单栏分别设置图标，并调整缩放与位置。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("图标模式", selection: Binding(
                get: { iconSettings.renderMode },
                set: { iconSettings.renderMode = $0 }
            )) {
                ForEach(MenuBarIconRenderMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 184)

            Button {
                iconSettings.resetToDefault()
            } label: {
                Label("恢复默认", systemImage: "arrow.counterclockwise")
            }
            .disabled(!iconSettings.hasCustomIcon)
        }
    }
}

private struct MenuBarIconEditorControls: View {
    @ObservedObject var iconSettings: MenuBarIconSettings
    let appearance: MenuBarIconAppearance

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    selectImage()
                } label: {
                    Label("选择图片", systemImage: "photo.badge.plus")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    selectAnimation()
                } label: {
                    Label("选择动画", systemImage: "film")
                }
                .buttonStyle(.bordered)

                Text("动画仅支持轻量 GIF/MP4，会抽帧为低帧率循环图标。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Toggle("导入动画时自动扣除纯色背景", isOn: Binding(
                get: { iconSettings.backgroundRemovalOptions.isEnabled },
                set: { isEnabled in
                    var options = iconSettings.backgroundRemovalOptions
                    options.isEnabled = isEnabled
                    iconSettings.backgroundRemovalOptions = options
                }
            ))
            .font(.footnote)

            adjustmentSlider(
                title: "缩放",
                value: Binding(
                    get: { iconSettings.adjustment(for: appearance).scale },
                    set: { updateAdjustment(\.scale, value: $0) }
                ),
                range: 0.6...2
            )

            adjustmentSlider(
                title: "水平位置",
                value: Binding(
                    get: { iconSettings.adjustment(for: appearance).offsetX },
                    set: { updateAdjustment(\.offsetX, value: $0) }
                ),
                range: -8...8
            )

            adjustmentSlider(
                title: "垂直位置",
                value: Binding(
                    get: { iconSettings.adjustment(for: appearance).offsetY },
                    set: { updateAdjustment(\.offsetY, value: $0) }
                ),
                range: -8...8
            )

            Divider()

            animationSpeedControls
        }
    }

    private var animationSpeedControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("播放速度")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(width: 62, alignment: .leading)

                Picker("播放速度", selection: Binding(
                    get: { iconSettings.animationSpeedMode },
                    set: { iconSettings.animationSpeedMode = $0 }
                )) {
                    ForEach(MenuBarIconAnimationSpeedMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 180)

                Text(speedDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Text("倍率")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(width: 62, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { iconSettings.manualAnimationSpeedMultiplier },
                        set: { iconSettings.manualAnimationSpeedMultiplier = $0 }
                    ),
                    in: MenuBarIconAnimationSpeedPolicy.minimumMultiplier...MenuBarIconAnimationSpeedPolicy.maximumMultiplier
                )
                .disabled(iconSettings.animationSpeedMode != .manual)

                Text(String(format: "%.1fx", iconSettings.manualAnimationSpeedMultiplier))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .trailing)
            }
        }
    }

    private var speedDescription: String {
        switch iconSettings.animationSpeedMode {
        case .manual:
            return "固定倍率循环播放。"
        case .adaptiveSystemLoad:
            return "CPU、GPU、内存越高越快。"
        }
    }

    private func adjustmentSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)

            Slider(value: value, in: range)
        }
    }

    private func updateAdjustment(
        _ keyPath: WritableKeyPath<MenuBarIconAdjustment, Double>,
        value: Double
    ) {
        var adjustment = iconSettings.adjustment(for: appearance)
        adjustment[keyPath: keyPath] = value
        iconSettings.setAdjustment(adjustment, for: appearance)
    }

    private func selectImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = MenuBarIconProcessing.supportedImageContentTypes
        panel.message = "选择一张图片作为 MacTools 状态栏图标"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        iconSettings.importIcon(from: url, for: appearance)
    }

    private func selectAnimation() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = MenuBarIconProcessing.supportedAnimationContentTypes
        panel.message = "选择 5 MB 以内、画面简单的 GIF 或 MP4 动画"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        iconSettings.importAnimation(from: url, for: appearance)
    }
}

private struct MenuBarIconPreviewPair: View {
    let lightImage: NSImage
    let darkImage: NSImage
    let renderMode: MenuBarIconRenderMode
    let selectedAppearance: MenuBarIconAppearance

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("菜单栏预览")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                MenuBarIconPreviewStrip(
                    title: "浅色",
                    image: lightImage,
                    renderMode: renderMode,
                    backgroundColor: Color(nsColor: .windowBackgroundColor),
                    foregroundColor: .black,
                    isSelected: selectedAppearance == .light
                )

                MenuBarIconPreviewStrip(
                    title: "深色",
                    image: darkImage,
                    renderMode: renderMode,
                    backgroundColor: Color(red: 0.12, green: 0.12, blue: 0.13),
                    foregroundColor: .white,
                    isSelected: selectedAppearance == .dark
                )
            }
        }
    }
}

private struct MenuBarIconPreviewStrip: View {
    let title: String
    let image: NSImage
    let renderMode: MenuBarIconRenderMode
    let backgroundColor: Color
    let foregroundColor: Color
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Circle()
                    .fill(.yellow)
                    .frame(width: 8, height: 8)
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)

                Spacer()

                Image(nsImage: image)
                    .renderingMode(renderMode == .template ? .template : .original)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(foregroundColor)
                    .frame(width: 18, height: 18)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }
}

private struct MenuBarIconRecentGrid: View {
    @ObservedObject var iconSettings: MenuBarIconSettings
    let appearance: MenuBarIconAppearance

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近使用")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if iconSettings.recentItems.isEmpty {
                Text("上传图片后会显示在这里。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(46), spacing: 8), count: 6),
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(iconSettings.recentItems) { item in
                        Button {
                            iconSettings.useRecentIcon(item, for: appearance)
                        } label: {
                            ZStack(alignment: .bottomTrailing) {
                                Image(nsImage: iconSettings.previewImage(for: item))
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                                    .frame(width: 42, height: 42)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                                    )

                                if item.mediaKind == .animation {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 14, height: 14)
                                        .background(Color.accentColor)
                                        .clipShape(Circle())
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .help(item.displayName)
                    }
                }
            }
        }
    }
}

private struct MenuBarIconBuiltInGrid: View {
    @ObservedObject var iconSettings: MenuBarIconSettings
    let appearance: MenuBarIconAppearance

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("内置动画")
                .font(.footnote)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(76), spacing: 8), count: 4),
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(iconSettings.builtInAnimations) { animation in
                    Button {
                        iconSettings.useBuiltInAnimation(animation, for: appearance)
                    } label: {
                        VStack(spacing: 6) {
                            Image(nsImage: iconSettings.previewImage(for: animation))
                                .resizable()
                                .renderingMode(.template)
                                .scaledToFit()
                                .foregroundStyle(.primary)
                                .frame(width: 28, height: 18)
                                .frame(width: 54, height: 34)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                                )

                            Text(animation.displayName)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .frame(width: 76)
                    }
                    .buttonStyle(.plain)
                    .help("使用 \(animation.displayName)")
                }
            }
        }
    }
}
