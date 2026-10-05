import SceneKit
import UIKit
import AppSurfaces

/// The figure at one moment, as directions rather than joint angles.
///
/// Each limb says where it points, in the frame of the body part it hangs
/// from: x towards the racket side, y up, z backwards (the figure faces -z,
/// the net). "Upper arm up and a little back, forearm folded behind the
/// head" is a direction pair, and the rig works out the rotations; stacked
/// Euler angles made every shot a puzzle about rotation order.
struct FigurePose {
    var lift: Float = 0, step: Float = 0
    /// Lean (negative is forwards) and turn (negative turns the racket
    /// shoulder back), in radians.
    var torsoPitch: Float = -0.1, torsoYaw: Float = 0
    var racketUpper: SIMD3<Float> = [0.35, -0.6, -0.7], racketFore: SIMD3<Float> = [0.1, 0.75, -0.65]
    var freeUpper: SIMD3<Float> = [-0.35, -0.65, -0.65], freeFore: SIMD3<Float> = [-0.1, 0.4, -0.9]
    var racketThigh: SIMD3<Float> = [0.05, -0.95, -0.3], racketShin: SIMD3<Float> = [0, -0.97, 0.25]
    var freeThigh: SIMD3<Float> = [-0.05, -0.95, -0.3], freeShin: SIMD3<Float> = [0, -0.97, 0.25]

    static let ready = FigurePose()

    static func mix(_ a: FigurePose, _ b: FigurePose, _ t: Float) -> FigurePose {
        func m(_ x: Float, _ y: Float) -> Float { x + (y - x) * t }
        func d(_ x: SIMD3<Float>, _ y: SIMD3<Float>) -> SIMD3<Float> {
            let v = x + (y - x) * t
            return simd_length(v) > 0.001 ? simd_normalize(v) : y
        }
        return FigurePose(lift: m(a.lift, b.lift), step: m(a.step, b.step),
                          torsoPitch: m(a.torsoPitch, b.torsoPitch), torsoYaw: m(a.torsoYaw, b.torsoYaw),
                          racketUpper: d(a.racketUpper, b.racketUpper), racketFore: d(a.racketFore, b.racketFore),
                          freeUpper: d(a.freeUpper, b.freeUpper), freeFore: d(a.freeFore, b.freeFore),
                          racketThigh: d(a.racketThigh, b.racketThigh), racketShin: d(a.racketShin, b.racketShin),
                          freeThigh: d(a.freeThigh, b.freeThigh), freeShin: d(a.freeShin, b.freeShin))
    }
}

/// A shot's movement, as keyframes over the swing from 0 to 1.
///
/// These are illustrations of how each shot is played, chosen from the
/// player's tag, the estimated serve, or the learned forehand and backhand,
/// not a reconstruction of the player's own body: the watch measures the
/// wrist, nothing else. The review says which it is showing.
enum SwingMotion: Equatable {
    case shot(BadmintonShotType)
    case stroke(BadmintonStroke)
    /// Tagged as not a shot: the figure shrugs it off with a little hop.
    case notAShot

    var title: String {
        switch self {
        case .shot(let type): type.title.lowercased()
        case .stroke(let stroke): stroke.title.lowercased()
        case .notAShot: "not a shot"
        }
    }

    /// Picks the motion for a swing: the tagged shot type first, then an
    /// estimated serve for a rally opener, then the tagged or learned side,
    /// else nil for the wrist-only replay.
    static func choose(for event: SwingEvent, in events: [SwingEvent], tags: BadmintonShotTags, convention: Double?) -> SwingMotion? {
        if tags[event.id]?.notAShot == true { return .notAShot }
        if let type = tags[event.id]?.type { return .shot(type) }
        if let serve = StrokeClassifier.serve(of: event, in: events, convention: convention, tags: tags) { return .shot(serve) }
        return StrokeClassifier.stroke(of: event, convention: convention, tags: tags).map(SwingMotion.stroke)
    }

