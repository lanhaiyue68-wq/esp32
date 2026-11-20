import SwiftUI

/// The agent's mood; drives the character on Home, in onboarding, in the replay player and in the Live Activity.
enum Mood: String, Codable, Hashable {
    case sleeping, idle, listening, thinking, acting, success, failure
    /// Poke reactions (Home): a spin after a flurry of taps, the circles snuggling while petted, a wink of the dot.
    case dizzy, content, wink
}

/// The Duet mark, alive: Pilot (this iPhone, the big blue circle) and Echo (the Android phone, the small light-blue
/// one) overlap, and the white dot where they meet is the one brain they share ("两部手机，一个大脑"). It breathes,
/// looks toward a tap, swings while thinking and hops on success. Motion is short springs and slow drifts; under
/// Reduce Motion it stands still.
struct AgentFace: View {
    var mood: Mood
    /// Where it looks, -1...1 on each axis (e.g. toward a tap point).
    var look: CGPoint = .zero
    /// How far a full look moves the dot (1 = Home size; the tiny island mark needs more to read).
    var lookRange: CGFloat = 1
    var animated = true
    /// Kept for the layouts made for the old character (it had a tab below): the mark keeps that frame's shape.
    var showsTab = true
    /// Hop / shake by itself when the mood changes (off while a poke drives it).
    var reacts = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hop: CGFloat = 0
    @State private var shake: CGFloat = 0

