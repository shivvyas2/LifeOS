import SwiftUI
import SceneKit
import Insights

/// A lit 3D bubble. Audio is interpolated at display cadence; touch gently tilts it.
struct CoachVoiceOrb: UIViewRepresentable {
    var level: CGFloat
    var isResponding = false
    var isEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        context.coordinator.target = Double(level)
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
        private let core = SCNNode()
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
            camera.position = SCNVector3(0, 0, 6)
            scene.rootNode.addChildNode(camera)
            scene.rootNode.addChildNode(bubble)

            let sphere = SCNSphere(radius: 1)
            sphere.segmentCount = 96
            shell.lightingModel = .physicallyBased
            shell.diffuse.contents = UIColor(red: 0.28, green: 0.50, blue: 0.86, alpha: 1)
            shell.metalness.contents = 0.35
            shell.roughness.contents = 0.24
            shell.fresnelExponent = 2.4
            shell.emission.contents = UIColor(red: 0.025, green: 0.08, blue: 0.2, alpha: 1)
            shell.shaderModifiers = [.geometry: """
                uniform float phase;
                uniform float energy;
                #pragma body
                float3 p = _geometry.position.xyz;
                float wave = sin(p.y * 3.2 + phase) * cos(p.x * 2.7 - phase * 0.7)
                           + 0.35 * sin(p.z * 4.0 + phase * 0.8);
                _geometry.position.xyz += _geometry.normal * wave * (0.035 + energy * 0.09);
                """]
            shell.setValue(Float(0), forKey: "phase")
            shell.setValue(Float(0), forKey: "energy")
            sphere.firstMaterial = shell
            bubble.geometry = sphere

            // A smaller translucent volume gives the reflected light depth.
            let inner = SCNSphere(radius: 0.93)
            inner.segmentCount = 64
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(red: 0.35, green: 0.85, blue: 1, alpha: 0.16)
            material.emission.contents = UIColor(red: 0.02, green: 0.15, blue: 0.3, alpha: 1)
            material.transparency = 0.2
            inner.firstMaterial = material
            core.geometry = inner
            core.position = SCNVector3(0.08, -0.1, 0.16)
            bubble.addChildNode(core)

            light(.ambient, color: UIColor(red: 0.2, green: 0.32, blue: 0.65, alpha: 1), intensity: 300, position: SCNVector3Zero)
            light(.omni, color: .white, intensity: 950, position: SCNVector3(-2.5, 3, 4))
            light(.omni, color: UIColor(red: 0.18, green: 0.72, blue: 1, alpha: 1), intensity: 850, position: SCNVector3(3, -1, 2))
            light(.omni, color: UIColor(red: 1, green: 0.7, blue: 0.45, alpha: 1), intensity: 450, position: SCNVector3(-3, -2, 0))
        }

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
            guard enabled && !reduced else {
                stop()
                bubble.scale = SCNVector3(1, 1, 1)
                bubble.eulerAngles = SCNVector3Zero
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
            bubble.eulerAngles = SCNVector3(tiltX + Float(sin(time * 0.5) * 0.08), tiltY + Float(sin(time * 0.4) * 0.2), Float(sin(time * 0.7) * 0.04))
            SCNTransaction.commit()
        }

        @objc func nudge() { if !reduced { impulse = 1 } }
        @objc func tilt(_ gesture: UIPanGestureRecognizer) {
            guard !reduced, let view = gesture.view else { return }
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
