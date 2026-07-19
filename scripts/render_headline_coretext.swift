import AppKit
import Foundation
import CoreText

// usage: render_headline_coretext fontPath sizePx weight hexRRGGBBAA outPNG
// text via HT_HEADLINE_TEXT env (supports real newlines)
guard CommandLine.arguments.count >= 6 else {
    fputs("usage: fontPath sizePx weight hexAARRGGBB outPNG  (text in HT_HEADLINE_TEXT)\n", stderr)
    exit(2)
}
let fontPath = CommandLine.arguments[1]
let size = CGFloat(Double(CommandLine.arguments[2]) ?? 32)
let weightVal = CGFloat(Double(CommandLine.arguments[3]) ?? 800)
let colorHex = CommandLine.arguments[4]
let outPath = CommandLine.arguments[5]
guard let text = ProcessInfo.processInfo.environment["HT_HEADLINE_TEXT"], !text.isEmpty else {
    fputs("HT_HEADLINE_TEXT missing\n", stderr)
    exit(3)
}

func color(_ hex: String) -> NSColor {
    var h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    if h.count == 6 { h = "FF" + h }
    var n: UInt64 = 0
    Scanner(string: h).scanHexInt64(&n)
    let a = CGFloat((n & 0xff000000) >> 24) / 255
    let r = CGFloat((n & 0x00ff0000) >> 16) / 255
    let g = CGFloat((n & 0x0000ff00) >> 8) / 255
    let b = CGFloat(n & 0x000000ff) / 255
    return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

let fontURL = URL(fileURLWithPath: fontPath)
guard let descs = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor],
      let baseDesc = descs.first else {
    fputs("failed to load font descriptors for \(fontPath)\n", stderr)
    exit(4)
}

let variation: [CFNumber: CFNumber] = [
    2003265652 as CFNumber: weightVal as CFNumber // 'wght'
]
let desc = CTFontDescriptorCreateCopyWithAttributes(
    baseDesc,
    [kCTFontVariationAttribute as CFString: variation] as CFDictionary
)
var font = CTFontCreateWithFontDescriptor(desc, size, nil)
if weightVal >= 700, let bold = CTFontCreateCopyWithSymbolicTraits(font, size, nil, .traitBold, .traitBold) {
    font = bold
}

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .natural
paragraph.lineBreakMode = .byWordWrapping
paragraph.baseWritingDirection = .rightToLeft
paragraph.lineSpacing = max(2, size * 0.08)

let attr = NSAttributedString(string: text, attributes: [
    .font: font as NSFont,
    .foregroundColor: color(colorHex),
    .paragraphStyle: paragraph,
    .kern: size * 0.02
])

let bounds = attr.boundingRect(
    with: NSSize(width: 2000, height: 2000),
    options: [.usesLineFragmentOrigin, .usesFontLeading]
).integral
let width = max(1, Int(ceil(bounds.width)) + 8)
let height = max(1, Int(ceil(bounds.height)) + 8)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else { exit(5) }
rep.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
attr.draw(
    with: NSRect(x: 4, y: 4, width: bounds.width, height: bounds.height),
    options: [.usesLineFragmentOrigin, .usesFontLeading]
)
NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(6) }
try png.write(to: URL(fileURLWithPath: outPath))
fputs("\(width)x\(height)\n", stdout)
