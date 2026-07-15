import SwiftUI

// MARK: - Day catalog (1...31)

enum StickmanPose: Int, CaseIterable {
    case thumbsUp
    case wave
    case victory
    case armsWide
    case salute
    case pointing
    case dancing
    case running
    case jumping
    case bow
    case flex
    case heartHands
}

enum StickmanAccessory: Int, CaseIterable {
    case none
    case redTie
    case blueTie
    case bowTie
    case scarf
    case backpack
    case hardHat
    case cap
    case chefHat
    case headphones
    case glasses
    case cape
}

enum StickmanMotionKind: Int, CaseIterable {
    case zigzag
    case bounceHop
    case highArc
    case sprint
    case orbit
    case slide
    case figureEight
    case riseAndFall
    case diagonalDash
    case skipRope
}

struct StickmanDayStyle: Equatable {
    let pose: StickmanPose
    let accessory: StickmanAccessory
    let accent: Color
    let shirt: Color
    let motion: StickmanMotionKind
    let duration: Double
    let peakOpacity: Double
    let facingLeft: Bool

    /// Stable style for calendar day 1...31. Same day-of-month → same look every month.
    static func style(forDayOfMonth day: Int) -> StickmanDayStyle {
        let clamped = min(max(day, 1), 31)
        return catalog[clamped - 1]
    }

