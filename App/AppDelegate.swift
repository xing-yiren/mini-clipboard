import AppKit
import SwiftUI
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var controller: AppController?
    var statusItem: NSStatusItem?
    private var preferencesWindow: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = SettingsStore().load()
        AppTheme.applyAppearance(settings.appearance)
        controller = AppController()
        controller?.onOpenSettings = { [weak self] in
            self?.openSettings()
        }
        NSApp.setActivationPolicy(.accessory)
        setApplicationIconFromPublic()
        controller?.start()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let fm = FileManager.default
            if let base = Bundle.main.resourceURL {
                let png = base.appendingPathComponent("public/menubar.png")
                if fm.fileExists(atPath: png.path), let img = NSImage(contentsOf: png) {
                    let thickness = NSStatusBar.system.thickness
                    let target = NSSize(width: thickness - 4, height: thickness - 4)
                    img.size = target
                    img.isTemplate = true
                    button.image = img
                    button.imageScaling = .scaleProportionallyDown
                    button.imagePosition = .imageOnly
                    button.title = ""
                } else if let symbol = NSImage(systemSymbolName: "clipboard", accessibilityDescription: nil) {
                    symbol.isTemplate = true
                    button.image = symbol
                    button.title = ""
                } else {
                    button.title = "MiniClip"
                }
            } else if let symbol = NSImage(systemSymbolName: "clipboard", accessibilityDescription: nil) {
                symbol.isTemplate = true
                button.image = symbol
                button.title = ""
            } else {
                button.title = "MiniClip"
            }
        }
        item.menu = buildStatusMenu()
        statusItem = item
        observeLanguageChanges()
    }
    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: L("panel.menu.panel"), action: #selector(openPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L("panel.menu.settings"), action: #selector(openSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L("panel.menu.quit"), action: #selector(quitApp), keyEquivalent: ""))
        return menu
    }
    private func observeLanguageChanges() {
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            if let item = self.statusItem { item.menu = self.buildStatusMenu() }
            if let w = self.preferencesWindow { w.title = L("window.settings.title") }
        }
    }
    private func ensureAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) { return }
    }
    private func setApplicationIconFromPublic() {
        let fm = FileManager.default
        if let base = Bundle.main.resourceURL {
            let png = base.appendingPathComponent("public/logo.png")
            let icns = base.appendingPathComponent("public/logo.icns")
            if fm.fileExists(atPath: png.path), let img = NSImage(contentsOf: png) {
                NSApp.applicationIconImage = img
                return
            }
            if fm.fileExists(atPath: icns.path), let img = NSImage(contentsOf: icns) {
                NSApp.applicationIconImage = img
                return
            }
        }
    }
    @objc func openPanel() { controller?.panel.show() }
    @objc func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if preferencesWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 560), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = L("window.settings.title")
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            w.minSize = NSSize(width: 600, height: 420)
            let hosting = NSHostingView(rootView: SettingsView())
            hosting.translatesAutoresizingMaskIntoConstraints = false
            let content = NSView()
            content.translatesAutoresizingMaskIntoConstraints = false
            w.contentView = content
            content.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: content.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: content.bottomAnchor)
            ])
            preferencesWindow = w
        }
        preferencesWindow?.center()
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func quitApp() { NSApp.terminate(nil) }

    func windowWillClose(_ notification: Notification) {
        if let w = notification.object as? NSWindow, w == preferencesWindow {
            preferencesWindow = nil
        }
    }
}

struct AppTheme {
    static func applyAppearance(_ mode: AppearanceMode) {
        let appearance: NSAppearance?
        switch mode {
        case .light: appearance = NSAppearance(named: .aqua)
        case .dark: appearance = NSAppearance(named: .darkAqua)
        case .system: appearance = nil
        }
        NSApp.appearance = appearance
    }

