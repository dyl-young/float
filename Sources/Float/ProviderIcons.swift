import AppKit
import SwiftUI

enum ProviderIcon {
    case openAI, claude, cursor, antigravity, openCode

    init?(driverKind: String?) {
        switch driverKind {
        case "codex", "openai": self = .openAI
        case "claudeAgent": self = .claude
        case "cursor": self = .cursor
        case "antigravity": self = .antigravity
        case "opencode": self = .openCode
        default: return nil
        }
    }

    private var isAntigravity: Bool {
        if case .antigravity = self { return true }
        return false
    }

    private var viewBox: CGRect {
        switch self {
        case .openAI: CGRect(x: 100, y: 100, width: 411, height: 411)
        case .claude: CGRect(x: 0, y: 0, width: 256, height: 257)
        case .cursor: CGRect(x: 0, y: 0, width: 466.73, height: 532.09)
        case .antigravity: .zero
        case .openCode: CGRect(x: 0, y: 0, width: 32, height: 40)
        }
    }

    private var layers: [(Path, Color)] {
        switch self {
        case .openAI: [(ProviderPaths.openAI, Theme.text)]
        case .claude: [(ProviderPaths.claude, Theme.claude)]
        case .cursor: [(ProviderPaths.cursor, Theme.cursor)]
        case .antigravity: []
        case .openCode: [(ProviderPaths.openCodeInset, Theme.openCodeInset), (ProviderPaths.openCode, Theme.openCode)]
        }
    }

    private func fit(_ path: Path, in rect: CGRect) -> Path {
        let box = viewBox
        let scale = min(rect.width / box.width, rect.height / box.height)
        return path.applying(.init(
            a: scale, b: 0, c: 0, d: scale,
            tx: rect.midX - box.midX * scale, ty: rect.midY - box.midY * scale
        ))
    }

    @ViewBuilder var glyph: some View {
        if isAntigravity, let image = Self.antigravityImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Canvas { context, size in
                for (path, tint) in layers {
                    context.fill(fit(path, in: CGRect(origin: .zero, size: size)), with: .color(tint), style: .init(eoFill: true))
                }
            }
        }
    }

    func menuImage(size: CGFloat = 13) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            if isAntigravity, let image = Self.antigravityImage {
                image.draw(
                    in: rect, from: NSRect(origin: .zero, size: image.size),
                    operation: .sourceOver, fraction: 1, respectFlipped: true,
                    hints: [.interpolation: NSImageInterpolation.high]
                )
                return true
            }
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            for (path, tint) in layers {
                context.setFillColor(NSColor(tint).cgColor)
                context.addPath(fit(path, in: rect).cgPath)
                context.fillPath(using: .evenOdd)
            }
            return true
        }
    }

    private static let antigravityImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "antigravity", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()
}

struct ProviderGlyph: View {
    let driverKind: String?