    private static let catalog: [StickmanDayStyle] = [
        // 1
        StickmanDayStyle(pose: .thumbsUp, accessory: .redTie, accent: .red, shirt: .clear, motion: .zigzag, duration: 3.8, peakOpacity: 0.34, facingLeft: false),
        // 2
        StickmanDayStyle(pose: .wave, accessory: .cap, accent: Color(red: 0.2, green: 0.55, blue: 0.95), shirt: Color(red: 0.25, green: 0.7, blue: 0.45).opacity(0.35), motion: .bounceHop, duration: 4.0, peakOpacity: 0.36, facingLeft: false),
        // 3
        StickmanDayStyle(pose: .victory, accessory: .scarf, accent: Color(red: 0.95, green: 0.45, blue: 0.2), shirt: .clear, motion: .highArc, duration: 3.6, peakOpacity: 0.33, facingLeft: true),
        // 4
        StickmanDayStyle(pose: .running, accessory: .backpack, accent: Color(red: 0.35, green: 0.55, blue: 0.9), shirt: Color(red: 0.2, green: 0.35, blue: 0.7).opacity(0.3), motion: .sprint, duration: 3.2, peakOpacity: 0.38, facingLeft: false),
        // 5
        StickmanDayStyle(pose: .salute, accessory: .hardHat, accent: Color(red: 0.95, green: 0.75, blue: 0.15), shirt: Color(red: 0.9, green: 0.7, blue: 0.2).opacity(0.25), motion: .slide, duration: 3.9, peakOpacity: 0.34, facingLeft: false),
        // 6
        StickmanDayStyle(pose: .dancing, accessory: .headphones, accent: Color(red: 0.75, green: 0.3, blue: 0.85), shirt: Color(red: 0.55, green: 0.2, blue: 0.7).opacity(0.3), motion: .figureEight, duration: 4.2, peakOpacity: 0.36, facingLeft: false),
        // 7
        StickmanDayStyle(pose: .jumping, accessory: .bowTie, accent: Color(red: 0.15, green: 0.55, blue: 0.45), shirt: .clear, motion: .riseAndFall, duration: 3.7, peakOpacity: 0.35, facingLeft: false),
        // 8
        StickmanDayStyle(pose: .pointing, accessory: .glasses, accent: Color(red: 0.25, green: 0.25, blue: 0.3), shirt: Color.gray.opacity(0.25), motion: .diagonalDash, duration: 3.5, peakOpacity: 0.33, facingLeft: true),
        // 9
        StickmanDayStyle(pose: .armsWide, accessory: .cape, accent: Color(red: 0.85, green: 0.2, blue: 0.25), shirt: Color(red: 0.15, green: 0.2, blue: 0.55).opacity(0.35), motion: .orbit, duration: 4.1, peakOpacity: 0.32, facingLeft: false),
        // 10
        StickmanDayStyle(pose: .flex, accessory: .none, accent: Color(red: 0.95, green: 0.4, blue: 0.2), shirt: Color(red: 0.9, green: 0.35, blue: 0.2).opacity(0.28), motion: .bounceHop, duration: 3.6, peakOpacity: 0.37, facingLeft: false),
        // 11
        StickmanDayStyle(pose: .bow, accessory: .chefHat, accent: Color.white, shirt: Color(red: 0.95, green: 0.95, blue: 0.97).opacity(0.4), motion: .slide, duration: 3.8, peakOpacity: 0.34, facingLeft: false),
        // 12
        StickmanDayStyle(pose: .heartHands, accessory: .scarf, accent: Color(red: 0.9, green: 0.25, blue: 0.45), shirt: Color(red: 0.95, green: 0.55, blue: 0.65).opacity(0.28), motion: .highArc, duration: 4.0, peakOpacity: 0.35, facingLeft: false),
        // 13
        StickmanDayStyle(pose: .thumbsUp, accessory: .blueTie, accent: Color(red: 0.2, green: 0.4, blue: 0.9), shirt: .clear, motion: .zigzag, duration: 3.9, peakOpacity: 0.34, facingLeft: true),
        // 14
        StickmanDayStyle(pose: .wave, accessory: .headphones, accent: Color(red: 0.2, green: 0.8, blue: 0.7), shirt: Color(red: 0.15, green: 0.65, blue: 0.55).opacity(0.3), motion: .skipRope, duration: 4.0, peakOpacity: 0.36, facingLeft: false),
        // 15
        StickmanDayStyle(pose: .running, accessory: .cap, accent: Color(red: 0.95, green: 0.55, blue: 0.1), shirt: Color(red: 0.9, green: 0.5, blue: 0.1).opacity(0.28), motion: .sprint, duration: 3.1, peakOpacity: 0.38, facingLeft: true),
        // 16
        StickmanDayStyle(pose: .victory, accessory: .hardHat, accent: Color(red: 0.3, green: 0.75, blue: 0.35), shirt: .clear, motion: .riseAndFall, duration: 3.7, peakOpacity: 0.33, facingLeft: false),
        // 17
        StickmanDayStyle(pose: .salute, accessory: .redTie, accent: Color(red: 0.8, green: 0.15, blue: 0.2), shirt: Color(red: 0.15, green: 0.2, blue: 0.35).opacity(0.3), motion: .diagonalDash, duration: 3.6, peakOpacity: 0.34, facingLeft: false),
        // 18
        StickmanDayStyle(pose: .dancing, accessory: .bowTie, accent: Color(red: 0.65, green: 0.25, blue: 0.8), shirt: Color(red: 0.5, green: 0.2, blue: 0.7).opacity(0.28), motion: .figureEight, duration: 4.3, peakOpacity: 0.36, facingLeft: false),
        // 19
        StickmanDayStyle(pose: .jumping, accessory: .backpack, accent: Color(red: 0.2, green: 0.6, blue: 0.85), shirt: Color(red: 0.2, green: 0.5, blue: 0.75).opacity(0.28), motion: .bounceHop, duration: 3.8, peakOpacity: 0.35, facingLeft: false),
        // 20
        StickmanDayStyle(pose: .pointing, accessory: .cape, accent: Color(red: 0.55, green: 0.2, blue: 0.75), shirt: .clear, motion: .orbit, duration: 4.0, peakOpacity: 0.32, facingLeft: true),
        // 21
        StickmanDayStyle(pose: .armsWide, accessory: .glasses, accent: Color(red: 0.15, green: 0.7, blue: 0.55), shirt: Color(red: 0.1, green: 0.55, blue: 0.45).opacity(0.3), motion: .highArc, duration: 3.9, peakOpacity: 0.34, facingLeft: false),
        // 22
        StickmanDayStyle(pose: .flex, accessory: .chefHat, accent: Color(red: 0.95, green: 0.35, blue: 0.25), shirt: Color.white.opacity(0.35), motion: .slide, duration: 3.5, peakOpacity: 0.36, facingLeft: false),
        // 23
        StickmanDayStyle(pose: .bow, accessory: .blueTie, accent: Color(red: 0.25, green: 0.35, blue: 0.85), shirt: .clear, motion: .zigzag, duration: 3.8, peakOpacity: 0.33, facingLeft: true),
        // 24
        StickmanDayStyle(pose: .heartHands, accessory: .none, accent: Color(red: 0.95, green: 0.3, blue: 0.55), shirt: Color(red: 0.9, green: 0.4, blue: 0.55).opacity(0.28), motion: .skipRope, duration: 4.1, peakOpacity: 0.35, facingLeft: false),
        // 25
        StickmanDayStyle(pose: .thumbsUp, accessory: .headphones, accent: Color(red: 0.3, green: 0.85, blue: 0.5), shirt: Color(red: 0.2, green: 0.65, blue: 0.4).opacity(0.3), motion: .diagonalDash, duration: 3.6, peakOpacity: 0.37, facingLeft: false),
        // 26
        StickmanDayStyle(pose: .wave, accessory: .hardHat, accent: Color(red: 0.95, green: 0.8, blue: 0.2), shirt: Color(red: 0.25, green: 0.45, blue: 0.7).opacity(0.28), motion: .sprint, duration: 3.3, peakOpacity: 0.36, facingLeft: true),
        // 27
        StickmanDayStyle(pose: .running, accessory: .scarf, accent: Color(red: 0.85, green: 0.35, blue: 0.2), shirt: .clear, motion: .figureEight, duration: 4.0, peakOpacity: 0.34, facingLeft: false),
        // 28
        StickmanDayStyle(pose: .victory, accessory: .cap, accent: Color(red: 0.2, green: 0.75, blue: 0.9), shirt: Color(red: 0.15, green: 0.55, blue: 0.7).opacity(0.3), motion: .riseAndFall, duration: 3.7, peakOpacity: 0.35, facingLeft: false),
        // 29
        StickmanDayStyle(pose: .salute, accessory: .backpack, accent: Color(red: 0.45, green: 0.7, blue: 0.3), shirt: Color(red: 0.35, green: 0.55, blue: 0.25).opacity(0.28), motion: .bounceHop, duration: 3.9, peakOpacity: 0.34, facingLeft: false),
        // 30
        StickmanDayStyle(pose: .dancing, accessory: .cape, accent: Color(red: 0.7, green: 0.25, blue: 0.85), shirt: Color(red: 0.2, green: 0.15, blue: 0.4).opacity(0.35), motion: .orbit, duration: 4.2, peakOpacity: 0.33, facingLeft: true),
        // 31
        StickmanDayStyle(pose: .jumping, accessory: .bowTie, accent: Color(red: 0.95, green: 0.55, blue: 0.15), shirt: Color(red: 0.9, green: 0.45, blue: 0.15).opacity(0.28), motion: .highArc, duration: 3.8, peakOpacity: 0.36, facingLeft: false)
    ]
}

