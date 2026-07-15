import SwiftUI

/// Doodle-style stickman with a thumbs-up pose (red tie accent).
struct StickmanThumbsUpView: View {
    var body: some View {
        Canvas { context, size in
            let stroke = Color.primary.opacity(0.85)
            let lineWidth = max(1.6, size.width * 0.045)
            var ink = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)

            let w = size.width
            let h = size.height

            // Proportions inside the canvas
            let headCenter = CGPoint(x: w * 0.48, y: h * 0.18)
            let headRadius = w * 0.13
            let neck = CGPoint(x: headCenter.x, y: headCenter.y + headRadius)
            let torsoBottom = CGPoint(x: w * 0.48, y: h * 0.58)
            let hip = torsoBottom

            // Head
            let headRect = CGRect(
                x: headCenter.x - headRadius,
                y: headCenter.y - headRadius,
                width: headRadius * 2,
                height: headRadius * 2
            )
            context.stroke(Path(ellipseIn: headRect), with: .color(stroke), style: ink)

            // Simple grin + eyes
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

            // Hair tufts
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
            torso.addLine(to: torsoBottom)
            context.stroke(torso, with: .color(stroke), style: ink)

            // Jacket lapel hint (short diagonals)
            var lapel = Path()
            lapel.move(to: CGPoint(x: neck.x - w * 0.02, y: neck.y + h * 0.04))
            lapel.addLine(to: CGPoint(x: neck.x - w * 0.10, y: neck.y + h * 0.16))
            lapel.move(to: CGPoint(x: neck.x + w * 0.02, y: neck.y + h * 0.04))
            lapel.addLine(to: CGPoint(x: neck.x + w * 0.10, y: neck.y + h * 0.16))
            context.stroke(lapel, with: .color(stroke.opacity(0.75)), style: StrokeStyle(lineWidth: lineWidth * 0.65, lineCap: .round))

            // Red necktie
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
            context.fill(tie, with: .color(Color(red: 0.86, green: 0.18, blue: 0.22)))
            context.stroke(tie, with: .color(stroke.opacity(0.55)), style: StrokeStyle(lineWidth: lineWidth * 0.35, lineJoin: .round))

            // Left arm on hip
            var leftArm = Path()
            leftArm.move(to: CGPoint(x: neck.x, y: neck.y + h * 0.08))
            leftArm.addQuadCurve(
                to: CGPoint(x: w * 0.18, y: h * 0.48),
                control: CGPoint(x: w * 0.12, y: h * 0.28)
            )
            context.stroke(leftArm, with: .color(stroke), style: ink)

            // Right arm raised with thumbs-up
            let shoulder = CGPoint(x: neck.x, y: neck.y + h * 0.08)
            let elbow = CGPoint(x: w * 0.72, y: h * 0.22)
            let wrist = CGPoint(x: w * 0.78, y: h * 0.10)
            var rightArm = Path()
            rightArm.move(to: shoulder)
            rightArm.addQuadCurve(to: elbow, control: CGPoint(x: w * 0.68, y: h * 0.30))
            rightArm.addLine(to: wrist)
            context.stroke(rightArm, with: .color(stroke), style: ink)

            // Thumbs-up fist + thumb
            let fistCenter = CGPoint(x: w * 0.82, y: h * 0.09)
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

            // Legs
            var legs = Path()
            legs.move(to: hip)
            legs.addLine(to: CGPoint(x: w * 0.30, y: h * 0.92))
            legs.move(to: hip)
            legs.addLine(to: CGPoint(x: w * 0.66, y: h * 0.92))
            context.stroke(legs, with: .color(stroke), style: ink)
        }
        .accessibilityHidden(true)
    }
}

/// Plays a short background walk + thumbs-up bounce after a shift is closed.
struct StickmanBackgroundAnimation: View {
    @State private var phase: CGFloat = 0
    @State private var thumbBounce: CGFloat = 0
    @State private var opacity: Double = 0
    @State private var isFinished = false

    private let duration: Double = 3.8

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let figureSize = min(56, max(44, size * 0.16))

            if !isFinished {
                StickmanThumbsUpView()
                    .frame(width: figureSize, height: figureSize * 1.35)
                    .scaleEffect(1 + thumbBounce * 0.04, anchor: .top)
                    .rotationEffect(.degrees(Double(thumbBounce) * -4), anchor: .bottom)
                    .opacity(opacity)
                    .position(position(in: geo.size, phase: phase))
                    .allowsHitTesting(false)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear(perform: play)
    }

    private func position(in size: CGSize, phase: CGFloat) -> CGPoint {
        // Waypoints across the upper area of the sheet (behind the hero / card).
        let points: [CGPoint] = [
            CGPoint(x: size.width * 0.14, y: size.height * 0.18),
            CGPoint(x: size.width * 0.48, y: size.height * 0.12),
            CGPoint(x: size.width * 0.82, y: size.height * 0.20),
            CGPoint(x: size.width * 0.62, y: size.height * 0.32),
            CGPoint(x: size.width * 0.28, y: size.height * 0.26)
        ]

        guard points.count > 1 else {
            return points.first ?? .zero
        }

        let clamped = min(max(phase, 0), 1)
        let segments = points.count - 1
        let scaled = clamped * CGFloat(segments)
        let index = min(Int(scaled), segments - 1)
        let localT = scaled - CGFloat(index)
        let eased = easeInOut(localT)

        let a = points[index]
        let b = points[index + 1]
        return CGPoint(
            x: a.x + (b.x - a.x) * eased,
            y: a.y + (b.y - a.y) * eased
        )
    }

    private func easeInOut(_ t: CGFloat) -> CGFloat {
        t * t * (3 - 2 * t)
    }

    private func play() {
        opacity = 0
        phase = 0
        thumbBounce = 0

        withAnimation(.easeOut(duration: 0.35)) {
            opacity = 0.34
        }

        withAnimation(.easeInOut(duration: duration)) {
            phase = 1
        }

        // Light "like" bounce while walking.
        withAnimation(.easeInOut(duration: 0.45).repeatCount(8, autoreverses: true)) {
            thumbBounce = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration - 0.45) {
            withAnimation(.easeIn(duration: 0.45)) {
                opacity = 0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            isFinished = true
            thumbBounce = 0
        }
    }
}
