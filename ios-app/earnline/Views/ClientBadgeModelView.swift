import RealityKit
import SwiftUI
import UIKit

/// A real, procedural RealityKit medal. The view always switches RealityKit
/// to its virtual camera, so these awards never request camera permission or
/// enter AR. Grid medals stay still; the detail presentation can be rotated
/// with a direct drag, like Apple Fitness award details.
struct ClientBadgeModelView: View {
    let achievement: ClientAchievement
    var isInteractive = false

    private static let defaultRotation = simd_quatf(angle: -0.24, axis: [0, 1, 0])
        * simd_quatf(angle: 0.10, axis: [1, 0, 0])

    private var rotation: simd_quatf {
        Self.defaultRotation
    }

    var body: some View {
        RealityView { (content: inout RealityViewCameraContent) in
            content.camera = .virtual

            let medal = ClientBadgeFactory.makeMedal(for: achievement)
            medal.name = ClientBadgeFactory.rootName
            medal.position = .zero
            medal.transform.rotation = rotation
            content.add(medal)

            let camera = PerspectiveCamera()
            camera.camera = PerspectiveCameraComponent(
                near: 0.01,
                far: 5,
                fieldOfViewInDegrees: 31
            )
            camera.look(at: medal.position, from: [0, 0, 0.58], relativeTo: nil)
            content.add(camera)

            let keyLight = DirectionalLight()
            keyLight.light.intensity = 1_900
            keyLight.look(at: medal.position, from: [-0.35, 0.45, 0.48], relativeTo: nil)
            content.add(keyLight)

            let fillLight = PointLight()
            fillLight.light.intensity = 850
            fillLight.light.attenuationRadius = 1.5
            fillLight.position = [0.35, -0.2, 0.35]
            content.add(fillLight)
        }
        .contentShape(.rect)
        .clipped()
        .realityViewCameraControls(isInteractive ? .orbit : .none)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(achievement.kind.title)
        .accessibilityValue(achievement.isUnlocked ? String(localized: "Earned") : String(localized: "Locked"))
        .accessibilityHint(isInteractive ? Text("Drag to rotate the 3D award") : Text("Open to inspect the 3D award"))
    }
}

@MainActor
private enum ClientBadgeFactory {
    static let rootName = "client-achievement-medal"

    static func makeMedal(for achievement: ClientAchievement) -> Entity {
        let root = Entity()
        let palette = palette(for: achievement.material, unlocked: achievement.isUnlocked)

        root.addChild(cylinder(radius: 0.132, depth: 0.036, z: 0, material: palette.rim))
        root.addChild(cylinder(radius: 0.115, depth: 0.041, z: 0.004, material: palette.face))
        root.addChild(cylinder(radius: 0.088, depth: 0.044, z: 0.008, material: palette.inner))

        // Raised perimeter beads catch the light during rotation and make the
        // medal visibly volumetric even at the compact collection size.
        for index in 0..<12 {
            let angle = Float(index) / 12 * .pi * 2
            let bead = ModelEntity(
                mesh: .generateSphere(radius: 0.0085),
                materials: [palette.highlight]
            )
            bead.position = [cos(angle) * 0.105, sin(angle) * 0.105, 0.028]
            root.addChild(bead)
        }

        let emblem = emblem(for: achievement.symbol, material: palette.emblem)
        emblem.position.z = 0.035
        root.addChild(emblem)

        if !achievement.isUnlocked {
            let lock = lockedMark(material: palette.highlight)
            lock.position = [0.07, -0.072, 0.047]
            root.addChild(lock)
        }
        return root
    }