    private var keyframes: [(Float, FigurePose)] {
        func pose(_ change: (inout FigurePose) -> Void) -> FigurePose { var p = FigurePose.ready; change(&p); return p }
        // Knees bent for a load or a landing.
        func loaded(_ p: inout FigurePose) {
            p.racketThigh = [0.05, -0.8, -0.6]; p.racketShin = [0, -0.9, 0.45]
            p.freeThigh = [-0.05, -0.8, -0.6]; p.freeShin = [0, -0.9, 0.45]
        }
        // The overhead preparation shared by smash, clear and drop: side on,
        // racket arm up with the forearm folded behind the head, the free
        // arm pointing at the shuttle.
        let cocked = pose {
            $0.torsoYaw = -0.75; $0.torsoPitch = 0.15
            $0.racketUpper = [0.45, 0.82, 0.35]; $0.racketFore = [0.15, -0.7, 0.7]
            $0.freeUpper = [-0.2, 0.85, -0.5]; $0.freeFore = [-0.05, 0.95, -0.3]
            loaded(&$0)
        }
        switch self {
        case .shot(.smash):
            let airborne = pose { $0 = cocked; $0.lift = 0.32
                $0.racketThigh = [0.05, -0.6, -0.8]; $0.racketShin = [0, -0.95, 0.3] }
            let contact = pose { $0.lift = 0.34; $0.torsoYaw = 0.35; $0.torsoPitch = -0.35
                $0.racketUpper = [0.25, 0.92, -0.3]; $0.racketFore = [0.05, 0.75, -0.66]
                $0.freeUpper = [-0.35, -0.75, -0.55]; $0.freeFore = [0.1, -0.2, -0.97]
                $0.racketThigh = [0.05, -0.6, -0.8]; $0.racketShin = [0, -0.95, 0.3] }
            let follow = pose { $0.lift = 0.02; $0.torsoYaw = 0.55; $0.torsoPitch = -0.55
                $0.racketUpper = [-0.15, -0.55, -0.82]; $0.racketFore = [-0.55, -0.7, -0.45]
                $0.freeUpper = [-0.5, -0.6, 0.6]; loaded(&$0) }
            return [(0, .ready), (0.3, cocked), (0.46, airborne), (0.56, contact), (0.8, follow), (1, .ready)]
        case .shot(.clear), .stroke(.forehand):
            let contact = pose { $0.torsoYaw = 0.25; $0.torsoPitch = -0.15
                $0.racketUpper = [0.25, 0.96, 0.05]; $0.racketFore = [0.05, 0.98, -0.15]
                $0.freeUpper = [-0.3, -0.8, -0.5] }
            let follow = pose { $0.torsoYaw = 0.5
                $0.racketUpper = [0.1, 0.1, -0.99]; $0.racketFore = [-0.35, -0.4, -0.85] }
            return [(0, .ready), (0.35, cocked), (0.58, contact), (0.82, follow), (1, .ready)]
        case .shot(.drop):
            let contact = pose { $0.torsoYaw = 0.15; $0.torsoPitch = -0.15
                $0.racketUpper = [0.25, 0.94, -0.2]; $0.racketFore = [0.05, 0.88, -0.45]
                $0.freeUpper = [-0.3, -0.8, -0.5] }
            // A drop checks the swing: the racket stops in front instead of
            // following through across the body.
            let checked = pose { $0.torsoYaw = 0.15
                $0.racketUpper = [0.3, 0.45, -0.84]; $0.racketFore = [0.1, 0.55, -0.83] }
            return [(0, .ready), (0.35, cocked), (0.62, contact), (0.86, checked), (1, .ready)]
        case .shot(.drive):
            let back = pose { $0.torsoYaw = -0.8
                $0.racketUpper = [0.95, -0.1, 0.3]; $0.racketFore = [0.4, 0.6, 0.7] }
            let contact = pose { $0.torsoYaw = 0
                $0.racketUpper = [0.75, 0.05, -0.65]; $0.racketFore = [0.6, 0.15, -0.79] }
            let follow = pose { $0.torsoYaw = 0.65
                $0.racketUpper = [-0.35, 0.05, -0.93]; $0.racketFore = [-0.9, 0.15, -0.4] }
            return [(0, .ready), (0.3, back), (0.55, contact), (0.8, follow), (1, .ready)]
        case .stroke(.backhand):
            // Turned to the free side, elbow leading across the body, then
            // the forearm uncoils out to the racket side.
            let back = pose { $0.torsoYaw = 0.9
                $0.racketUpper = [-0.6, 0.2, -0.77]; $0.racketFore = [-0.55, -0.6, 0.58]
                $0.freeUpper = [-0.4, -0.85, 0.35]; loaded(&$0) }
            let contact = pose { $0.torsoYaw = 0.35
                $0.racketUpper = [0.15, 0.4, -0.9]; $0.racketFore = [0.55, 0.7, -0.45] }
            let follow = pose { $0.torsoYaw = 0
                $0.racketUpper = [0.7, 0.5, -0.5]; $0.racketFore = [0.85, 0.5, -0.15] }
            return [(0, .ready), (0.32, back), (0.56, contact), (0.8, follow), (1, .ready)]
        case .shot(.net), .shot(.lift):
            let lifts = self == .shot(.lift)
            func lunge(_ p: inout FigurePose) {
                p.step = 0.6; p.torsoPitch = -0.4
                p.racketThigh = [0.05, -0.55, -0.84]; p.racketShin = [0, -0.98, -0.2]
                p.freeThigh = [-0.05, -0.7, 0.71]; p.freeShin = [0, -0.45, 0.89]
                p.freeUpper = [-0.6, -0.4, 0.69]; p.freeFore = [-0.4, -0.6, 0.69]
            }
            let reach = pose { lunge(&$0)
                $0.racketUpper = lifts ? [0.25, -0.6, -0.76] : [0.2, -0.2, -0.96]
                $0.racketFore = lifts ? [0.1, -0.7, -0.7] : [0.1, 0.2, -0.97] }
            let contact = pose { lunge(&$0)
                $0.racketUpper = lifts ? [0.2, 0.25, -0.95] : [0.2, -0.1, -0.97]
                $0.racketFore = lifts ? [0.1, 0.88, -0.46] : [0.05, 0.45, -0.89] }
            return [(0, .ready), (0.4, reach), (0.62, contact), (0.8, contact), (1, .ready)]
        case .shot(.shortServe):
            // Backhand, elbow up, racket held across the waist, the shuttle
            // held just ahead of the strings; a short push from the elbow.
            let set = pose { $0.torsoPitch = -0.15; $0.torsoYaw = 0.2
                $0.racketUpper = [0.3, -0.2, -0.93]; $0.racketFore = [-0.78, -0.05, -0.62]
                $0.freeUpper = [-0.15, -0.45, -0.88]; $0.freeFore = [0.35, 0.05, -0.94]
                $0.racketThigh = [0.05, -0.85, -0.52]; $0.freeThigh = [-0.05, -0.97, 0.25] }
            let push = pose { $0 = set; $0.racketFore = [-0.55, 0.2, -0.81]; $0.freeUpper = [-0.35, -0.85, -0.4] }
            return [(0, .ready), (0.35, set), (0.62, push), (0.85, push), (1, .ready)]
        case .shot(.longServe), .shot(.serve):
            // Forehand underarm: racket back and low, shuttle dropped from
            // the free hand, a full swing finishing high over the shoulder.
            let back = pose { $0.torsoYaw = -0.5
                $0.racketUpper = [0.35, -0.75, 0.56]; $0.racketFore = [0.2, -0.8, 0.56]
                $0.freeUpper = [-0.2, -0.3, -0.93]; $0.freeFore = [0.2, 0.1, -0.97] }
            let contact = pose {
                $0.racketUpper = [0.25, -0.85, -0.46]; $0.racketFore = [0.1, -0.5, -0.86]
                $0.freeUpper = [-0.3, -0.85, -0.42] }
            let follow = pose { $0.torsoYaw = 0.45; $0.step = 0.15
                $0.racketUpper = [-0.3, 0.85, -0.43]; $0.racketFore = [-0.4, 0.8, -0.45]
                $0.racketThigh = [0.05, -0.8, -0.6] }
            return [(0, .ready), (0.32, back), (0.55, contact), (0.85, follow), (1, .ready)]
        case .notAShot:
            // A shrug, twice, with a hop: arms out, forearms up, palms to the
            // sky, the torso wiggling. Something to make a mis-tap smile.
            let shrug = pose { $0.lift = 0.08; $0.torsoYaw = 0.25; $0.torsoPitch = 0.05
                $0.racketUpper = [0.88, -0.4, -0.25]; $0.racketFore = [0.45, 0.85, -0.28]
                $0.freeUpper = [-0.88, -0.4, -0.25]; $0.freeFore = [-0.45, 0.85, -0.28] }
            let other = pose { $0 = shrug; $0.torsoYaw = -0.25; $0.lift = 0 }
            return [(0, .ready), (0.2, shrug), (0.4, other), (0.6, shrug), (0.8, other), (1, .ready)]
        }
    }

