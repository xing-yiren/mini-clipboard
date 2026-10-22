import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 图片负载服务：粘贴板中的图片数据（TIFF/PNG/JPEG 等）并不总是与其声明的
// 类型一致（例如系统截图得到的是 TIFF，却被存成 .png）。统一在这里识别真实
// 格式并重编码为标准的 PNG/HEIC，保证写入粘贴板和落盘的数据始终有效。
public enum ImagePayloadService {
    /// 识别图片数据的真实格式
    public static func detectUTType(of data: Data) -> UTType? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) else { return nil }
        return UTType(identifier as String)
    }

    /// 从任意常见图片数据中解码出 CGImage
    public static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
    }

    /// 把 NSImage 编码为指定格式（默认 PNG）。优先使用原始位图，避免 tiffRepresentation 的额外损失。
    public static func encode(_ image: NSImage, as type: UTType = .png) -> Data? {
        guard let cg = bestCGImage(from: image) else { return nil }
        return encode(cg, as: type)
    }

    /// 把任意图片数据重编码为指定格式
    public static func encode(_ data: Data, as type: UTType = .png) -> Data? {
        guard let cg = cgImage(from: data) else { return nil }
        return encode(cg, as: type)
    }

    public static func encode(_ cgImage: CGImage, as type: UTType = .png) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// 检查数据是否与期望格式一致；不一致时重编码为期望格式，无法解码时返回 nil。
    public static func normalize(_ data: Data, to type: UTType = .png) -> Data? {
        guard let actual = detectUTType(of: data) else { return nil }
        // UTType 对不同的具体类型（png/heic/jpeg）不构成“遵从”关系，直接比较即可
        if actual == type { return data }
        guard let cg = cgImage(from: data) else { return nil }
        return encode(cg, as: type)
    }

    /// 根据文件真实内容推导图片类型，无法识别时回退到扩展名，最后回退 PNG。
    public static func type(ofFileAt url: URL) -> UTType {
        if let data = try? Data(contentsOf: url), let actual = detectUTType(of: data) {
            return actual
        }
        if let ext = UTType(filenameExtension: url.pathExtension), ext.conforms(to: .image) {
            return ext
        }
        return .png
    }

    
    private static func bestCGImage(from image: NSImage) -> CGImage? {
        let candidates = image.representations.compactMap { $0 as? NSBitmapImageRep }
        let best = candidates.max { lhs, rhs in
            lhs.pixelsWide * lhs.pixelsHigh < rhs.pixelsWide * rhs.pixelsHigh
        }
        if let cg = best?.cgImage { return cg }
        var rect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