    private static func cylinder(
        radius: Float,
        depth: Float,
        z: Float,
        material: SimpleMaterial
    ) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateCylinder(height: depth, radius: radius),
            materials: [material]
        )
        entity.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        entity.position.z = z
        return entity
    }

    private static func emblem(
        for symbol: ClientAchievementSymbol,
        material: SimpleMaterial
    ) -> Entity {
        let root = Entity()
        switch symbol {
        case .payment:
            root.addChild(box(width: 0.112, height: 0.066, depth: 0.018,
                              radius: 0.012, y: 0, material: material))
            root.addChild(box(width: 0.076, height: 0.008, depth: 0.022,
                              radius: 0.004, y: 0.017, material: material))
            root.addChild(box(width: 0.050, height: 0.008, depth: 0.022,
                              radius: 0.004, y: -0.017, material: material))

        case .returning:
            for index in 0..<3 {
                let angle = Float(index) / 3 * .pi * 2 + 0.25
                let bead = ModelEntity(mesh: .generateSphere(radius: 0.025), materials: [material])
                bead.position = [cos(angle) * 0.052, sin(angle) * 0.052, 0]
                root.addChild(bead)
            }
            root.addChild(cylinder(radius: 0.019, depth: 0.022, z: 0, material: material))

        case .projects:
            for index in 0..<3 {
                let item = box(width: 0.058, height: 0.058, depth: 0.026,
                               radius: 0.010, y: Float(index - 1) * 0.012, material: material)
                item.position.x = Float(index - 1) * 0.032
                item.position.z = Float(index) * 0.010
                root.addChild(item)
            }

        case .streak:
            let heights: [Float] = [0.052, 0.084, 0.116]
            for (index, height) in heights.enumerated() {
                let item = box(width: 0.026, height: height, depth: 0.024,
                               radius: 0.008, y: -0.055 + height / 2, material: material)
                item.position.x = Float(index - 1) * 0.041
                root.addChild(item)
            }

        case .anniversary:
            for index in 0..<8 {
                let angle = Float(index) / 8 * .pi * 2
                let bead = ModelEntity(mesh: .generateSphere(radius: 0.014), materials: [material])
                bead.position = [cos(angle) * 0.060, sin(angle) * 0.060, 0]
                root.addChild(bead)
            }
            root.addChild(cylinder(radius: 0.025, depth: 0.024, z: 0, material: material))

        case .core:
            root.addChild(box(width: 0.118, height: 0.030, depth: 0.026,
                              radius: 0.008, y: -0.040, material: material))
            for index in 0..<3 {
                let height: Float = index == 1 ? 0.100 : 0.078
                let pillar = box(width: 0.028, height: height, depth: 0.026,
                                 radius: 0.006, y: 0.006, material: material)
                pillar.position.x = Float(index - 1) * 0.041
                root.addChild(pillar)
                let jewel = ModelEntity(mesh: .generateSphere(radius: 0.018), materials: [material])
                jewel.position = [Float(index - 1) * 0.041, 0.006 + height / 2, 0]
                root.addChild(jewel)
            }
        }
        return root
    }

    private static func lockedMark(material: SimpleMaterial) -> Entity {
        let root = Entity()
        root.addChild(box(width: 0.040, height: 0.035, depth: 0.018,
                          radius: 0.008, y: -0.010, material: material))
        let left = box(width: 0.008, height: 0.030, depth: 0.014,
                       radius: 0.004, y: 0.022, material: material)
        left.position.x = -0.014
        root.addChild(left)
        let right = left.clone(recursive: true)
        right.position.x = 0.014
        root.addChild(right)
        root.addChild(box(width: 0.036, height: 0.008, depth: 0.014,
                          radius: 0.004, y: 0.037, material: material))
        return root
    }

    private static func box(
        width: Float,
        height: Float,
        depth: Float,
        radius: Float,
        y: Float,
        material: SimpleMaterial
    ) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateBox(width: width, height: height, depth: depth, cornerRadius: radius),
            materials: [material]
        )
        entity.position.y = y
        return entity
    }

    private struct Palette {
        let rim: SimpleMaterial
        let face: SimpleMaterial
        let inner: SimpleMaterial
        let highlight: SimpleMaterial
        let emblem: SimpleMaterial
    }

    private static func palette(
        for material: ClientAchievementMaterial,
        unlocked: Bool
    ) -> Palette {
        guard unlocked else {
            return Palette(
                rim: metal(0x3B3D42),
                face: metal(0x555860, roughness: 0.42),
                inner: metal(0x303238, roughness: 0.50),
                highlight: metal(0x777A82, roughness: 0.35),
                emblem: metal(0x858890, roughness: 0.32)
            )
        }

        // swiftlint:disable:next large_tuple
        let colors: (UInt32, UInt32, UInt32, UInt32, UInt32) = switch material {
        case .bronze: (0x6F321E, 0xB96737, 0x7D3E24, 0xF0A36B, 0xFFD0A1)
        case .copper: (0x6A2A22, 0xC45A42, 0x87342B, 0xFF9575, 0xFFD0BD)
        case .silver: (0x515A68, 0xAEBAC8, 0x697687, 0xEDF4FF, 0xFFFFFF)
        case .gold: (0x725013, 0xD8A62A, 0x93701B, 0xFFE680, 0xFFF8C9)
        case .roseGold: (0x70423F, 0xD69086, 0x91544E, 0xFFD0C8, 0xFFF0EB)
        case .platinum: (0x3D5260, 0x93B6C5, 0x566F7B, 0xD9F5FF, 0xFFFFFF)
        }
        return Palette(
            rim: metal(colors.0),
            face: metal(colors.1, roughness: 0.22),
            inner: metal(colors.2, roughness: 0.30),
            highlight: metal(colors.3, roughness: 0.16),
            emblem: metal(colors.4, roughness: 0.12)
        )
    }

    private static func metal(_ hex: UInt32, roughness: Float = 0.26) -> SimpleMaterial {
        SimpleMaterial(color: uiColor(hex), roughness: .float(roughness), isMetallic: true)
    }

    private static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
