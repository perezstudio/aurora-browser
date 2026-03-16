import SwiftUI
import AppKit

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        default:
            r = 1; g = 1; b = 1
        }
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Hover Button Style

enum HoverButtonSize {
    case small, regular, large

    var dimension: CGFloat {
        switch self {
        case .small: 24
        case .regular: 28
        case .large: 32
        }
    }

    var symbolSize: CGFloat {
        switch self {
        case .small: 12
        case .regular: 13
        case .large: 15
        }
    }
}

struct HoverButtonStyle: ButtonStyle {
    let size: HoverButtonSize
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size.symbolSize))
            .foregroundStyle(.secondary)
            .frame(width: size.dimension, height: size.dimension)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(
                        configuration.isPressed ? 0.15 : (isHovered ? 0.08 : 0)
                    ))
            )
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}

extension ButtonStyle where Self == HoverButtonStyle {
    static func hoverButton(size: HoverButtonSize = .regular) -> HoverButtonStyle {
        HoverButtonStyle(size: size)
    }
}

// MARK: - Visual Effect Background

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    init(material: NSVisualEffectView.Material = .sidebar, blendingMode: NSVisualEffectView.BlendingMode = .behindWindow) {
        self.material = material
        self.blendingMode = blendingMode
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
