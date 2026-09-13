import SwiftUI
import SceneKit

/// A real, lit 3D character. The surface shader keeps the reference's horizontal
/// ink lines while the geometry, face and articulated paw move in depth.
struct OnboardingCat: UIViewRepresentable {
    var page: Int
    var isActive: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 30
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.camera
        view.addGestureRecognizer(UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.greet)
        ))
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        coordinator.update(dark: scheme == .dark, reduceMotion: reduceMotion, page: page)
        coordinator.scene.isPaused = !isActive || reduceMotion
        view.isPlaying = isActive && !reduceMotion
        view.setNeedsDisplay()
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        view.isPlaying = false
        view.scene = nil
    }

    @MainActor final class Coordinator: NSObject {
        let scene = SCNScene()
        let camera = SCNNode()
        private let character = SCNNode()
        private let head = SCNNode()
        private let paw = SCNNode()
        private let tail = SCNNode()
        private let coat = SCNMaterial()
        private var eyes: [SCNNode] = []
        private var lastPage: Int?
        private var motionReduced: Bool?

        override init() {
            super.init()
            camera.camera = SCNCamera()
            camera.camera?.usesOrthographicProjection = true
            camera.camera?.orthographicScale = 2.55
            camera.position = SCNVector3(0, 0.35, 9)
            scene.rootNode.addChildNode(camera)

            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 450
            scene.rootNode.addChildNode(ambient)
            let key = SCNNode()
            key.light = SCNLight()
            key.light?.type = .omni
            key.light?.intensity = 750
            key.position = SCNVector3(-3, 5, 6)
            scene.rootNode.addChildNode(key)

            coat.lightingModel = .physicallyBased
            coat.roughness.contents = 0.82
            coat.metalness.contents = 0.0
            // View-space rows stay horizontal as the cat turns. fwidth softens
            // each edge at the actual rendered resolution to avoid shimmer.
            coat.shaderModifiers = [.surface: """
                #pragma body
                float row = _surface.position.y * 16.0;
                float edge = abs(fract(row) - 0.5);
                float aa = max(fwidth(row), 0.025);
                float ink = 1.0 - smoothstep(0.14 - aa, 0.14 + aa, edge);
                _surface.diffuse.rgb *= mix(1.0, 0.035, ink);
                """]
            let ink = material(UIColor(white: 0.045, alpha: 1), roughness: 0.52)
            let warmDetail = material(UIColor(red: 0.64, green: 0.60, blue: 0.55, alpha: 1))
            let white = material(.white)

            scene.rootNode.addChildNode(character)
            character.eulerAngles.y = -0.12
            addOval(to: character, at: SCNVector3(0, -0.70, 0), scale: SCNVector3(0.72, 0.74, 0.62), material: coat)
            for x: Float in [-0.43, 0.43] {
                addOval(to: character, at: SCNVector3(x, -1.31, 0.26), scale: SCNVector3(0.35, 0.24, 0.46), material: coat)
            }
            // The resting arm and raised arm are separate from the torso.
            let resting = addOval(to: character, at: SCNVector3(-0.67, -0.52, 0.20), scale: SCNVector3(0.23, 0.57, 0.25), material: coat)
            resting.eulerAngles.z = -0.25
            paw.position = SCNVector3(0.67, -0.35, 0.1)
            character.addChildNode(paw)
            let arm = addOval(to: paw, at: SCNVector3(0.24, 0.39, 0), scale: SCNVector3(0.25, 0.62, 0.26), material: coat)
            arm.eulerAngles.z = -0.4
            addOval(to: paw, at: SCNVector3(0.45, 0.89, 0.04), scale: SCNVector3(0.32, 0.34, 0.28), material: coat)
            addOval(to: paw, at: SCNVector3(0.45, 0.88, 0.30), scale: SCNVector3(0.13, 0.14, 0.035), material: warmDetail)

            tail.position = SCNVector3(-0.50, -0.95, -0.25)
            character.addChildNode(tail)
            // Overlapping smooth joints form an upward curl behind the body.
            for index in 0..<16 {
                let t = Float(index) / 15
                let angle = t * Float.pi * 0.88
                addOval(to: tail, at: SCNVector3(-sin(angle) * 0.9, (1 - cos(angle)) * 0.52, 0), scale: SCNVector3(0.16, 0.17, 0.16), material: coat)
            }

            head.position = SCNVector3(0, 0.62, 0.12)
            character.addChildNode(head)
            for x: Float in [-0.82, 0.82] {
                let ear = SCNNode(geometry: earGeometry())
                ear.geometry?.firstMaterial = coat
                ear.position = SCNVector3(x, 0.70, -0.05)
                ear.eulerAngles.z = x < 0 ? 0.22 : -0.22
                head.addChildNode(ear)
                let inner = SCNNode(geometry: earGeometry())
                inner.geometry?.firstMaterial = warmDetail
                inner.scale = SCNVector3(0.49, 0.59, 0.25)
                inner.position = SCNVector3(0, 0.12, 0.19)
                ear.addChildNode(inner)
            }
            addOval(to: head, at: SCNVector3(0, 0, 0), scale: SCNVector3(1.25, 1.02, 0.76), material: coat)
            for x: Float in [-0.46, 0.46] {
                let eye = addOval(to: head, at: SCNVector3(x, -0.02, 0.73), scale: SCNVector3(0.205, 0.225, 0.095), material: ink)
                eyes.append(eye)
                addOval(to: eye, at: SCNVector3(-0.24, 0.30, 0.82), scale: SCNVector3(0.24, 0.20, 0.18), material: white)
                addOval(to: head, at: SCNVector3(x * 1.52, -0.28, 0.65), scale: SCNVector3(0.12, 0.055, 0.025), material: warmDetail)
            }
            addOval(to: head, at: SCNVector3(0, -0.25, 0.79), scale: SCNVector3(0.062, 0.046, 0.04), material: ink)
            for x: Float in [-0.065, 0.065] {
                let curve = UIBezierPath()
                curve.addArc(withCenter: .zero, radius: 0.064, startAngle: .pi,
                             endAngle: .pi * 2, clockwise: true)
                let outline = curve.cgPath.copy(strokingWithWidth: 0.028,
                                                lineCap: .round, lineJoin: .round, miterLimit: 2)
                let mouthPath = UIBezierPath(cgPath: outline)
                mouthPath.flatness = 0.001
                let smile = SCNShape(path: mouthPath, extrusionDepth: 0.025)
                let node = SCNNode(geometry: smile)
                node.geometry?.firstMaterial = ink
                node.position = SCNVector3(x, -0.285, 0.78)
                head.addChildNode(node)
            }
        }

        func update(dark: Bool, reduceMotion: Bool, page: Int) {
            coat.diffuse.contents = dark
                ? UIColor(red: 0.82, green: 0.81, blue: 0.77, alpha: 1)
                : UIColor(red: 0.95, green: 0.94, blue: 0.90, alpha: 1)
            if motionReduced != reduceMotion {
                motionReduced = reduceMotion
                character.removeAllActions()
                head.removeAllActions()
                paw.removeAllActions()
                tail.removeAllActions()
                eyes.forEach { $0.removeAllAnimations() }
                character.position = SCNVector3Zero
                head.eulerAngles = SCNVector3Zero
                paw.eulerAngles = SCNVector3Zero
                tail.eulerAngles = SCNVector3Zero
                if !reduceMotion { startIdle() }
            }
            if lastPage != page {
                lastPage = page
                let turn = Float([-0.12, 0.16, -0.20, 0.10][page % 4])
                if reduceMotion {
                    character.eulerAngles.y = turn
                } else {
                    let action = SCNAction.rotateTo(x: 0, y: CGFloat(turn), z: 0, duration: 0.65, usesShortestUnitArc: true)
                    action.timingMode = .easeInEaseOut
                    character.runAction(action, forKey: "turn")
                    greet()
                }
            }
        }

        @objc func greet() {
            guard motionReduced == false else { return }
            let left = SCNAction.rotateTo(x: 0, y: 0, z: -0.24, duration: 0.22)
            let right = SCNAction.rotateTo(x: 0, y: 0, z: 0.20, duration: 0.22)
            left.timingMode = .easeInEaseOut
            right.timingMode = .easeInEaseOut
            paw.runAction(.sequence([
                .repeat(.sequence([left, right]), count: 3),
                .rotateTo(x: 0, y: 0, z: 0, duration: 0.3),
                idleWave
            ]), forKey: "wave")
        }

        private func startIdle() {
            let rise = SCNAction.moveBy(x: 0, y: 0.07, z: 0, duration: 1.7)
            rise.timingMode = .easeInEaseOut
            character.runAction(.repeatForever(.sequence([rise, rise.reversed()])), forKey: "breathing")
            let tilt = SCNAction.rotateBy(x: 0, y: 0.06, z: 0.035, duration: 2.1)
            tilt.timingMode = .easeInEaseOut
            head.runAction(.repeatForever(.sequence([tilt, tilt.reversed()])))
            let curl = SCNAction.rotateBy(x: 0, y: 0.18, z: 0.10, duration: 1.4)
            curl.timingMode = .easeInEaseOut
            tail.runAction(.repeatForever(.sequence([curl, curl.reversed()])))
            for eye in eyes {
                let blink = CAKeyframeAnimation(keyPath: "scale.y")
                blink.values = [0.225, 0.225, 0.018, 0.225, 0.225]
                blink.keyTimes = [0, 0.84, 0.87, 0.90, 1]
                blink.duration = 4.6
                blink.repeatCount = .infinity
                eye.addAnimation(blink, forKey: "blink")
            }
            paw.runAction(idleWave, forKey: "wave")
        }

        private var idleWave: SCNAction {
            .repeatForever(.sequence([
                .wait(duration: 5),
                .rotateTo(x: 0, y: 0, z: -0.18, duration: 0.3),
                .rotateTo(x: 0, y: 0, z: 0.16, duration: 0.3),
                .rotateTo(x: 0, y: 0, z: 0, duration: 0.3)
            ]))
        }

        private func material(_ color: UIColor, roughness: Double = 0.8) -> SCNMaterial {
            let result = SCNMaterial()
            result.diffuse.contents = color
            result.roughness.contents = roughness
            result.lightingModel = .physicallyBased
            return result
        }

        @discardableResult private func addOval(to parent: SCNNode, at position: SCNVector3, scale: SCNVector3, material: SCNMaterial) -> SCNNode {
            let sphere = SCNSphere(radius: 1)
            sphere.segmentCount = 40
            sphere.firstMaterial = material
            let node = SCNNode(geometry: sphere)
            node.position = position
            node.scale = scale
            parent.addChildNode(node)
            return node
        }

        private func earGeometry() -> SCNShape {
            let path = UIBezierPath()
            path.flatness = 0.002
            path.move(to: CGPoint(x: -0.36, y: 0))
            path.addQuadCurve(to: CGPoint(x: -0.06, y: 0.48), controlPoint: CGPoint(x: -0.24, y: 0.64))
            path.addQuadCurve(to: CGPoint(x: 0.36, y: 0), controlPoint: CGPoint(x: 0.10, y: 0.46))
            path.close()
            let shape = SCNShape(path: path, extrusionDepth: 0.26)
            shape.chamferRadius = 0.12
            return shape
        }
    }
}
