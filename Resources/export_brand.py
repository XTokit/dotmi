"""Deterministic SVG/PNG/ICNS export using Python stdlib and macOS CoreGraphics.

This is a geometric reconstruction of the selected B concept, not a bitmap trace.
Run with python3 on macOS; requires Xcode Command Line Tools. No image model/API.
"""
from pathlib import Path
import json
import os
import subprocess
import tempfile

import argparse
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", required=True, type=Path, help="Directory for generated brand assets")
OUT = parser.parse_args().output.resolve()
OUT.mkdir(parents=True, exist_ok=True)
SUFFIX = '-codex-2026-10-15-v1.0'
BLUE = '#1555F5'
PAPER = '#FAFAF7'
# One continuous outside contour: a tall d, a shared shoulder and two m arches.
# D's counter is a real negative shape, rather than a white painted circle.
OUTLINE = [
    ('M', 452, 220), ('Q', 470, 220, 470, 238), ('L', 470, 430),
    ('C', 516, 430, 556, 446, 589, 478),
    ('C', 625, 445, 665, 430, 711, 430),
    ('C', 798, 430, 854, 490, 854, 575),
    ('L', 854, 759), ('Q', 854, 780, 833, 780),
    ('L', 770, 780), ('Q', 749, 780, 749, 759), ('L', 749, 577),
    ('C', 749, 553, 732, 536, 709, 536),
    ('C', 685, 536, 667, 554, 667, 578),
    ('L', 667, 759), ('Q', 667, 780, 646, 780),
    ('L', 580, 780), ('Q', 559, 780, 559, 759), ('L', 559, 578),
    ('C', 559, 553, 542, 536, 519, 536),
    ('C', 495, 536, 477, 554, 477, 578), ('L', 477, 590),
    ('C', 477, 700, 393, 780, 288, 780),
    ('C', 183, 780, 106, 700, 106, 593),
    ('C', 106, 485, 185, 406, 289, 406),
    ('C', 312, 406, 334, 410, 354, 416), ('L', 354, 310),
    ('C', 354, 260, 396, 220, 452, 220), ('Z',),
]
COUNTER = (288, 592, 78, 82)
DOT = (791, 342, 50)


def name(label, extension):
    return label + SUFFIX + '.' + extension


def svg(tile):
    contour = ' '.join(cmd[0] + ' '.join(map(str, cmd[1:])) for cmd in OUTLINE)
    x, y, rx, ry = COUNTER
    hole = f'M{x+rx} {y} A{rx} {ry} 0 1 0 {x-rx} {y} A{rx} {ry} 0 1 0 {x+rx} {y} Z'
    background = f'<rect x="72" y="72" width="880" height="880" rx="196" fill="{PAPER}"/>' if tile else ''
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
<title>点觅 Dotmi — B monogram</title>
{background}
<g transform="translate(512 512) scale(.92) translate(-480 -500)" fill="{BLUE}">
<path fill-rule="evenodd" d="{contour} {hole}"/>
<circle cx="{DOT[0]}" cy="{DOT[1]}" r="{DOT[2]}"/>
</g></svg>'''


def swift_path():
    lines = []
    for cmd in OUTLINE:
        kind, *p = cmd
        if kind == 'M': lines.append(f'path.move(to: CGPoint(x: {p[0]}, y: {p[1]}))')
        elif kind == 'L': lines.append(f'path.addLine(to: CGPoint(x: {p[0]}, y: {p[1]}))')
        elif kind == 'Q': lines.append(f'path.addQuadCurve(to: CGPoint(x: {p[2]}, y: {p[3]}), control: CGPoint(x: {p[0]}, y: {p[1]}))')
        elif kind == 'C': lines.append(f'path.addCurve(to: CGPoint(x: {p[4]}, y: {p[5]}), control1: CGPoint(x: {p[0]}, y: {p[1]}), control2: CGPoint(x: {p[2]}, y: {p[3]}))')
        elif kind == 'Z': lines.append('path.closeSubpath()')
    x, y, rx, ry = COUNTER
    lines.append(f'path.addEllipse(in: CGRect(x: {x-rx}, y: {y-ry}, width: {rx*2}, height: {ry*2}))')
    return '\n'.join(lines)


def export():
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / name('点觅Logo-B母版', 'svg')).write_text(svg(False))
    (OUT / name('点觅App图标-B母版', 'svg')).write_text(svg(True))
    with tempfile.TemporaryDirectory(prefix='dotmi-export-') as directory:
        stage = Path(directory)
        iconset = stage / 'Dotmi.iconset'
        iconset.mkdir()
        renderer = stage / 'render.swift'
        program = r'''
