import SwiftUI

/// Traveli's mascot: a cartoon girl with an orange backpack, walking in place.
/// Drawn entirely in code (no assets) and animated with a time-driven cycle.
/// Decorative only; hidden from VoiceOver, and still when Reduce Motion is on.
struct TravelerCharacter: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Palette {
        static let skin = Color(red: 0.98, green: 0.78, blue: 0.64)
        static let hair = Color(red: 0.20, green: 0.12, blue: 0.10)
        static let jacket = Color(red: 0.06, green: 0.46, blue: 0.48)
        static let jacketDark = Color(red: 0.04, green: 0.35, blue: 0.37)
        static let jeans = Color(red: 0.24, green: 0.30, blue: 0.46)
        static let jeansDark = Color(red: 0.17, green: 0.22, blue: 0.36)
        static let pack = Color(red: 0.96, green: 0.55, blue: 0.18)
        static let packDark = Color(red: 0.82, green: 0.40, blue: 0.10)
        static let shoe = Color.white
    }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0.15 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                var context = context
                context.scaleBy(x: size.width / 200, y: size.height / 240)
                draw(&context, time: t)
            }
        }
        .aspectRatio(200.0 / 240.0, contentMode: .fit)
        .accessibilityHidden(true)
    }

    // MARK: - Drawing (design space: 200 x 240, character faces right)

    private func draw(_ ctx: inout GraphicsContext, time t: Double) {
        let phase = t * 2 * .pi * 1.15              // one stride cycle per ~0.87 s
        let bob = -abs(sin(phase)) * 5               // body rises on each step
        let hip = CGPoint(x: 100, y: 152 + bob)
        let shoulder = CGPoint(x: 100, y: 94 + bob)

        // Ground shadow shrinks slightly as she rises.
        let shadowWidth = 96 + bob
        ctx.fill(Path(ellipseIn: CGRect(x: 100 - shadowWidth / 2, y: 218, width: shadowWidth, height: 12)),
                 with: .color(.black.opacity(0.16)))

        // Back leg and back arm first (darker), then body, then front limbs.
        leg(&ctx, hip: hip, angle: -sin(phase) * 0.5, color: Palette.jeansDark)
        arm(&ctx, shoulder: shoulder, angle: -sin(phase + .pi) * 0.55 - 0.05, sleeve: Palette.jacketDark)

        backpack(&ctx, bob: bob)
        torso(&ctx, bob: bob)
        head(&ctx, t: t, phase: phase, bob: bob)

        leg(&ctx, hip: hip, angle: sin(phase) * 0.5, color: Palette.jeans)
        arm(&ctx, shoulder: shoulder, angle: sin(phase + .pi) * 0.55 - 0.05, sleeve: Palette.jacket)
    }

    private func torso(_ ctx: inout GraphicsContext, bob: Double) {
        let body = CGRect(x: 76, y: 84 + bob, width: 48, height: 74)
        ctx.fill(Path(roundedRect: body, cornerRadius: 20), with: .color(Palette.jacket))
        // Zip line and hem.
        var zip = Path()
        zip.move(to: CGPoint(x: 112, y: 96 + bob))
        zip.addLine(to: CGPoint(x: 112, y: 154 + bob))
        ctx.stroke(zip, with: .color(Palette.jacketDark), lineWidth: 2.5)
        ctx.fill(Path(roundedRect: CGRect(x: 76, y: 146 + bob, width: 48, height: 12), cornerRadius: 6),
                 with: .color(Palette.jacketDark))
        // Backpack strap over the shoulder.
        ctx.fill(Path(roundedRect: CGRect(x: 90, y: 86 + bob, width: 9, height: 56), cornerRadius: 4),
                 with: .color(Palette.packDark))
    }

    private func backpack(_ ctx: inout GraphicsContext, bob: Double) {
        let main = CGRect(x: 52, y: 86 + bob, width: 40, height: 62)
        ctx.fill(Path(roundedRect: main, cornerRadius: 14), with: .color(Palette.pack))
        // Top flap, front pocket and a travel-pin patch.
        ctx.fill(Path(roundedRect: CGRect(x: 52, y: 86 + bob, width: 40, height: 20), cornerRadius: 12),
                 with: .color(Palette.packDark))
        ctx.fill(Path(roundedRect: CGRect(x: 58, y: 118 + bob, width: 28, height: 24), cornerRadius: 8),
                 with: .color(Palette.packDark.opacity(0.85)))
        ctx.fill(Path(ellipseIn: CGRect(x: 66, y: 126 + bob, width: 12, height: 12)), with: .color(.white))
        ctx.fill(Path(ellipseIn: CGRect(x: 70, y: 130 + bob, width: 4, height: 4)), with: .color(Palette.pack))
        // Rolled sleeping mat on top.
        ctx.fill(Path(roundedRect: CGRect(x: 54, y: 78 + bob, width: 36, height: 12), cornerRadius: 6),
                 with: .color(Palette.jacket))
    }

    private func head(_ ctx: inout GraphicsContext, t: Double, phase: Double, bob: Double) {
        let centre = CGPoint(x: 104, y: 58 + bob)

        // Ponytail swings behind the head.
        var tail = ctx
        tail.translateBy(x: 82, y: 48 + bob)
        tail.rotate(by: .radians(0.35 + sin(phase + 0.9) * 0.28))
        tail.fill(Path(roundedRect: CGRect(x: -8, y: -4, width: 16, height: 46), cornerRadius: 8),
                  with: .color(Palette.hair))

        // Hair back, face, fringe.
        ctx.fill(Path(ellipseIn: CGRect(x: centre.x - 30, y: centre.y - 29, width: 56, height: 56)), with: .color(Palette.hair))
        ctx.fill(Path(ellipseIn: CGRect(x: centre.x - 22, y: centre.y - 24, width: 48, height: 50)), with: .color(Palette.skin))
        ctx.fill(Path(ellipseIn: CGRect(x: centre.x - 28, y: centre.y - 34, width: 58, height: 28)), with: .color(Palette.hair))
        // Hair tie.
        ctx.fill(Path(ellipseIn: CGRect(x: 76, y: 43 + bob, width: 10, height: 10)), with: .color(Palette.pack))

        // Eye (blinks about every 3.2 s), cheek and smile.
        let blinking = t.truncatingRemainder(dividingBy: 3.2) < 0.12
        let eye = CGPoint(x: centre.x + 12, y: centre.y + 1)
        if blinking {
            var lid = Path()
            lid.move(to: CGPoint(x: eye.x - 4, y: eye.y))
            lid.addLine(to: CGPoint(x: eye.x + 4, y: eye.y))
            ctx.stroke(lid, with: .color(Palette.hair), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        } else {
            ctx.fill(Path(ellipseIn: CGRect(x: eye.x - 3, y: eye.y - 4, width: 6, height: 8)), with: .color(Palette.hair))
            ctx.fill(Path(ellipseIn: CGRect(x: eye.x - 0.5, y: eye.y - 3, width: 2.4, height: 2.4)), with: .color(.white))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: centre.x + 12, y: centre.y + 8, width: 11, height: 7)),
                 with: .color(Color.pink.opacity(0.35)))
        var smile = Path()
        smile.addArc(center: CGPoint(x: centre.x + 12, y: centre.y + 11), radius: 7,
                     startAngle: .degrees(20), endAngle: .degrees(150), clockwise: false)
        ctx.stroke(smile, with: .color(Palette.hair), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
    }

    private func leg(_ ctx: inout GraphicsContext, hip: CGPoint, angle: Double, color: Color) {
        var c = ctx
        c.translateBy(x: hip.x, y: hip.y)
        c.rotate(by: .radians(angle))
        c.fill(Path(roundedRect: CGRect(x: -9, y: -6, width: 18, height: 68), cornerRadius: 9), with: .color(color))
        c.fill(Path(roundedRect: CGRect(x: -8, y: 54, width: 28, height: 11), cornerRadius: 5.5), with: .color(Palette.shoe))
    }

    private func arm(_ ctx: inout GraphicsContext, shoulder: CGPoint, angle: Double, sleeve: Color) {
        var c = ctx
        c.translateBy(x: shoulder.x, y: shoulder.y)
        c.rotate(by: .radians(angle))
        c.fill(Path(roundedRect: CGRect(x: -7, y: -6, width: 14, height: 44), cornerRadius: 7), with: .color(sleeve))
        c.fill(Path(ellipseIn: CGRect(x: -6.5, y: 34, width: 13, height: 13)), with: .color(Palette.skin))
    }
}

#Preview {
    TravelerCharacter()
        .frame(width: 220)
        .padding()
}
