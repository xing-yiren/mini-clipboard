import SwiftUI
import AppKit
import Combine

/// Back-deployable value-change observer for the project's macOS 12 target.
/// SwiftUI's newer two-parameter `onChange` overload requires macOS 14.
struct ValueChangeModifier<Value: Equatable>: ViewModifier {
    let value: Value
    let action: (Value) -> Void
    @State private var previousValue: Value

    init(value: Value, action: @escaping (Value) -> Void) {
        self.value = value
        self.action = action
        _previousValue = State(initialValue: value)
    }

    func body(content: Content) -> some View {
        content.onReceive(Just(value)) { newValue in
            guard newValue != previousValue else { return }
            previousValue = newValue
            action(newValue)
        }
    }
}

extension View {
    func onValueChange<Value: Equatable>(of value: Value, perform action: @escaping (Value) -> Void) -> some View {
        modifier(ValueChangeModifier(value: value, action: action))
    }
}

struct PanelRootView: View {
    @ObservedObject var controller: AppController
    @State private var showSearchPopover: Bool = false
    @FocusState private var searchPopoverFocused: Bool
    @State private var tab: Int = 0
    @State private var sidebarWidth: CGFloat = 180
    @State private var dragStartWidth: CGFloat = 180
    @State private var isDragging: Bool = false
    @AppStorage("sidebarCollapsed") private var sidebarCollapsed: Bool = false
    @State private var lastExpandedSidebarWidth: CGFloat = 180
    private let collapsedSidebarWidth: CGFloat = 44
    @State private var showNewBoardPopover: Bool = false
    @State private var newBoardName: String = ""
    @State private var editingBoard: Pinboard?
    @State private var showRenamePopover: Bool = false
    @State private var showColorPopover: Bool = false
    @State private var renameInput: String = ""
    @State private var colorInput: String = ""
    @AppStorage("historyLayoutStyle") private var layoutStyleRaw: String = "horizontal"
    @AppStorage("panelPositionVertical") private var panelPositionVertical: Double = 0
    @AppStorage("panelPositionHorizontal") private var panelPositionHorizontal: Double = 0
    @AppStorage("panelCornerRadius") private var panelCornerRadius: Double = 16
    @AppStorage("panelHorizontalWidthPercent") private var panelHorizontalWidthPercent: Double = 90
    @AppStorage("panelVerticalHeightPercent") private var panelVerticalHeightPercent: Double = 90
    @AppStorage("panelGridWidthPercent") private var panelGridWidthPercent: Double = 80
    @AppStorage("panelGridHeightPercent") private var panelGridHeightPercent: Double = 80
    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                leftColumn
                separatorView
                mainArea
            }
        }
        .background(AppTheme.panelBackground)
        .coordinateSpace(name: "PanelWindow")
        .onAppear {
            if sidebarCollapsed {
                lastExpandedSidebarWidth = max(lastExpandedSidebarWidth, sidebarWidth)
                sidebarWidth = collapsedSidebarWidth
            }
            controller.sidebarWidth = sidebarWidth
            UserDefaults.standard.set(Double(sidebarWidth), forKey: "sidebarWidth")
            UserDefaults.standard.set(Double(lastExpandedSidebarWidth), forKey: "lastExpandedSidebarWidth")
        }
        .onValueChange(of: sidebarWidth) { w in
            controller.sidebarWidth = w
            UserDefaults.standard.set(Double(w), forKey: "sidebarWidth")
            controller.panel.updateLayoutHeight(animated: !isDragging)
        }
        .onValueChange(of: sidebarCollapsed) { c in
            if c {
                lastExpandedSidebarWidth = max(lastExpandedSidebarWidth, sidebarWidth)
                sidebarWidth = collapsedSidebarWidth
                controller.clearSelection()
                UserDefaults.standard.set(Double(lastExpandedSidebarWidth), forKey: "lastExpandedSidebarWidth")
            } else {
                if sidebarWidth <= collapsedSidebarWidth + 1 {
                    sidebarWidth = max(lastExpandedSidebarWidth, 180)
                }
                UserDefaults.standard.set(Double(lastExpandedSidebarWidth), forKey: "lastExpandedSidebarWidth")
            }
        }
        .onValueChange(of: layoutStyleRaw) { _ in controller.panel.updateLayoutHeight(animated: true) }
        .onValueChange(of: panelPositionVertical) { _ in controller.panel.updateLayoutHeight(animated: true) }
        .onValueChange(of: panelPositionHorizontal) { _ in controller.panel.updateLayoutHeight(animated: true) }
        .onValueChange(of: panelHorizontalWidthPercent) { _ in controller.panel.updateLayoutHeight(animated: true) }
        .onValueChange(of: panelVerticalHeightPercent) { _ in controller.panel.updateLayoutHeight(animated: true) }
        .onValueChange(of: panelGridWidthPercent) { _ in controller.panel.updateLayoutHeight(animated: true) }
        .onValueChange(of: panelGridHeightPercent) { _ in controller.panel.updateLayoutHeight(animated: true) }
        .onValueChange(of: panelCornerRadius) { _ in controller.panel.updateCornerRadius() }
        .frame(minWidth: minWidthForLayout, minHeight: 260)
    }
    private var toolbar: some View {
        HStack {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.22)) {
                    sidebarCollapsed = true
                    lastExpandedSidebarWidth = sidebarWidth
                    sidebarWidth = collapsedSidebarWidth
                }
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
            }
            .buttonStyle(.borderless)
            if !controller.query.isEmpty {
                Button(action: { controller.query = ""; controller.refresh() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            Button(action: { showNewBoardPopover = true }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $showNewBoardPopover) {
                NewBoardPopoverContent(controller: controller,
                                       newBoardName: $newBoardName,
                                       onDismiss: { showNewBoardPopover = false })
                    .frame(width: 220)
            }
            Button(action: {
                let current = HistoryLayoutStyle(rawValue: layoutStyleRaw) ?? .horizontal
                let next: HistoryLayoutStyle = {
                    switch current {
                    case .horizontal: return .grid
                    case .grid: return .vertical
                    case .vertical: return .horizontal
                    }
                }()
                layoutStyleRaw = next.rawValue
            }) {
                let current = HistoryLayoutStyle(rawValue: layoutStyleRaw) ?? .horizontal
                let nextIcon: String = {
                    switch current {
                    case .horizontal: return "square.grid.2x2"
                    case .grid: return "list.bullet.rectangle.portrait"
                    case .vertical: return "list.bullet.rectangle"
                    }
                }()
                Image(systemName: nextIcon)
                    .font(.system(size: 12, weight: .bold))
            }
            .buttonStyle(.borderless)
            Button(action: { controller.toggleSelectionMode() }) {
                Image(systemName: controller.selectionMode ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 12, weight: .bold))
            }
            .buttonStyle(.borderless)
            Spacer(minLength: 6)
            Button(action: { controller.openSettings() }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help(L("panel.menu.settings"))
            Button(action: { controller.searchPopoverVisible = true }) {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $controller.searchPopoverVisible, attachmentAnchor: .rect(.bounds), arrowEdge: .leading) {
                HStack(spacing: 8) {
                    TextField(L("panel.search.placeholder"), text: $controller.query)
                        .textFieldStyle(.plain)
                        .focused($searchPopoverFocused)
                        .onSubmit { }
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 12)
                .frame(height: 32)
                .frame(width: 115)
                .background(Color.clear)
                .onAppear { searchPopoverFocused = true }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(AppTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: AppTheme.shadowColor, radius: 4, x: 0, y: 2)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        controller.searchBarWidth = geo.size.width
                        reportSearchFrame(geo)
                    }
                    .onValueChange(of: geo.size.width) { w in
                        controller.searchBarWidth = w
                        reportSearchFrame(geo)
                    }
            }
        )
    }
    private var selectionContent: some View {
        ZStack(alignment: .topLeading) {
            if controller.selectionMode || !controller.selectedIDs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(format: L("panel.selection.count"), controller.selectedIDs.count))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Button { controller.copySelectedPlainText() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.on.clipboard")
                                .foregroundColor(.blue)
                            Text(L("panel.selection.copyPlainText"))
                                .font(.system(size: 12))
                        }
                    }
                    .buttonStyle(.borderless)
                    Button { controller.copySelectedRichText() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.richtext")
                                .foregroundColor(.purple)
                            Text(L("panel.selection.copyRichText"))
                                .font(.system(size: 12))
                        }
                    }
                    .buttonStyle(.borderless)
                    Button { controller.directPasteSelected() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "keyboard")
                                .foregroundColor(.orange)
                            Text(L("panel.selection.directPaste"))
                                .font(.system(size: 12))
                        }
                    }
                    .buttonStyle(.borderless)
                    Button { controller.confirmDeleteSelected() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                            Text(L("panel.selection.deleteSelected"))
                                .font(.system(size: 12))
                        }
                    }
                    .buttonStyle(.borderless)
                    Menu {
                        ForEach(controller.boards.filter { $0.id != controller.store.defaultBoardID }) { b in
                            Button(action: { controller.addSelectedToBoard(b.id) }) {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(boardColor(b))
                                        .frame(width: 8, height: 8)
                                    Text(b.name)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.badge.plus")
                                .foregroundColor(.indigo)
                            Text(L("panel.selection.addToBoard"))
                                .font(.system(size: 12))
                        }
                    }
                    .menuStyle(.borderlessButton)
                    Divider()
                    Button { controller.clearSelection() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle")
                                .foregroundColor(.secondary)
                            Text(L("panel.selection.clearSelection"))
                                .font(.system(size: 12))
                        }
                    }
                    .buttonStyle(.borderless)
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: AppTheme.shadowColor, radius: 4, x: 0, y: 2)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(controller.boards) { b in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(boardColor(b))
                                    .frame(width: 10, height: 10)
                                Text(boardDisplayName(b))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle((controller.selectedBoardID == b.id) ? .white : .primary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Group { if controller.selectedBoardID == b.id { AppTheme.highlightGradient } else { Color.clear } }
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                            .contextMenu {
                                if b.id == controller.store.defaultBoardID || b.id == controller.store.favoritesBoardID {
                                    Text(L("panel.builtInBoard.uneditable"))
                                } else {
                                    Button(L("panel.editName")) { editingBoard = b; renameInput = b.name; showRenamePopover = true }
                                    Button(L("panel.changeColor")) { editingBoard = b; colorInput = b.color ?? ""; showColorPopover = true }
                                    Divider()
                                    Button(L("panel.deleteBoard")) { try? controller.store.deletePinboard(b.id); controller.refresh() }
                                }
                            }
                            .onTapGesture { controller.selectBoard(b.id) }
                            .popover(isPresented: Binding(get: { showRenamePopover && editingBoard?.id == b.id }, set: { v in showRenamePopover = v })) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(L("panel.rename.title")).font(.system(size: 13, weight: .medium))
                                    TextField(L("panel.name.placeholder"), text: $renameInput)
                                        .textFieldStyle(.roundedBorder)
                                        .onSubmit {
                                            let name = renameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                            if let id = editingBoard?.id { controller.store.updatePinboardName(id, name: name.isEmpty ? L("panel.rename.untitled") : name) }
                                            controller.refresh()
                                            showRenamePopover = false
                                        }
                                    HStack {
                                        Spacer()
                                        Button(L("panel.cancel")) { showRenamePopover = false }
                                        Button(L("timeline.rename.save")) {
                                            let name = renameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                            if let id = editingBoard?.id { controller.store.updatePinboardName(id, name: name.isEmpty ? L("panel.rename.untitled") : name) }
                                            controller.refresh()
                                            showRenamePopover = false
                                        }.keyboardShortcut(.defaultAction)
                                    }
                                }
                                .padding(12)
                                .frame(width: 220)
                            }
                            .popover(isPresented: Binding(get: { showColorPopover && editingBoard?.id == b.id }, set: { v in showColorPopover = v })) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(L("panel.boardColor.title")).font(.system(size: 13, weight: .medium))
                                    HStack(spacing: 8) {
                                        ForEach(["red","orange","yellow","green","blue","indigo","purple","pink"], id: \.self) { c in
                                            Circle()
                                                .fill(boardColor(Pinboard(name: "", color: c)))
                                                .frame(width: 16, height: 16)
                                                .onTapGesture {
                                                    if let id = editingBoard?.id { controller.store.updatePinboardColor(id, color: c) }
                                                    controller.refresh()
                                                    showColorPopover = false
                                                }
                                        }
                                        Button(L("panel.clear")) {
                                            if let id = editingBoard?.id { controller.store.updatePinboardColor(id, color: nil) }
                                            controller.refresh()
                                            showColorPopover = false
                                        }
                                    }
                                    TextField(L("panel.color.hexPlaceholder"), text: $colorInput)
                                        .textFieldStyle(.roundedBorder)
                                    HStack {
                                        Spacer()
                                        Button(L("panel.cancel")) { showColorPopover = false }
                                        Button(L("timeline.rename.save")) {
                                            var s = colorInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                            if s.isEmpty { s = "" }
                                            if let id = editingBoard?.id { controller.store.updatePinboardColor(id, color: s.isEmpty ? nil : s) }
                                            controller.refresh()
                                            showColorPopover = false
                                        }.keyboardShortcut(.defaultAction)
                                    }
                                }
                                .padding(12)
                                .frame(width: 260)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: controller.selectionMode)
        .animation(.easeInOut(duration: 0.25), value: controller.selectedIDs.count)
    }
    private var leftColumn: some View {
        Group {
            if sidebarCollapsed {
                VStack(spacing: 10) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            sidebarCollapsed = false
                            sidebarWidth = max(lastExpandedSidebarWidth, 180)
                        }
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .buttonStyle(.borderless)

                    Button(action: { showNewBoardPopover = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $showNewBoardPopover) {
                        NewBoardPopoverContent(controller: controller,
                                               newBoardName: $newBoardName,
                                               onDismiss: { showNewBoardPopover = false })
                            .frame(width: 220)
                    }

                    Button(action: {
                        let current = HistoryLayoutStyle(rawValue: layoutStyleRaw) ?? .horizontal
                        let next: HistoryLayoutStyle = {
                            switch current {
                            case .horizontal: return .grid
                            case .grid: return .vertical
                            case .vertical: return .horizontal
                            }
                        }()
                        layoutStyleRaw = next.rawValue
                    }) {
                        let current = HistoryLayoutStyle(rawValue: layoutStyleRaw) ?? .horizontal
                        let nextIcon: String = {
                            switch current {
                            case .horizontal: return "square.grid.2x2"
                            case .grid: return "list.bullet.rectangle.portrait"
                            case .vertical: return "list.bullet.rectangle"
                            }
                        }()
                        Image(systemName: nextIcon)
                            .font(.system(size: 14, weight: .bold))
                    }
                    .buttonStyle(.borderless)

                    // 折叠模式不支持批量选择，隐藏选择模式按钮

                    Button(action: { controller.searchPopoverVisible = true }) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $controller.searchPopoverVisible, attachmentAnchor: .rect(.bounds), arrowEdge: .leading) {
                        HStack(spacing: 8) {
                            TextField(L("panel.search.placeholder"), text: $controller.query)
                                .textFieldStyle(.plain)
                                .focused($searchPopoverFocused)
                                .onSubmit { }
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .frame(width: 115)
                        .background(Color.clear)
                        .onAppear { searchPopoverFocused = true }
                    }

                    Divider()

                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(controller.boards) { b in
                                BoardDotView(b: b,
                                             isSelected: controller.selectedBoardID == b.id,
                                             color: boardColor(b),
                                             onTap: { controller.selectBoard(b.id) },
                                             helpText: boardDisplayName(b))
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                .padding(.top, 16)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .transition(.move(edge: .leading).combined(with: .opacity))
            } else {
                VStack(spacing: 8) {
                    toolbar
                    selectionContent
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.25), value: controller.selectionMode)
                .animation(.easeInOut(duration: 0.25), value: controller.selectedIDs.count)
                .padding(12)
            }
        }
        .frame(width: sidebarWidth)
        .background(AppTheme.sidebarBackground)
    }
    private var separatorView: some View {
        ZStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.1))
                .frame(width: 1)
                .frame(maxHeight: .infinity)
        }
        .frame(width: 8)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            if !isDragging {
                if hovering { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if !isDragging { isDragging = true; dragStartWidth = sidebarWidth }
                    let minW: CGFloat = sidebarCollapsed ? collapsedSidebarWidth : 180
                    let maxW: CGFloat = 480
                    let newW = dragStartWidth + value.translation.width
                    sidebarWidth = max(minW, min(maxW, newW))
                    if sidebarCollapsed && sidebarWidth > 160 { sidebarCollapsed = false }
                }
                .onEnded { _ in
                    isDragging = false
                    if sidebarWidth <= collapsedSidebarWidth + 4 {
                        sidebarCollapsed = true
                        sidebarWidth = collapsedSidebarWidth
                    } else {
                        lastExpandedSidebarWidth = sidebarWidth
                    }
                    NSCursor.arrow.set()
                }
        )
    }
    private var mainArea: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                HistoryTimelineView(items: controller.items, boards: controller.boards, defaultBoardID: controller.store.defaultBoardID, currentBoardID: controller.selectedBoardID, onPaste: { item, format in controller.pasteItem(item, format: format) }, onAddToBoard: { item, bid in controller.addToBoard(item, bid) }, onToggleFavorite: { item in controller.toggleFavorite(item) }, onDelete: { item in controller.deleteItem(item) }, selectedItemID: controller.selectedItemID, onSelect: { item in controller.onItemTapped(item) }, onRename: { item, name in controller.renameItem(item, name: name) }, scrollOnSelection: controller.selectionByKeyboard, selectedIDs: controller.selectedIDs, selectedOrder: controller.selectedOrder, selectionMode: controller.selectionMode, onDefaultAction: { item in controller.onDefaultAction(item) }, onDirectPaste: { item in controller.directPasteItem(item) }, onSelectedItemFrame: { rect in
                    if let rect, let win = NSApp.keyWindow ?? NSApp.windows.first {
                        let windowHeight = win.contentView?.bounds.height ?? win.frame.size.height
                        let cocoaY = windowHeight - (rect.origin.y + rect.size.height)
                        let nsRect = NSRect(x: rect.origin.x, y: cocoaY, width: rect.size.width, height: rect.size.height)
                        let screenRect = win.convertToScreen(nsRect)
                        controller.panel.updatePreviewAnchorRect(screenRect)
                    } else {
                        controller.panel.updatePreviewAnchorRect(nil)
                    }
                })
                    .animation(.easeInOut(duration: 0.35), value: controller.items)
                    .animation(.easeInOut(duration: 0.35), value: layoutStyleRaw)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.panelBackground)
        .overlay(alignment: .bottomTrailing) {
            Text(controller.enterActionHint)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(8)
                .help(L("panel.enterAction.help"))
        }
        
    }
    private var isPanelInLowerHalfOfScreen: Bool {
        if let w = NSApp.keyWindow, let s = w.screen ?? NSScreen.main {
            let f = s.visibleFrame
            return w.frame.midY < f.midY
        }
        return true
    }

    
    private var layoutStyle: HistoryLayoutStyle { HistoryLayoutStyle(rawValue: layoutStyleRaw) ?? .horizontal }
    private var minWidthForLayout: CGFloat {
        switch layoutStyle {
        case .horizontal: return 880
        case .grid: return 880
        case .vertical:
            let base: CGFloat = 460
            if sidebarCollapsed {
                let collapsedW: CGFloat = collapsedSidebarWidth
                let delta = max(0, lastExpandedSidebarWidth - collapsedW)
                let minW: CGFloat = 300
                return max(minW, base - delta)
            }
            return base
        }
    }
    private func boardDisplayName(_ b: Pinboard) -> String {
        if b.id == controller.store.defaultBoardID && b.name == "剪贴板" { return L("boards.default.displayName") }
        if b.id == controller.store.favoritesBoardID { return L("boards.favorites.displayName") }
        return b.name
    }
    private func reportSearchFrame(_ geo: GeometryProxy) {
        if let win = NSApp.keyWindow ?? NSApp.windows.first {
            let local = geo.frame(in: .named("PanelWindow"))
            let windowHeight = win.contentView?.bounds.height ?? win.frame.size.height
            let cocoaY = windowHeight - (local.origin.y + local.size.height)
            let nsRect = NSRect(x: local.origin.x, y: cocoaY, width: local.size.width, height: local.size.height)
            let screenRect = win.convertToScreen(nsRect)
            controller.panel.updateSearchOverlayRect(screenRect)
        }
    }
    private func boardColor(_ b: Pinboard) -> Color {
        guard let s = b.color?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !s.isEmpty else { return .accentColor }
        switch s {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "indigo": return .indigo
        case "purple": return .purple
        case "pink": return .pink
        default:
            let hex = s.hasPrefix("#") ? String(s.dropFirst()) : s
            if hex.count == 6, let v = Int(hex, radix: 16) {
                let r = Double((v >> 16) & 0xFF) / 255.0
                let g = Double((v >> 8) & 0xFF) / 255.0
                let b = Double(v & 0xFF) / 255.0
                return Color(red: r, green: g, blue: b)
            }
            return .accentColor
        }
    }
}
private struct BoardDotView: View {
    var b: Pinboard
    var isSelected: Bool
    var color: Color
    var onTap: () -> Void
    var helpText: String
    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 16, height: 16)
            if isSelected {
                Circle()
                    .stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: 20, height: 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .help(helpText)
    }
}
private struct NewBoardPopoverContent: View {
    @ObservedObject var controller: AppController
    @Binding var newBoardName: String
    var onDismiss: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("panel.newBoard.title")).font(.system(size: 13, weight: .medium))
            TextField(L("panel.name.placeholder"), text: $newBoardName)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    let name = newBoardName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let presetColors = ["red","orange","yellow","green","blue","indigo","purple","pink"]
                    let randomColor = presetColors.randomElement()
                    _ = controller.store.createPinboard(name: name.isEmpty ? L("panel.newBoard.title") : name, color: randomColor)
                    controller.refresh()
                    onDismiss()
                    newBoardName = ""
                }
            HStack {
                Spacer()
                Button(L("panel.cancel")) { onDismiss(); newBoardName = "" }
                Button(L("panel.add")) {
                    let name = newBoardName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let presetColors = ["red","orange","yellow","green","blue","indigo","purple","pink"]
                    let randomColor = presetColors.randomElement()
                    _ = controller.store.createPinboard(name: name.isEmpty ? L("panel.newBoard.title") : name, color: randomColor)
                    controller.refresh()
                    onDismiss()
                    newBoardName = ""
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
    }
}
// 搜索弹窗视图已移除，统一由顶部按钮弹出