    private static func dynamic(light: String, dark: String) -> Color {
        return Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
                return NSColor(Color(hex: dark))
            } else {
                return NSColor(Color(hex: light))
            }
        }))
    }

    // 主色调
    static let mainPurple = dynamic(light: "8C7CF0", dark: "7C6CE0")
    static let palePinkPurple = dynamic(light: "C6B9FF", dark: "5A4BC0")
    
    // 辅色调
    static let softGreen = dynamic(light: "A0E8AF", dark: "059669")
    static let softYellow = dynamic(light: "FDE68A", dark: "D97706")
    static let paleOrange = dynamic(light: "FDBA74", dark: "EA580C")
    
    // 背景色
    static var background: Color { dynamic(light: "F9F9FB", dark: "1E1E1E") }
    static var panelBackground: Color { dynamic(light: "F5F5F7", dark: "252525") }
    static var cardBackground: Color { dynamic(light: "FFFFFF", dark: "333333") }
    static var sidebarBackground: Color { dynamic(light: "F0F0F5", dark: "2C2C2C") }
    
    // 阴影
    static var shadowColor: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
                return NSColor.black.withAlphaComponent(0.3)
            } else {
                return NSColor.black.withAlphaComponent(0.05)
            }
        }))
    }
    static let shadowRadius: CGFloat = 8
    static let shadowY: CGFloat = 4
    
    // 渐变
    static let highlightGradient = LinearGradient(
        colors: [mainPurple, palePinkPurple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // 圆角
    static let cornerRadius: CGFloat = 16
    static let cardCornerRadius: CGFloat = 16
    static let buttonCornerRadius: CGFloat = 12
    
    // MARK: - 多彩主题支持
    struct Palette {
        let main: Color
        let secondary: Color
        let background: Color
        let referenceColor: NSColor // 用于颜色匹配的参考色（固定为浅色模式下的主色）
    }
    
    static let purple = Palette(main: mainPurple, secondary: palePinkPurple, background: dynamic(light: "F9F9FB", dark: "2D2D2D"), referenceColor: NSColor(Color(hex: "8C7CF0")))
    static let blue = Palette(main: dynamic(light: "60A5FA", dark: "2563EB"), secondary: dynamic(light: "93C5FD", dark: "1E40AF"), background: dynamic(light: "EFF6FF", dark: "1E3A8A"), referenceColor: NSColor(Color(hex: "60A5FA")))
    static let green = Palette(main: dynamic(light: "34D399", dark: "059669"), secondary: dynamic(light: "6EE7B7", dark: "065F46"), background: dynamic(light: "ECFDF5", dark: "064E3B"), referenceColor: NSColor(Color(hex: "34D399")))
    static let orange = Palette(main: dynamic(light: "FB923C", dark: "EA580C"), secondary: dynamic(light: "FDBA74", dark: "9A3412"), background: dynamic(light: "FFF7ED", dark: "431407"), referenceColor: NSColor(Color(hex: "FB923C")))
    static let pink = Palette(main: dynamic(light: "F472B6", dark: "DB2777"), secondary: dynamic(light: "FBCFE8", dark: "9D174D"), background: dynamic(light: "FDF2F8", dark: "500724"), referenceColor: NSColor(Color(hex: "F472B6")))
    static let teal = Palette(main: dynamic(light: "2DD4BF", dark: "0D9488"), secondary: dynamic(light: "5EEAD4", dark: "115E59"), background: dynamic(light: "F0FDFA", dark: "134E4A"), referenceColor: NSColor(Color(hex: "2DD4BF")))
    static let yellow = Palette(main: dynamic(light: "FBBF24", dark: "D97706"), secondary: dynamic(light: "FDE68A", dark: "92400E"), background: dynamic(light: "FFFBEB", dark: "451A03"), referenceColor: NSColor(Color(hex: "FBBF24")))
    static let red = Palette(main: dynamic(light: "F87171", dark: "DC2626"), secondary: dynamic(light: "FCA5A5", dark: "991B1B"), background: dynamic(light: "FEF2F2", dark: "450A0A"), referenceColor: NSColor(Color(hex: "F87171")))
    
    static let allPalettes = [purple, blue, green, orange, pink, teal, yellow, red]
    
    // 缓存已计算的应用主题色
    private static var appColorCache: [String: Palette] = [:]
    
    static func palette(for bundleID: String) -> Palette {
        if let cached = appColorCache[bundleID] { return cached }
        
        // 尝试从应用图标提取颜色
        if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path {
            let icon = NSWorkspace.shared.icon(forFile: path).resize(to: NSSize(width: 32, height: 32))
            if let dominant = icon.dominantColor() {
                // 寻找最接近的预设色板
                let best = allPalettes.min(by: { p1, p2 in
                    distance(from: dominant, to: p1.referenceColor) < distance(from: dominant, to: p2.referenceColor)
                }) ?? purple
                appColorCache[bundleID] = best
                return best
            }
        }
        
        // 降级方案：Hash 映射
        let hash = abs(bundleID.hashValue)
        let p = allPalettes[hash % allPalettes.count]
        appColorCache[bundleID] = p
        return p
    }
    
    static func closestPalette(for color: Color) -> Palette {
        let nsColor = NSColor(color)
        return allPalettes.min(by: { p1, p2 in
            distance(from: nsColor, to: p1.referenceColor) < distance(from: nsColor, to: p2.referenceColor)
        }) ?? purple
    }
    
    private static func distance(from c1: NSColor, to c2: NSColor) -> Double {
        // 确保颜色转换到 sRGB 颜色空间，避免 Catalog color 报错
        guard let s1 = c1.usingColorSpace(.sRGB),
              let s2 = c2.usingColorSpace(.sRGB) else {
            return Double.greatestFiniteMagnitude
        }
        let r1 = s1.redComponent, g1 = s1.greenComponent, b1 = s1.blueComponent
        let r2 = s2.redComponent, g2 = s2.greenComponent, b2 = s2.blueComponent
        return sqrt(pow(r1-r2, 2) + pow(g1-g2, 2) + pow(b1-b2, 2))
    }
}

extension NSImage {
    func resize(to size: NSSize) -> NSImage {
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        self.draw(in: NSRect(origin: .zero, size: size), from: NSRect(origin: .zero, size: self.size), operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
    
    func dominantColor() -> NSColor? {
        // 缩放到 1x1 取平均色
        let onePixel = self.resize(to: NSSize(width: 1, height: 1))
        guard let tiff = onePixel.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.colorAt(x: 0, y: 0)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
