// Собирает плоские 1024×1024 PNG иконки (светлая, тёмная, тонированная) из слоёв design/app-icon (§3.8).
// Временная замена AppIcon.icon из Icon Composer. Запуск: swiftc -o /tmp/compose scripts/compose_app_icon.swift; /tmp/compose design/app-icon App/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit

let args = CommandLine.arguments
let src = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[2])
let size = 1024

func color(_ hex: String, _ alpha: CGFloat = 1) -> CGColor {
    let v = Int(hex.dropFirst(), radix: 16)!
    return CGColor(red: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: alpha)
}

func cgImage(_ name: String) -> CGImage {
    let image = NSImage(contentsOf: src.appendingPathComponent(name))!
    var rect = CGRect(x: 0, y: 0, width: size, height: size)
    return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
}

/// Слой как маска, залитый одним цветом.
func drawTinted(_ image: CGImage, _ fill: CGColor, in ctx: CGContext) {
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: 0, width: size, height: size), mask: image)
    ctx.setFillColor(fill)
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    ctx.restoreGState()
}

func render(_ file: String, draw: (CGContext) -> Void) {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    draw(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(file))
}

func gradient(_ top: String, _ bottom: String, in ctx: CGContext) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [color(top), color(bottom)] as CFArray, locations: [0, 1])!
    // CGContext: y вверх — «сверху вниз» = от y=size к y=0.
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
}

let receipt = cgImage("receipt.svg")
let swatches = ["1-shalfey", "2-abrikos", "3-ametist", "4-kobalt"].map { cgImage("swatches/\($0).svg") }

render("AppIcon.png") { ctx in
    gradient("#332C26", "#1B1714", in: ctx)
    ctx.draw(receipt, in: CGRect(x: 0, y: 0, width: size, height: size))
    swatches.forEach { ctx.draw($0, in: CGRect(x: 0, y: 0, width: size, height: size)) }
}
render("AppIcon-dark.png") { ctx in
    gradient("#13110F", "#080706", in: ctx)
    drawTinted(receipt, color("#D8D1C6"), in: ctx)
    swatches.forEach { ctx.draw($0, in: CGRect(x: 0, y: 0, width: size, height: size)) }
}
render("AppIcon-tinted.png") { ctx in
    ctx.setFillColor(color("#000000"))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    drawTinted(receipt, color("#FFFFFF"), in: ctx)
    for (swatch, opacity) in zip(swatches, [0.30, 0.42, 0.54, 0.66]) {
        drawTinted(swatch, color("#FFFFFF", opacity), in: ctx)
    }
}
print("ok")