// MARK: - Figure drawing

struct StickmanFigureView: View {
    let style: StickmanDayStyle

    var body: some View {
        Canvas { context, size in
            draw(context: context, size: size, style: style)
        }
        .scaleEffect(x: style.facingLeft ? -1 : 1, y: 1)
        .accessibilityHidden(true)
    }

    private func draw(context: GraphicsContext, size: CGSize, style: StickmanDayStyle) {
        let stroke = Color.primary.opacity(0.85)
        let lineWidth = max(1.6, size.width * 0.045)
        let ink = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        let w = size.width
        let h = size.height

        let headCenter = CGPoint(x: w * 0.48, y: h * 0.18)
        let headRadius = w * 0.13
        let neck = CGPoint(x: headCenter.x, y: headCenter.y + headRadius)
        let shoulderY = neck.y + h * 0.08
        let hip = CGPoint(x: w * 0.48, y: h * 0.58)

        // Optional shirt wash behind torso
        if style.shirt != .clear {
            var shirt = Path()
            shirt.move(to: CGPoint(x: neck.x - w * 0.12, y: neck.y + h * 0.02))
            shirt.addLine(to: CGPoint(x: neck.x + w * 0.12, y: neck.y + h * 0.02))
            shirt.addLine(to: CGPoint(x: hip.x + w * 0.14, y: hip.y))
            shirt.addLine(to: CGPoint(x: hip.x - w * 0.14, y: hip.y))
            shirt.closeSubpath()
            context.fill(shirt, with: .color(style.shirt))
        }

        drawAccessoryBehind(context: context, style: style, headCenter: headCenter, headRadius: headRadius, hip: hip, w: w, h: h, stroke: stroke, ink: ink)

        // Head
        let headRect = CGRect(
            x: headCenter.x - headRadius,
            y: headCenter.y - headRadius,
            width: headRadius * 2,
            height: headRadius * 2
        )
        context.stroke(Path(ellipseIn: headRect), with: .color(stroke), style: ink)

        // Face
        var smile = Path()
        smile.addArc(
            center: CGPoint(x: headCenter.x, y: headCenter.y + headRadius * 0.12),
            radius: headRadius * 0.45,
            startAngle: .degrees(20),
            endAngle: .degrees(160),
            clockwise: false
        )
        context.stroke(smile, with: .color(stroke), style: StrokeStyle(lineWidth: lineWidth * 0.7, lineCap: .round))

        let eyeY = headCenter.y - headRadius * 0.15
        let eyeR = max(1.0, w * 0.018)
        context.fill(
            Path(ellipseIn: CGRect(x: headCenter.x - headRadius * 0.35 - eyeR, y: eyeY - eyeR, width: eyeR * 2, height: eyeR * 2)),
            with: .color(stroke)
        )
        context.fill(
            Path(ellipseIn: CGRect(x: headCenter.x + headRadius * 0.35 - eyeR, y: eyeY - eyeR, width: eyeR * 2, height: eyeR * 2)),
            with: .color(stroke)
        )

        // Hair
        var hair = Path()
        hair.move(to: CGPoint(x: headCenter.x - headRadius * 0.35, y: headCenter.y - headRadius * 0.75))
        hair.addQuadCurve(
            to: CGPoint(x: headCenter.x - headRadius * 0.1, y: headCenter.y - headRadius * 1.15),
            control: CGPoint(x: headCenter.x - headRadius * 0.45, y: headCenter.y - headRadius * 1.05)
        )
        hair.move(to: CGPoint(x: headCenter.x + headRadius * 0.05, y: headCenter.y - headRadius * 0.85))
        hair.addQuadCurve(
            to: CGPoint(x: headCenter.x + headRadius * 0.35, y: headCenter.y - headRadius * 1.1),
            control: CGPoint(x: headCenter.x + headRadius * 0.25, y: headCenter.y - headRadius * 1.05)
        )
        context.stroke(hair, with: .color(stroke), style: StrokeStyle(lineWidth: lineWidth * 0.75, lineCap: .round))

        // Torso
        var torso = Path()
        torso.move(to: neck)
        torso.addLine(to: hip)
        context.stroke(torso, with: .color(stroke), style: ink)

        drawAccessoryFront(context: context, style: style, neck: neck, headCenter: headCenter, headRadius: headRadius, w: w, h: h, stroke: stroke, ink: ink, lineWidth: lineWidth)

        drawArms(
            context: context,
            pose: style.pose,
            accent: style.accent,
            neck: neck,
            shoulderY: shoulderY,
            w: w,
            h: h,
            stroke: stroke,
            ink: ink,
            lineWidth: lineWidth
        )

        drawLegs(context: context, pose: style.pose, hip: hip, w: w, h: h, stroke: stroke, ink: ink)
    }