    /// Brand colors (Duet): Pilot is the big blue, Echo the small light blue, brighter where they overlap.
    static let pilotBlue = Color(red: 61 / 255, green: 102 / 255, blue: 234 / 255)
    static let echoBlue = Color(red: 91 / 255, green: 180 / 255, blue: 222 / 255)
    static let overlapBlue = Color(red: 92 / 255, green: 193 / 255, blue: 248 / 255)

    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height / (showsTab ? 1.12 : 1))
            Group {
                if animated && !reduceMotion {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { t in face(s, t: t.date.timeIntervalSinceReferenceDate) }
                } else {
                    face(s, t: 0)
                }
            }
            .offset(x: shake, y: hop)
            .frame(width: g.size.width, height: g.size.height)
        }
        .aspectRatio(showsTab ? 1 / 1.12 : 1, contentMode: .fit)
        .onChange(of: mood) { _, m in react(to: m) }
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "Pilot"))
        .accessibilityValue(Text(LocalizedStringKey(mood.rawValue)))
    }

    private func react(to m: Mood) {
        guard animated && !reduceMotion && reacts else { return }
        switch m {
        case .acting:
            jump(1)
        case .success:
            jump(2)
        case .failure:
            withAnimation(.spring(response: 0.12, dampingFraction: 0.2)) { shake = 6 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.4)) { shake = 0 }
            }
        default:
            break
        }
    }

    private func jump(_ times: Int) {
        for i in 0..<times {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.32) {
                withAnimation(.spring(response: 0.16, dampingFraction: 0.6)) { hop = -14 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { hop = 0 }
                }
            }
        }
    }

    // MARK: - drawing

    /// A circle of the mark: its center and diameter, 0-1 of the square it is drawn in.
    private struct Disc {
        var x: Double
        var y: Double
        var d: Double
    }

    private func face(_ s: CGFloat, t: Double) -> some View {
        let gaze = gazeOffset(t: t)
        let lx = Double(gaze.x * lookRange) * 0.03, ly = Double(gaze.y * lookRange) * 0.03
        let big = Disc(x: 0.40, y: 0.523, d: 0.68)
        var small = Disc(x: 0.723, y: 0.354, d: 0.432)
        var dotSize = 0.092
        var squash = Double(blink(t))
        var breathe = 1.0
        switch mood {
        case .idle:
            small.x += 0.012 * cos(t * 0.9)
            small.y += 0.010 * sin(t * 0.9)
            breathe = 1 + 0.01 * sin(t * 1.6)
            dotSize *= 1 + 0.06 * sin(t * 2.2)
        case .listening:
            small.x -= 0.02
            small.y += 0.015
            dotSize *= 1.3 + 0.05 * sin(t * 4)
        case .thinking:
            small = Self.turn(small, about: big, by: 0.18 * sin(t * 2.4))
            dotSize *= 1 + 0.15 * sin(t * 4.8)
        case .acting:
            small.x += lx
            small.y += ly
            dotSize *= 1.15
        case .success:
            dotSize *= 1.35
        case .failure:
            small.y += 0.03
        case .dizzy:
            small = Self.turn(small, about: big, by: t * 6)
        case .content:
            small.x -= 0.04
            small.y += 0.03
            squash = 0.55
        case .wink:
            squash = 0.15
        case .sleeping:
            small.x -= 0.03
            small.y += 0.03
            dotSize *= 0.6
        }
        // The dot sits where the two meet: most of the way from the big circle's center to the small one's, then a
        // touch toward where it looks.
        let dot = Disc(x: big.x + 0.64 * (small.x - big.x) + 0.009 + lx, y: big.y + 0.64 * (small.y - big.y) + 0.015 + ly,
                       d: dotSize)
        let glow = mood == .success || mood == .listening
        return ZStack {
            disc(big, s).fill(Self.pilotBlue)
            disc(small, s).fill(Self.echoBlue)
            disc(small, s).fill(Self.overlapBlue).mask { disc(big, s).fill(Color.white) }
            disc(dot, s).fill(Color.white)
                .scaleEffect(x: 1, y: CGFloat(squash), anchor: UnitPoint(x: CGFloat(dot.x), y: CGFloat(dot.y)))
                .shadow(color: .white.opacity(glow ? 0.9 : 0), radius: s * 0.04)
            if mood == .sleeping { zz(s, t: t) }
        }
        .frame(width: s, height: s)
        .opacity(mood == .sleeping ? 0.6 : 1)
        .scaleEffect(CGFloat(breathe))
    }

    /// A circle placed in the s × s square.
    private func disc(_ c: Disc, _ s: CGFloat) -> some Shape {
        Circle().path(in: CGRect(x: s * CGFloat(c.x - c.d / 2), y: s * CGFloat(c.y - c.d / 2),
                                 width: s * CGFloat(c.d), height: s * CGFloat(c.d)))
    }

    /// The small circle swung around the big one's center by `a` radians.
    private static func turn(_ p: Disc, about c: Disc, by a: Double) -> Disc {
        let dx = p.x - c.x, dy = p.y - c.y
        return Disc(x: c.x + dx * cos(a) - dy * sin(a), y: c.y + dx * sin(a) + dy * cos(a), d: p.d)
    }

    /// 1 = open; the dot closes briefly every few seconds while idle or listening, like a blink.
    private func blink(_ t: Double) -> CGFloat {
        guard mood == .idle || mood == .listening, animated else { return 1 }
        let phase = t.truncatingRemainder(dividingBy: 4.3)
        return phase < 0.13 ? max(0.08, abs(phase - 0.065) / 0.065) : 1
    }

    private func gazeOffset(t: Double) -> CGPoint {
        switch mood {
        case .acting: return look
        case .listening: return CGPoint(x: 0, y: 0.6)
        case .thinking: return animated ? CGPoint(x: sin(t * 2.4), y: -0.2) : look  // static (island): the app moves it
        case .idle where animated:  // a look around now and then
            let p = t.truncatingRemainder(dividingBy: 9)
            return CGPoint(x: p > 6 && p < 7 ? -0.7 : p > 7.4 && p < 8.2 ? 0.7 : 0, y: 0)
        default: return .zero
        }
    }

    private func zz(_ s: CGFloat, t: Double) -> some View {
        let p = animated ? t.truncatingRemainder(dividingBy: 3) / 3 : 0.5
        return Text(verbatim: "z")
            .font(.system(size: s * 0.12, weight: .bold, design: .rounded))
            .foregroundStyle(Self.echoBlue.opacity(1 - p))
            .offset(x: s * 0.3 + p * s * 0.08, y: -s * 0.3 - p * s * 0.12)
    }
}

/// "^" for happy eyes (kept for other drawings).
struct Caret: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        return p
    }
}

/// "‿" for closed, contented eyes.
struct Smile: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.midX, y: r.maxY * 2 - r.minY))
        return p
    }
}

/// A spiral.
struct Spiral: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY), maxR = min(r.width, r.height) / 2
        for i in 0...60 {
            let a = CGFloat(i) / 60 * 2.6 * 2 * .pi
            let rad = maxR * CGFloat(i) / 60
            let pt = CGPoint(x: c.x + rad * cos(a), y: c.y + rad * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}
