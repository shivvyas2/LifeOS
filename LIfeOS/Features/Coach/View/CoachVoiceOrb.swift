import SwiftUI
import SceneKit
import Insights

/// A continuous folded ribbon. Voice gently opens the folds; touch tilts the sculpture.
struct CoachVoiceOrb: UIViewRepresentable {
    var level: CGFloat
    var isResponding = false
    var isEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.camera
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.isAccessibilityElement = false
        view.addGestureRecognizer(UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tilt(_:))))
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.nudge)))
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.target = level.isFinite ? Double(min(max(level, 0), 1)) : 0
        context.coordinator.setOpaque(reduceTransparency)
        context.coordinator.responding = isResponding
        context.coordinator.configure(enabled: isEnabled, reduced: reduceMotion)
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        coordinator.stop()
        view.scene = nil
    }

    @MainActor final class Coordinator: NSObject {
        let scene = SCNScene()
        let camera = SCNNode()
        weak var view: SCNView?
        var target = 0.0
        var responding = false
        private var reduced = false
        private let bubble = SCNNode()
        private let shell = SCNMaterial()
        private var enabled = false
        private var link: CADisplayLink?
        private var envelope = AudioEnvelope()
        private var time = 0.0
        private var lastTime = 0.0
        private var impulse = 0.0
        private var tiltX: Float = 0
        private var tiltY: Float = 0
        private var dragging = false

        override init() {
            super.init()
            camera.camera = SCNCamera()
            camera.camera?.usesOrthographicProjection = true
            camera.camera?.orthographicScale = 1.48
            camera.camera?.wantsHDR = true
            camera.camera?.exposureOffset = -0.35
            camera.position = SCNVector3(0, 0, 6)
            scene.rootNode.addChildNode(camera)
            scene.rootNode.addChildNode(bubble)

            let ribbon = Self.ribbonGeometry()
            shell.lightingModel = .physicallyBased
            shell.diffuse.contents = UIColor(red: 1, green: 0.61, blue: 0.10, alpha: 1)
            shell.metalness.contents = 0.18
            shell.roughness.contents = 0.48
            shell.isDoubleSided = true
            shell.transparency = 0.94
            shell.shaderModifiers = [.geometry: Self.foldShader, .surface: """
                uniform float phase;
                #pragma body
                float u = _surface.diffuseTexcoord.x * 6.2831853;
                float warmth = clamp(0.5 + _surface.position.x * 0.72 - _surface.position.y * 0.20, 0.0, 1.0);
                float3 gold = float3(0.94, 0.56, 0.055);
                float3 coral = float3(0.93, 0.105, 0.025);
                float3 silk = mix(gold, coral, smoothstep(0.18, 0.88, warmth));
                float row = _surface.diffuseTexcoord.y * 80.0;
                float aa = max(fwidth(row), 0.04);
                float filament = 1.0 - smoothstep(0.025, 0.025 + aa, abs(fract(row) - 0.5));
                _surface.diffuse.rgb = silk * (1.0 - filament * 0.08);
                _surface.emission.rgb = silk * 0.065;
                """]
            shell.setValue(Float(0), forKey: "phase")
            shell.setValue(Float(0), forKey: "energy")
            ribbon.firstMaterial = shell
            bubble.geometry = ribbon
            bubble.eulerAngles = SCNVector3(-0.32, 0.18, -0.2)

            light(.ambient, color: UIColor(white: 0.9, alpha: 1), intensity: 150, position: SCNVector3Zero)
            light(.omni, color: UIColor(red: 1, green: 0.94, blue: 0.76, alpha: 1), intensity: 420, position: SCNVector3(-2.5, 3, 4))
            light(.omni, color: UIColor(red: 1, green: 0.47, blue: 0.2, alpha: 1), intensity: 200, position: SCNVector3(3, -1, 1))
            light(.omni, color: UIColor(red: 1, green: 0.86, blue: 0.45, alpha: 1), intensity: 280, position: SCNVector3(-2, -1, -2))
        }

        // The thin closed tube makes a three-half-twist ribbon, with a real
        // opening and self-occluding folds rather than a displaced sphere.
        private static func ribbonGeometry() -> SCNGeometry {
            let around = 160, across = 32
            var vertices: [SCNVector3] = []
            var normals: [SCNVector3] = []
            var coordinates: [CGPoint] = []
            var indices: [UInt32] = []
            for i in 0...around {
                for j in 0...across {
                    let u = Float(i) / Float(around) * 2 * .pi
                    let v = Float(j) / Float(across) * 2 * .pi
                    // Nondegenerate bounds for SceneKit culling. The GPU evaluates
                    // the animated surface and its normals from these UVs.
                    vertices.append(SCNVector3((0.76 + 0.4 * cos(v)) * cos(u), (0.76 + 0.4 * cos(v)) * sin(u), 0.4 * sin(v)))
                    normals.append(SCNVector3(cos(v) * cos(u), cos(v) * sin(u), sin(v)))
                    coordinates.append(CGPoint(x: Double(i) / Double(around), y: Double(j) / Double(across)))
                    if i < around && j < across {
                        let a = UInt32(i * (across + 1) + j), b = a + UInt32(across + 1)
                        indices += [a, b, a + 1, a + 1, b, b + 1]
                    }
                }
            }
            return SCNGeometry(sources: [.init(vertices: vertices), .init(normals: normals), .init(textureCoordinates: coordinates)],
                               elements: [.init(indices: indices, primitiveType: .triangles)])
        }

        private static let foldShader = """
            uniform float phase;
            uniform float energy;
            float3 coachFold(float u, float v, float t, float e) {
                float twist = 1.5 * u + 0.26 * sin(t * 0.65);
                float radius = 0.66 + 0.10 * cos(3.0 * u + t * 0.35);
                float width = 0.38 + 0.055 * sin(3.0 * u - t * 0.6) + e * 0.055;
                float a = width * cos(v);
                float b = 0.055 * sin(v);
                float r = radius + a * cos(twist) - b * sin(twist);
                float z = a * sin(twist) + b * cos(twist)
                        + (0.22 + e * 0.065) * sin(3.0 * u + t * 0.4);
                return float3(r * cos(u), r * sin(u), z);
            }
            #pragma body
            float u = _geometry.texcoords[0].x * 6.2831853;
            float v = _geometry.texcoords[0].y * 6.2831853;
            float3 p = coachFold(u, v, phase, energy);
            float3 du = coachFold(u + 0.002, v, phase, energy) - coachFold(u - 0.002, v, phase, energy);
            float3 dv = coachFold(u, v + 0.002, phase, energy) - coachFold(u, v - 0.002, phase, energy);
            _geometry.position.xyz = p;
            _geometry.normal = normalize(cross(du, dv));
            """

        func setOpaque(_ opaque: Bool) { shell.transparency = opaque ? 1 : 0.94 }

        private func light(_ type: SCNLight.LightType, color: UIColor, intensity: CGFloat, position: SCNVector3) {
            let node = SCNNode()
            node.light = SCNLight()
            node.light?.type = type
            node.light?.color = color
            node.light?.intensity = intensity
            node.position = position
            scene.rootNode.addChildNode(node)
        }

        func configure(enabled: Bool, reduced: Bool) {
            self.reduced = reduced
            self.enabled = enabled
            guard enabled && !reduced else {
                stop()
                bubble.scale = SCNVector3(1, 1, 1)
                bubble.eulerAngles = SCNVector3(-0.32, 0.18, -0.2)
                shell.setValue(Float(0), forKey: "energy")
                shell.setValue(Float(0), forKey: "phase")
                view?.setNeedsDisplay()
                return
            }
            guard link == nil else { return }
            let proxy = TickProxy()
            proxy.owner = self
            let link = CADisplayLink(target: proxy, selector: #selector(TickProxy.tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            self.link = link
            view?.isPlaying = true
        }

        func stop() {
            link?.invalidate()
            link = nil
            lastTime = 0
            envelope = AudioEnvelope()
            impulse = 0
            view?.isPlaying = false
        }

        func tick(_ display: CADisplayLink) {
            let dt = lastTime == 0 ? 1.0 / 60 : min(display.timestamp - lastTime, 0.05)
            lastTime = display.timestamp
            let energy = envelope.update(target: target, elapsed: dt)
            time += dt * (responding ? 0.8 : 0.5)
            impulse *= exp(-dt * 5)
            if !dragging {
                tiltX *= Float(exp(-dt * 6))
                tiltY *= Float(exp(-dt * 6))
            }
            SCNTransaction.begin()
            SCNTransaction.disableActions = true
            shell.setValue(Float(time), forKey: "phase")
            shell.setValue(Float(energy), forKey: "energy")
            let breath = Float(1 + 0.018 * sin(time * 2) + energy * 0.09)
            bubble.scale = SCNVector3(breath + Float(impulse * 0.08), breath - Float(impulse * 0.05), breath)
            bubble.eulerAngles = SCNVector3(-0.32 + tiltX + Float(sin(time * 0.5) * 0.2), 0.18 + tiltY + Float(sin(time * 0.4) * 0.38), -0.2 + Float(sin(time * 0.3) * 0.22))
            SCNTransaction.commit()
        }

        @objc func nudge() { if enabled && !reduced { impulse = 1 } }
        @objc func tilt(_ gesture: UIPanGestureRecognizer) {
            guard enabled && !reduced, let view = gesture.view else { return }
            let point = gesture.translation(in: view)
            dragging = gesture.state == .began || gesture.state == .changed
            tiltX = Float(min(max(point.y / max(view.bounds.height, 1), -0.5), 0.5))
            tiltY = Float(min(max(point.x / max(view.bounds.width, 1), -0.5), 0.5))
        }
    }

    @MainActor private final class TickProxy: NSObject {
        weak var owner: Coordinator?
        @objc func tick(_ display: CADisplayLink) { owner?.tick(display) }
    }
}