    private func drawAccessoryBehind(
        context: GraphicsContext,
        style: StickmanDayStyle,
        headCenter: CGPoint,
        headRadius: CGFloat,
        hip: CGPoint,
        w: CGFloat,
        h: CGFloat,
        stroke: Color,
        ink: StrokeStyle
    ) {
        switch style.accessory {
        case .cape:
            var cape = Path()
            cape.move(to: CGPoint(x: headCenter.x, y: headCenter.y + headRadius))
            cape.addQuadCurve(
                to: CGPoint(x: w * 0.12, y: h * 0.72),
                control: CGPoint(x: w * 0.05, y: h * 0.4)
            )
            cape.addLine(to: CGPoint(x: hip.x - w * 0.02, y: hip.y))
            cape.closeSubpath()
            context.fill(cape, with: .color(style.accent.opacity(0.35)))
            context.stroke(cape, with: .color(stroke.opacity(0.5)), style: StrokeStyle(lineWidth: ink.lineWidth * 0.6, lineJoin: .round))
        case .backpack:
            let pack = CGRect(x: w * 0.22, y: h * 0.28, width: w * 0.18, height: h * 0.22)
            context.fill(Path(roundedRect: pack, cornerRadius: 3), with: .color(style.accent.opacity(0.45)))
            context.stroke(Path(roundedRect: pack, cornerRadius: 3), with: .color(stroke), style: StrokeStyle(lineWidth: ink.lineWidth * 0.7))
        default:
            break
        }
    }

    private func drawAccessoryFront(
        context: GraphicsContext,
        style: StickmanDayStyle,
        neck: CGPoint,
        headCenter: CGPoint,
        headRadius: CGFloat,
        w: CGFloat,
        h: CGFloat,
        stroke: Color,
        ink: StrokeStyle,
        lineWidth: CGFloat
    ) {
        switch style.accessory {
        case .none:
            break
        case .redTie, .blueTie:
            let color = style.accessory == .redTie
                ? Color(red: 0.86, green: 0.18, blue: 0.22)
                : Color(red: 0.2, green: 0.4, blue: 0.9)
            let tieTop = CGPoint(x: neck.x, y: neck.y + h * 0.02)
            let tieMid = CGPoint(x: neck.x, y: neck.y + h * 0.14)
            let tieTip = CGPoint(x: neck.x, y: neck.y + h * 0.22)
            var tie = Path()
            tie.move(to: CGPoint(x: tieTop.x - w * 0.035, y: tieTop.y))
            tie.addLine(to: CGPoint(x: tieTop.x + w * 0.035, y: tieTop.y))
            tie.addLine(to: CGPoint(x: tieMid.x + w * 0.02, y: tieMid.y))
            tie.addLine(to: tieTip)
            tie.addLine(to: CGPoint(x: tieMid.x - w * 0.02, y: tieMid.y))
            tie.closeSubpath()
            context.fill(tie, with: .color(color))
            // Lapels
            var lapel = Path()
            lapel.move(to: CGPoint(x: neck.x - w * 0.02, y: neck.y + h * 0.04))
            lapel.addLine(to: CGPoint(x: neck.x - w * 0.10, y: neck.y + h * 0.16))
            lapel.move(to: CGPoint(x: neck.x + w * 0.02, y: neck.y + h * 0.04))
            lapel.addLine(to: CGPoint(x: neck.x + w * 0.10, y: neck.y + h * 0.16))
            context.stroke(lapel, with: .color(stroke.opacity(0.75)), style: StrokeStyle(lineWidth: lineWidth * 0.65, lineCap: .round))
        case .bowTie:
            var bow = Path()
            bow.move(to: CGPoint(x: neck.x, y: neck.y + h * 0.04))
            bow.addLine(to: CGPoint(x: neck.x - w * 0.08, y: neck.y + h * 0.01))
            bow.addLine(to: CGPoint(x: neck.x - w * 0.08, y: neck.y + h * 0.07))
            bow.closeSubpath()
            bow.move(to: CGPoint(x: neck.x, y: neck.y + h * 0.04))
            bow.addLine(to: CGPoint(x: neck.x + w * 0.08, y: neck.y + h * 0.01))
            bow.addLine(to: CGPoint(x: neck.x + w * 0.08, y: neck.y + h * 0.07))
            bow.closeSubpath()
            context.fill(bow, with: .color(style.accent))
            context.fill(
                Path(ellipseIn: CGRect(x: neck.x - w * 0.015, y: neck.y + h * 0.03, width: w * 0.03, height: h * 0.025)),
                with: .color(stroke)
            )
        case .scarf:
            var scarf = Path()
            scarf.move(to: CGPoint(x: neck.x - w * 0.1, y: neck.y))
            scarf.addQuadCurve(
                to: CGPoint(x: neck.x + w * 0.1, y: neck.y + h * 0.02),
                control: CGPoint(x: neck.x, y: neck.y - h * 0.02)
            )
            scarf.addLine(to: CGPoint(x: neck.x + w * 0.04, y: neck.y + h * 0.18))
            context.stroke(scarf, with: .color(style.accent), style: StrokeStyle(lineWidth: lineWidth * 1.4, lineCap: .round))
        case .hardHat:
            let brim = CGRect(x: headCenter.x - headRadius * 1.2, y: headCenter.y - headRadius * 0.55, width: headRadius * 2.4, height: headRadius * 0.35)
            context.fill(Path(ellipseIn: brim), with: .color(style.accent.opacity(0.85)))
            let dome = CGRect(x: headCenter.x - headRadius * 0.95, y: headCenter.y - headRadius * 1.35, width: headRadius * 1.9, height: headRadius * 1.1)
            context.fill(Path(ellipseIn: dome), with: .color(style.accent))
            context.stroke(Path(ellipseIn: dome), with: .color(stroke.opacity(0.5)), style: StrokeStyle(lineWidth: lineWidth * 0.5))
        case .cap:
            var cap = Path()
            cap.addArc(
                center: CGPoint(x: headCenter.x, y: headCenter.y - headRadius * 0.15),
                radius: headRadius * 1.05,
                startAngle: .degrees(200),
                endAngle: .degrees(340),
                clockwise: false
            )
            context.stroke(cap, with: .color(style.accent), style: StrokeStyle(lineWidth: lineWidth * 1.6, lineCap: .round))
            var bill = Path()
            bill.move(to: CGPoint(x: headCenter.x + headRadius * 0.4, y: headCenter.y - headRadius * 0.2))
            bill.addLine(to: CGPoint(x: headCenter.x + headRadius * 1.35, y: headCenter.y - headRadius * 0.05))
            context.stroke(bill, with: .color(style.accent), style: StrokeStyle(lineWidth: lineWidth * 1.3, lineCap: .round))
        case .chefHat:
            let band = CGRect(x: headCenter.x - headRadius * 0.95, y: headCenter.y - headRadius * 0.55, width: headRadius * 1.9, height: headRadius * 0.28)
            context.fill(Path(roundedRect: band, cornerRadius: 2), with: .color(Color.primary.opacity(0.12)))
            context.stroke(Path(roundedRect: band, cornerRadius: 2), with: .color(stroke), style: StrokeStyle(lineWidth: lineWidth * 0.55))
            let puff = CGRect(x: headCenter.x - headRadius * 0.85, y: headCenter.y - headRadius * 1.55, width: headRadius * 1.7, height: headRadius * 1.15)
            context.fill(Path(ellipseIn: puff), with: .color(Color.primary.opacity(0.08)))
            context.stroke(Path(ellipseIn: puff), with: .color(stroke), style: StrokeStyle(lineWidth: lineWidth * 0.7))
        case .headphones:
            var band = Path()
            band.addArc(
                center: headCenter,
                radius: headRadius * 1.15,
                startAngle: .degrees(200),
                endAngle: .degrees(340),
                clockwise: false
            )
            context.stroke(band, with: .color(style.accent), style: StrokeStyle(lineWidth: lineWidth * 1.1, lineCap: .round))
            let earL = CGRect(x: headCenter.x - headRadius * 1.25, y: headCenter.y - headRadius * 0.25, width: headRadius * 0.45, height: headRadius * 0.7)
            let earR = CGRect(x: headCenter.x + headRadius * 0.8, y: headCenter.y - headRadius * 0.25, width: headRadius * 0.45, height: headRadius * 0.7)
            context.fill(Path(roundedRect: earL, cornerRadius: 3), with: .color(style.accent))
            context.fill(Path(roundedRect: earR, cornerRadius: 3), with: .color(style.accent))
        case .glasses:
            let lensR = headRadius * 0.32
            let left = CGRect(x: headCenter.x - headRadius * 0.55 - lensR, y: headCenter.y - headRadius * 0.2 - lensR * 0.5, width: lensR * 2, height: lensR * 1.2)
            let right = CGRect(x: headCenter.x + headRadius * 0.55 - lensR, y: headCenter.y - headRadius * 0.2 - lensR * 0.5, width: lensR * 2, height: lensR * 1.2)
            context.stroke(Path(ellipseIn: left), with: .color(stroke), style: StrokeStyle(lineWidth: lineWidth * 0.7))
            context.stroke(Path(ellipseIn: right), with: .color(stroke), style: StrokeStyle(lineWidth: lineWidth * 0.7))
            var bridge = Path()
            bridge.move(to: CGPoint(x: left.maxX, y: left.midY))
            bridge.addLine(to: CGPoint(x: right.minX, y: right.midY))
            context.stroke(bridge, with: .color(stroke), style: StrokeStyle(lineWidth: lineWidth * 0.6, lineCap: .round))
        case .backpack, .cape:
            break
        }
    }

