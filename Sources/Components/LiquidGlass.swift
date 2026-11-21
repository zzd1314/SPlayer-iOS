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

// MARK: - 玻璃参数

/// 对应 liquid_glass_widgets 的 RecommendedGlassSettings。
/// 着色器以 SDF 法线计算定向镜面高光，玻璃体只保留极低白度。
enum LiquidGlassVariant {
    /// 卡片、列表分组
    case standard
    /// App 栏、侧栏、工具栏
    case surface
    /// 底部播放栏
    case bottomBar
    /// 输入框、搜索框
    case input
    /// 弹窗、面板
    case overlay

    var thickness: Double {
        switch self {
        case .standard: return 0
        case .bottomBar: return 20
        default: return 10
        }
    }

    var glassAlpha: Double {
        switch self {
        case .surface: return 0.20
        case .bottomBar: return 0.08
        default: return 0.12
        }
    }

    var ambient: Double {
        switch self {
        case .surface: return 0.3
        case .bottomBar: return 0.5
        default: return 0.4
        }
    }

    var refractiveIndex: Double {
        switch self {
        case .surface: return 1.15
        case .bottomBar: return 1.2
        default: return 0.7
        }
    }

    /// 光源方向：135°，左上高光 + 右下回弹
    var lightAngle: Double { 135 }

    var lightIntensity: Double { 0.7 }

    /// 玻璃体亮度（着色器 bodyColor）
    var bodyLuma: Double {
        ambient + 0.1 * (1 + lightIntensity * 0.15)
    }
}

// MARK: - 玻璃表面

/// iOS 17 自绘液态玻璃：
/// 背景模糊 + 低白度玻璃体 + SDF 边缘镜面高光（对齐 liquid_glass_widgets）
struct LiquidGlassSurface<S: InsettableShape>: View {
    let shape: S
    /// 形状圆角，用于边缘法线计算；矩形传 0，胶囊传高度的一半
    var cornerRadius: CGFloat = 0
    var variant: LiquidGlassVariant = .standard
    /// 边缘高光强度，大面积栏位可适当调低
    var borderStrength: Double = 1

    var body: some View {
        ZStack {
            // 背景模糊：对应 BackdropFilter sigma 10
            shape.fill(.ultraThinMaterial)

            // 玻璃体：极低白度，只做轻微提亮（保持着色器的预乘透明度）
            shape.fill(Color(white: variant.bodyLuma, opacity: variant.glassAlpha))

            // 边缘：0.5pt 发丝高光 + 定向镜面
            LiquidGlassRim(cornerRadius: cornerRadius, variant: variant)
                .clipShape(shape)
                .opacity(borderStrength)
        }
    }
}

// MARK: - 边缘镜面

/// 复刻 lightweight_glass.frag 的 STAGE 4–7：
/// 按边缘外法线与光源夹角计算主高光与背面回弹高光
private struct LiquidGlassRim: View {
    let cornerRadius: CGFloat
    let variant: LiquidGlassVariant

