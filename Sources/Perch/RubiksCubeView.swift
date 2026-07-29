import SceneKit
import SwiftUI

// A monochrome 3D Rubik's cube that tumbles slowly and twists a random
// layer every couple of seconds — shown while an agent is working
struct RubiksCubeView: NSViewRepresentable {
    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.scene
        view.backgroundColor = .clear
        view.allowsCameraControl = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 30
        view.autoenablesDefaultLighting = false
        view.rendersContinuously = true
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        let scene = SCNScene()
        private let cubeRoot = SCNNode()
        private var cubelets: [SCNNode] = []

        init() {
            buildScene()
            startTumble()
            scheduleTwists()
        }

        private func buildScene() {
            scene.background.contents = NSColor.clear

            let camera = SCNCamera()
            camera.fieldOfView = 24
            let cameraNode = SCNNode()
            cameraNode.camera = camera
            cameraNode.position = SCNVector3(0, 0, 11)
            scene.rootNode.addChildNode(cameraNode)

            let key = SCNNode()
            key.light = SCNLight()
            key.light?.type = .directional
            key.light?.intensity = 900
            key.eulerAngles = SCNVector3(-0.6, 0.5, 0)
            scene.rootNode.addChildNode(key)

            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 420
            scene.rootNode.addChildNode(ambient)

            // One shade per cube face, like a solved monochrome Rubik's cube —
            // the layer twists then visibly scramble it over time.
            // SCNBox material order: +z, +x, -z, -x, +y, -y
            let faceShades: [CGFloat] = [0.95, 0.62, 0.30, 0.78, 0.45, 0.14]

            for x in -1...1 {
                for y in -1...1 {
                    for z in -1...1 {
                        let box = SCNBox(width: 0.92, height: 0.92, length: 0.92, chamferRadius: 0.06)
                        let materials: [SCNMaterial] = faceShades.map { shade in
                            let material = SCNMaterial()
                            material.diffuse.contents = NSColor(white: shade, alpha: 1)
                            material.metalness.contents = 0.85
                            material.roughness.contents = 0.35
                            material.lightingModel = .physicallyBased
                            return material
                        }
                        box.materials = materials

                        let node = SCNNode(geometry: box)
                        node.position = SCNVector3(CGFloat(x), CGFloat(y), CGFloat(z))
                        cubeRoot.addChildNode(node)
                        cubelets.append(node)
                    }
                }
            }

            cubeRoot.eulerAngles = SCNVector3(-0.4, 0.6, 0)
            scene.rootNode.addChildNode(cubeRoot)
        }

        private func startTumble() {
            let spin = SCNAction.rotateBy(x: 0.9, y: 2 * .pi, z: 0.4, duration: 14)
            cubeRoot.runAction(.repeatForever(spin))
        }

        private func scheduleTwists() {
            let sequence = SCNAction.sequence([
                .wait(duration: 1.6, withRange: 1.2),
                .run { [weak self] _ in self?.twistRandomLayer() }
            ])
            scene.rootNode.runAction(.repeatForever(sequence))
        }

        private func twistRandomLayer() {
            let axis = Int.random(in: 0...2)
            let layer = CGFloat(Int.random(in: -1...1))
            let direction: CGFloat = Bool.random() ? 1 : -1

            let selected = cubelets.filter { node in
                let p = node.position
                let value: CGFloat = axis == 0 ? p.x : axis == 1 ? p.y : p.z
                return abs(value - layer) < 0.3
            }
            guard !selected.isEmpty else { return }

            let container = SCNNode()
            cubeRoot.addChildNode(container)
            for node in selected {
                node.removeFromParentNode()
                container.addChildNode(node)
            }

            let angle = direction * .pi / 2
            let rotation = axis == 0
                ? SCNAction.rotateBy(x: angle, y: 0, z: 0, duration: 0.55)
                : axis == 1
                    ? SCNAction.rotateBy(x: 0, y: angle, z: 0, duration: 0.55)
                    : SCNAction.rotateBy(x: 0, y: 0, z: angle, duration: 0.55)
            rotation.timingMode = .easeInEaseOut

            container.runAction(rotation) { [weak self] in
                guard let self else { return }
                for node in selected {
                    let world = node.worldTransform
                    node.removeFromParentNode()
                    self.cubeRoot.addChildNode(node)
                    node.transform = self.cubeRoot.convertTransform(world, from: nil)
                    node.position = SCNVector3(
                        round(node.position.x),
                        round(node.position.y),
                        round(node.position.z)
                    )
                }
                container.removeFromParentNode()
            }
        }
    }
}