    private func drawArms(
        context: GraphicsContext,
        pose: StickmanPose,
        accent: Color,
        neck: CGPoint,
        shoulderY: CGFloat,
        w: CGFloat,
        h: CGFloat,
        stroke: Color,
        ink: StrokeStyle,
        lineWidth: CGFloat
    ) {
        let shoulder = CGPoint(x: neck.x, y: shoulderY)

        switch pose {
        case .thumbsUp:
            var leftArm = Path()
            leftArm.move(to: shoulder)
            leftArm.addQuadCurve(to: CGPoint(x: w * 0.18, y: h * 0.48), control: CGPoint(x: w * 0.12, y: h * 0.28))
            context.stroke(leftArm, with: .color(stroke), style: ink)

            var rightArm = Path()
            rightArm.move(to: shoulder)
            rightArm.addQuadCurve(to: CGPoint(x: w * 0.72, y: h * 0.22), control: CGPoint(x: w * 0.68, y: h * 0.30))
            rightArm.addLine(to: CGPoint(x: w * 0.78, y: h * 0.10))
            context.stroke(rightArm, with: .color(stroke), style: ink)
            drawThumbsUp(context: context, at: CGPoint(x: w * 0.82, y: h * 0.09), w: w, stroke: stroke, lineWidth: lineWidth)

        case .wave:
            var leftArm = Path()
            leftArm.move(to: shoulder)
            leftArm.addLine(to: CGPoint(x: w * 0.22, y: h * 0.42))
            context.stroke(leftArm, with: .color(stroke), style: ink)
            var rightArm = Path()
            rightArm.move(to: shoulder)
            rightArm.addQuadCurve(to: CGPoint(x: w * 0.78, y: h * 0.08), control: CGPoint(x: w * 0.70, y: h * 0.28))
            context.stroke(rightArm, with: .color(stroke), style: ink)
            // Wave hand
            context.stroke(
                Path(ellipseIn: CGRect(x: w * 0.74, y: h * 0.02, width: w * 0.12, height: w * 0.12)),
                with: .color(stroke),
                style: StrokeStyle(lineWidth: lineWidth * 0.8)
            )

        case .victory:
            var left = Path()
            left.move(to: shoulder)
            left.addLine(to: CGPoint(x: w * 0.22, y: h * 0.08))
            context.stroke(left, with: .color(stroke), style: ink)
            var right = Path()
            right.move(to: shoulder)
            right.addLine(to: CGPoint(x: w * 0.78, y: h * 0.08))
            context.stroke(right, with: .color(stroke), style: ink)
            // V fingers hint
            var v = Path()
            v.move(to: CGPoint(x: w * 0.76, y: h * 0.05))
            v.addLine(to: CGPoint(x: w * 0.72, y: h * 0.0))
            v.move(to: CGPoint(x: w * 0.76, y: h * 0.05))
            v.addLine(to: CGPoint(x: w * 0.84, y: h * 0.0))
            context.stroke(v, with: .color(accent), style: StrokeStyle(lineWidth: lineWidth * 0.8, lineCap: .round))

        case .armsWide:
            var left = Path()
            left.move(to: shoulder)
            left.addLine(to: CGPoint(x: w * 0.08, y: h * 0.32))
            context.stroke(left, with: .color(stroke), style: ink)
            var right = Path()
            right.move(to: shoulder)
            right.addLine(to: CGPoint(x: w * 0.92, y: h * 0.32))
            context.stroke(right, with: .color(stroke), style: ink)

        case .salute:
            var left = Path()
            left.move(to: shoulder)
            left.addLine(to: CGPoint(x: w * 0.20, y: h * 0.45))
            context.stroke(left, with: .color(stroke), style: ink)
            var right = Path()
            right.move(to: shoulder)
            right.addLine(to: CGPoint(x: w * 0.62, y: h * 0.14))
            right.addLine(to: CGPoint(x: w * 0.55, y: h * 0.06))
            context.stroke(right, with: .color(stroke), style: ink)

        case .pointing:
            var left = Path()
            left.move(to: shoulder)
            left.addLine(to: CGPoint(x: w * 0.22, y: h * 0.40))
            context.stroke(left, with: .color(stroke), style: ink)
            var right = Path()
            right.move(to: shoulder)
            right.addLine(to: CGPoint(x: w * 0.88, y: h * 0.26))
            context.stroke(right, with: .color(stroke), style: ink)
            context.fill(
                Path(ellipseIn: CGRect(x: w * 0.86, y: h * 0.23, width: w * 0.06, height: w * 0.06)),
                with: .color(accent)
            )

        case .dancing:
            var left = Path()
            left.move(to: shoulder)
            left.addQuadCurve(to: CGPoint(x: w * 0.15, y: h * 0.18), control: CGPoint(x: w * 0.18, y: h * 0.35))
            context.stroke(left, with: .color(stroke), style: ink)
            var right = Path()
            right.move(to: shoulder)
            right.addQuadCurve(to: CGPoint(x: w * 0.85, y: h * 0.42), control: CGPoint(x: w * 0.75, y: h * 0.18))
            context.stroke(right, with: .color(stroke), style: ink)

        case .running:
            var left = Path()
            left.move(to: shoulder)
            left.addLine(to: CGPoint(x: w * 0.18, y: h * 0.22))
            context.stroke(left, with: .color(stroke), style: ink)
            var right = Path()
            right.move(to: shoulder)
            right.addLine(to: CGPoint(x: w * 0.82, y: h * 0.38))
            context.stroke(right, with: .color(stroke), style: ink)

        case .jumping:
            var left = Path()
            left.move(to: shoulder)
            left.addLine(to: CGPoint(x: w * 0.16, y: h * 0.12))
            context.stroke(left, with: .color(stroke), style: ink)
            var right = Path()
            right.move(to: shoulder)
            right.addLine(to: CGPoint(x: w * 0.84, y: h * 0.12))
            context.stroke(right, with: .color(stroke), style: ink)

        case .bow:
            var left = Path()
            left.move(to: shoulder)
            left.addLine(to: CGPoint(x: w * 0.28, y: h * 0.52))
            context.stroke(left, with: .color(stroke), style: ink)
            var right = Path()
            right.move(to: shoulder)
            right.addLine(to: CGPoint(x: w * 0.68, y: h * 0.52))
            context.stroke(right, with: .color(stroke), style: ink)

        case .flex:
            var left = Path()
            left.move(to: shoulder)
            left.addQuadCurve(to: CGPoint(x: w * 0.18, y: h * 0.20), control: CGPoint(x: w * 0.12, y: h * 0.35))
            left.addLine(to: CGPoint(x: w * 0.28, y: h * 0.28))
            context.stroke(left, with: .color(stroke), style: ink)
            var right = Path()
            right.move(to: shoulder)
            right.addQuadCurve(to: CGPoint(x: w * 0.82, y: h * 0.20), control: CGPoint(x: w * 0.88, y: h * 0.35))
            right.addLine(to: CGPoint(x: w * 0.72, y: h * 0.28))
            context.stroke(right, with: .color(stroke), style: ink)

        case .heartHands:
            var left = Path()
            left.move(to: shoulder)
            left.addQuadCurve(to: CGPoint(x: w * 0.40, y: h * 0.36), control: CGPoint(x: w * 0.22, y: h * 0.30))
            context.stroke(left, with: .color(stroke), style: ink)
            var right = Path()
            right.move(to: shoulder)
            right.addQuadCurve(to: CGPoint(x: w * 0.56, y: h * 0.36), control: CGPoint(x: w * 0.74, y: h * 0.30))
            context.stroke(right, with: .color(stroke), style: ink)
            // Tiny heart
            var heart = Path()
            let c = CGPoint(x: w * 0.48, y: h * 0.34)
            heart.move(to: CGPoint(x: c.x, y: c.y + h * 0.04))
            heart.addCurve(
                to: CGPoint(x: c.x, y: c.y - h * 0.02),
                control1: CGPoint(x: c.x - w * 0.08, y: c.y + h * 0.01),
                control2: CGPoint(x: c.x - w * 0.06, y: c.y - h * 0.05)
            )
            heart.addCurve(
                to: CGPoint(x: c.x, y: c.y + h * 0.04),
                control1: CGPoint(x: c.x + w * 0.06, y: c.y - h * 0.05),
                control2: CGPoint(x: c.x + w * 0.08, y: c.y + h * 0.01)
            )
            context.fill(heart, with: .color(accent.opacity(0.85)))
        }
    }

