import AppKit
import Foundation
import Carbon

// 粘贴服务：负责将 ClipItem 写入系统粘贴板并触发 Command+V
public final class PasteService: PasteServiceProtocol {
    private var stack: [ClipItem] = []
    private var stackActive = false
    private var asc = true
    public init() {}
    @discardableResult
    public func paste(_ item: ClipItem, format: TextFormatMode) -> TextFormatMode {
        writeToPasteboard(item, format: format)
    }
    @discardableResult
    public func directPaste(_ item: ClipItem, format: TextFormatMode) -> TextFormatMode {
        let actualFormat = writeToPasteboard(item, format: format)
        triggerPasteCommand()
        return actualFormat
    }
    
    public func triggerPasteCommand() {
        // Delay to allow previous app to activate (panel hide animation is ~0.15s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let source = CGEventSource(stateID: .hidSystemState)
            let vKeyCode: CGKeyCode = 0x09 // kVK_ANSI_V
            
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
            
            keyDown?.flags = .maskCommand
            keyUp?.flags = .maskCommand
            
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    }
    public func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }
    public func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    // 开启栈式粘贴，asc 控制顺序（正序/倒序）
    public func activateStack(directionAsc: Bool) { stackActive = true; asc = directionAsc }
    public func deactivateStack() { stackActive = false; stack.removeAll() }
    public func pushToStack(_ item: ClipItem) { if stackActive { stack.append(item) } }
    public func deliverStack() {
        // 依序将栈中的条目写入并模拟粘贴快捷键
        let seq = asc ? stack : stack.reversed()
        let format = SettingsStore().load().defaultTextFormat
        for i in seq {
            writeToPasteboard(i, format: format)
        }
        stack.removeAll()
    }
    @discardableResult
    private func writeToPasteboard(_ item: ClipItem, format: TextFormatMode) -> TextFormatMode {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.type {
        case .text:
            if format == .preserveFormatting, writePreservedText(item, to: pb) {
                return .preserveFormatting
            }
            pb.setString(plainText(for: item), forType: .string)
            return .plainText
        case .link:
            // Standalone URLs always remain literal text. Rich URL flavors let
            // some editors synthesize Markdown such as `[title](url)`.
            pb.setString(plainText(for: item), forType: .string)
            return .plainText
        case .image:
            if let u = item.contentRef, let d = try? Data(contentsOf: u) { pb.setData(d, forType: .png) }
            return format
        case .file:
            if let u = item.contentRef { pb.setString(u.absoluteString, forType: .fileURL) }
            return format
        case .color:
            pb.setString(plainText(for: item), forType: .string)
            return .plainText
        }
    }

    private func writePreservedText(_ item: ClipItem, to pasteboard: NSPasteboard) -> Bool {
        guard let url = item.contentRef else { return false }
        let plain = plainText(for: item)
        switch item.metadata["rich"] {
        case "html":
            guard let data = try? Data(contentsOf: url) else { return false }
            pasteboard.setData(data, forType: .html)
            pasteboard.setString(plain, forType: .string)
            return true
        case "rtf":
            guard let data = try? Data(contentsOf: url) else { return false }
            pasteboard.setData(data, forType: .rtf)
            pasteboard.setString(plain, forType: .string)
            return true
        default:
            return false
        }
    }

    public func plainText(for item: ClipItem) -> String {
        switch item.type {
        case .text:
            // Prefer the exact plain-text flavor supplied by the source app. If
            // the source only supplied rich content, derive readable text from it.
            if let url = item.contentRef {
                if item.metadata["rich"] == "html",
                   let data = try? Data(contentsOf: url) {
                    // A rendered selection containing images must not leak image
                    // sources into plain-text output. Markdown source copied as
                    // text has no rendered <img>/<picture> node and stays intact.
                    if htmlContainsRenderedImages(data) {
                        if let text = textFromHTML(data, removingImages: true) {
                            return text
                        }
                        return removingRenderedImageSources(from: item.text ?? "", htmlData: data)
                    }
                    if item.metadata["plainSource"] == "pb", let text = item.text {
                        return text
                    }
                    if let text = textFromHTML(data, removingImages: false) {
                        return text
                    }
                }
                if item.metadata["rich"] == "rtf",
                   let attributed = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) {
                    if item.metadata["plainSource"] == "pb", let text = item.text {
                        return text
                    }
                    return attributed.string
                }
                if url.pathExtension.lowercased() == "txt",
                   let text = try? String(contentsOf: url, encoding: .utf8) {
                    return text
                }
            }
            return item.text ?? ""
        case .link:
            // A literal Markdown string is captured as `.text`, so links here
            // represent URL values and are written without a rich URL flavor.
            return item.text ?? item.metadata["url"] ?? item.contentRef?.absoluteString ?? ""
        case .image:
            return item.text ?? ""
        case .file:
            return item.contentRef?.path ?? item.text ?? ""
        case .color:
            return item.metadata["colorHex"] ?? item.text ?? ""
        }
    }

    private func htmlContainsRenderedImages(_ data: Data) -> Bool {
        guard let html = String(data: data, encoding: .utf8) else { return false }
        return html.range(of: "<img", options: .caseInsensitive) != nil
            || html.range(of: "<picture", options: .caseInsensitive) != nil
    }

    private func textFromHTML(_ data: Data, removingImages: Bool) -> String? {
        var sourceData = data
        if removingImages, var html = String(data: data, encoding: .utf8) {
            html = replacingHTMLPattern(#"<picture[^>]*>.*?</picture\s*>"#, in: html)
            html = replacingHTMLPattern(#"<img[^>]*>"#, in: html)
            sourceData = Data(html.utf8)
        }
        guard let attributed = try? NSAttributedString(
            data: sourceData,
            options: [.documentType: NSAttributedString.DocumentType.html],
            documentAttributes: nil
        ) else { return nil }
        return attributed.string.replacingOccurrences(of: "\u{FFFC}", with: "")
    }

    private func replacingHTMLPattern(_ pattern: String, in html: String) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return html }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return expression.stringByReplacingMatches(in: html, range: range, withTemplate: "")
    }

    private func removingRenderedImageSources(from text: String, htmlData: Data) -> String {
        guard let html = String(data: htmlData, encoding: .utf8),
              let expression = try? NSRegularExpression(
                  pattern: #"\bsrc\s*=\s*[\"']([^\"']+)[\"']"#,
                  options: .caseInsensitive
              ) else { return text }
        let htmlRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let sources = expression.matches(in: html, range: htmlRange).compactMap { match -> String? in
            guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[range])
        }
        return sources.reduce(text) { partial, source in
            partial.replacingOccurrences(of: source, with: "")
        }
    }
}
