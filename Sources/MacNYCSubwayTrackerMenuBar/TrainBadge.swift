import SwiftUI

struct TrainBadge: View {
    let size: CGFloat
    var routeID = "A"
    var colorHex: String? = "0062CF"

    var body: some View {
        ZStack {
            Circle()
                .fill(routeColor)

            Text(routeID)
                .font(.system(size: size * routeFontScale, weight: .bold))
                .foregroundStyle(routeTextColor)
                .minimumScaleFactor(0.5)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(routeID) train")
    }

    private var routeFontScale: CGFloat {
        routeID.count > 1 ? 0.42 : 0.67
    }

    private var routeColor: Color {
        let value = routeColorValue
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    private var routeTextColor: Color {
        let value = routeColorValue
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance > 0.62 ? .black : .white
    }

    private var routeColorValue: UInt64 {
        guard let colorHex,
              let value = UInt64(colorHex.trimmingCharacters(in: .whitespacesAndNewlines), radix: 16)
        else {
            return 0x0062CF
        }
        return value
    }
}