    private func drawThumbsUp(
        context: GraphicsContext,
        at fistCenter: CGPoint,
        w: CGFloat,
        stroke: Color,
        lineWidth: CGFloat
    ) {
        let fistR = w * 0.055
        context.fill(
            Path(ellipseIn: CGRect(x: fistCenter.x - fistR, y: fistCenter.y - fistR * 0.85, width: fistR * 1.7, height: fistR * 1.5)),
            with: .color(stroke.opacity(0.12))
        )
        context.stroke(
            Path(ellipseIn: CGRect(x: fistCenter.x - fistR, y: fistCenter.y - fistR * 0.85, width: fistR * 1.7, height: fistR * 1.5)),
            with: .color(stroke),
            style: StrokeStyle(lineWidth: lineWidth * 0.85, lineCap: .round)
        )
        var thumb = Path()
        thumb.move(to: CGPoint(x: fistCenter.x + fistR * 0.15, y: fistCenter.y - fistR * 0.7))
        thumb.addQuadCurve(
            to: CGPoint(x: fistCenter.x + fistR * 0.1, y: fistCenter.y - fistR * 2.0),
            control: CGPoint(x: fistCenter.x + fistR * 1.1, y: fistCenter.y - fistR * 1.6)
        )
        context.stroke(thumb, with: .color(stroke), style: StrokeStyle(lineWidth: lineWidth * 0.95, lineCap: .round))
    }