    /// The pose at `t` (0...1), eased in and out between keyframes so the
    /// swing accelerates into contact and settles after it.
    func pose(at t: Float) -> FigurePose {
        let frames = keyframes
        let t = min(max(t, 0), 1)
        guard let next = frames.firstIndex(where: { $0.0 >= t }), next > 0 else { return frames.first?.1 ?? .ready }
        let (t0, a) = frames[next - 1], (t1, b) = frames[next]
        let local = t1 > t0 ? (t - t0) / (t1 - t0) : 1
        return FigurePose.mix(a, b, local * local * (3 - 2 * local))
    }
}

/// The figure: a minimal cartoon stick figure after the reference drawing,
/// with a large round head, dot eyes, a smile and three tufts of hair, thin
/// white limbs, a black oversized T-shirt, blue cuffed shorts and white
/// sneakers, every part flat colour inside a black outline.
///
/// It is a rig rather than a statue: hips, knees, waist, shoulders and
/// elbows are named nodes that `apply` turns, and the forearm hangs from a
/// pivot named "wrist" that the wrist-only replay turns by the recorded
/// orientation.
enum BadmintonFigure {
    static func build(leftHanded: Bool) -> SCNNode {
        let white = flat(UIColor(white: 0.98, alpha: 1))
        let ink = flat(UIColor(white: 0.06, alpha: 1))
        let denim = flat(UIColor(red: 0.30, green: 0.45, blue: 0.63, alpha: 1))
        let cuff = flat(UIColor(red: 0.42, green: 0.57, blue: 0.74, alpha: 1))

        let root = SCNNode(); root.name = "figure"
        if leftHanded { root.scale.x = -1 }
        let shadow = SCNCylinder(radius: 0.32, height: 0.002)
        shadow.firstMaterial = flat(UIColor(white: 0, alpha: 0.18))
        let shadowNode = SCNNode(geometry: shadow); shadowNode.name = "shadow"; shadowNode.position.y = 0.012
        root.addChildNode(shadowNode)

        let body = SCNNode(); body.name = "body"; root.addChildNode(body)
        let hips = SCNNode(); hips.simdPosition = [0, 0.92, 0]; body.addChildNode(hips)
        hips.addChildNode(outlined(rounded(0.32, 0.12, 0.2, at: [0, 0, 0], denim)))

        // Legs: thigh in the shorts with a rolled cuff, white shin, sneaker.
        for (name, x) in [("racketHip", Float(0.11)), ("freeHip", Float(-0.11))] {
            let hip = SCNNode(); hip.name = name; hip.simdPosition = [x, -0.02, 0]; hips.addChildNode(hip)
            hip.addChildNode(outlined(limb(from: [0, 0, 0], to: [0, -0.36, 0], radius: 0.085, denim)))
            let hem = SCNNode(geometry: SCNCylinder(radius: 0.092, height: 0.05))
            hem.geometry?.firstMaterial = cuff; hem.simdPosition = [0, -0.36, 0]
            hip.addChildNode(outlined(hem))
            let knee = SCNNode(); knee.name = name == "racketHip" ? "racketKnee" : "freeKnee"
            knee.simdPosition = [0, -0.4, 0]; hip.addChildNode(knee)
            knee.addChildNode(outlined(limb(from: [0, 0, 0], to: [0, -0.4, 0], radius: 0.022, white)))
            let shoe = SCNNode(geometry: SCNCapsule(capRadius: 0.06, height: 0.24))
            shoe.geometry?.firstMaterial = white
            shoe.eulerAngles.x = .pi / 2; shoe.simdPosition = [0, -0.44, -0.05]
            knee.addChildNode(outlined(shoe))
        }

        // Waist up: the T-shirt, its sleeves, the arms, the head.
        let torso = SCNNode(); torso.name = "torso"; torso.simdPosition = [0, 0.06, 0]; hips.addChildNode(torso)
        torso.addChildNode(outlined(rounded(0.36, 0.48, 0.21, at: [0, 0.24, 0], ink)))
        torso.addChildNode(outlined(limb(from: [0, 0.5, 0], to: [0, 0.58, 0], radius: 0.022, white)))
        torso.addChildNode(outlined(head(white: white, ink: ink), thickness: 1.07))

        for (prefix, x) in [("racket", Float(0.2)), ("free", Float(-0.2))] {
            let shoulder = SCNNode(); shoulder.name = prefix + "Shoulder"; shoulder.simdPosition = [x, 0.44, 0]
            torso.addChildNode(shoulder)
            shoulder.addChildNode(outlined(limb(from: [0, 0, 0], to: [0, -0.12, 0], radius: 0.065, ink)))
            shoulder.addChildNode(outlined(limb(from: [0, -0.1, 0], to: [0, -0.28, 0], radius: 0.022, white)))
            let elbow = SCNNode(); elbow.name = prefix + "Elbow"; elbow.simdPosition = [0, -0.29, 0]
            shoulder.addChildNode(elbow)
            let forearm = SCNNode(); forearm.name = prefix == "racket" ? "wrist" : "freeForearm"; elbow.addChildNode(forearm)
            forearm.addChildNode(outlined(limb(from: [0, 0, 0], to: [0, -0.26, 0], radius: 0.022, white)))
            let fist = SCNNode(geometry: SCNSphere(radius: 0.04)); fist.geometry?.firstMaterial = white
            fist.simdPosition = [0, -0.28, 0]; forearm.addChildNode(outlined(fist))
            if prefix == "racket" { forearm.addChildNode(racket(ink: ink)) }
        }
        return root
    }

