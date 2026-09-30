import Foundation

// 剪贴类型枚举
public enum ClipType: String, Codable, CaseIterable {
    case text
    case link
    case image
    case file
    case color
}

public enum HistoryLayoutStyle: String, Codable, CaseIterable {
    case horizontal
    case grid
    case vertical
}

public enum AppearanceMode: String, Codable, CaseIterable {
    case light
    case dark
    case system
}

public enum DefaultAction: String, Codable, CaseIterable {
    case copy
    case paste
}

/// Controls how text-like clipboard items are written back to NSPasteboard.
public enum TextFormatMode: String, Codable, CaseIterable {
    case plainText
    case preserveFormatting
}

// 搜索过滤条件：按类型与来源应用过滤
public struct SearchFilters: Codable, Equatable {
    public var types: [ClipType]
    public var sourceApps: [String]
    public init(types: [ClipType] = [], sourceApps: [String] = []) {
        self.types = types
        self.sourceApps = sourceApps
    }
}