    var body: some View {
        Group {
            if let icon = ProviderIcon(driverKind: driverKind) {
                icon.glyph
            } else {
                Image(systemName: "cpu")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(width: 13, height: 13)
        .accessibilityHidden(true)
    }
}

// SVG paths from T3’s provider assets and the OpenCode provider package.
private enum ProviderPaths {
    static let openAI: Path = {
        var path = Path()
        path.move(to: .init(x: 252.7940, y: 108.8020))
        path.addCurve(to: .init(x: 351.1480, y: 135.1350), control1: .init(x: 289.1910, y: 99.0484), control2: .init(x: 326.2650, y: 110.3050))
        path.addCurve(to: .init(x: 449.4920, y: 161.5050), control1: .init(x: 385.1130, y: 126.0720), control2: .init(x: 422.8500, y: 134.8620))
        path.addCurve(to: .init(x: 475.8620, y: 259.8500), control1: .init(x: 476.1360, y: 188.1490), control2: .init(x: 484.9250, y: 225.8880))
        path.addLine(to: .init(x: 475.8620, y: 259.8540))
        path.addCurve(to: .init(x: 502.1980, y: 358.2070), control1: .init(x: 500.6960, y: 284.7350), control2: .init(x: 511.9500, y: 321.8100))
        path.addCurve(to: .init(x: 430.2150, y: 430.2170), control1: .init(x: 492.4470, y: 394.6020), control2: .init(x: 464.1610, y: 421.0840))
        path.addCurve(to: .init(x: 358.2060, y: 502.1990), control1: .init(x: 421.0830, y: 464.1620), control2: .init(x: 394.6030, y: 492.4480))
        path.addCurve(to: .init(x: 259.8520, y: 475.8640), control1: .init(x: 321.8120, y: 511.9510), control2: .init(x: 284.7340, y: 500.6930))
        path.addCurve(to: .init(x: 161.5070, y: 449.4950), control1: .init(x: 225.8870, y: 484.9270), control2: .init(x: 188.1500, y: 476.1370))
        path.addCurve(to: .init(x: 135.1360, y: 351.1490), control1: .init(x: 134.8640, y: 422.8510), control2: .init(x: 126.0730, y: 385.1110))
        path.addCurve(to: .init(x: 108.8010, y: 252.7950), control1: .init(x: 110.3040, y: 326.2660), control2: .init(x: 99.0496, y: 289.1920))
        path.addCurve(to: .init(x: 180.7840, y: 180.7850), control1: .init(x: 118.5520, y: 216.4000), control2: .init(x: 146.8400, y: 189.9180))
        path.addCurve(to: .init(x: 252.7940, y: 108.8020), control1: .init(x: 189.9170, y: 146.8410), control2: .init(x: 216.3960, y: 118.5530))
        path.closeSubpath()
        path.move(to: .init(x: 374.2920, y: 407.1450))
        path.addCurve(to: .init(x: 368.5170, y: 417.1480), control1: .init(x: 374.2920, y: 411.2710), control2: .init(x: 372.0920, y: 415.0860))
        path.addLine(to: .init(x: 283.7230, y: 466.1020))
        path.addCurve(to: .init(x: 352.2170, y: 479.8520), control1: .init(x: 302.4870, y: 480.5850), control2: .init(x: 327.5550, y: 486.4590))
        path.addCurve(to: .init(x: 410.5550, y: 405.0060), control1: .init(x: 386.9970, y: 470.5320), control2: .init(x: 410.0680, y: 439.3120))
        path.addLine(to: .init(x: 410.5550, y: 317.7170))
        path.addCurve(to: .init(x: 406.8430, y: 311.3030), control1: .init(x: 410.5550, y: 315.0800), control2: .init(x: 409.1250, y: 312.6210))
        path.addLine(to: .init(x: 374.2920, y: 292.5090))
        path.addLine(to: .init(x: 374.2920, y: 407.1450))
        path.closeSubpath()
        path.move(to: .init(x: 251.8680, y: 415.8970))
        path.addCurve(to: .init(x: 240.3170, y: 415.8970), control1: .init(x: 248.2960, y: 417.9590), control2: .init(x: 243.8930, y: 417.9590))
        path.addLine(to: .init(x: 155.5260, y: 366.9420))
        path.addCurve(to: .init(x: 177.8660, y: 433.1360), control1: .init(x: 152.3660, y: 390.4360), control2: .init(x: 159.8110, y: 415.0800))
        path.addLine(to: .init(x: 177.8630, y: 433.1360))
        path.addCurve(to: .init(x: 271.8500, y: 446.2320), control1: .init(x: 203.3250, y: 458.5940), control2: .init(x: 241.8960, y: 462.9620))
        path.addLine(to: .init(x: 347.4490, y: 402.5860))
        path.addCurve(to: .init(x: 351.1480, y: 396.1630), control1: .init(x: 349.7350, y: 401.2680), control2: .init(x: 351.1480, y: 398.8000))
        path.addLine(to: .init(x: 351.1480, y: 358.5790))
        path.addLine(to: .init(x: 251.8680, y: 415.8970))
        path.closeSubpath()
        path.move(to: .init(x: 368.6020, y: 220.6280))
        path.addCurve(to: .init(x: 361.1910, y: 220.6370), control1: .init(x: 366.3190, y: 219.3090), control2: .init(x: 363.4740, y: 219.3180))
        path.addLine(to: .init(x: 328.6410, y: 239.4310))
        path.addLine(to: .init(x: 427.9210, y: 296.7490))
        path.addCurve(to: .init(x: 433.6970, y: 306.7520), control1: .init(x: 431.4960, y: 298.8110), control2: .init(x: 433.6970, y: 302.6270))
        path.addLine(to: .init(x: 433.6970, y: 404.6610))
        path.addCurve(to: .init(x: 479.8510, y: 352.2180), control1: .init(x: 455.6220, y: 395.6540), control2: .init(x: 473.2440, y: 376.8810))
        path.addCurve(to: .init(x: 444.2010, y: 264.2740), control1: .init(x: 489.1690, y: 317.4420), control2: .init(x: 473.6680, y: 281.8500))
        path.addLine(to: .init(x: 368.6020, y: 220.6280))
        path.closeSubpath()
        path.move(to: .init(x: 177.3030, y: 206.3400))
        path.addCurve(to: .init(x: 131.1480, y: 258.7830), control1: .init(x: 155.3770, y: 215.3480), control2: .init(x: 137.7560, y: 234.1220))
        path.addCurve(to: .init(x: 166.7990, y: 346.7270), control1: .init(x: 121.8320, y: 293.5610), control2: .init(x: 137.3310, y: 329.1530))
        path.addLine(to: .init(x: 242.3980, y: 390.3730))
        path.addCurve(to: .init(x: 249.8070, y: 390.3660), control1: .init(x: 244.6800, y: 391.6920), control2: .init(x: 247.5250, y: 391.6840))
        path.addLine(to: .init(x: 282.3570, y: 371.5720))
        path.addLine(to: .init(x: 183.0780, y: 314.2530))
        path.addCurve(to: .init(x: 177.3030, y: 304.2510), control1: .init(x: 179.5040, y: 312.1890), control2: .init(x: 177.3030, y: 308.3750))
        path.addLine(to: .init(x: 177.3030, y: 206.3400))
        path.closeSubpath()
        path.move(to: .init(x: 259.8490, y: 279.1450))
        path.addLine(to: .init(x: 259.8490, y: 331.8580))
        path.addLine(to: .init(x: 305.5000, y: 358.2130))
        path.addLine(to: .init(x: 351.1500, y: 331.8580))
        path.addLine(to: .init(x: 351.1500, y: 279.1450))
        path.addLine(to: .init(x: 305.5000, y: 252.7890))
        path.addLine(to: .init(x: 259.8490, y: 279.1450))
        path.closeSubpath()
        path.move(to: .init(x: 327.2760, y: 144.9000))
        path.addCurve(to: .init(x: 258.7820, y: 131.1500), control1: .init(x: 308.5120, y: 130.4180), control2: .init(x: 283.4450, y: 124.5430))
        path.addCurve(to: .init(x: 200.4450, y: 205.9950), control1: .init(x: 224.0020, y: 140.4710), control2: .init(x: 200.9310, y: 171.6910))
        path.addLine(to: .init(x: 200.4450, y: 293.2860))
        path.addCurve(to: .init(x: 204.1580, y: 299.7000), control1: .init(x: 200.4450, y: 295.9230), control2: .init(x: 201.8750, y: 298.3810))
        path.addLine(to: .init(x: 236.7070, y: 318.4930))
        path.addLine(to: .init(x: 236.7070, y: 203.8560))
        path.addCurve(to: .init(x: 242.4830, y: 193.8530), control1: .init(x: 236.7070, y: 199.7310), control2: .init(x: 238.9090, y: 195.9160))
        path.addLine(to: .init(x: 327.2760, y: 144.9000))
        path.closeSubpath()
        path.move(to: .init(x: 433.1370, y: 177.8670))
        path.addCurve(to: .init(x: 339.1490, y: 164.7690), control1: .init(x: 407.6750, y: 152.4070), control2: .init(x: 369.1030, y: 148.0380))
        path.addLine(to: .init(x: 263.5500, y: 208.4150))
        path.addCurve(to: .init(x: 259.8520, y: 214.8380), control1: .init(x: 261.2650, y: 209.7340), control2: .init(x: 259.8520, y: 212.2020))
        path.addLine(to: .init(x: 259.8520, y: 252.4230))
        path.addLine(to: .init(x: 359.1320, y: 195.1050))
        path.addCurve(to: .init(x: 370.6820, y: 195.1050), control1: .init(x: 362.7030, y: 193.0410), control2: .init(x: 367.1080, y: 193.0410))
        path.addLine(to: .init(x: 455.4730, y: 244.0600))
        path.addCurve(to: .init(x: 433.1350, y: 177.8670), control1: .init(x: 458.6350, y: 220.5670), control2: .init(x: 451.1890, y: 195.9220))
        path.addLine(to: .init(x: 433.1370, y: 177.8670))
        path.closeSubpath()
        return path
    }()

    static let claude: Path = {
        var path = Path()
        path.move(to: .init(x: 50.2280, y: 170.3210))
        path.addLine(to: .init(x: 100.5850, y: 142.0640))
        path.addLine(to: .init(x: 101.4280, y: 139.6010))
        path.addLine(to: .init(x: 100.5850, y: 138.2400))
        path.addLine(to: .init(x: 98.1230, y: 138.2400))
        path.addLine(to: .init(x: 89.6970, y: 137.7220))
        path.addLine(to: .init(x: 60.9220, y: 136.9440))
        path.addLine(to: .init(x: 35.9700, y: 135.9070))
        path.addLine(to: .init(x: 11.7950, y: 134.6110))
        path.addLine(to: .init(x: 5.7030, y: 133.3140))
        path.addLine(to: .init(x: 0.0000, y: 125.7960))
        path.addLine(to: .init(x: 0.5830, y: 122.0370))
        path.addLine(to: .init(x: 5.7030, y: 118.6030))
        path.addLine(to: .init(x: 13.0270, y: 119.2510))
        path.addLine(to: .init(x: 29.2290, y: 120.3520))
        path.addLine(to: .init(x: 53.5330, y: 122.0370))
        path.addLine(to: .init(x: 71.1620, y: 123.0740))
        path.addLine(to: .init(x: 97.2800, y: 125.7960))
        path.addLine(to: .init(x: 101.4280, y: 125.7960))
        path.addLine(to: .init(x: 102.0110, y: 124.1110))
        path.addLine(to: .init(x: 100.5850, y: 123.0740))
        path.addLine(to: .init(x: 99.4840, y: 122.0370))
        path.addLine(to: .init(x: 74.3370, y: 104.9920))
        path.addLine(to: .init(x: 47.1170, y: 86.9750))
        path.addLine(to: .init(x: 32.8590, y: 76.6050))
        path.addLine(to: .init(x: 25.1460, y: 71.3550))
        path.addLine(to: .init(x: 21.2580, y: 66.4300))
        path.addLine(to: .init(x: 19.5730, y: 55.6720))
        path.addLine(to: .init(x: 26.5730, y: 47.9590))
        path.addLine(to: .init(x: 35.9700, y: 48.6080))
        path.addLine(to: .init(x: 38.3680, y: 49.2560))
        path.addLine(to: .init(x: 47.8950, y: 56.5790))
        path.addLine(to: .init(x: 68.2450, y: 72.3290))
        path.addLine(to: .init(x: 94.8170, y: 91.9000))
        path.addLine(to: .init(x: 98.7060, y: 95.1400))
        path.addLine(to: .init(x: 100.2610, y: 94.0380))
        path.addLine(to: .init(x: 100.4560, y: 93.2610))
        path.addLine(to: .init(x: 98.7060, y: 90.3440))
        path.addLine(to: .init(x: 84.2530, y: 64.2260))
        path.addLine(to: .init(x: 68.8280, y: 37.6540))
        path.addLine(to: .init(x: 61.9580, y: 26.6360))
        path.addLine(to: .init(x: 60.1440, y: 20.0260))
        path.addCurve(to: .init(x: 59.0420, y: 12.2480), control1: .init(x: 59.4960, y: 17.3030), control2: .init(x: 59.0420, y: 15.0350))
        path.addLine(to: .init(x: 67.0140, y: 1.4250))
        path.addLine(to: .init(x: 71.4200, y: 0.0000))
        path.addLine(to: .init(x: 82.0500, y: 1.4260))
        path.addLine(to: .init(x: 86.5220, y: 5.3140))
        path.addLine(to: .init(x: 93.1320, y: 20.4150))
        path.addLine(to: .init(x: 103.8260, y: 44.2010))
        path.addLine(to: .init(x: 120.4170, y: 76.5410))
        path.addLine(to: .init(x: 125.2780, y: 86.1330))
        path.addLine(to: .init(x: 127.8700, y: 95.0120))
        path.addLine(to: .init(x: 128.8430, y: 97.7340))
        path.addLine(to: .init(x: 130.5280, y: 97.7340))
        path.addLine(to: .init(x: 130.5280, y: 96.1780))
        path.addLine(to: .init(x: 131.8880, y: 77.9670))
        path.addLine(to: .init(x: 134.4160, y: 55.6070))
        path.addLine(to: .init(x: 136.8790, y: 26.8310))
        path.addLine(to: .init(x: 137.7220, y: 18.7310))
        path.addLine(to: .init(x: 141.7400, y: 9.0090))
        path.addLine(to: .init(x: 149.7110, y: 3.7590))
        path.addLine(to: .init(x: 155.9330, y: 6.7400))
        path.addLine(to: .init(x: 161.0530, y: 14.0640))
        path.addLine(to: .init(x: 160.3400, y: 18.7940))
        path.addLine(to: .init(x: 157.2940, y: 38.5620))
        path.addLine(to: .init(x: 151.3320, y: 69.5420))
        path.addLine(to: .init(x: 147.4430, y: 90.2810))
        path.addLine(to: .init(x: 149.7110, y: 90.2810))
        path.addLine(to: .init(x: 152.3040, y: 87.6880))
        path.addLine(to: .init(x: 162.8030, y: 73.7540))
        path.addLine(to: .init(x: 180.4310, y: 51.7180))
        path.addLine(to: .init(x: 188.2090, y: 42.9690))
        path.addLine(to: .init(x: 197.2820, y: 33.3120))
        path.addLine(to: .init(x: 203.1150, y: 28.7110))
        path.addLine(to: .init(x: 214.1330, y: 28.7110))
        path.addLine(to: .init(x: 222.2330, y: 40.7660))
        path.addLine(to: .init(x: 218.6050, y: 53.2090))
        path.addLine(to: .init(x: 207.2630, y: 67.5970))
        path.addLine(to: .init(x: 197.8650, y: 79.7810))
        path.addLine(to: .init(x: 184.3850, y: 97.9280))
        path.addLine(to: .init(x: 175.9590, y: 112.4460))
        path.addLine(to: .init(x: 176.7370, y: 113.6120))
        path.addLine(to: .init(x: 178.7470, y: 113.4180))
        path.addLine(to: .init(x: 209.2070, y: 106.9370))
        path.addLine(to: .init(x: 225.6690, y: 103.9550))
        path.addLine(to: .init(x: 245.3060, y: 100.5850))
        path.addLine(to: .init(x: 254.1860, y: 104.7330))
        path.addLine(to: .init(x: 255.1570, y: 108.9460))
        path.addLine(to: .init(x: 251.6570, y: 117.5660))
        path.addLine(to: .init(x: 230.6590, y: 122.7500))
        path.addLine(to: .init(x: 206.0310, y: 127.6760))
        path.addLine(to: .init(x: 169.3490, y: 136.3610))
        path.addLine(to: .init(x: 168.8950, y: 136.6850))
        path.addLine(to: .init(x: 169.4140, y: 137.3330))
        path.addLine(to: .init(x: 185.9400, y: 138.8880))
        path.addLine(to: .init(x: 193.0050, y: 139.2770))
        path.addLine(to: .init(x: 210.3090, y: 139.2770))
        path.addLine(to: .init(x: 242.5190, y: 141.6750))
        path.addLine(to: .init(x: 250.9450, y: 147.2490))
        path.addLine(to: .init(x: 256.0000, y: 154.0540))
        path.addLine(to: .init(x: 255.1570, y: 159.2380))
        path.addLine(to: .init(x: 242.1950, y: 165.8490))
        path.addLine(to: .init(x: 224.6970, y: 161.7010))
        path.addLine(to: .init(x: 183.8670, y: 151.9800))
        path.addLine(to: .init(x: 169.8670, y: 148.4800))
        path.addLine(to: .init(x: 167.9230, y: 148.4800))
        path.addLine(to: .init(x: 167.9230, y: 149.6470))
        path.addLine(to: .init(x: 179.5890, y: 161.0530))
        path.addLine(to: .init(x: 200.9760, y: 180.3670))
        path.addLine(to: .init(x: 227.7430, y: 205.2540))
        path.addLine(to: .init(x: 229.1030, y: 211.4110))
        path.addLine(to: .init(x: 225.6690, y: 216.2710))
        path.addLine(to: .init(x: 222.0390, y: 215.7530))
        path.addLine(to: .init(x: 198.5130, y: 198.0600))
        path.addLine(to: .init(x: 189.4400, y: 190.0880))
        path.addLine(to: .init(x: 168.8950, y: 172.7840))
        path.addLine(to: .init(x: 167.5350, y: 172.7840))
        path.addLine(to: .init(x: 167.5350, y: 174.5980))
        path.addLine(to: .init(x: 172.2650, y: 181.5330))
        path.addLine(to: .init(x: 197.2820, y: 219.1230))
        path.addLine(to: .init(x: 198.5780, y: 230.6590))
        path.addLine(to: .init(x: 196.7640, y: 234.4190))
        path.addLine(to: .init(x: 190.2830, y: 236.6870))
        path.addLine(to: .init(x: 183.1530, y: 235.3900))
        path.addLine(to: .init(x: 168.5060, y: 214.8460))
        path.addLine(to: .init(x: 153.4060, y: 191.7080))
        path.addLine(to: .init(x: 141.2210, y: 170.9690))
        path.addLine(to: .init(x: 139.7310, y: 171.8120))
        path.addLine(to: .init(x: 132.5370, y: 249.2600))
        path.addLine(to: .init(x: 129.1670, y: 253.2130))
        path.addLine(to: .init(x: 121.3890, y: 256.1940))
        path.addLine(to: .init(x: 114.9090, y: 251.2690))
        path.addLine(to: .init(x: 111.4730, y: 243.2970))
        path.addLine(to: .init(x: 114.9080, y: 227.5480))
        path.addLine(to: .init(x: 119.0560, y: 207.0040))
        path.addLine(to: .init(x: 122.4260, y: 190.6710))
        path.addLine(to: .init(x: 125.4720, y: 170.3860))
        path.addLine(to: .init(x: 127.2870, y: 163.6460))
        path.addLine(to: .init(x: 127.1570, y: 163.1920))
        path.addLine(to: .init(x: 125.6670, y: 163.3860))
        path.addLine(to: .init(x: 110.3720, y: 184.3850))
        path.addLine(to: .init(x: 87.1050, y: 215.8180))
        path.addLine(to: .init(x: 68.6990, y: 235.5200))
        path.addLine(to: .init(x: 64.2920, y: 237.2700))
        path.addLine(to: .init(x: 56.6440, y: 233.3160))
        path.addLine(to: .init(x: 57.3570, y: 226.2520))
        path.addLine(to: .init(x: 61.6340, y: 219.9660))
        path.addLine(to: .init(x: 87.1040, y: 187.5610))
        path.addLine(to: .init(x: 102.4640, y: 167.4690))
        path.addLine(to: .init(x: 112.3810, y: 155.8690))
        path.addLine(to: .init(x: 112.3160, y: 154.1830))
        path.addLine(to: .init(x: 111.7330, y: 154.1830))
        path.addLine(to: .init(x: 44.0700, y: 198.1250))
        path.addLine(to: .init(x: 32.0150, y: 199.6800))
        path.addLine(to: .init(x: 26.8300, y: 194.8200))
        path.addLine(to: .init(x: 27.4780, y: 186.8480))
        path.addLine(to: .init(x: 29.9410, y: 184.2550))
        path.addLine(to: .init(x: 50.2910, y: 170.2560))
        path.addLine(to: .init(x: 50.2270, y: 170.3210))
        path.closeSubpath()
        return path
    }()

    static let cursor: Path = {
        var path = Path()
        path.move(to: .init(x: 457.4300, y: 125.9400))
        path.addLine(to: .init(x: 244.4200, y: 2.9600))
        path.addCurve(to: .init(x: 222.3000, y: 2.9600), control1: .init(x: 237.5800, y: -0.9900), control2: .init(x: 229.1400, y: -0.9900))
        path.addLine(to: .init(x: 9.3000, y: 125.9400))
        path.addCurve(to: .init(x: 0.0000, y: 142.0500), control1: .init(x: 3.5500, y: 129.2600), control2: .init(x: 0.0000, y: 135.4000))
        path.addLine(to: .init(x: 0.0000, y: 390.0400))
        path.addCurve(to: .init(x: 9.3000, y: 406.1500), control1: .init(x: 0.0000, y: 396.6900), control2: .init(x: 3.5500, y: 402.8300))
        path.addLine(to: .init(x: 222.3100, y: 529.1300))
        path.addCurve(to: .init(x: 244.4300, y: 529.1300), control1: .init(x: 229.1500, y: 533.0800), control2: .init(x: 237.5900, y: 533.0800))
        path.addLine(to: .init(x: 457.4400, y: 406.1500))
        path.addCurve(to: .init(x: 466.7400, y: 390.0400), control1: .init(x: 463.1900, y: 402.8300), control2: .init(x: 466.7400, y: 396.6900))
        path.addLine(to: .init(x: 466.7400, y: 142.0500))
        path.addCurve(to: .init(x: 457.4400, y: 125.9400), control1: .init(x: 466.7400, y: 135.4000), control2: .init(x: 463.1900, y: 129.2600))
        path.addLine(to: .init(x: 457.4300, y: 125.9400))
        path.closeSubpath()
        path.move(to: .init(x: 444.0500, y: 151.9900))
        path.addLine(to: .init(x: 238.4200, y: 508.1500))
        path.addCurve(to: .init(x: 233.3600, y: 506.7900), control1: .init(x: 237.0300, y: 510.5500), control2: .init(x: 233.3600, y: 509.5700))
        path.addLine(to: .init(x: 233.3600, y: 273.5800))
        path.addCurve(to: .init(x: 226.8300, y: 262.2700), control1: .init(x: 233.3600, y: 268.9200), control2: .init(x: 230.8700, y: 264.6100))
        path.addLine(to: .init(x: 24.8700, y: 145.6700))
        path.addCurve(to: .init(x: 26.2300, y: 140.6100), control1: .init(x: 22.4700, y: 144.2800), control2: .init(x: 23.4500, y: 140.6100))
        path.addLine(to: .init(x: 437.4900, y: 140.6100))
        path.addCurve(to: .init(x: 444.0600, y: 152.0000), control1: .init(x: 443.3300, y: 140.6100), control2: .init(x: 446.9800, y: 146.9400))
        path.addLine(to: .init(x: 444.0500, y: 152.0000))
        path.closeSubpath()
        return path
    }()

    static let openCodeInset: Path = {
        var path = Path()
        path.move(to: .init(x: 24.0000, y: 32.0000))
        path.addLine(to: .init(x: 8.0000, y: 32.0000))
        path.addLine(to: .init(x: 8.0000, y: 16.0000))
        path.addLine(to: .init(x: 24.0000, y: 16.0000))
        path.addLine(to: .init(x: 24.0000, y: 32.0000))
        path.closeSubpath()
        return path
    }()

    static let openCode: Path = {
        var path = Path()
        path.move(to: .init(x: 24.0000, y: 8.0000))
        path.addLine(to: .init(x: 8.0000, y: 8.0000))
        path.addLine(to: .init(x: 8.0000, y: 32.0000))
        path.addLine(to: .init(x: 24.0000, y: 32.0000))
        path.addLine(to: .init(x: 24.0000, y: 8.0000))
        path.closeSubpath()
        path.move(to: .init(x: 32.0000, y: 40.0000))
        path.addLine(to: .init(x: 0.0000, y: 40.0000))
        path.addLine(to: .init(x: 0.0000, y: 0.0000))
        path.addLine(to: .init(x: 32.0000, y: 0.0000))
        path.addLine(to: .init(x: 32.0000, y: 40.0000))
        path.closeSubpath()
        return path
    }()
}