    /// Turns the rig to a pose and places it at `base` on the court.
    static func apply(_ pose: FigurePose, to figure: SCNNode, base: SIMD3<Float>) {
        figure.simdPosition = base + [0, 0, -pose.step]
        figure.childNode(withName: "body", recursively: false)?.simdPosition = [0, pose.lift, 0]
        figure.childNode(withName: "torso", recursively: true)?.eulerAngles = SCNVector3(pose.torsoPitch, pose.torsoYaw, 0)
        // Every limb hangs along -y at rest, so each joint is the rotation
        // from straight down to where the pose says the limb points. The
        // lower joint's direction is taken into its parent's frame first.
        func chain(_ upper: String, _ lower: String, _ upperDirection: SIMD3<Float>, _ lowerDirection: SIMD3<Float>) {
            guard let top = figure.childNode(withName: upper, recursively: true),
                  let bottom = figure.childNode(withName: lower, recursively: true) else { return }
            let topTurn = aim(upperDirection)
            top.simdOrientation = topTurn
            bottom.simdOrientation = aim(topTurn.inverse.act(lowerDirection))
        }
        chain("racketShoulder", "racketElbow", pose.racketUpper, pose.racketFore)
        chain("freeShoulder", "freeElbow", pose.freeUpper, pose.freeFore)
        chain("racketHip", "racketKnee", pose.racketThigh, pose.racketShin)
        chain("freeHip", "freeKnee", pose.freeThigh, pose.freeShin)
    }