import AppKit
import CoreGraphics
import ImageIO
let out = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = URL(fileURLWithPath: CommandLine.arguments[2])
let suffix = "-codex-2026-10-15-v1.0"
func file(_ label: String, _ ext: String = "png") -> URL { out.appendingPathComponent(label + suffix + "." + ext) }
let path = CGMutablePath()
__PATH__
let blue = CGColor(red: 21/255, green: 85/255, blue: 245/255, alpha: 1)
let paper = CGColor(red: 250/255, green: 250/255, blue: 247/255, alpha: 1)
func bitmap(_ width: Int, _ height: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
}
func write(_ rep: NSBitmapImageRep, _ url: URL) throws {
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}
func render(_ size: Int, tile: Bool, menu: Bool = false) -> NSBitmapImageRep {
    let rep = bitmap(size, size)
    let cg = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    cg.clear(CGRect(x: 0, y: 0, width: size, height: size))
    cg.setAllowsAntialiasing(true); cg.setShouldAntialias(true)
    cg.translateBy(x: 0, y: CGFloat(size)); cg.scaleBy(x: CGFloat(size)/1024, y: -CGFloat(size)/1024)
    if tile {
        cg.setFillColor(paper)
        cg.addPath(CGPath(roundedRect: CGRect(x: 72, y: 72, width: 880, height: 880), cornerWidth: 196, cornerHeight: 196, transform: nil))
        cg.fillPath()
    }
    cg.translateBy(x: 512, y: 512)
    let markScale: CGFloat = menu ? 1.16 : 0.92
    cg.scaleBy(x: markScale, y: markScale); cg.translateBy(x: -480, y: -500)
    cg.setFillColor(menu ? CGColor(gray: 0, alpha: 1) : blue)
    cg.addPath(path); cg.drawPath(using: .eoFill)
    // One documented optical correction: slightly enlarge the point at tiny sizes.
    let radius: CGFloat = size <= 32 || menu ? 56 : 50
    cg.fillEllipse(in: CGRect(x: 791-radius, y: 342-radius, width: 2*radius, height: 2*radius))
    return rep
}
var exported = 0
for size in [16,32,64,128,256,512,1024] {
    let image = render(size, tile: true)
    try write(image, file("点觅App图标-\(size)px")); exported += 1
    precondition(image.pixelsWide == size && image.pixelsHigh == size)
    precondition(image.colorAt(x: 0, y: 0)!.alphaComponent == 0)
}
let symbol = render(1024, tile: false)
try write(symbol, file("点觅Logo-透明底-1024px"))
// Verify the independent mark has a genuinely transparent counter and margins.
precondition(symbol.colorAt(x: 335, y: 597)!.alphaComponent < 0.01)
precondition(symbol.colorAt(x: 0, y: 0)!.alphaComponent == 0)
for size in [16,18,32,36] { try write(render(size, tile: false, menu: true), file("点觅菜单栏-\(size)px")); exported += 1 }
for point in [16,32,128,256,512] {
    for scale in [1,2] {
        let filename = "icon_\(point)x\(point)" + (scale == 2 ? "@2x" : "") + ".png"
        try write(render(point*scale, tile: true), iconset.appendingPathComponent(filename))
    }
}

// Real exported PNGs are placed at their actual pixel dimensions in the lower strip.
let board = bitmap(1280, 900)
let gc = NSGraphicsContext(bitmapImageRep: board)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = gc
NSColor(calibratedWhite: 0.965, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 1280, height: 900).fill()
func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat = 14, bold: Bool = false) {
    let attrs: [NSAttributedString.Key: Any] = [.font: bold ? NSFont.systemFont(ofSize: size, weight: .semibold) : NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.labelColor]
    (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
}
func picture(_ url: URL, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat) {
    let image = NSImage(contentsOf: url)!
    image.draw(in: NSRect(x: x, y: y, width: width, height: width), from: .zero, operation: .sourceOver, fraction: 1)
}
text("点觅 · B 版矢量重建", 48, 838, 28, bold: true)
text("统一几何轮廓与负形 · 蓝色 #1555F5 · 暖白底板 #FAFAF7", 48, 808)
picture(file("点觅App图标-1024px"), 40, 382, 400)
picture(file("点觅Logo-透明底-1024px"), 465, 382, 400)
text("应用图标", 80, 382, 16, bold: true)
text("独立符号 · 内部透空", 505, 382, 16, bold: true)
text("轮廓调整", 925, 723, 17, bold: true)
text("1  连体 d/m 保留共享肩部", 925, 681)
text("2  两个 m 开口保持可见", 925, 649)
text("3  缩小圆点，拉开上方间距", 925, 617)
text("4  外缘无杂点、无光晕", 925, 585)
text("小尺寸实际导出（1:1 放置）", 48, 318, 18, bold: true)
let sizes = [16,32,64,128]
let positions: [CGFloat] = [62,184,338,540]
for (i,size) in sizes.enumerated() {
    picture(file("点觅App图标-\(size)px"), positions[i], 148, CGFloat(size))
    text("\(size) px", positions[i], 112, 13)
}
NSColor(calibratedWhite: 1, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 866, y: 141, width: 340, height: 104), xRadius: 16, yRadius: 16).fill()
picture(file("点觅菜单栏-18px"), 897, 185, 18)
picture(file("点觅菜单栏-36px"), 972, 176, 36)
text("单色菜单栏", 1040, 183, 13)
text("18 px / 36 px（Retina）", 886, 112, 13)
text("基于所选 B 概念重新构建；不是原 PNG 的逐像素描摹。小尺寸仅对圆点作光学校正。", 48, 40, 13)
NSGraphicsContext.restoreGraphicsState()
try write(board, file("点觅Logo-B实际尺寸检查"))
print("Exported SVG-aligned PNGs; verified dimensions, transparent corners and open counter. Variants:", exported + 1)
'''.replace('__PATH__', swift_path())
        renderer.write_text(program)
        env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(stage / 'module-cache'), SWIFT_MODULECACHE_PATH=str(stage / 'module-cache'))
        subprocess.run(['swift', str(renderer), str(OUT), str(iconset)], env=env, check=True)
        icon = OUT / name('点觅App图标', 'icns')
        subprocess.run(['iconutil', '-c', 'icns', str(iconset), '-o', str(icon)], check=True)
        # Round-trip validation checks the container, not a claim of live Dock testing.
        decoded = stage / 'verified.iconset'
        subprocess.run(['iconutil', '-c', 'iconset', str(icon), '-o', str(decoded)], check=True)
        assert len(list(decoded.glob('*.png'))) == 10
        print('ICNS decoded successfully: 10 representations')
    print('Export directory:', OUT)


if __name__ == '__main__':
    export()
