import SwiftUI

/// Windows dialog look used by PuTTY's configuration window.
enum Win {
    static let face = Color(rgb: 0xF0F0F0)
    static let border = Color(rgb: 0xADADAD)
    static let fieldBorder = Color(rgb: 0x7A7A7A)
    static let button = Color(rgb: 0xE1E1E1)
    static let buttonPressed = Color(rgb: 0xCCE4F7)
    static let accent = Color(rgb: 0x0078D7)
    static let groupLine = Color(rgb: 0xDCDCDC)
    static let disabled = Color(rgb: 0x838383)
    static let glyph = Color(rgb: 0x333333)
    static let treeBorder = Color(rgb: 0x828790)
    static let treeSelection = Color(rgb: 0xCCE8FF)
    static let treeSelectionBorder = Color(rgb: 0x99D1FF)
    static let desktop = Color(rgb: 0x0063B1)
    static let taskbar = Color(rgb: 0x1C1C1C)
    static let font = Font.system(size: 13)
    static let small = Font.system(size: 11)
}

extension Color {
    init(rgb: UInt32) {
        self.init(red: Double(rgb >> 16 & 0xff) / 255, green: Double(rgb >> 8 & 0xff) / 255, blue: Double(rgb & 0xff) / 255)
    }
}

struct WinButtonStyle: ButtonStyle {
    var isDefault = false
    var minWidth: CGFloat = 75

    func makeBody(configuration: Configuration) -> some View {
        WinButtonBody(configuration: configuration, isDefault: isDefault, minWidth: minWidth)
    }

    private struct WinButtonBody: View {
        let configuration: Configuration
        let isDefault: Bool
        let minWidth: CGFloat
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(Win.font)
                .foregroundColor(isEnabled ? .black : Win.disabled)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(minWidth: minWidth, minHeight: 30)
                .background(configuration.isPressed ? Win.buttonPressed : Win.button)
                .overlay(
                    Rectangle().strokeBorder(
                        configuration.isPressed || (isDefault && isEnabled) ? Win.accent : (isEnabled ? Win.border : Color(rgb: 0xBFBFBF)),
                        lineWidth: isDefault && isEnabled ? 2 : 1)
                )
                .contentShape(Rectangle())
        }
    }
}

struct WinButton: View {
    let title: String
    var isDefault = false
    var minWidth: CGFloat = 75
    let action: () -> Void

    init(_ title: String, isDefault: Bool = false, minWidth: CGFloat = 75, action: @escaping () -> Void) {
        self.title = title
        self.isDefault = isDefault
        self.minWidth = minWidth
        self.action = action
    }

    var body: some View {
        Button(title, action: action).buttonStyle(WinButtonStyle(isDefault: isDefault, minWidth: minWidth))
    }
}

struct WinTextField: View {
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var monospaced = false

    var body: some View {
        TextField("", text: $text)
            .font(monospaced ? .system(size: 13, design: .monospaced) : Win.font)
            .foregroundColor(.black)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(keyboard)
            .padding(.horizontal, 5)
            .frame(height: 30)
            .background(Color.white)
            .overlay(Rectangle().strokeBorder(Win.fieldBorder, lineWidth: 1))
    }
}

struct WinNumberField: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...Int.max

    var body: some View {
        WinTextField(text: Binding(
            get: { String(value) },
            set: { value = min(range.upperBound, max(range.lowerBound, Int($0.filter(\.isNumber)) ?? 0)) }
        ), keyboard: .numberPad)
    }
}

struct WinRadio: View {
    let label: String
    let selected: Bool
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ZStack {
                    Circle().fill(Color.white)
                    Circle().strokeBorder(enabled ? Win.glyph : Win.disabled, lineWidth: 1)
                    if selected { Circle().fill(enabled ? Win.glyph : Win.disabled).frame(width: 7, height: 7) }
                }
                .frame(width: 14, height: 14)
                Text(label).font(Win.font).foregroundColor(enabled ? .black : Win.disabled).fixedSize()
            }
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct WinCheckbox: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(alignment: .top, spacing: 6) {
                ZStack {
                    Rectangle().fill(Color.white)
                    Rectangle().strokeBorder(Win.glyph, lineWidth: 1)
                    if isOn {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundColor(Win.glyph)
                    }
                }
                .frame(width: 14, height: 14)
                .padding(.top, 1)
                Text(label).font(Win.font).foregroundColor(.black).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct WinGroupBox<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) { content }
            .padding(.horizontal, 10)
            .padding(.top, 18)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 2).strokeBorder(Win.groupLine, lineWidth: 1).padding(.top, 8)
            )
            .overlay(alignment: .topLeading) {
                Text(title).font(Win.font).foregroundColor(.black).padding(.horizontal, 3).background(Win.face).offset(x: 6)
            }
    }
}