    /// The rotation that turns a limb hanging straight down to `direction`.
    private static func aim(_ direction: SIMD3<Float>) -> simd_quatf {
        let down: SIMD3<Float> = [0, -1, 0]
        let target = simd_normalize(direction)
        // Straight up is the one direction with no unique shortest turn;
        // go over the front, the way an arm actually rises.
        if simd_dot(down, target) < -0.9999 { return simd_quatf(angle: .pi, axis: [1, 0, 0]) }
        return simd_quatf(from: down, to: target)
    }

    private static func head(white: SCNMaterial, ink: SCNMaterial) -> SCNNode {
        let head = SCNNode(geometry: SCNSphere(radius: 0.17))
        head.geometry?.firstMaterial = white
        head.simdPosition = [0, 0.74, -0.02]
        for x: Float in [-0.055, 0.055] {
            let eye = SCNNode(geometry: SCNSphere(radius: 0.022))
            eye.geometry?.firstMaterial = ink
            eye.scale = SCNVector3(0.8, 1.15, 0.5)
            eye.simdPosition = [x, 0.03, -0.158]
            head.addChildNode(eye)
        }
        let arc = UIBezierPath(arcCenter: .zero, radius: 0.06, startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: true)
        let stroke = arc.cgPath.copy(strokingWithWidth: 0.012, lineCap: .round, lineJoin: .round, miterLimit: 1)
        let smile = SCNShape(path: UIBezierPath(cgPath: stroke), extrusionDepth: 0.01)
        smile.firstMaterial = ink
        let smileNode = SCNNode(geometry: smile)
        smileNode.simdPosition = [0, 0, -0.163]; smileNode.eulerAngles.y = .pi
        head.addChildNode(smileNode)
        for (x, lean): (Float, Float) in [(-0.04, -0.35), (0.0, 0.0), (0.04, 0.35)] {
            head.addChildNode(limb(from: [x, 0.16, -0.01], to: [x + lean * 0.12, 0.27, 0.0], radius: 0.007, ink))
        }
        return head
    }

