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

/// iOS 17 自绘液态玻璃：低白度通透玻璃 + 边缘色散 + 底部内阴影
/// （系统 glassEffect 需要 iOS 26，这里用材质、渐变与描边模拟同等观感）
struct LiquidGlassSurface<S: InsettableShape>: View {
    let shape: S
    /// 边缘高光强度，大面积栏位可适当调低
    var borderStrength: Double = 1

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark

        ZStack {
            // 背景模糊与轻微提饱和，玻璃通透感的来源
            shape.fill(.ultraThinMaterial)
            shape.fill(Color.white.opacity(isDark ? 0.02 : 0.03))

            // 玻璃体色：只保留很低的白色叠加，避免塑料感
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(isDark ? 0.10 : 0.20), location: 0),
                        .init(color: Color.white.opacity(isDark ? 0.03 : 0.07), location: 0.40),
                        .init(color: Color.white.opacity(isDark ? 0.01 : 0.02), location: 0.70),
                        .init(color: Color.white.opacity(isDark ? 0.05 : 0.12), location: 1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            // 左上体积光：光从玻璃内部透出
            shape.fill(
                RadialGradient(
                    colors: [Color.white.opacity(isDark ? 0.13 : 0.34), Color.white.opacity(0)],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 170
                )
            )

            // 底部内阴影：让玻璃有厚度与体积
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: Color.clear, location: 0.58),
                        .init(color: Color.black.opacity(isDark ? 0.34 : 0.15), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .blendMode(isDark ? .normal : .multiply)

            // 边缘色散：左上偏青、右下偏粉，模拟玻璃折射
            shape.strokeBorder(
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: 0x7AE8FF).opacity(isDark ? 0.55 : 0.75), location: 0),
                        .init(color: Color.clear, location: 0.46),
                        .init(color: Color(hex: 0xFF8FD8).opacity(isDark ? 0.5 : 0.7), location: 1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.6
            )
            .blur(radius: 1.1)
            .mask(shape)
            .opacity(borderStrength)

            // 边缘高光
            shape.strokeBorder(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(isDark ? 0.6 : 0.95), location: 0),
                        .init(color: Color.white.opacity(isDark ? 0.1 : 0.28), location: 0.34),
                        .init(color: Color.white.opacity(isDark ? 0.04 : 0.12), location: 0.66),
                        .init(color: Color.white.opacity(isDark ? 0.4 : 0.8), location: 1)
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
                    colors: [Color.clear, Color.white.opacity(isDark ? 0.1 : 0.3)],
                    startPoint: .center,
                    endPoint: .bottom
                ),
                lineWidth: 0.8
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
        let isDark = colorScheme == .dark

        if uiStyle == UIStyleMode.glass.rawValue {
            content
                .background {
                    LiquidGlassSurface(shape: shape)
                        // 体积光：贴合轮廓外扩的微光
                        .shadow(
                            color: Color.splayerAccent.opacity(isDark ? 0.28 : 0.14),
                            radius: 18,
                            y: 2
                        )
                        // 外层落影
                        .shadow(
                            color: .black.opacity(isDark ? 0.5 : 0.16),
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

// MARK: - 果冻按压

/// 果冻按压反馈：按压时横向微撑、纵向回缩，松手弹回
struct JellyPressButtonStyle: ButtonStyle {
    var scale: CGFloat = 1

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                x: configuration.isPressed ? 1.05 : 1,
                y: configuration.isPressed ? 0.93 : 1
            )
            .scaleEffect(scale)
            .animation(
                .spring(response: 0.42, dampingFraction: 0.55),
                value: configuration.isPressed
            )
    }
}

// MARK: - 背景光晕

/// 液态玻璃模式的应用背景：极光光带与彩色光斑，为玻璃提供折射层次
struct LiquidGlassAmbientBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 320)
            let height = max(geo.size.height, 480)
            let isDark = colorScheme == .dark

            ZStack {
                if isDark {
                    LinearGradient(
                        colors: [Color(hex: 0x0A1020), Color(hex: 0x141033)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    LinearGradient(
                        colors: [Color(hex: 0xEAF2FB), Color(hex: 0xF8EEF9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

                // 极光光带
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: 0x5AD1FF).opacity(isDark ? 0.42 : 0.5),
                                Color(hex: 0x8A7CFF).opacity(isDark ? 0.34 : 0.38)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width * 1.1, height: height * 0.3)
                    .blur(radius: 80)
                    .rotationEffect(.degrees(-24))
                    .offset(x: -width * 0.2, y: -height * 0.26)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: 0xFF7BC8).opacity(isDark ? 0.36 : 0.42),
                                Color(hex: 0x8A7CFF).opacity(isDark ? 0.26 : 0.26)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width * 1.15, height: height * 0.26)
                    .blur(radius: 90)
                    .rotationEffect(.degrees(18))
                    .offset(x: width * 0.22, y: height * 0.2)

                // 主题色光斑
                Circle()
                    .fill(Color.splayerAccent.opacity(isDark ? 0.34 : 0.28))
                    .frame(width: width * 0.72)
                    .blur(radius: 100)
                    .offset(x: -width * 0.3, y: height * 0.34)

                // 左上主光源
                Circle()
                    .fill(Color.white.opacity(isDark ? 0.08 : 0.55))
                    .frame(width: width * 0.7)
                    .blur(radius: 110)
                    .offset(x: -width * 0.28, y: -height * 0.38)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}