    private func drawLegs(
        context: GraphicsContext,
        pose: StickmanPose,
        hip: CGPoint,
        w: CGFloat,
        h: CGFloat,
        stroke: Color,
        ink: StrokeStyle
    ) {
        var legs = Path()
        switch pose {
        case .running:
            legs.move(to: hip)
            legs.addLine(to: CGPoint(x: w * 0.22, y: h * 0.88))
            legs.move(to: hip)
            legs.addLine(to: CGPoint(x: w * 0.78, y: h * 0.72))
        case .jumping, .dancing:
            legs.move(to: hip)
            legs.addLine(to: CGPoint(x: w * 0.28, y: h * 0.86))
            legs.move(to: hip)
            legs.addLine(to: CGPoint(x: w * 0.72, y: h * 0.86))
        case .bow:
            legs.move(to: hip)
            legs.addLine(to: CGPoint(x: w * 0.34, y: h * 0.90))
            legs.move(to: hip)
            legs.addLine(to: CGPoint(x: w * 0.62, y: h * 0.90))
        default:
            legs.move(to: hip)
            legs.addLine(to: CGPoint(x: w * 0.30, y: h * 0.92))
            legs.move(to: hip)
            legs.addLine(to: CGPoint(x: w * 0.66, y: h * 0.92))
        }
        context.stroke(legs, with: .color(stroke), style: ink)
    }
}

// MARK: - Background animation

struct StickmanBackgroundAnimation: View {
    let dayOfMonth: Int

    @State private var phase: CGFloat = 0
    @State private var secondary: CGFloat = 0
    @State private var opacity: Double = 0
    @State private var isFinished = false

