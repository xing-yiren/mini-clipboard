import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

final class AppController: ObservableObject {
    var onOpenSettings: (() -> Void)?
    let store: IndexStore
    let settingsStore: SettingsStore
    let monitor: ClipboardMonitor
    let paste: PasteService
    let preview: PreviewService
    let hotkeys: HotkeyService
    let panel: PanelWindowController
    @Published var items: [ClipItem] = []
    @Published var query: String = ""
    @Published var filters: SearchFilters = SearchFilters()
    @Published var boards: [Pinboard] = []
    @Published var selectedBoardID: UUID?
    @Published var selectedItemID: UUID?
    @Published var selectionByKeyboard: Bool = false
    @Published var selectedIDs: Set<UUID> = []
    @Published var selectedOrder: [UUID] = []
    @Published var selectionMode: Bool = false
    @Published var selectionAnchorID: UUID?
    @Published var searchPopoverVisible: Bool = false
    @Published var searchBarWidth: CGFloat = 0
    @Published var sidebarWidth: CGFloat = 180
    @Published var appSettings: AppSettings = AppSettings()
    private let search: SearchService
    private var cancellables: Set<AnyCancellable> = []
    init() {
        store = IndexStore()
        settingsStore = SettingsStore()
        monitor = ClipboardMonitor()
        paste = PasteService()
        hotkeys = HotkeyService()
        preview = PreviewService()
        panel = PanelWindowController()
        search = SearchService(store: store)
        appSettings = settingsStore.load()
        if let bid = Bundle.main.bundleIdentifier { monitor.setIgnoredApps([bid]) }
        monitor.onItemCaptured = { [weak self] item in
            try? self?.store.save(item)
            self?.paste.pushToStack(item)
            self?.refresh()
        }
        hotkeys.onShowPanel = { [weak self] in self?.panel.toggle() }
        hotkeys.onQuickPaste = { [weak self] idx, plain in
            guard let self = self else { return }
            let list = self.search.search(self.query, filters: self.filters, limit: 100)
            if idx-1 < list.count {
                self.monitor.suppressCaptures(for: 1.0)
                let format: TextFormatMode = plain ? .plainText : self.appSettings.defaultTextFormat
                self.paste.paste(list[idx-1], format: format)
                self.store.moveToFront(list[idx-1].id)
                self.refresh()
            }
        }
        hotkeys.onStackToggle = { [weak self] in
            guard let self = self else { return }
            self.paste.activateStack(directionAsc: true)
        }
        panel.setRoot(PanelRootView(controller: self))
        panel.onQuickPaste = { [weak self] idx, plain in
            guard let self = self else { return }
            let list = self.search.search(self.query, filters: self.filters, limit: 100)
            if idx-1 < list.count {
                self.monitor.suppressCaptures(for: 1.0)
                let format: TextFormatMode = plain ? .plainText : self.appSettings.defaultTextFormat
                self.paste.paste(list[idx-1], format: format)
                self.store.moveToFront(list[idx-1].id)
                self.refresh()
            }
        }
        panel.onQueryUpdate = { [weak self] q in self?.query = q }
        panel.onSearchOverlayVisibleChanged = { [weak self] in self?.searchPopoverVisible = $0 }
        panel.onShowSearchPopover = { [weak self] _ in
            self?.searchPopoverVisible = true
        }
        panel.onHideSearchPopover = { [weak self] in self?.searchPopoverVisible = false }
        panel.onShown = { [weak self] in
            self?.selectFirstItemIfNeeded()
        }
        panel.onArrowLeft = { [weak self] in self?.moveSelectionLeft() }
        panel.onArrowRight = { [weak self] in self?.moveSelectionRight() }
        panel.onArrowUp = { [weak self] in self?.moveSelectionUp() }
        panel.onArrowDown = { [weak self] in self?.moveSelectionDown() }
        panel.onEnter = { [weak self] formatOverride in self?.confirmSelectionAndPaste(formatOverride: formatOverride) }
        panel.previewService = preview
        panel.onSpace = { [weak self] in
            guard let self = self else { return }
            if self.panel.previewService?.isVisible() == true {
                self.panel.previewService?.close()
            } else {
                if let id = self.selectedItemID, let item = self.items.first(where: { $0.id == id }) {
                    self.panel.showPreview(item)
                }
            }
        }
        $searchPopoverVisible
            .sink { [weak self] v in self?.panel.setSearchActive(v) }
            .store(in: &cancellables)
        selectedBoardID = store.defaultBoardID

        $query
            .debounce(for: .milliseconds(120), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        $selectedItemID
            .removeDuplicates()
            .sink { [weak self] id in
                guard let self = self else { return }
                guard self.panel.previewService?.isVisible() == true else { return }
                guard let id = id, let item = self.items.first(where: { $0.id == id }) else { return }
                self.panel.showPreview(item)
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .miniClipboardSettingsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let settings = notification.object as? AppSettings {
                    self?.appSettings = settings
                } else {
                    self?.appSettings = self?.settingsStore.load() ?? AppSettings()
                }
            }
            .store(in: &cancellables)
    }
    
    func start() {
        monitor.start()
        hotkeys.registerShowPanel()
        hotkeys.registerQuickPasteSlots()
        hotkeys.registerStackToggle()
        refresh()
    }
    func refresh() {
        boards = store.listPinboards()
        if let bid = selectedBoardID, bid != store.defaultBoardID {
            var r = store.listItems(in: bid)
            if !filters.types.isEmpty { r = r.filter { filters.types.contains($0.type) } }
            if !filters.sourceApps.isEmpty { r = r.filter { filters.sourceApps.contains($0.sourceApp) } }
            if !query.isEmpty {
                let qs = query
                r = r.filter {
                    ($0.text?.range(of: qs, options: [.caseInsensitive]) != nil) ||
                    ($0.metadata["url"]?.range(of: qs, options: [.caseInsensitive]) != nil)
                }
            }
            items = Array(r.prefix(200))
        } else {
            let currentQuery = query
            let currentFilters = filters
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                let result = self.search.search(currentQuery, filters: currentFilters, limit: 200)
                DispatchQueue.main.async { [weak self] in
                    self?.items = result
                }
            }
        }
    }
    func pasteItem(_ item: ClipItem, format: TextFormatMode? = nil) {
        monitor.suppressCaptures(for: 1.0)
        let actualFormat = paste.paste(item, format: format ?? appSettings.defaultTextFormat)
        store.moveToFront(item.id)
        refresh()
        panel.hide()
        let msg: String
        if item.type == .image || item.type == .file {
            msg = L("toast.copied")
        } else {
            msg = actualFormat == .preserveFormatting ? L("toast.copiedFormatted") : L("toast.copiedPlain")
        }
        panel.showToast(msg)
    }
    func copySelectedPlainText() {
        let ids = Array(selectedIDs)
        guard !ids.isEmpty else { return }
        let orderedIDs = selectedOrder.filter { selectedIDs.contains($0) }
        let finalIDs = orderedIDs.isEmpty ? ids : orderedIDs
        let itemsToCopy = finalIDs.compactMap { id in items.first(where: { $0.id == id }) }
        let parts: [String] = itemsToCopy.map { plainText(of: $0) }
        let joined = parts.joined(separator: "\n\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(joined, forType: .string)
        panel.showToast(L("toast.copiedPlain"))
        clearSelection()
    }
    func copySelectedRichText() {
        let ids = Array(selectedIDs)
        guard !ids.isEmpty else { return }
        let orderedIDs = selectedOrder.filter { selectedIDs.contains($0) }
        let finalIDs = orderedIDs.isEmpty ? ids : orderedIDs
        let itemsToCopy = finalIDs.compactMap { id in items.first(where: { $0.id == id }) }
        if let item = itemsToCopy.first, itemsToCopy.count == 1 {
            let actualFormat = paste.paste(item, format: .preserveFormatting)
            let message: String
            if item.type == .image || item.type == .file {
                message = L("toast.copied")
            } else {
                message = actualFormat == .preserveFormatting ? L("toast.copiedFormatted") : L("toast.copiedPlain")
            }
            panel.showToast(message)
            clearSelection()
            return
        }
        let agg = NSMutableAttributedString()
        for (idx, it) in itemsToCopy.enumerated() {
            agg.append(richSegment(of: it))
            if idx < itemsToCopy.count - 1 { agg.append(NSAttributedString(string: "\n\n")) }
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        let range = NSRange(location: 0, length: agg.length)
        if let html = try? agg.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.html]) {
            pb.setData(html, forType: .html)
        }
        if let rtf = agg.rtf(from: range, documentAttributes: [:]) {
            pb.setData(rtf, forType: .rtf)
        }
        pb.setString(agg.string, forType: .string)
        panel.showToast(L("toast.copiedFormatted"))
        clearSelection()
    }
    private func richSegment(of item: ClipItem) -> NSAttributedString {
        switch item.type {
        case .text:
            if let url = item.contentRef, item.metadata["rich"] == "html",
               let data = try? Data(contentsOf: url),
               let attributed = try? NSAttributedString(
                   data: data,
                   options: [.documentType: NSAttributedString.DocumentType.html],
                   documentAttributes: nil
               ) {
                return attributed
            }
            if let url = item.contentRef, item.metadata["rich"] == "rtf",
               let attributed = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) {
                return attributed
            }
            return NSAttributedString(string: plainText(of: item))
        case .link:
            let urlString = item.contentRef?.absoluteString ?? (item.metadata["url"] ?? (item.text ?? ""))
            let m = NSMutableAttributedString(string: urlString)
            if let u = URL(string: urlString) { m.addAttribute(.link, value: u, range: NSRange(location: 0, length: (m.string as NSString).length)) }
            return m
        case .image:
            if let u = item.contentRef, let d = try? Data(contentsOf: u), let img = NSImage(data: d) {
                let att = NSTextAttachment()
                att.image = img
                if let tiff = img.tiffRepresentation {
                    let fw = FileWrapper(regularFileWithContents: tiff)
                    fw.preferredFilename = "image.tiff"
                    att.fileWrapper = fw
                }
                let seg = NSMutableAttributedString(attachment: att)
                if let t = item.text, !t.isEmpty { seg.append(NSAttributedString(string: "\n")); seg.append(NSAttributedString(string: t)) }
                return seg
            }
            return NSAttributedString(string: item.text ?? "")
        case .file:
            if let u = item.contentRef {
                let extLower = u.pathExtension.lowercased()
                if !extLower.isEmpty, let t = UTType(filenameExtension: extLower), t.conforms(to: .image), let d = try? Data(contentsOf: u), let img = NSImage(data: d) {
                    let att = NSTextAttachment()
                    att.image = img
                    if let tiff = img.tiffRepresentation {
                        let fw = FileWrapper(regularFileWithContents: tiff)
                        fw.preferredFilename = "image.tiff"
                        att.fileWrapper = fw
                    }
                    let seg = NSMutableAttributedString(attachment: att)
                    if let tt = item.text, !tt.isEmpty { seg.append(NSAttributedString(string: "\n")); seg.append(NSAttributedString(string: tt)) } else { seg.append(NSAttributedString(string: "\n" + u.lastPathComponent)) }
                    return seg
                } else {
                    let m = NSMutableAttributedString(string: u.lastPathComponent)
                    m.append(NSAttributedString(string: "\n" + u.absoluteString))
                    if let url = URL(string: u.absoluteString) { m.addAttribute(.link, value: url, range: NSRange(location: (m.string as NSString).length - u.absoluteString.count, length: u.absoluteString.count)) }
                    return m
                }
            }
            return NSAttributedString(string: item.text ?? "")
        case .color:
            return NSAttributedString(string: item.metadata["colorHex"] ?? (item.text ?? ""))
        }
    }
    private func plainText(of item: ClipItem) -> String {
        paste.plainText(for: item)
    }
    func deleteSelected() {
        let ids = Array(selectedIDs)
        guard !ids.isEmpty else { return }
        ids.forEach { id in try? store.delete(id) }
        if let sel = selectedItemID, selectedIDs.contains(sel) { selectedItemID = nil }
        selectedIDs.removeAll()
        selectionMode = false
        refresh()
        panel.showToast(L("toast.deleted"))
    }
    func addSelectedToBoard(_ boardID: UUID) {
        let ids = Array(selectedIDs)
        guard !ids.isEmpty else { return }
        ids.forEach { id in try? store.pin(id, to: boardID) }
        refresh()
        panel.showToast(L("toast.addedToBoard"))
        clearSelection()
    }
    func clearSelection() {
        selectedIDs.removeAll()
        selectedOrder.removeAll()
        selectionMode = false
    }
    func toggleSelectionMode() {
        selectionMode.toggle()
        if !selectionMode { selectedIDs.removeAll(); selectedOrder.removeAll() }
    }
    func onItemTapped(_ item: ClipItem) {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        if selectionMode {
            if selectedIDs.contains(item.id) { selectedIDs.remove(item.id); selectedOrder.removeAll(where: { $0 == item.id }) } else { selectedIDs.insert(item.id); if !selectedOrder.contains(item.id) { selectedOrder.append(item.id) } }
            selectionAnchorID = item.id
            return
        }
        if flags.contains(.command) {
            if selectedIDs.contains(item.id) { selectedIDs.remove(item.id); selectedOrder.removeAll(where: { $0 == item.id }) } else { selectedIDs.insert(item.id); if !selectedOrder.contains(item.id) { selectedOrder.append(item.id) } }
            selectionAnchorID = item.id
            return
        }
        if flags.contains(.shift) {
            guard let anchor = selectionAnchorID ?? selectedItemID, let aIdx = items.firstIndex(where: { $0.id == anchor }), let bIdx = items.firstIndex(where: { $0.id == item.id }) else {
                selectedIDs.insert(item.id); if !selectedOrder.contains(item.id) { selectedOrder.append(item.id) }
                selectionAnchorID = item.id
                return
            }
            let step = (aIdx <= bIdx) ? 1 : -1
            var i = aIdx
            while true {
                let id = items[i].id
                if !selectedIDs.contains(id) { selectedIDs.insert(id) }
                if !selectedOrder.contains(id) { selectedOrder.append(id) }
                if i == bIdx { break }
                i += step
            }
            return
        }
        selectionByKeyboard = false
        selectedItemID = item.id
        selectedIDs.removeAll()
        selectedOrder.removeAll()
        selectionAnchorID = item.id
    }

    func confirmDeleteSelected() {
        let count = selectedIDs.count
        guard count > 0 else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "确定删除所选项？"
        alert.informativeText = "这将删除 \(count) 项，操作不可撤销。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            deleteSelected()
        }
    }
    func addToBoard(_ item: ClipItem, _ boardID: UUID) {
        try? store.pin(item.id, to: boardID)
        refresh()
        panel.showToast(L("toast.addedToBoard"))
    }
    func deleteItem(_ item: ClipItem) {
        try? store.delete(item.id)
        if selectedItemID == item.id { selectedItemID = nil }
        refresh()
        panel.showToast(L("toast.deleted"))
    }
    func renameItem(_ item: ClipItem, name: String) {
        var updated = item
        updated.name = name
        try? store.save(updated)
        refresh()
    }
    func selectBoard(_ id: UUID) {
        selectedBoardID = id
        refresh()
    }
    func selectItem(_ item: ClipItem) {
        selectionByKeyboard = false
        selectedItemID = item.id
    }
    private func selectFirstItemIfNeeded() {
        if selectedItemID == nil { selectedItemID = items.first?.id }
    }
    private func currentIndex() -> Int? {
        guard let id = selectedItemID, let idx = items.firstIndex(where: { $0.id == id }) else { return nil }
        return idx
    }
    private func setIndex(_ idx: Int) {
        guard !items.isEmpty else { return }
        let clamped = max(0, min(items.count - 1, idx))
        selectedItemID = items[clamped].id
    }
    private func layoutStyle() -> HistoryLayoutStyle {
        let raw = UserDefaults.standard.string(forKey: "historyLayoutStyle") ?? "horizontal"
        return HistoryLayoutStyle(rawValue: raw) ?? .horizontal
    }
    private func estimatedGridColumns() -> Int {
        let width = panel.contentWidth()
        let divider: CGFloat = 8
        let horizontalPadding: CGFloat = 24
        let cardWidth: CGFloat = 240
        let spacing: CGFloat = 12
        let contentArea = max(0, width - sidebarWidth - divider)
        let available = max(0, contentArea - horizontalPadding)
        let cols = Int(floor((available + spacing) / (cardWidth + spacing)))
        return max(1, cols)
    }
    private func moveSelectionLeft() {
        guard !items.isEmpty else { return }
        if layoutStyle() == .grid {
            let idx = currentIndex() ?? 0
            selectionByKeyboard = true
            setIndex(idx - 1)
        } else {
            let idx = currentIndex() ?? 0
            selectionByKeyboard = true
            setIndex(idx - 1)
        }
    }
    private func moveSelectionRight() {
        guard !items.isEmpty else { return }
        let idx = currentIndex() ?? 0
        selectionByKeyboard = true
        setIndex(idx + 1)
    }
    private func moveSelectionUp() {
        guard !items.isEmpty else { return }
        if layoutStyle() == .grid {
            let cols = estimatedGridColumns()
            let idx = currentIndex() ?? 0
            selectionByKeyboard = true
            setIndex(idx - cols)
        } else if layoutStyle() == .vertical {
            let idx = currentIndex() ?? 0
            selectionByKeyboard = true
            setIndex(idx - 1)
        }
    }
    private func moveSelectionDown() {
        guard !items.isEmpty else { return }
        if layoutStyle() == .grid {
            let cols = estimatedGridColumns()
            let idx = currentIndex() ?? 0
            selectionByKeyboard = true
            setIndex(idx + cols)
        } else if layoutStyle() == .vertical {
            let idx = currentIndex() ?? 0
            selectionByKeyboard = true
            setIndex(idx + 1)
        }
    }
    private func confirmSelectionAndPaste(formatOverride: TextFormatMode?) {
        if let id = selectedItemID, let item = items.first(where: { $0.id == id }) {
            onDefaultAction(item, formatOverride: formatOverride)
        } else if let first = items.first {
            onDefaultAction(first, formatOverride: formatOverride)
        }
    }
    
    func directPasteItem(_ item: ClipItem, format: TextFormatMode? = nil) {
        if paste.checkAccessibilityPermission() {
            // Direct paste
            panel.hide()
            monitor.suppressCaptures(for: 1.0)
            paste.directPaste(item, format: format ?? appSettings.defaultTextFormat)
            store.moveToFront(item.id)
            refresh()
        } else {
            showAccessibilityAlert()
        }
    }
    
    func directPasteSelected() {
        if paste.checkAccessibilityPermission() {
            let ids = Array(selectedIDs)
            guard !ids.isEmpty else { return }
            let orderedIDs = selectedOrder.filter { selectedIDs.contains($0) }
            let finalIDs = orderedIDs.isEmpty ? ids : orderedIDs
            let itemsToCopy = finalIDs.compactMap { id in items.first(where: { $0.id == id }) }
            let parts: [String] = itemsToCopy.map { plainText(of: $0) }
            let joined = parts.joined(separator: "\n\n")
            
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(joined, forType: .string)
            
            panel.hide()
            monitor.suppressCaptures(for: 1.0)
            paste.triggerPasteCommand()
            clearSelection()
        } else {
            showAccessibilityAlert()
        }
    }
    
    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = L("alert.accessibility.title")
        alert.informativeText = L("alert.accessibility.message")
        alert.addButton(withTitle: L("alert.accessibility.openSettings"))
        alert.addButton(withTitle: L("alert.cancel"))
        let resp = alert.runModal()
        if resp == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func openSettings() {
        panel.hide()
        DispatchQueue.main.async { [weak self] in
            self?.onOpenSettings?()
        }
    }

    func onDefaultAction(_ item: ClipItem, formatOverride: TextFormatMode? = nil) {
        let format = formatOverride ?? appSettings.defaultTextFormat
        if appSettings.defaultAction == .paste {
            directPasteItem(item, format: format)
        } else {
            pasteItem(item, format: format)
        }
    }

    var enterActionHint: String {
        let action = appSettings.defaultAction == .paste ? L("panel.enterAction.paste") : L("panel.enterAction.copy")
        let format = appSettings.defaultTextFormat == .plainText ? L("panel.enterFormat.plain") : L("panel.enterFormat.formatted")
        return "↩ \(action) · \(format)"
    }
}