    var body: some View {
        Canvas { context, size in
            let segments = Self.segments(size: size, radius: cornerRadius)
            guard !segments.isEmpty else { return }

            for segment in segments {
                let specular = Self.specular(normal: segment.normal, variant: variant)
                var path = Path()
                path.move(to: segment.start)
                path.addLine(to: segment.end)
                context.stroke(
                    path,
                    with: .color(Color(
                        white: specular.color,
                        opacity: specular.opacity
                    )),
                    style: StrokeStyle(lineWidth: 1, lineCap: .butt)
                )
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: 边缘采样

    private struct Segment {
        let start: CGPoint
        let end: CGPoint
        let normal: CGVector
    }

    private static func segments(size: CGSize, radius: CGFloat) -> [Segment] {
        let w = size.width
        let h = size.height
        guard w > 1, h > 1 else { return [] }

        let r = min(max(radius, 0), min(w, h) / 2)
        var samples: [(CGPoint, CGVector)] = []

        func add(_ point: CGPoint, _ normal: CGVector) {
            if let last = samples.last,
               distance(last.0, point) < 0.01,
               abs(last.1.dx - normal.dx) < 0.001,
               abs(last.1.dy - normal.dy) < 0.001 {
                return
            }
            samples.append((point, normal))
        }

        if r < 0.5 {
            // 直角矩形：四条边，拐角处保留各自法线
            add(CGPoint(x: 0, y: 0), CGVector(dx: 0, dy: -1))
            add(CGPoint(x: w, y: 0), CGVector(dx: 0, dy: -1))
            add(CGPoint(x: w, y: 0), CGVector(dx: 1, dy: 0))
            add(CGPoint(x: w, y: h), CGVector(dx: 1, dy: 0))
            add(CGPoint(x: w, y: h), CGVector(dx: 0, dy: 1))
            add(CGPoint(x: 0, y: h), CGVector(dx: 0, dy: 1))
            add(CGPoint(x: 0, y: h), CGVector(dx: -1, dy: 0))
            add(CGPoint(x: 0, y: 0), CGVector(dx: -1, dy: 0))
        } else {
            // 上边
            add(CGPoint(x: r, y: 0), CGVector(dx: 0, dy: -1))
            add(CGPoint(x: w - r, y: 0), CGVector(dx: 0, dy: -1))
            // 右上角
            appendArc(center: CGPoint(x: w - r, y: r), radius: r,
                      from: -.pi / 2, to: 0, into: &samples)
            // 右边
            add(CGPoint(x: w, y: r), CGVector(dx: 1, dy: 0))
            add(CGPoint(x: w, y: h - r), CGVector(dx: 1, dy: 0))
            // 右下角
            appendArc(center: CGPoint(x: w - r, y: h - r), radius: r,
                      from: 0, to: .pi / 2, into: &samples)
            // 下边
            add(CGPoint(x: w - r, y: h), CGVector(dx: 0, dy: 1))
            add(CGPoint(x: r, y: h), CGVector(dx: 0, dy: 1))
            // 左下角
            appendArc(center: CGPoint(x: r, y: h - r), radius: r,
                      from: .pi / 2, to: .pi, into: &samples)
            // 左边
            add(CGPoint(x: 0, y: h - r), CGVector(dx: -1, dy: 0))
            add(CGPoint(x: 0, y: r), CGVector(dx: -1, dy: 0))
            // 左上角
            appendArc(center: CGPoint(x: r, y: r), radius: r,
                      from: .pi, to: .pi * 1.5, into: &samples)
        }

        guard samples.count >= 2 else { return [] }

        var result: [Segment] = []
        result.reserveCapacity(samples.count)
        for index in samples.indices {
            let current = samples[index]
            let next = samples[(index + 1) % samples.count]
            var nx = current.1.dx + next.1.dx
            var ny = current.1.dy + next.1.dy
            let length = (nx * nx + ny * ny).squareRoot()
            if length > 0.0001 {
                nx /= length
                ny /= length
            } else {
                nx = current.1.dx
                ny = current.1.dy
            }
            result.append(Segment(
                start: current.0,
                end: next.0,
                normal: CGVector(dx: nx, dy: ny)
            ))
        }
        return result
    }

    /// 按弧长密度采样圆角
    private static func appendArc(
        center: CGPoint,
        radius: CGFloat,
        from start: CGFloat,
        to end: CGFloat,
        into samples: inout [(CGPoint, CGVector)]
    ) {
        let arcLength = abs(end - start) * radius
        let count = max(6, Int(arcLength / 1.2))
        for step in 0...count {
            let angle = start + (end - start) * CGFloat(step) / CGFloat(count)
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            let normal = CGVector(dx: cos(angle), dy: sin(angle))
            if let last = samples.last,
               distance(last.0, point) < 0.01 {
                continue
            }
            samples.append((point, normal))
        }
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    // MARK: 高光计算

    private static func specular(
        normal: CGVector,
        variant: LiquidGlassVariant
    ) -> (color: Double, opacity: Double) {
        let radians = variant.lightAngle * .pi / 180
        let lightX = cos(radians)
        let lightY = -sin(radians)
        let dot = Double(normal.dx) * lightX + Double(normal.dy) * lightY

        let thicknessOffset = (variant.thickness - 10) / 10
        let sharpness = 1 + thicknessOffset * 0.15

        let key = pow(max(dot, 0), 14 * sharpness) * variant.lightIntensity
        let kick = pow(max(-dot, 0), 20 * sharpness) * variant.lightIntensity * 0.4
        let total = key + kick

        // 边缘基础亮度与不透明度
        let rimBase = max(0.5, 0.4 * variant.lightIntensity * 0.6) + thicknessOffset * 0.10
        let rimBrightness = min(1, rimBase + total * 0.6)

        var rimAlpha = 0.8 * variant.refractiveIndex + total * 0.5
        rimAlpha *= 1 + thicknessOffset * 0.15
        rimAlpha = min(1, max(0, rimAlpha))

        // 与玻璃体混合后输出，对应着色器 STAGE 7
        let color = variant.bodyLuma * (1 - rimAlpha) + rimBrightness * rimAlpha
        let opacity = max(variant.glassAlpha, rimAlpha * 0.8)
        return (color, opacity)
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
                    LiquidGlassSurface(
                        shape: shape,
                        cornerRadius: cornerRadius,
                        variant: .standard
                    )
                    .shadow(
                        color: .black.opacity(isDark ? 0.45 : 0.16),
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

// MARK: - 按压反馈

/// 对齐 LiquidStretch：按下整体放大 5%，300ms 临界阻尼回弹，并带按压辉光
struct JellyPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.05 : 1)
            .shadow(
                color: .white.opacity(configuration.isPressed ? 0.45 : 0),
                radius: configuration.isPressed ? 10 : 0
            )
            .animation(
                .spring(response: 0.3, dampingFraction: 1),
                value: configuration.isPressed
            )
    }
}

// MARK: - 背景光晕

/// 液态玻璃模式的壁纸背景：大面积柔光色块，为玻璃提供折射层次
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
                        colors: [Color(hex: 0x05060C), Color(hex: 0x0C0A1A)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    LinearGradient(
                        colors: [Color(hex: 0xEEF3FB), Color(hex: 0xFDF1F6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

                // 暖橙
                Circle()
                    .fill(Color(hex: 0xFF6A3D).opacity(isDark ? 0.30 : 0.20))
                    .frame(width: width * 0.95)
                    .blur(radius: 110)
                    .offset(x: width * 0.34, y: -height * 0.28)

                // 蓝
                Circle()
                    .fill(Color(hex: 0x3D7BFF).opacity(isDark ? 0.30 : 0.24))
                    .frame(width: width * 0.9)
                    .blur(radius: 120)
                    .offset(x: -width * 0.34, y: -height * 0.02)

                // 品红
                Circle()
                    .fill(Color(hex: 0xFF4FA3).opacity(isDark ? 0.24 : 0.22))
                    .frame(width: width * 0.85)
                    .blur(radius: 120)
                    .offset(x: width * 0.22, y: height * 0.32)

                // 青绿
                Circle()
                    .fill(Color(hex: 0x24D3C0).opacity(isDark ? 0.20 : 0.16))
                    .frame(width: width * 0.75)
                    .blur(radius: 110)
                    .offset(x: -width * 0.18, y: height * 0.26)

                // 主题色
                Circle()
                    .fill(Color.splayerAccent.opacity(isDark ? 0.22 : 0.18))
                    .frame(width: width * 0.6)
                    .blur(radius: 100)
                    .offset(x: width * 0.1, y: height * 0.02)

                // 左上主光源
                Circle()
                    .fill(Color.white.opacity(isDark ? 0.06 : 0.5))
                    .frame(width: width * 0.7)
                    .blur(radius: 110)
                    .offset(x: -width * 0.3, y: -height * 0.4)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}