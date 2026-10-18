// 레트로 픽셀 스타일 부품: 5×7 도트 글꼴, 칸 나뉜 막대, 계단 모서리 상자, CRT 주사선
import SwiftUI

/// 다크는 형광 녹색 CRT, 라이트는 게임보이 같은 LCD
struct RetroTheme {
    let background: Color
    let panel: Color
    let phosphor: Color
    let claude: Color
    let gemini: Color
    let danger: Color
    let scanline: Double
    let glow: Bool

    var dim: Color { phosphor.opacity(0.5) }

    static func of(_ scheme: ColorScheme) -> RetroTheme { scheme == .dark ? dark : light }

    static let dark = RetroTheme(
        background: Color(red: 0.035, green: 0.045, blue: 0.035),
        panel: Color(red: 0.06, green: 0.08, blue: 0.06),
        phosphor: Color(red: 0.49, green: 1.0, blue: 0.42),
        claude: Color(red: 1.0, green: 0.69, blue: 0.0),
        gemini: Color(red: 0.36, green: 0.88, blue: 0.95),
        danger: Color(red: 1.0, green: 0.33, blue: 0.33),
        scanline: 0.28, glow: true)

    static let light = RetroTheme(
        background: Color(red: 0.77, green: 0.81, blue: 0.62),
        panel: Color(red: 0.71, green: 0.76, blue: 0.55),
        phosphor: Color(red: 0.13, green: 0.22, blue: 0.10),
        claude: Color(red: 0.55, green: 0.27, blue: 0.0),
        gemini: Color(red: 0.0, green: 0.30, blue: 0.36),
        danger: Color(red: 0.66, green: 0.08, blue: 0.08),
        scanline: 0.07, glow: false)
}

func monoFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight, design: .monospaced)
}

/// 5×7 도트 글꼴. 없는 글자는 빈칸으로 그린다.
enum PixelFont {
    static let glyphs: [Character: [String]] = [
        "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
        "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
        "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
        "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
        "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
        "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
        "%": ["11001", "11010", "00010", "00100", "01000", "01011", "10011"],
        ":": ["00000", "01100", "01100", "00000", "01100", "01100", "00000"],
        ".": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
        "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
        "/": ["00001", "00010", "00010", "00100", "01000", "01000", "10000"],
        "?": ["01110", "10001", "00001", "00010", "00100", "00000", "00100"],
        "!": ["00100", "00100", "00100", "00100", "00100", "00000", "00100"],
        ">": ["01000", "00100", "00010", "00001", "00010", "00100", "01000"],
        "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
        "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
        "C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
        "D": ["11100", "10010", "10001", "10001", "10001", "10010", "11100"],
        "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
        "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
        "G": ["01110", "10001", "10000", "10111", "10001", "10001", "01111"],
        "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
        "I": ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
        "J": ["00111", "00010", "00010", "00010", "00010", "10010", "01100"],
        "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
        "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
        "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
        "N": ["10001", "10001", "11001", "10101", "10011", "10001", "10001"],
        "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
        "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
        "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
        "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
        "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
        "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
        "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
        "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
        "W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
        "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
        "Y": ["10001", "10001", "10001", "01010", "00100", "00100", "00100"],
        "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
    ]
}

/// 도트 글꼴로 쓴 글자. px는 도트 한 칸 크기(pt). 도트 사이에 틈을 둬서 LED처럼 보이게 한다.
struct PixelText: View {
    let text: String
    let px: CGFloat
    let color: Color
    let glow: Bool

    init(_ text: String, px: CGFloat = 4, color: Color, glow: Bool = true) {
        self.text = text.uppercased()
        self.px = px
        self.color = color
        self.glow = glow
    }

    var body: some View {
        let chars = Array(text)
        let width = CGFloat(max(0, chars.count * 6 - 1)) * px
        Canvas { ctx, _ in
            let gap = max(0.5, px * 0.15)
            for (i, ch) in chars.enumerated() {
                guard let rows = PixelFont.glyphs[ch] else { continue }
                for (y, row) in rows.enumerated() {
                    for (x, bit) in row.enumerated() where bit == "1" {
                        let rect = CGRect(x: CGFloat(i * 6 + x) * px, y: CGFloat(y) * px, width: px - gap, height: px - gap)
                        ctx.fill(Path(rect), with: .color(color))
                    }
                }
            }
        }
        .frame(width: width, height: 7 * px)
        .shadow(color: glow ? color.opacity(0.7) : .clear, radius: px * 1.2)
    }
}

/// 칸으로 나뉜 진행 막대. 채워진 칸은 빛나고 빈 칸은 테두리만 보인다.
struct SegmentBar: View {
    let fraction: Double
    var cells = 24
    let color: Color
    var glow = true

    var body: some View {
        let filled = Int((min(1, max(0, fraction)) * Double(cells)).rounded())
        GeometryReader { geo in
            let gap: CGFloat = 5
            let w = (geo.size.width - gap * CGFloat(cells - 1)) / CGFloat(cells)
            HStack(spacing: gap) {
                ForEach(0..<cells, id: \.self) { i in
                    if i < filled {
                        Rectangle().fill(color).frame(width: w)
                            .shadow(color: glow ? color.opacity(0.6) : .clear, radius: 4)
                    } else {
                        Rectangle().strokeBorder(color.opacity(0.25), lineWidth: 2).frame(width: w)
                    }
                }
            }
        }
    }
}

/// 모서리가 계단 모양으로 깎인 상자
struct PixelBox: Shape {
    var step: CGFloat = 6

    func path(in r: CGRect) -> Path {
        let s = step
        let points: [(CGFloat, CGFloat)] = [
            (r.minX + 2 * s, r.minY), (r.maxX - 2 * s, r.minY), (r.maxX - 2 * s, r.minY + s), (r.maxX - s, r.minY + s),
            (r.maxX - s, r.minY + 2 * s), (r.maxX, r.minY + 2 * s), (r.maxX, r.maxY - 2 * s), (r.maxX - s, r.maxY - 2 * s),
            (r.maxX - s, r.maxY - s), (r.maxX - 2 * s, r.maxY - s), (r.maxX - 2 * s, r.maxY), (r.minX + 2 * s, r.maxY),
            (r.minX + 2 * s, r.maxY - s), (r.minX + s, r.maxY - s), (r.minX + s, r.maxY - 2 * s), (r.minX, r.maxY - 2 * s),
            (r.minX, r.minY + 2 * s), (r.minX + s, r.minY + 2 * s), (r.minX + s, r.minY + s), (r.minX + 2 * s, r.minY + s),
        ]
        var p = Path()
        p.addLines(points.map { CGPoint(x: $0.0, y: $0.1) })
        p.closeSubpath()
        return p
    }
}

/// 계단 모서리 테두리를 두른 패널
struct RetroPanel<Content: View>: View {
    let t: RetroTheme
    let color: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(PixelBox().fill(t.panel))
            .overlay(PixelBox().stroke(color.opacity(0.55), lineWidth: 4))
    }
}

/// CRT 주사선과 가장자리 어둡게 하기
struct Scanlines: View {
    let opacity: Double

    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1.2)), with: .color(.black.opacity(opacity)))
                y += 4
            }
        }
        .overlay(RadialGradient(colors: [.clear, .black.opacity(opacity * 1.6)], center: .center, startRadius: 500, endRadius: 1000))
        .allowsHitTesting(false)
    }
}