struct WinDropdown<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T

    var body: some View {
        Menu {
            ForEach(options, id: \.0) { option in
                Button(option.1) { selection = option.0 }
            }
        } label: {
            HStack {
                Text(options.first { $0.0 == selection }?.1 ?? "").font(Win.font).foregroundColor(.black)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundColor(Win.glyph)
            }
            .padding(.horizontal, 6)
            .frame(height: 30)
            .background(Win.button)
            .overlay(Rectangle().strokeBorder(Win.border, lineWidth: 1))
        }
    }
}

/// A top-level window with a Windows 10 style title bar.
struct WinWindow<Content: View, Accessory: View>: View {
    let title: String
    var showsHelp = false
    var onClose: (() -> Void)?
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                accessory.padding(.leading, 8)
                Text(title).font(.system(size: 13)).foregroundColor(.black).lineLimit(1).padding(.leading, 6)
                Spacer(minLength: 4)
                if showsHelp {
                    Text("?").font(.system(size: 15)).foregroundColor(.black).frame(width: 44, height: 32)
                }
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .light)).foregroundColor(.black)
                            .frame(width: 46, height: 32).contentShape(Rectangle())
                    }
                    .buttonStyle(TitleCloseStyle())
                }
            }
            .frame(height: 32)
            .background(Color.white, ignoresSafeAreaEdges: [])
            content
        }
        .background(Win.face)
        .overlay(Rectangle().strokeBorder(Color(rgb: 0x1883D7), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }
}

extension WinWindow where Accessory == PuttyIcon {
    init(title: String, showsHelp: Bool = false, onClose: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.showsHelp = showsHelp
        self.onClose = onClose
        self.accessory = PuttyIcon(size: 16)
        self.content = content()
    }
}

private struct TitleCloseStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color(rgb: 0xE81123) : Color.clear)
            .foregroundColor(configuration.isPressed ? .white : .black)
    }
}

/// Two terminals joined by a lightning bolt, drawn on a 16×16 grid.
struct PuttyIcon: View {
    var size: CGFloat = 16

    var body: some View {
        Canvas { ctx, sz in
            let u = sz.width / 16
            func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x * u, y: y * u, width: w * u, height: h * u) }
            let beige = Color(rgb: 0xD9D2BF), shade = Color(rgb: 0x8C846E), screen = Color(rgb: 0x10206A), glow = Color(rgb: 0x4A7BD8)
            func computer(_ x: CGFloat, _ y: CGFloat) {
                ctx.fill(Path(r(x, y, 9, 7)), with: .color(beige))
                ctx.stroke(Path(r(x, y, 9, 7)), with: .color(shade), lineWidth: max(0.5, u * 0.6))
                ctx.fill(Path(r(x + 1.4, y + 1.2, 6.2, 4.4)), with: .color(screen))
                ctx.fill(Path(r(x + 2.2, y + 2, 2.4, 0.9)), with: .color(glow))
                ctx.fill(Path(r(x + 1.5, y + 7, 6, 1.6)), with: .color(shade))
                ctx.fill(Path(r(x + 0.5, y + 8.4, 8, 1.2)), with: .color(beige))
            }
            computer(6.5, 0.5)
            computer(0.5, 5.8)
            var bolt = Path()
            bolt.addLines([CGPoint(x: 13.5 * u, y: 6 * u), CGPoint(x: 9 * u, y: 10.2 * u), CGPoint(x: 11.4 * u, y: 10.6 * u),
                           CGPoint(x: 8.2 * u, y: 15.6 * u), CGPoint(x: 14.6 * u, y: 9.3 * u), CGPoint(x: 12 * u, y: 9 * u),
                           CGPoint(x: 15 * u, y: 6 * u)])
            bolt.closeSubpath()
            ctx.fill(bolt, with: .color(Color(rgb: 0xFFD800)))
            ctx.stroke(bolt, with: .color(Color(rgb: 0x5A4500)), lineWidth: max(0.5, u * 0.5))
        }
        .frame(width: size, height: size)
    }
}
