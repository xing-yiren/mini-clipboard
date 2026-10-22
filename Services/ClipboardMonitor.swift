import AppKit
import Foundation

// 剪贴板监控：定时轮询系统粘贴板并解析为统一的 ClipItem
public final class ClipboardMonitor: ClipboardMonitorProtocol {
    private var lastCount = NSPasteboard.general.changeCount
    private var timer: DispatchSourceTimer?
    public var onItemCaptured: ((ClipItem) -> Void)?
    private var ignoredApps: Set<String> = []
    private var suppressUntil: Date?
    // 忽略的应用（通过 bundleID 过滤）
    public init() {}
    public func start() {
        // 使用 GCD 定时器轮询粘贴板变更
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        t.schedule(deadline: .now(), repeating: .milliseconds(400))
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }
    public func stop() { timer?.cancel(); timer = nil }
    public func setIgnoredApps(_ bundleIDs: [String]) { ignoredApps = Set(bundleIDs) }
    public func suppressCaptures(for duration: TimeInterval) { suppressUntil = Date().addingTimeInterval(duration) }
    private func poll() {
        let pb = NSPasteboard.general
        // 若变更计数未变化则直接返回
        if pb.changeCount == lastCount { return }
        lastCount = pb.changeCount
        if let s = suppressUntil, s > Date() { return }
        // 前台应用在忽略列表中则不采集
        if let app = NSWorkspace.shared.frontmostApplication, let bid = app.bundleIdentifier, ignoredApps.contains(bid) { return }
        handlePasteboard(pb)
    }
    private func handlePasteboard(_ pb: NSPasteboard) {
        let types = pb.types ?? []
        let app = NSWorkspace.shared.frontmostApplication
        let appName = app?.localizedName ?? "Unknown"
        let bundleID = app?.bundleIdentifier
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [NSPasteboard.ReadingOptionKey.urlReadingFileURLsOnly: true]) as? [URL], let u = urls.first {
            var m: [String: String] = [:]
            if let bid = bundleID { m["bundleID"] = bid }
            let item = ClipItem(type: .file, contentRef: u, text: u.lastPathComponent, sourceApp: appName, metadata: m)
            DispatchQueue.main.async { self.onItemCaptured?(item) }
            return
        }
        // 图片优先于文本/HTML/RTF 处理：部分应用（浏览器、Keynote、截图工具等）会同时
        // 提供 HTML/RTF 描述，此时仍应保存图片本身，否则粘贴时只剩文字或链接。
        if let payload = imagePayload(from: pb) {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(payload.fileExtension)
            try? payload.data.write(to: tmp)
            var m: [String: String] = [:]
            if let bid = bundleID { m["bundleID"] = bid }
            let item = ClipItem(type: .image, contentRef: tmp, text: nil, sourceApp: appName, metadata: m)
            DispatchQueue.main.async { self.onItemCaptured?(item) }
            return
        }
        // 颜色类型
        if types.contains(.color) {
            var m: [String: String] = [:]
            if let bid = bundleID { m["bundleID"] = bid }
            if let colors = pb.readObjects(forClasses: [NSColor.self], options: nil) as? [NSColor], let c = colors.first, let rgb = c.usingColorSpace(.deviceRGB) {
                let r = Int(round(rgb.redComponent * 255))
                let g = Int(round(rgb.greenComponent * 255))
                let b = Int(round(rgb.blueComponent * 255))
                m["colorHex"] = String(format: "#%02X%02X%02X", r, g, b)
            }
            let item = ClipItem(type: .color, contentRef: nil, text: nil, sourceApp: appName, metadata: m)
            DispatchQueue.main.async { self.onItemCaptured?(item) }
            return
        }
        if types.contains(.string) {
            let raw = pb.string(forType: .string) ?? ""
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let hex = detectHexColorHex(fromString: text) {
                var m: [String: String] = [:]
                m["colorHex"] = hex
                if let bid = bundleID { m["bundleID"] = bid }
                let item = ClipItem(type: .color, contentRef: nil, text: nil, sourceApp: appName, metadata: m)
                DispatchQueue.main.async { self.onItemCaptured?(item) }
                return
            }
        }
        // 链接类型（元数据包含原始 URL）
        if types.contains(.URL) {
            if let s = pb.string(forType: .URL), let u = URL(string: s) {
                var m: [String: String] = [:]
                if let bid = bundleID { m["bundleID"] = bid }
                if u.isFileURL {
                    let item = ClipItem(type: .file, contentRef: u, text: u.lastPathComponent, sourceApp: appName, metadata: m)
                    DispatchQueue.main.async { self.onItemCaptured?(item) }
                    return
                } else {
                    m["url"] = u.absoluteString
                    let item = ClipItem(type: .link, contentRef: u, text: s, sourceApp: appName, metadata: m)
                    DispatchQueue.main.async { self.onItemCaptured?(item) }
                    return
                }
            }
        }
        // HTML 富文本
        if types.contains(.html), let d = pb.data(forType: .html) {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("html")
            try? d.write(to: tmp)
            let plainTextFromPasteboard = pb.string(forType: .string)
            var plainText = plainTextFromPasteboard
            if plainTextFromPasteboard == nil {
                if let a = try? NSAttributedString(data: d, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil) {
                    plainText = a.string
                }
            }
            var m: [String: String] = [:]
            if let bid = bundleID { m["bundleID"] = bid }
            m["rich"] = "html"
            m["plainSource"] = (plainTextFromPasteboard != nil) ? "pb" : "derived"
            let item = ClipItem(type: .text, contentRef: tmp, text: plainText, sourceApp: appName, metadata: m)
            DispatchQueue.main.async { self.onItemCaptured?(item) }
            return
        }
        // 富文本（优先于纯文本）
        if let objs = pb.readObjects(forClasses: [NSAttributedString.self], options: nil) as? [NSAttributedString], let attr = objs.first, !attr.string.isEmpty {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("rtf")
            let range = NSRange(location: 0, length: attr.length)
            if let d = attr.rtf(from: range, documentAttributes: [:]) {
                try? d.write(to: tmp)
                var m: [String: String] = [:]
                if let bid = bundleID { m["bundleID"] = bid }
                m["rich"] = "rtf"
                let plainFromPB = pb.string(forType: .string)
                if plainFromPB != nil { m["plainSource"] = "pb" } else { m["plainSource"] = "derived" }
                let item = ClipItem(type: .text, contentRef: tmp, text: plainFromPB ?? attr.string, sourceApp: appName, metadata: m)
                DispatchQueue.main.async { self.onItemCaptured?(item) }
                return
            }
        }
        if types.contains(.fileURL) {
            if let urls = pb.readObjects(forClasses: [NSURL.self], options: [NSPasteboard.ReadingOptionKey.urlReadingFileURLsOnly: true]) as? [URL], let u = urls.first {
                var m: [String: String] = [:]
                if let bid = bundleID { m["bundleID"] = bid }
                let item = ClipItem(type: .file, contentRef: u, text: u.lastPathComponent, sourceApp: appName, metadata: m)
                DispatchQueue.main.async { self.onItemCaptured?(item) }
                return
            }
            if let s = pb.string(forType: .fileURL), let u = URL(string: s) {
                var m: [String: String] = [:]
                if let bid = bundleID { m["bundleID"] = bid }
                let item = ClipItem(type: .file, contentRef: u, text: u.lastPathComponent, sourceApp: appName, metadata: m)
                DispatchQueue.main.async { self.onItemCaptured?(item) }
                return
            }
        }
        // 文本类型及字符串中的链接/颜色识别
        if types.contains(.string) {
            let raw = pb.string(forType: .string) ?? ""
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let u = detectURL(fromString: text) {
                var m: [String: String] = [:]
                m["url"] = u.absoluteString
                if let bid = bundleID { m["bundleID"] = bid }
                let item = ClipItem(type: .link, contentRef: u, text: text, sourceApp: appName, metadata: m)
                DispatchQueue.main.async { self.onItemCaptured?(item) }
                return
            }
            if let hex = detectHexColorHex(fromString: text) {
                var m: [String: String] = [:]
                m["colorHex"] = hex
                if let bid = bundleID { m["bundleID"] = bid }
                let item = ClipItem(type: .color, contentRef: nil, text: nil, sourceApp: appName, metadata: m)
                DispatchQueue.main.async { self.onItemCaptured?(item) }
                return
            }
            let threshold = 4000
            var m: [String: String] = [:]
            if let bid = bundleID { m["bundleID"] = bid }
            if text.count > threshold {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("txt")
                try? raw.write(to: tmp, atomically: true, encoding: .utf8)
                let preview = String(text.prefix(1200))
                let item = ClipItem(type: .text, contentRef: tmp, text: preview, sourceApp: appName, metadata: m)
                DispatchQueue.main.async { self.onItemCaptured?(item) }
                return
            } else {
                let item = ClipItem(type: .text, contentRef: nil, text: raw, sourceApp: appName, metadata: m)
                DispatchQueue.main.async { self.onItemCaptured?(item) }
                return
            }
        }
    }
    // 从粘贴板读取图片并按真实格式重新编码，返回落盘数据与匹配的扩展名，
    // 避免出现扩展名与内容不一致的文件（例如 TIFF 内容存成 .png）。
    private func imagePayload(from pb: NSPasteboard) -> (data: Data, fileExtension: String)? {
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            guard let raw = pb.data(forType: type) else { continue }
            if let png = ImagePayloadService.normalize(raw, to: .png) {
                return (png, "png")
            }
            // 无法重编码但系统能识别时，保留原始数据并使用真实扩展名
            if let actual = ImagePayloadService.detectUTType(of: raw) {
                return (raw, actual.preferredFilenameExtension ?? "tiff")
            }
        }
        return nil
    }
    private func detectURL(fromString s: String) -> URL? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        if let u = URL(string: t), let scheme = u.scheme?.lowercased(), ["http", "https"].contains(scheme) { return u }
        if let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(t.startIndex..<t.endIndex, in: t)
            if let m = det.firstMatch(in: t, options: [], range: range) {
                if m.range.location == 0 && m.range.length >= range.length - 1 { return m.url }
            }
        }
        return nil
    }
    private func detectHexColorHex(fromString s: String) -> String? {
        let t = s.uppercased()
        let hex = t.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        if hex.count == 6, let _ = Int(hex, radix: 16) {
            return "#" + hex
        }
        if hex.count == 8, let val = Int(hex, radix: 16) {
            let r = (val >> 16) & 0xFF
            let g = (val >> 8) & 0xFF
            let b = val & 0xFF
            return String(format: "#%02X%02X%02X", r, g, b)
        }
        return nil
    }
}
