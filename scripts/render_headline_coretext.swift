import AppKit
import CoreText
import Foundation

// HoursTracker — CoreText marketing headline renderer (macOS only).
//
// Builds a transparent PNG for Hebrew / Arabic App Store headlines so the
// Python compose pipeline can place them with the same metrics as English
// Montserrat ExtraBold (weight 800).
//
// Usage:
//   export HT_HEADLINE_TEXT=$'שורה אחת\nשורה שתיים'
//   ./scripts/render_headline_coretext \
//       AppStoreScreenshots/watch/marketing/fonts/Rubik[wght].ttf \
//       56 800 FFFFFFF0 /tmp/headline.png
//
// Exit codes:
//   0  success (prints WIDTHxHEIGHT to stdout)
//   1  font missing / not loadable / not in allow-list (NO silent fallback)
//   2  bad argv
//   3  HT_HEADLINE_TEXT missing
//   5  bitmap allocation failed
//   6  PNG encode / write failed
//
// Critical rules:
// - Always RTL (`baseWritingDirection = .rightToLeft`) for he/ar.
// - Never fall back to a system font if the file path fails.
// - Padding matches the EN compose path (±4 px inset) for baseline parity.

enum HeadlineRendererExit {
    static let ok = 0
    static let fontFailure = 1
    static let badArgs = 2
    static let missingText = 3
    static let bitmapFailure = 5
    static let pngFailure = 6
}

/// Bundled OFL fonts approved for marketing headlines.
/// he → Rubik / Assistant · ar → Cairo / Tajawal · en uses Pillow+Montserrat.
enum ApprovedMarketingFonts {
    static let basenames: Set<String> = [
        "Rubik[wght].ttf",
        "Assistant[wght].ttf",
        "Cairo[slnt,wght].ttf",
        "Tajawal-ExtraBold.ttf",
        "Tajawal-Bold.ttf",
        "Montserrat[wght].ttf",
    ]

    static func isApproved(path: String) -> Bool {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return basenames.contains(name)
    }
}

enum HeadlineRendererLogic {
    /// Marketing he/ar headlines are always explicit RTL (never “natural”).
    static var requiredWritingDirection: NSWritingDirection { .rightToLeft }

    /// Horizontal / vertical padding around the glyphs — keep in sync with
    /// `compose_iphone_marketing_screenshots.draw_headline` (CoreText path).
    static let edgePadding: CGFloat = 4

    static func validateFontPath(_ path: String) -> String? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
            return "Font file not found: \(path)"
        }
        guard ApprovedMarketingFonts.isApproved(path: path) else {
            return """
            Font not in marketing allow-list: \(URL(fileURLWithPath: path).lastPathComponent)
            Approved: \(ApprovedMarketingFonts.basenames.sorted().joined(separator: ", "))
            Refusing silent system-font fallback.
            """
        }
        return nil
    }

    static func makeParagraphStyle(lineSpacingFor size: CGFloat) -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        // Explicit RTL — do not rely on .natural / alignment alone.
        paragraph.baseWritingDirection = requiredWritingDirection
        paragraph.alignment = .right
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = max(2, size * 0.08)
        return paragraph
    }
}

