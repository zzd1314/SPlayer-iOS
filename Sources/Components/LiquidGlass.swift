import SwiftUI

// MARK: - 界面风格

/// 界面风格：经典材质 / 液态玻璃
enum UIStyleMode: String, CaseIterable, Identifiable {
    case classic
    case glass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "经典"
        case .glass: return "液态玻璃"
        }
    }
}

// MARK: - 玻璃表面

/// iOS 17 自绘液态玻璃：超薄材质 + 渐变折射 + 边缘高光
/// （系统 glassEffect 需要 iOS 26，这里用材质与渐变模拟同等观感）
struct LiquidGlassSurface<S: InsettableShape>: View {
    let shape: S
    /// 边缘高光强度，大面积栏位可适当调低
    var borderStrength: Double = 1

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark

        ZStack {
            shape.fill(.ultraThinMaterial)

            // 玻璃体色：左上偏亮、中段通透、右下轻微反光
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(isDark ? 0.14 : 0.55), location: 0),
                        .init(color: Color.white.opacity(isDark ? 0.03 : 0.16), location: 0.42),
                        .init(color: Color.white.opacity(isDark ? 0.01 : 0.06), location: 0.72),
                        .init(color: Color.white.opacity(isDark ? 0.08 : 0.28), location: 1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            // 左上柔光
            shape.fill(
                RadialGradient(
                    colors: [Color.white.opacity(isDark ? 0.16 : 0.45), Color.white.opacity(0)],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 150
                )
            )

            // 边缘高光
            shape.strokeBorder(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(isDark ? 0.55 : 0.95), location: 0),
                        .init(color: Color.white.opacity(isDark ? 0.08 : 0.25), location: 0.32),
                        .init(color: Color.white.opacity(isDark ? 0.04 : 0.12), location: 0.62),
                        .init(color: Color.white.opacity(isDark ? 0.38 : 0.8), location: 1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
            .opacity(borderStrength)

            // 底部内侧反光
            shape.strokeBorder(
                LinearGradient(
                    colors: [Color.clear, Color.white.opacity(isDark ? 0.05 : 0.18)],
                    startPoint: .center,
                    endPoint: .bottom
                ),
                lineWidth: 0.75
            )
            .opacity(borderStrength)
        }
    }
}

// MARK: - 卡片背景

/// 卡片背景：液态玻璃模式使用玻璃表面，经典模式保持原有 thinMaterial
private struct AppCardBackgroundModifier: ViewModifier {
    @AppStorage("uiStyle") private var uiStyle = UIStyleMode.classic.rawValue
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if uiStyle == UIStyleMode.glass.rawValue {
            content
                .background {
                    LiquidGlassSurface(shape: shape)
                        .shadow(
                            color: .black.opacity(colorScheme == .dark ? 0.4 : 0.1),
                            radius: 12,
                            y: 6
                        )
                }
        } else {
            content
                .background(.thinMaterial, in: shape)
        }
    }
}

extension View {
    /// 卡片统一背景：随界面风格自动切换
    func appCardBackground(cornerRadius: CGFloat) -> some View {
        modifier(AppCardBackgroundModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - 背景光晕

/// 液态玻璃模式的应用背景：柔和彩色光晕，为玻璃材质提供折射层次
struct LiquidGlassAmbientBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 320)
            let height = max(geo.size.height, 480)
            let isDark = colorScheme == .dark

            ZStack {
                if isDark {
                    Color(hex: 0x14121A)
                } else {
                    LinearGradient(
                        colors: [Color(hex: 0xF7F5FB), Color(hex: 0xFFF6F1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

                Circle()
                    .fill(Color.splayerAccent.opacity(isDark ? 0.32 : 0.3))
                    .frame(width: width * 0.8)
                    .blur(radius: 90)
                    .offset(x: -width * 0.28, y: -height * 0.3)

                Circle()
                    .fill(Color(hex: 0x7C6BFF).opacity(isDark ? 0.3 : 0.22))
                    .frame(width: width * 0.9)
                    .blur(radius: 110)
                    .offset(x: width * 0.34, y: height * 0.02)

                Circle()
                    .fill(Color(hex: 0x4FA8FF).opacity(isDark ? 0.22 : 0.16))
                    .frame(width: width * 0.7)
                    .blur(radius: 100)
                    .offset(x: -width * 0.06, y: height * 0.44)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
