// Значок строки списка: символ на цветной плашке со скруглением —
// тот же приём, которым система рисует значки в своих настройках.
// Взято из проекта words как есть, убраны только ветки для iOS.

import SwiftUI

struct RowIcon: View {

    private enum Source {
        case system(String)
        case asset(String)
    }

    /// Standard list-row footprint. Everything else scales off it, so a larger icon keeps the same proportions.
    static let standardSideLength: CGFloat = 30

    private let source: Source

    let backgroundColor: Color
    /// Pass a larger value where the icon is the focal point rather than a row's leading accessory.
    let sideLength: CGFloat
    /// Set where the icon is *not* in a list row — a card, a grid cell — and something around it is laid out
    /// against its height. See `reservesItsHeight`.
    let reservesHeight: Bool

    init(
        systemName: String,
        backgroundColor: Color,
        sideLength: CGFloat = RowIcon.standardSideLength,
        reservesHeight: Bool = false
    ) {
        self.source = .system(systemName)
        self.backgroundColor = backgroundColor
        self.sideLength = sideLength
        self.reservesHeight = reservesHeight
    }

    init(
        assetName: String,
        backgroundColor: Color,
        sideLength: CGFloat = RowIcon.standardSideLength,
        reservesHeight: Bool = false
    ) {
        self.source = .asset(assetName)
        self.backgroundColor = backgroundColor
        self.sideLength = sideLength
        self.reservesHeight = reservesHeight
    }

    var body: some View {
        if reservesItsHeight {
            badge
        } else {
            // What UIKit calls `reservedLayoutSize`: the space an icon is *measured* at, apart from the size it is
            // *drawn* at, and how the system's own Settings keeps a 30-point icon in a row whose height the text
            // decides. Measured on iOS 26 in this app: a `UITableViewCell` reserving the icon's full 30 points is
            // 61 tall; reserving none of it is 53 — the same as a row with no icon — and the icon still draws full
            // size. So the badge is drawn over a footprint that is its width and no height at all.
            Color.clear
                .frame(width: sideLength, height: 0)
                .overlay { badge }
        }
    }

    /// Stepping out of the measurement is right in a list row and wrong everywhere else: in a card or a grid cell
    /// something is laid out against this icon's height, and zero would let it overlap what sits below. A larger
    /// icon is never a row accessory, so it always measures; at row size the caller says.
    private var reservesItsHeight: Bool { reservesHeight || sideLength > RowIcon.standardSideLength }

    private var badge: some View {
        icon
            .font(.system(size: 16 * scale, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            // Микротень под самим символом — как у системных значков,
            // иначе белое по цветному выглядит наклейкой.
            .shadow(color: .black.opacity(0.25), radius: 0.5 * scale, y: 0.5 * scale)
            .frame(width: sideLength, height: sideLength)
            .background(
                LinearGradient(
                    colors: [lighterGradientColor, backgroundColor],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10 * scale, style: .continuous))
            // Система кладёт под свои значки едва заметную тень — без неё
            // плашка выглядит наклейкой, а не значком.
            .shadow(color: .black.opacity(0.22), radius: 0.7 * scale, y: 0.5 * scale)
    }

    private var scale: CGFloat { sideLength / RowIcon.standardSideLength }

    @ViewBuilder
    private var icon: some View {
        switch source {
        case .system(let name):
            Image(systemName: name)
        case .asset(let name):
            Image(name)
        }
    }

    private var lighterGradientColor: Color {
        Color(NSColor(backgroundColor).mixed(with: .white, amount: 0.22))
    }
}

private extension NSColor {
    func mixed(with color: NSColor, amount: CGFloat) -> NSColor {
        let clampedAmount = min(max(amount, 0), 1)
        guard let from = usingColorSpace(.deviceRGB),
              let to = color.usingColorSpace(.deviceRGB) else {
            return self
        }

        return NSColor(
            red: from.redComponent + (to.redComponent - from.redComponent) * clampedAmount,
            green: from.greenComponent + (to.greenComponent - from.greenComponent) * clampedAmount,
            blue: from.blueComponent + (to.blueComponent - from.blueComponent) * clampedAmount,
            alpha: from.alphaComponent + (to.alphaComponent - from.alphaComponent) * clampedAmount
        )
    }
}
