import SwiftUI
import AppKit

    public struct SettingsView: View {
        @State private var settings = AppSettings()
        @AppStorage("historyLayoutStyle") private var layoutStyleRaw: String = "horizontal"
        @AppStorage("appLanguage") private var appLanguage: String = "zh-Hans"
        @AppStorage("panelPositionVertical") private var panelPositionVertical: Double = 0
        @AppStorage("panelPositionHorizontal") private var panelPositionHorizontal: Double = 0
        @AppStorage("panelCornerRadius") private var panelCornerRadius: Double = 16
        @AppStorage("panelHorizontalWidthPercent") private var panelHorizontalWidthPercent: Double = 90
        @AppStorage("panelVerticalHeightPercent") private var panelVerticalHeightPercent: Double = 90
        @AppStorage("panelGridWidthPercent") private var panelGridWidthPercent: Double = 80
        @AppStorage("panelGridHeightPercent") private var panelGridHeightPercent: Double = 80
        private let settingsStore = SettingsStore()
        public init() {}
        public var body: some View {
        ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("settings.title"))
                .font(.system(size: 16, weight: .semibold))
            VStack(alignment: .leading, spacing: 8) {
                Text(L("settings.section.general"))
                    .font(.system(size: 13, weight: .medium))
                VStack(spacing: 6) {
                    HStack {
                        Text(L("settings.retentionDays"))
                            .font(.system(size: 13))
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        Stepper(value: $settings.historyRetentionDays, in: 1...365) {
                            Text("\(settings.historyRetentionDays)")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 120)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    HStack {
                        Text(L("settings.maxItems"))
                            .font(.system(size: 13))
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        Stepper(value: $settings.historyMaxItems, in: 50...500, step: 50) {
                            Text("\(settings.historyMaxItems)")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 120)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    HStack {
                        Text(L("settings.appearance"))
                            .font(.system(size: 13))
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        Picker("", selection: $settings.appearance) {
                            Text(L("appearance.system")).tag(AppearanceMode.system)
                            Text(L("appearance.light")).tag(AppearanceMode.light)
                            Text(L("appearance.dark")).tag(AppearanceMode.dark)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 190)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    HStack {
                        Text(L("settings.appLanguage"))
                            .font(.system(size: 13))
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        Picker("", selection: $appLanguage) {
                            Text(L("language.zh")).tag("zh-Hans")
                            Text(L("language.en")).tag("en")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 190)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    HStack {
                        Text(L("settings.defaultAction"))
                            .font(.system(size: 13))
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        Picker("", selection: $settings.defaultAction) {
                            Text(L("defaultAction.copy")).tag(DefaultAction.copy)
                            Text(L("defaultAction.paste")).tag(DefaultAction.paste)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 190)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    HStack {
                        Text(L("settings.defaultTextFormat"))
                            .font(.system(size: 13))
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        Picker("", selection: $settings.defaultTextFormat) {
                            Text(L("textFormat.plain")).tag(TextFormatMode.plainText)
                            Text(L("textFormat.formatted")).tag(TextFormatMode.preserveFormatting)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 190)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    HStack {
                        Text(L("settings.historyLayout"))
                            .font(.system(size: 13))
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        Picker("", selection: Binding(get: { HistoryLayoutStyle(rawValue: layoutStyleRaw) ?? .horizontal }, set: { layoutStyleRaw = $0.rawValue })) {
                            Text(L("settings.historyLayout.horizontal")).tag(HistoryLayoutStyle.horizontal)
                            Text(L("settings.historyLayout.grid")).tag(HistoryLayoutStyle.grid)
                            Text(L("settings.historyLayout.vertical")).tag(HistoryLayoutStyle.vertical)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 190)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    HStack {
                        Text(L("settings.panelPosition"))
                            .font(.system(size: 13))
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        Group {
                            switch HistoryLayoutStyle(rawValue: layoutStyleRaw) ?? .horizontal {
                            case .grid:
                                VStack(alignment: .leading, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(L("settings.panel.width"))
                                            .font(.system(size: 12))
                                    Slider(value: $panelGridWidthPercent, in: 40...100, step: 1) { Text("") }
                                            .frame(width: 190)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(L("settings.panel.height"))
                                            .font(.system(size: 12))
                                        Slider(value: $panelGridHeightPercent, in: 40...100, step: 1) { Text("") }
                                            .frame(width: 190)
                                    }
                                }
                            case .horizontal:
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L("settings.panelPosition.vertical"))
                                        .font(.system(size: 12))
                                    Slider(value: $panelPositionVertical, in: -100...100, step: 1) {
                                        Text("")
                                    }
                                    .frame(width: 190)
                                    Text(L("settings.panel.length"))
                                        .font(.system(size: 12))
                                        .padding(.top, 4)
                                    Slider(value: $panelHorizontalWidthPercent, in: 40...100, step: 1) { Text("") }
                                        .frame(width: 190)
                                }
                            case .vertical:
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L("settings.panelPosition.horizontal"))
                                        .font(.system(size: 12))
                                    Slider(value: $panelPositionHorizontal, in: -100...100, step: 1) {
                                        Text("")
                                    }
                                    .frame(width: 190)
                                    Text(L("settings.panel.height"))
                                        .font(.system(size: 12))
                                        .padding(.top, 4)
                                    Slider(value: $panelVerticalHeightPercent, in: 40...100, step: 1) { Text("") }
                                        .frame(width: 190)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    HStack {
                        Text(L("settings.panel.cornerRadius"))
                            .font(.system(size: 13))
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        Slider(value: $panelCornerRadius, in: 0...48, step: 1) { Text("") }
                            .frame(width: 190)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                }
            }
            .padding(10)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .shadow(color: AppTheme.shadowColor, radius: 4, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
            VStack(alignment: .leading, spacing: 8) {
                Text(L("shortcuts.title"))
                    .font(.system(size: 13, weight: .medium))
                VStack(spacing: 6) {
                    HStack {
                        Text(L("shortcuts.panel"))
                            .font(.system(size: 13))
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        ShortcutRecorder(shortcut: Binding(get: { settings.shortcuts.showPanel }, set: { settings.shortcuts.showPanel = $0 }))
                            .frame(width: 190, height: 22)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                }
            }
            .padding(10)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .shadow(color: AppTheme.shadowColor, radius: 4, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
            VStack(alignment: .leading, spacing: 8) {
                Text(L("about.title"))
                    .font(.system(size: 13, weight: .medium))
                VStack(spacing: 6) {
                    HStack {
                        Text(L("about.text"))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                }
            }
            .padding(10)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .shadow(color: AppTheme.shadowColor, radius: 4, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
        }
        .padding(10)
        }
        .background(AppTheme.panelBackground)

        .frame(maxWidth: 400)
        .controlSize(.small)
        .onAppear { settings = settingsStore.load() }
        .onValueChange(of: settings) { s in
            try? settingsStore.save(s)
            HotkeyService.shared?.unregisterAll()
            HotkeyService.shared?.registerShowPanel()
            HotkeyService.shared?.registerQuickPasteSlots()
            HotkeyService.shared?.registerStackToggle()
            AppTheme.applyAppearance(s.appearance)
        }
    }
    
}
