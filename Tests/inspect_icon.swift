import AppKit

// Check the image returned by macOS icon services, rather than only the source PNG.
let arguments = CommandLine.arguments
precondition(arguments.count >= 2, "Usage: swift Tests/inspect_icon.swift <app-path> [preview.png] [--require-flat]")
let icon = NSWorkspace.shared.icon(forFile: arguments[1])
let size = 256
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                          isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current!.cgContext.clear(CGRect(x: 0, y: 0, width: size, height: size))
icon.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
var colors = Array(repeating: [Double](), count: 3)
func blue(_ x: Int, _ y: Int) -> Bool {
    guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
    return c.alphaComponent > 0.99 && c.redComponent < 0.4 && c.greenComponent < 0.7 && c.blueComponent > 0.7 && c.blueComponent > c.greenComponent + 0.2
}
for y in 3..<(size - 3) {
    for x in 3..<(size - 3) where blue(x, y) {
        // Remove the edge region, where anti-aliasing legitimately changes colors.
        guard (-3...3).allSatisfy({ dy in (-3...3).allSatisfy { dx in blue(x + dx, y + dy) } }) else { continue }
        let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
        colors[0].append(c.redComponent); colors[1].append(c.greenComponent); colors[2].append(c.blueComponent)
    }
}
let spreads = colors.map { values -> Double in
    let sorted = values.sorted()
    guard sorted.count > 100 else { return 1 }
    return sorted[Int(Double(sorted.count - 1) * 0.9)] - sorted[Int(Double(sorted.count - 1) * 0.1)]
}
let flat = colors[0].count > 100 && spreads.allSatisfy { $0 < 0.02 }
print("System icon interior samples:", colors[0].count, "RGB P90-P10:", spreads, "flat:", flat)
if arguments.count > 2 && arguments[2] != "--require-flat" {
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: arguments[2]))
}
if arguments.contains("--require-flat") && !flat { exit(1) }
