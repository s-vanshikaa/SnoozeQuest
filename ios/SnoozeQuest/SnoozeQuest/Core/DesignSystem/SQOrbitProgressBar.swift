//
//  SQOrbitProgressBar.swift
//  SnoozeQuest
//
//  An orbit-path-inspired progress treatment for the Journey card — a shallow
//  arc with a small world traveling along it, in place of a generic bar.
//

import SwiftUI

private struct SQOrbitArc: Shape {
    func path(in rect: CGRect) -> Path {
        let start = CGPoint(x: rect.minX, y: rect.maxY)
        let end = CGPoint(x: rect.maxX, y: rect.maxY)
        let control = CGPoint(x: rect.midX, y: rect.minY)

        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        return path
    }
}

struct SQOrbitProgressBar: View {
    var progress: Double
    var tint: Color = SQColor.moonlight
    var height: CGFloat = 26

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedProgress: Double = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SQOrbitArc()
                    .stroke(
                        SQColor.textTertiary.opacity(0.22),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1, 5])
                    )

                SQOrbitArc()
                    .trim(from: 0, to: animatedProgress)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                    .shadow(color: tint.opacity(0.6), radius: 4)
                    .position(point(atProgress: animatedProgress, in: geometry.size))
            }
        }
        .frame(height: height)
        .onAppear {
            withAnimation(SQMotion.interactive(reduceMotion: reduceMotion)) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(SQMotion.interactive(reduceMotion: reduceMotion)) {
                animatedProgress = newValue
            }
        }
    }

    /// Point on the quadratic curve at parameter `t`, matching SQOrbitArc's geometry.
    private func point(atProgress t: Double, in size: CGSize) -> CGPoint {
        let start = CGPoint(x: 0, y: size.height)
        let end = CGPoint(x: size.width, y: size.height)
        let control = CGPoint(x: size.width / 2, y: 0)

        let oneMinusT = 1 - t
        let x = oneMinusT * oneMinusT * start.x + 2 * oneMinusT * t * control.x + t * t * end.x
        let y = oneMinusT * oneMinusT * start.y + 2 * oneMinusT * t * control.y + t * t * end.y
        return CGPoint(x: x, y: y)
    }
}

#Preview("Orbit Progress") {
    VStack(spacing: SQSpacing.xl) {
        SQOrbitProgressBar(progress: 0.35)
        SQOrbitProgressBar(progress: 0.7, tint: SQColor.skyBlue)
    }
    .padding(SQSpacing.xl)
    .background(SQColor.surfaceDeep)
}
