import SwiftUI
import SceneKit
import Insights

/// A softly glowing emerald sphere with liquid currents and voice-driven breathing.
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
            camera.camera?.exposureOffset = -0.55
            camera.position = SCNVector3(0, 0, 6)
            scene.rootNode.addChildNode(camera)
            scene.rootNode.addChildNode(bubble)

            let orb = SCNSphere(radius: 0.92)
            orb.segmentCount = 96
            shell.lightingModel = .physicallyBased
            shell.diffuse.contents = UIColor(red: 0.12, green: 0.85, blue: 0.62, alpha: 1)
            shell.metalness.contents = 0.28
            shell.roughness.contents = 0.34
            shell.isDoubleSided = false
            shell.transparency = 1
            shell.shaderModifiers = [.geometry: Self.orbShader, .surface: """
                uniform float phase;
                uniform float energy;
                #pragma body
                float3 p = _surface.position;
                float flow = phase * 0.32;
                // Smooth, layered currents give the solid sphere a liquid interior.
                float cloud = sin(p.x * 3.8 + sin(p.y * 4.0 + flow))
                            * cos(p.z * 3.1 - flow * 0.7);
                float current = p.y + 0.16 * sin(p.x * 3.0 + flow)
                              + 0.10 * sin(p.z * 4.0 - flow);
                float band = smoothstep(-0.10, 0.08, current)
                           - smoothstep(0.13, 0.34, current);
                float pool = smoothstep(-0.75, 0.85, cloud + p.y * 0.55);
                float3 teal = float3(0.004, 0.14, 0.12);
                float3 emerald = float3(0.035, 0.57, 0.31);
                float3 jade = mix(teal, emerald, pool);
                jade = mix(jade, float3(0.035, 0.36, 0.29), band * 0.48);
                float shimmer = sin(p.x * 34.0 + sin(p.y * 27.0))
                              * sin(p.z * 31.0 - flow);
                _surface.diffuse.rgb = jade * (1.0 + shimmer * 0.012);
                _surface.emission.rgb = jade * (0.12 + energy * 0.07);
                """]
            shell.setValue(Float(0), forKey: "phase")
            shell.setValue(Float(0), forKey: "energy")
            orb.firstMaterial = shell
            bubble.geometry = orb
            addGlow()
            bubble.eulerAngles = SCNVector3(-0.32, 0.18, -0.2)

            light(.ambient, color: UIColor(white: 0.9, alpha: 1), intensity: 110, position: SCNVector3Zero)
            light(.omni, color: UIColor(red: 0.85, green: 1, blue: 0.95, alpha: 1), intensity: 300, position: SCNVector3(-2.5, 3, 4))
            light(.omni, color: UIColor(red: 0.1, green: 0.85, blue: 0.7, alpha: 1), intensity: 100, position: SCNVector3(3, -1, 1))
            light(.omni, color: UIColor(red: 0.4, green: 1, blue: 0.8, alpha: 1), intensity: 160, position: SCNVector3(-2, -1, -2))
        }

        private static let orbShader = """
            uniform float phase;
            uniform float energy;
            float3 liquidOrb(float3 n, float t, float e) {
                float swell = 0.022 * sin(n.y * 3.2 + t * 0.7) * sin(n.x * 3.0 - t * 0.45)
                            + 0.015 * sin(n.z * 4.0 + n.y * 2.0 + t * 0.6)
                            + e * 0.016 * sin(n.x * 5.0 + n.z * 3.0 - t);
                return n * (0.92 + swell);
            }
            #pragma body
            float3 n = normalize(_geometry.position.xyz);
            float3 axis = abs(n.y) < 0.95 ? float3(0.0, 1.0, 0.0) : float3(1.0, 0.0, 0.0);
            float3 tangent = normalize(cross(axis, n));
            float3 bitangent = cross(n, tangent);
            float3 du = liquidOrb(normalize(n + tangent * 0.002), phase, energy)
                      - liquidOrb(normalize(n - tangent * 0.002), phase, energy);
            float3 dv = liquidOrb(normalize(n + bitangent * 0.002), phase, energy)
                      - liquidOrb(normalize(n - bitangent * 0.002), phase, energy);
            _geometry.position.xyz = liquidOrb(n, phase, energy);
            _geometry.normal = normalize(cross(du, dv));
            """

        private let glow = SCNNode()

        private func addGlow() {
            let plane = SCNPlane(width: 2.8, height: 2.8)
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.isDoubleSided = true
            material.writesToDepthBuffer = false
            material.blendMode = .add
            material.shaderModifiers = [.fragment: """
                #pragma transparent
                #pragma body
                float radius = length(_surface.position.xy) / 1.4;
                float halo = exp(-radius * radius * 5.5) * (1.0 - smoothstep(0.65, 1.0, radius));
                _output.color = float4(float3(0.02, 0.80, 0.48) * halo * 0.24, halo * 0.24);
                """]
            plane.firstMaterial = material
            glow.geometry = plane
            glow.position = SCNVector3(0, 0, -1.2)
            glow.renderingOrder = -1
            scene.rootNode.addChildNode(glow)
        }

        func setOpaque(_ opaque: Bool) { glow.isHidden = opaque }

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
                glow.scale = SCNVector3(1, 1, 1)
                glow.opacity = 1
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
            time += dt * ((responding ? 1.0 : 0.72) + energy * 0.35)
            impulse *= exp(-dt * 2.8)
            if !dragging {
                tiltX *= Float(exp(-dt * 6))
                tiltY *= Float(exp(-dt * 6))
            }
            SCNTransaction.begin()
            SCNTransaction.disableActions = true
            shell.setValue(Float(time), forKey: "phase")
            shell.setValue(Float(min(1, energy + impulse * 0.45)), forKey: "energy")
            let breath = Float(1 + 0.018 * sin(time * 2) + energy * 0.035)
            glow.scale = SCNVector3(breath, breath, 1)
            glow.opacity = CGFloat(0.75 + energy * 0.25)
            bubble.scale = SCNVector3(breath + Float(impulse * 0.03), breath - Float(impulse * 0.02), breath)
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