    private var style: StickmanDayStyle {
        StickmanDayStyle.style(forDayOfMonth: dayOfMonth)
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let figureSize = min(58, max(44, size * 0.16))

            if !isFinished {
                StickmanFigureView(style: style)
                    .frame(width: figureSize, height: figureSize * 1.35)
                    .scaleEffect(scaleEffect)
                    .rotationEffect(rotationEffect)
                    .opacity(opacity)
                    .position(position(in: geo.size, phase: phase, secondary: secondary))
                    .allowsHitTesting(false)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear(perform: play)
    }

    private var scaleEffect: CGFloat {
        switch style.motion {
        case .bounceHop, .skipRope, .riseAndFall:
            return 1 + secondary * 0.08
        case .orbit:
            return 0.92 + secondary * 0.12
        default:
            return 1 + secondary * 0.04
        }
    }

    private var rotationEffect: Angle {
        switch style.motion {
        case .orbit:
            return .degrees(Double(phase) * 360)
        case .figureEight:
            return .degrees(Double(secondary) * 12 - 6)
        case .skipRope:
            return .degrees(Double(secondary) * 10 - 5)
        default:
            return .degrees(Double(secondary) * -5)
        }
    }

    private func position(in size: CGSize, phase: CGFloat, secondary: CGFloat) -> CGPoint {
        let t = min(max(phase, 0), 1)
        let points = waypoints(for: style.motion, in: size)
        let base = interpolate(points: points, phase: t)

        switch style.motion {
        case .bounceHop, .skipRope:
            let hop = abs(sin(Double(t) * .pi * 4)) * size.height * 0.04
            return CGPoint(x: base.x, y: base.y - hop)
        case .riseAndFall:
            let bob = sin(Double(t) * .pi) * size.height * 0.06
            return CGPoint(x: base.x, y: base.y - bob)
        case .orbit:
            let radiusX = size.width * 0.22
            let radiusY = size.height * 0.10
            let angle = Double(t) * .pi * 2
            return CGPoint(
                x: size.width * 0.5 + cos(angle) * radiusX,
                y: size.height * 0.22 + sin(angle) * radiusY
            )
        case .figureEight:
            let angle = Double(t) * .pi * 2
            return CGPoint(
                x: size.width * 0.5 + sin(angle) * size.width * 0.28,
                y: size.height * 0.22 + sin(angle * 2) * size.height * 0.08
            )
        default:
            return base
        }
    }

    private func waypoints(for motion: StickmanMotionKind, in size: CGSize) -> [CGPoint] {
        switch motion {
        case .zigzag:
            return [
                CGPoint(x: size.width * 0.12, y: size.height * 0.20),
                CGPoint(x: size.width * 0.40, y: size.height * 0.12),
                CGPoint(x: size.width * 0.65, y: size.height * 0.24),
                CGPoint(x: size.width * 0.88, y: size.height * 0.14)
            ]
        case .bounceHop:
            return [
                CGPoint(x: size.width * 0.10, y: size.height * 0.28),
                CGPoint(x: size.width * 0.35, y: size.height * 0.16),
                CGPoint(x: size.width * 0.60, y: size.height * 0.26),
                CGPoint(x: size.width * 0.85, y: size.height * 0.15)
            ]
        case .highArc:
            return [
                CGPoint(x: size.width * 0.15, y: size.height * 0.30),
                CGPoint(x: size.width * 0.50, y: size.height * 0.08),
                CGPoint(x: size.width * 0.85, y: size.height * 0.28)
            ]
        case .sprint:
            return [
                CGPoint(x: size.width * 0.05, y: size.height * 0.22),
                CGPoint(x: size.width * 0.95, y: size.height * 0.18)
            ]
        case .slide:
            return [
                CGPoint(x: size.width * 0.88, y: size.height * 0.16),
                CGPoint(x: size.width * 0.50, y: size.height * 0.20),
                CGPoint(x: size.width * 0.12, y: size.height * 0.18)
            ]
        case .riseAndFall:
            return [
                CGPoint(x: size.width * 0.25, y: size.height * 0.30),
                CGPoint(x: size.width * 0.50, y: size.height * 0.14),
                CGPoint(x: size.width * 0.75, y: size.height * 0.28)
            ]
        case .diagonalDash:
            return [
                CGPoint(x: size.width * 0.12, y: size.height * 0.32),
                CGPoint(x: size.width * 0.88, y: size.height * 0.10)
            ]
        case .skipRope:
            return [
                CGPoint(x: size.width * 0.30, y: size.height * 0.24),
                CGPoint(x: size.width * 0.50, y: size.height * 0.18),
                CGPoint(x: size.width * 0.70, y: size.height * 0.24),
                CGPoint(x: size.width * 0.50, y: size.height * 0.16)
            ]
        case .orbit, .figureEight:
            // Position computed analytically; waypoints unused.
            return [CGPoint(x: size.width * 0.5, y: size.height * 0.22)]
        }
    }

    private func interpolate(points: [CGPoint], phase: CGFloat) -> CGPoint {
        guard points.count > 1 else { return points.first ?? .zero }
        let segments = points.count - 1
        let scaled = phase * CGFloat(segments)
        let index = min(Int(scaled), segments - 1)
        let localT = easeInOut(scaled - CGFloat(index))
        let a = points[index]
        let b = points[index + 1]
        return CGPoint(x: a.x + (b.x - a.x) * localT, y: a.y + (b.y - a.y) * localT)
    }

    private func easeInOut(_ t: CGFloat) -> CGFloat {
        t * t * (3 - 2 * t)
    }

    private func play() {
        let duration = style.duration
        opacity = 0
        phase = 0
        secondary = 0

        withAnimation(.easeOut(duration: 0.35)) {
            opacity = style.peakOpacity
        }

        withAnimation(.easeInOut(duration: duration)) {
            phase = 1
        }

        let bounceCount = max(4, Int(duration / 0.45))
        withAnimation(.easeInOut(duration: 0.45).repeatCount(bounceCount, autoreverses: true)) {
            secondary = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration - 0.45) {
            withAnimation(.easeIn(duration: 0.45)) {
                opacity = 0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            isFinished = true
            secondary = 0
        }
    }
}
