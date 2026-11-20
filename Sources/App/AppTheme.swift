import SwiftUI

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

    /// SPlayer 品牌主色 #FE7971
    static let splayerAccent = Color(hex: 0xFE7971)
}
