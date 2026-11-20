import SwiftUI
import UIKit

extension Color {
    /// 0xRRGGBB 初始化
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// 形如 "FE7971" / "#FE7971" / "FE7971FF"
    init?(hexString: String) {
        var value = hexString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        if value.count == 6 {
            value += "FF"
        }
        guard value.count == 8, let number = UInt32(value, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((number >> 24) & 0xFF) / 255,
            green: Double((number >> 16) & 0xFF) / 255,
            blue: Double((number >> 8) & 0xFF) / 255,
            opacity: Double(number & 0xFF) / 255
        )
    }

    var hexString: String? {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return String(
            format: "%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    /// SPlayer 品牌主色 #FE7971
    static let splayerAccent = Color(hex: 0xFE7971)
}

// MARK: - 自定义背景图

enum BackgroundImageStore {
    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("splayer-background.jpg")
    }

    static func load() -> UIImage? {
        UIImage(contentsOfFile: fileURL.path)
    }

    @discardableResult
    static func save(_ data: Data) -> Bool {
        guard let image = UIImage(data: data),
              let jpeg = image.jpegData(compressionQuality: 0.9)
        else { return false }
        do {
            try jpeg.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// 应用全局背景（纯色 / 自定义图片 + 模糊 + 遮罩）
struct AppBackground: View {
    @AppStorage("appearanceStyle") private var appearanceStyle = "solid"
    @AppStorage("backgroundBlur") private var backgroundBlur = 20.0
    @AppStorage("backgroundDim") private var backgroundDim = 0.32
    @AppStorage("backgroundRevision") private var backgroundRevision = 0

    var body: some View {
        let _ = backgroundRevision
        GeometryReader { geo in
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                if appearanceStyle == "image", let image = BackgroundImageStore.load() {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .blur(radius: backgroundBlur)
                        .overlay(Color.black.opacity(backgroundDim))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - 列表透明背景

extension View {
    /// 使用自定义背景图时隐藏列表自带的不透明背景
    func adaptiveListBackground() -> some View {
        modifier(AdaptiveListBackground())
    }
}

private struct AdaptiveListBackground: ViewModifier {
    @AppStorage("appearanceStyle") private var appearanceStyle = "solid"

    func body(content: Content) -> some View {
        if appearanceStyle == "image" {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}