    /// Handle and shaft along the forearm's line, and the frame beyond the
    /// fist, so the racket swings as the forearm does.
    private static func racket(ink: SCNMaterial) -> SCNNode {
        let racket = SCNNode()
        racket.addChildNode(limb(from: [0, -0.28, 0], to: [0, -0.7, -0.04], radius: 0.011, ink))
        let frame = SCNTorus(ringRadius: 0.11, pipeRadius: 0.011)
        frame.firstMaterial = ink
        let frameNode = SCNNode(geometry: frame)
        frameNode.simdPosition = [0, -0.83, -0.05]
        frameNode.eulerAngles.x = .pi / 2
        frameNode.scale = SCNVector3(1, 1, 1.3)
        let strings = SCNCylinder(radius: 0.102, height: 0.002)
        strings.firstMaterial = flat(UIColor(white: 1, alpha: 0.55))
        frameNode.addChildNode(SCNNode(geometry: strings))
        racket.addChildNode(frameNode)
        return racket
    }

    // MARK: - Drawing helpers

    /// Flat colour, unlit, so every part reads as a filled shape in a drawing.
    static func flat(_ color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .constant
        if color.cgColor.alpha < 1 { material.transparency = color.cgColor.alpha; material.blendMode = .alpha }
        return material
    }

    /// The drawn outline: a black copy of the shape, slightly larger, with
    /// its front faces culled so only the rim shows around the original.
    private static func outlined(_ node: SCNNode, thickness: Float = 1.12) -> SCNNode {
        guard let geometry = node.geometry?.copy() as? SCNGeometry else { return node }
        let ink = SCNMaterial()
        ink.diffuse.contents = UIColor(white: 0.04, alpha: 1)
        ink.lightingModel = .constant
        ink.cullMode = .front
        geometry.materials = [ink]
        let rim = SCNNode(geometry: geometry)
        rim.scale = SCNVector3(thickness, thickness, thickness)
        node.addChildNode(rim)
        return node
    }

    private static func rounded(_ width: CGFloat, _ height: CGFloat, _ length: CGFloat, at position: SIMD3<Float>,
                                _ material: SCNMaterial) -> SCNNode {
        let geometry = SCNBox(width: width, height: height, length: length, chamferRadius: min(width, length) * 0.35)
        geometry.firstMaterial = material
        let node = SCNNode(geometry: geometry); node.simdPosition = position
        return node
    }

    /// A round limb from one joint to the next.
    private static func limb(from a: SIMD3<Float>, to b: SIMD3<Float>, radius: CGFloat, _ material: SCNMaterial) -> SCNNode {
        let length = simd_length(b - a)
        let geometry = SCNCapsule(capRadius: radius, height: CGFloat(length) + radius * 2)
        geometry.firstMaterial = material
        let node = SCNNode(geometry: geometry)
        node.simdPosition = (a + b) / 2
        node.simdOrientation = simd_quatf(from: [0, 1, 0], to: simd_normalize(b - a))
        return node
    }
}