func parseColor(_ hex: String) -> NSColor {
    var h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    if h.count == 6 { h = "FF" + h }
    var n: UInt64 = 0
    Scanner(string: h).scanHexInt64(&n)
    let a = CGFloat((n & 0xff00_0000) >> 24) / 255
    let r = CGFloat((n & 0x00ff_0000) >> 16) / 255
    let g = CGFloat((n & 0x0000_ff00) >> 8) / 255
    let b = CGFloat(n & 0x0000_00ff) / 255
    return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func loadCTFont(path: String, size: CGFloat, weight: CGFloat) -> CTFont? {
    let url = URL(fileURLWithPath: path) as CFURL
    // Register the file so CoreText resolves glyphs from THIS file only.
    CTFontManagerRegisterFontsForURL(url, .process, nil)
    guard
        let descs = CTFontManagerCreateFontDescriptorsFromURL(url) as? [CTFontDescriptor],
        let baseDesc = descs.first
    else {
        return nil
    }

    // Variable-font weight axis 'wght' = 2003265652
    let variation: [CFNumber: CFNumber] = [
        2003265652 as CFNumber: weight as CFNumber
    ]
    let desc = CTFontDescriptorCreateCopyWithAttributes(
        baseDesc,
        [kCTFontVariationAttribute as CFString: variation] as CFDictionary
    )
    var font = CTFontCreateWithFontDescriptor(desc, size, nil)
    if weight >= 700,
       let bold = CTFontCreateCopyWithSymbolicTraits(font, size, nil, .traitBold, .traitBold) {
        font = bold
    }

    // Sanity: PostScript / family name must come from the loaded file, not a substitute.
    let family = CTFontCopyFamilyName(font) as String
    if family.isEmpty {
        return nil
    }
    return font
}

// MARK: - main

guard CommandLine.arguments.count >= 6 else {
    fputs(
        "usage: render_headline_coretext fontPath sizePx weight hexAARRGGBB outPNG\n"
            + "       text via HT_HEADLINE_TEXT (real newlines allowed)\n",
        stderr
    )
    exit(HeadlineRendererExit.badArgs)
}

let fontPath = CommandLine.arguments[1]
let size = CGFloat(Double(CommandLine.arguments[2]) ?? 0)
let weightVal = CGFloat(Double(CommandLine.arguments[3]) ?? 800)
let colorHex = CommandLine.arguments[4]
let outPath = CommandLine.arguments[5]

guard size > 0 else {
    fputs("Invalid sizePx\n", stderr)
    exit(HeadlineRendererExit.badArgs)
}

guard let text = ProcessInfo.processInfo.environment["HT_HEADLINE_TEXT"], !text.isEmpty else {
    fputs("HT_HEADLINE_TEXT missing\n", stderr)
    exit(HeadlineRendererExit.missingText)
}

if let err = HeadlineRendererLogic.validateFontPath(fontPath) {
    fputs(err + "\n", stderr)
    exit(HeadlineRendererExit.fontFailure)
}

guard let ctFont = loadCTFont(path: fontPath, size: size, weight: weightVal) else {
    fputs(
        "Failed to load CoreText font from \(fontPath)\n"
            + "Refusing silent system-font fallback.\n",
        stderr
    )
    exit(HeadlineRendererExit.fontFailure)
}

let paragraph = HeadlineRendererLogic.makeParagraphStyle(lineSpacingFor: size)
let pad = HeadlineRendererLogic.edgePadding

let attr = NSAttributedString(string: text, attributes: [
    .font: ctFont as NSFont,
    .foregroundColor: parseColor(colorHex),
    .paragraphStyle: paragraph,
    .kern: size * 0.02
])

let bounds = attr.boundingRect(
    with: NSSize(width: 2000, height: 2000),
    options: [.usesLineFragmentOrigin, .usesFontLeading]
).integral

let width = max(1, Int(ceil(bounds.width)) + Int(pad * 2))
let height = max(1, Int(ceil(bounds.height)) + Int(pad * 2))

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
) else {
    fputs("NSBitmapImageRep allocation failed\n", stderr)
    exit(HeadlineRendererExit.bitmapFailure)
}

rep.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
// Clear to transparent.
NSColor.clear.setFill()
NSBezierPath.fill(NSRect(x: 0, y: 0, width: width, height: height))
attr.draw(
    with: NSRect(x: pad, y: pad, width: bounds.width, height: bounds.height),
    options: [.usesLineFragmentOrigin, .usesFontLeading]
)
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fputs("PNG encode failed\n", stderr)
    exit(HeadlineRendererExit.pngFailure)
}

do {
    try png.write(to: URL(fileURLWithPath: outPath))
} catch {
    fputs("PNG write failed: \(error)\n", stderr)
    exit(HeadlineRendererExit.pngFailure)
}

fputs("\(width)x\(height)\n", stdout)
exit(HeadlineRendererExit.ok)
