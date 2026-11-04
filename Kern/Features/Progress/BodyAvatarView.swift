import SwiftUI
import SwiftData
import SceneKit

// MARK: - Körperform

/// Vereinfachte, illustrative Körperform aus Umfängen (cm).
struct ProgressBodyShape: Equatable {
    var heightCm: Double
    var weightKg: Double
    var shoulder: Double
    var chest: Double
    var waist: Double
    var hip: Double
    var thigh: Double
    var arm: Double
    var calf: Double
    var neck: Double
    /// Werte, die geschätzt statt gemessen sind.
    var estimated: Set<String>

    static let fieldTitles: [(key: String, title: String)] = [
        ("shoulder", "Schultern"), ("chest", "Brust"), ("waist", "Taille"),
        ("hip", "Hüfte"), ("thigh", "Oberschenkel"), ("arm", "Oberarm")
    ]

    func value(_ key: String) -> Double {
        switch key {
        case "shoulder": shoulder
        case "chest": chest
        case "waist": waist
        case "hip": hip
        case "thigh": thigh
        case "arm": arm
        case "calf": calf
        case "neck": neck
        default: 0
        }
    }

    mutating func set(_ key: String, _ v: Double) {
        switch key {
        case "shoulder": shoulder = v
        case "chest": chest = v
        case "waist": waist = v
        case "hip": hip = v
        case "thigh": thigh = v
        case "arm": arm = v
        case "calf": calf = v
        case "neck": neck = v
        default: break
        }
    }

    /// Erstellt eine Form aus Grösse/Gewicht und – soweit vorhanden – echten Messwerten.
    static func make(heightCm: Double, weightKg: Double, measurement: [String: Double],
                     bodyFat: Double?, sex: PhysiologicalSex) -> ProgressBodyShape {
        let h = max(heightCm, 120)
        let bmi = weightKg / pow(h / 100, 2)
        let f = (bmi / 22).clamped(0.6...2.2)
        var fatAdjust = 1.0
        if let bodyFat {
            let reference: Double = sex == .male ? 18 : (sex == .female ? 27 : 22)
            fatAdjust = (1 + (bodyFat - reference) / 100 * 0.6).clamped(0.85...1.25)
        }
        var shape = ProgressBodyShape(
            heightCm: h, weightKg: weightKg,
            shoulder: 0.64 * h * pow(f, 0.5),
            chest: 0.54 * h * pow(f, 0.6),
            waist: 0.45 * h * pow(f, 0.85) * fatAdjust,
            hip: 0.53 * h * pow(f, 0.6) * sqrt(fatAdjust),
            thigh: 0.31 * h * pow(f, 0.75),
            arm: 0.17 * h * pow(f, 0.75),
            calf: 0.21 * h * pow(f, 0.5),
            neck: 0.215 * h * pow(f, 0.5),
            estimated: ["shoulder", "chest", "waist", "hip", "thigh", "arm", "calf", "neck"])
        let mapping = ["shoulderCm": "shoulder", "chestCm": "chest", "waistCm": "waist", "hipCm": "hip",
                       "thighCm": "thigh", "armCm": "arm", "calfCm": "calf", "neckCm": "neck"]
        for (source, target) in mapping {
            if let v = measurement[source], v > 10 {
                shape.set(target, v)
                shape.estimated.remove(target)
            }
        }
        return shape
    }

    /// Illustratives Zielszenario – keine Vorhersage.
    func target(weightKg targetWeight: Double?, goal: FitnessGoal, overrides: [String: Double]) -> ProgressBodyShape {
        var t = self
        if let targetWeight, targetWeight > 30 {
            let ratio = (targetWeight / max(weightKg, 30)).clamped(0.6...1.5)
            t.weightKg = targetWeight
            t.waist *= pow(ratio, 0.85)
            t.hip *= pow(ratio, 0.6)
            t.chest *= pow(ratio, 0.5)
            t.thigh *= pow(ratio, 0.7)
            t.arm *= pow(ratio, 0.6)
            t.shoulder *= pow(ratio, 0.3)
            t.calf *= pow(ratio, 0.4)
            t.neck *= pow(ratio, 0.4)
        }
        if [.buildMuscle, .recomposition, .strengthEndurance, .gainWeight].contains(goal) {
            t.arm *= 1.04
            t.chest *= 1.03
            t.shoulder *= 1.03
            t.thigh *= 1.02
        }
        for (key, value) in overrides where value > 10 {
            t.set(key, value)
        }
        return t
    }
}

private struct ProgressBodySnapshot: Identifiable {
    let id: String
    let date: Date
    let shape: ProgressBodyShape
    let isMeasured: Bool
}

// MARK: - Szene

/// Prozedurales Körpermodell aus weichen Grundformen. Matte Oberflächen, keine Effekte.
@MainActor
final class ProgressAvatarScene {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let stage = SCNNode()
    private var bodies: [SCNNode] = []
    private var rotation: Float = 0

    init() {
        let camera = SCNCamera()
        camera.fieldOfView = 32
        camera.zNear = 0.1
        camera.zFar = 20
        cameraNode.camera = camera
        resetCamera()
        scene.rootNode.addChildNode(cameraNode)
        scene.rootNode.addChildNode(stage)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 420
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 750
        key.light?.castsShadow = false
        key.eulerAngles = SCNVector3(-0.5, 0.4, 0)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .directional
        fill.light?.intensity = 300
        fill.light?.castsShadow = false
        fill.eulerAngles = SCNVector3(-0.2, -2.6, 0)
        scene.rootNode.addChildNode(fill)
    }

    func resetCamera() {
        cameraNode.position = SCNVector3(0, 0.92, 3.7)
        cameraNode.look(at: SCNVector3(0, 0.9, 0))
        cameraNode.camera?.fieldOfView = 32
    }

    func zoom(in zoomIn: Bool) {
        guard let camera = cameraNode.camera else { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.25
        camera.fieldOfView = (camera.fieldOfView + (zoomIn ? -5 : 5)).clamped(12...46)
        SCNTransaction.commit()
    }

    func setRotation(_ angle: Float) {
        rotation = angle
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.45
        for body in bodies { body.eulerAngles.y = angle }
        SCNTransaction.commit()
    }

    struct BodySpec {
        var shape: ProgressBodyShape
        var color: UIColor
        var opacity: CGFloat
        var xOffset: Float
    }

    func update(_ specs: [BodySpec]) {
        bodies.forEach { $0.removeFromParentNode() }
        bodies = specs.map { spec in
            let node = ProgressBodyBuilder.makeBody(spec.shape, color: spec.color)
            node.opacity = spec.opacity
            node.position = SCNVector3(spec.xOffset, 0, 0)
            node.eulerAngles.y = rotation
            stage.addChildNode(node)
            return node
        }
    }
}

private extension CGFloat {
    func clamped(_ range: ClosedRange<CGFloat>) -> CGFloat { Swift.min(Swift.max(self, range.lowerBound), range.upperBound) }
}

@MainActor
private enum ProgressBodyBuilder {
    /// Halbachse einer Ellipse aus Umfang (m) und Seitenverhältnis k = Tiefe/Breite (Ramanujan).
    static func semiAxes(circumference c: Double, ratio k: Double) -> (a: Double, b: Double) {
        let f = 3 * (1 + k) - sqrt((3 + k) * (1 + 3 * k))
        let a = c / (Double.pi * f)
        return (a, a * k)
    }

    static func material(_ color: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = color
        m.isDoubleSided = false
        return m
    }

    static func ellipsoid(center: SCNVector3, a: Double, height: Double, b: Double, material: SCNMaterial) -> SCNNode {
        let sphere = SCNSphere(radius: 1)
        sphere.segmentCount = 48
        sphere.materials = [material]
        let node = SCNNode(geometry: sphere)
        node.position = center
        node.scale = SCNVector3(Float(a), Float(height), Float(b))
        return node
    }

    /// Kapsel zwischen zwei Punkten.
    static func capsule(from p1: SCNVector3, to p2: SCNVector3, radius: Double, material: SCNMaterial) -> SCNNode {
        let dx = p2.x - p1.x, dy = p2.y - p1.y, dz = p2.z - p1.z
        let length = Double(sqrt(dx * dx + dy * dy + dz * dz))
        let capsule = SCNCapsule(capRadius: CGFloat(radius), height: CGFloat(length + 2 * radius))
        capsule.radialSegmentCount = 36
        capsule.materials = [material]
        let node = SCNNode(geometry: capsule)
        node.position = SCNVector3((p1.x + p2.x) / 2, (p1.y + p2.y) / 2, (p1.z + p2.z) / 2)
        // Ausrichtung der Kapsel-Achse (y) auf die Verbindungsrichtung
        let len = Float(length)
        guard len > 0.0001 else { return node }
        let d = SCNVector3(dx / len, dy / len, dz / len)
        let axis = SCNVector3(d.z, 0, -d.x) // Kreuzprodukt (0,1,0) × d
        let axisLength = sqrt(axis.x * axis.x + axis.z * axis.z)
        let angle = acos(max(-1, min(1, d.y)))
        if axisLength > 0.0001 {
            node.rotation = SCNVector4(axis.x / axisLength, 0, axis.z / axisLength, angle)
        }
        return node
    }

    static func makeBody(_ s: ProgressBodyShape, color: UIColor) -> SCNNode {
        let root = SCNNode()
        let m = material(color)
        let H = s.heightCm / 100
        func y(_ fraction: Double) -> Float { Float(H * fraction) }

        let hip = semiAxes(circumference: s.hip / 100, ratio: 0.72)
        let waist = semiAxes(circumference: s.waist / 100, ratio: 0.74)
        let chest = semiAxes(circumference: s.chest / 100, ratio: 0.66)
        let armR = s.arm / 100 / (2 * Double.pi)
        let thighR = s.thigh / 100 / (2 * Double.pi)
        let calfR = s.calf / 100 / (2 * Double.pi)
        let neckR = s.neck / 100 / (2 * Double.pi)
        let shoulderHalf = max(s.shoulder / 100 / Double.pi * 1.25 / 2, chest.a + armR * 0.6)

        // Rumpf
        root.addChildNode(ellipsoid(center: SCNVector3(0, y(0.515), 0), a: hip.a, height: H * 0.075, b: hip.b, material: m))
        root.addChildNode(ellipsoid(center: SCNVector3(0, y(0.615), 0), a: waist.a, height: H * 0.095, b: waist.b, material: m))
        root.addChildNode(ellipsoid(center: SCNVector3(0, y(0.715), 0), a: chest.a, height: H * 0.095, b: chest.b, material: m))
        root.addChildNode(capsule(from: SCNVector3(Float(-shoulderHalf * 0.82), y(0.795), 0),
                                  to: SCNVector3(Float(shoulderHalf * 0.82), y(0.795), 0),
                                  radius: max(armR * 1.15, H * 0.032), material: m))

        // Hals & Kopf
        root.addChildNode(capsule(from: SCNVector3(0, y(0.80), 0), to: SCNVector3(0, y(0.865), 0), radius: neckR, material: m))
        root.addChildNode(ellipsoid(center: SCNVector3(0, y(0.925), Float(H * 0.004)), a: H * 0.052, height: H * 0.064, b: H * 0.058, material: m))

        // Arme
        for side in [-1.0, 1.0] {
            let shoulderJoint = SCNVector3(Float(side * shoulderHalf * 0.92), y(0.79), 0)
            let elbow = SCNVector3(Float(side * (shoulderHalf * 0.92 + H * 0.018)), y(0.625), Float(-H * 0.005))
            let wrist = SCNVector3(Float(side * (shoulderHalf * 0.92 + H * 0.028)), y(0.48), Float(H * 0.01))
            root.addChildNode(capsule(from: shoulderJoint, to: elbow, radius: armR, material: m))
            root.addChildNode(capsule(from: elbow, to: wrist, radius: armR * 0.8, material: m))
            root.addChildNode(ellipsoid(center: SCNVector3(wrist.x, y(0.445), wrist.z), a: armR * 0.75, height: H * 0.04, b: armR * 0.45, material: m))
        }

        // Beine
        for side in [-1.0, 1.0] {
            let hipJoint = SCNVector3(Float(side * hip.a * 0.5), y(0.495), 0)
            let knee = SCNVector3(Float(side * hip.a * 0.38), y(0.285), Float(H * 0.004))
            let ankle = SCNVector3(Float(side * hip.a * 0.35), y(0.05), 0)
            root.addChildNode(capsule(from: hipJoint, to: knee, radius: thighR, material: m))
            root.addChildNode(capsule(from: knee, to: ankle, radius: calfR, material: m))
            root.addChildNode(capsule(from: SCNVector3(ankle.x, y(0.022), Float(-H * 0.02)),
                                      to: SCNVector3(ankle.x, y(0.022), Float(H * 0.075)),
                                      radius: H * 0.022, material: m))
        }
        return root
    }
}

/// SCNView-Container mit Kantenglättung und transparentem Hintergrund.
private struct ProgressSceneContainer: UIViewRepresentable {
    let avatar: ProgressAvatarScene

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = avatar.scene
        view.pointOfView = avatar.cameraNode
        view.allowsCameraControl = true
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .clear
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.maximumVerticalAngle = 25
        view.defaultCameraController.minimumVerticalAngle = -10
        view.isAccessibilityElement = true
        view.accessibilityLabel = "Illustrativer 3D-Körper. Mit einem Finger drehen, mit zwei Fingern zoomen."
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        if view.pointOfView !== avatar.cameraNode { view.pointOfView = avatar.cameraNode }
    }
}

// MARK: - Ansicht

private enum ProgressAvatarMode: String, CaseIterable, Identifiable {
    case single, sideBySide, overlay
    var id: String { rawValue }
    var title: String {
        switch self {
        case .single: "Einzeln"
        case .sideBySide: "Vorher / Nachher"
        case .overlay: "Überlagerung"
        }
    }
}

private enum ProgressAvatarComparison: String, CaseIterable, Identifiable {
    case timepoints, target
    var id: String { rawValue }
    var title: String { self == .timepoints ? "Zeitpunkte" : "Aktuell & Ziel" }
}

private enum ProgressAvatarAngle: String, CaseIterable, Identifiable {
    case front, side, back
    var id: String { rawValue }
    var title: String {
        switch self {
        case .front: "Vorne"
        case .side: "Seite"
        case .back: "Hinten"
        }
    }
    var angle: Float {
        switch self {
        case .front: 0
        case .side: .pi / 2
        case .back: .pi
        }
    }
}

struct BodyAvatarView: View {
    @Environment(AppPreferences.self) private var prefs
    @Environment(\.colorScheme) private var colorScheme
    @Query private var profiles: [UserProfile]
    @Query(sort: \BodyMeasurement.date) private var measurements: [BodyMeasurement]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]

    @State private var avatar = ProgressAvatarScene()
    @State private var mode: ProgressAvatarMode = .single
    @State private var showsTarget = false
    @State private var comparison: ProgressAvatarComparison = .timepoints
    @State private var timelineIndex: Double = -1
    @State private var beforeID: String?
    @State private var afterID: String?
    @State private var angle: ProgressAvatarAngle = .front
    @State private var isEditingTarget = false

    @AppStorage("kern.avatar.target.weight") private var targetWeight: Double = 0
    @AppStorage("kern.avatar.target.shoulder") private var targetShoulder: Double = 0
    @AppStorage("kern.avatar.target.chest") private var targetChest: Double = 0
    @AppStorage("kern.avatar.target.waist") private var targetWaist: Double = 0
    @AppStorage("kern.avatar.target.hip") private var targetHip: Double = 0
    @AppStorage("kern.avatar.target.thigh") private var targetThigh: Double = 0
    @AppStorage("kern.avatar.target.arm") private var targetArm: Double = 0

    private var profile: UserProfile? { profiles.first }

    // MARK: Daten

    private var snapshots: [ProgressBodySnapshot] {
        let height = profile?.heightCm ?? 170
        let fallbackWeight = weights.last?.kg ?? profile?.startWeightKg ?? 70
        let sex = profile?.physiologicalSex ?? .unspecified
        var carried: [String: Double] = [:]
        var result: [ProgressBodySnapshot] = []
        for m in measurements {
            for field in BodyMeasurement.fields {
                if let v = m.value(for: field.key) { carried[field.key] = v }
            }
            let bodyFat = m.bodyFatPercent ?? profile?.bodyFatPercent
            let weight = closestWeight(to: m.date) ?? fallbackWeight
            let shape = ProgressBodyShape.make(heightCm: height, weightKg: weight, measurement: carried, bodyFat: bodyFat, sex: sex)
            result.append(ProgressBodySnapshot(id: m.id.uuidString, date: m.date, shape: shape, isMeasured: true))
        }
        let lastDate = measurements.last?.date ?? .distantPast
        if let latest = weights.last, latest.date.timeIntervalSince(lastDate) > 86_400 || result.isEmpty {
            let shape = ProgressBodyShape.make(heightCm: height, weightKg: latest.kg, measurement: carried,
                                               bodyFat: profile?.bodyFatPercent, sex: sex)
            result.append(ProgressBodySnapshot(id: "weight-\(latest.id.uuidString)", date: latest.date, shape: shape, isMeasured: !carried.isEmpty))
        } else if result.isEmpty {
            let shape = ProgressBodyShape.make(heightCm: height, weightKg: fallbackWeight, measurement: [:],
                                               bodyFat: profile?.bodyFatPercent, sex: sex)
            result.append(ProgressBodySnapshot(id: "profile", date: .now, shape: shape, isMeasured: false))
        }
        return result
    }

    private func closestWeight(to date: Date) -> Double? {
        weights.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }?.kg
    }

    private var targetOverrides: [String: Double] {
        ["shoulder": targetShoulder, "chest": targetChest, "waist": targetWaist,
         "hip": targetHip, "thigh": targetThigh, "arm": targetArm]
    }

    private var effectiveTargetWeight: Double? {
        targetWeight > 30 ? targetWeight : profile?.targetWeightKg
    }

    private func targetShape(from base: ProgressBodyShape) -> ProgressBodyShape {
        base.target(weightKg: effectiveTargetWeight, goal: profile?.primaryGoal ?? .healthierLife, overrides: targetOverrides)
    }

    private var currentSnapshot: ProgressBodySnapshot {
        let all = snapshots
        let index = timelineIndex < 0 ? all.count - 1 : min(Int(timelineIndex.rounded()), all.count - 1)
        return all[max(index, 0)]
    }

    /// Die (bis zu zwei) dargestellten Formen mit Beschriftung.
    private var displayed: [(title: String, shape: ProgressBodyShape, color: Color)] {
        let all = snapshots
        guard let latest = all.last else { return [] }
        switch mode {
        case .single:
            let base = currentSnapshot.shape
            return showsTarget
                ? [("Ziel (illustrativ)", targetShape(from: latest.shape), Theme.accent)]
                : [(Fmt.mediumDate(currentSnapshot.date), base, Theme.weight)]
        case .sideBySide, .overlay:
            if comparison == .timepoints, all.count >= 2 {
                let before = all.first { $0.id == beforeID } ?? all[0]
                let after = all.first { $0.id == afterID } ?? latest
                return [("Vorher · \(Fmt.mediumDate(before.date))", before.shape, Theme.weight),
                        ("Nachher · \(Fmt.mediumDate(after.date))", after.shape, Theme.accent)]
            }
            return [("Aktuell", latest.shape, Theme.weight), ("Ziel (illustrativ)", targetShape(from: latest.shape), Theme.accent)]
        }
    }

    private var sceneKey: String {
        let shapes = displayed.map { s in
            [s.shape.heightCm, s.shape.weightKg, s.shape.shoulder, s.shape.chest, s.shape.waist, s.shape.hip, s.shape.thigh, s.shape.arm]
                .map { String(format: "%.1f", $0) }.joined(separator: ",")
        }.joined(separator: "|")
        return "\(mode.rawValue)-\(colorScheme == .dark)-\(shapes)"
    }

    // MARK: Body

    var body: some View {
        Group {
            if prefs.isEnabled(.bodyAvatar) {
                content
            } else {
                ContentUnavailableView {
                    Label("3D-Körper ist deaktiviert", systemImage: "figure.stand")
                } description: {
                    Text("Die Körperdarstellung ist optional. Du kannst deinen Fortschritt auch vollständig ohne Körperbilder dokumentieren.")
                } actions: {
                    Button("Modul aktivieren") { prefs.setModule(.bodyAvatar, enabled: true) }
                        .buttonStyle(.glassProminent)
                }
            }
        }
        .navigationTitle("3D-Körper")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                InfoNote(text: "Illustrative Darstellung aus deinen Angaben – keine medizinisch exakte Körpervermessung. Die Zieldarstellung ist ein Szenario, keine verlässliche Vorhersage.",
                         symbol: "exclamationmark.circle", tint: Theme.warning)

                Picker("Ansicht", selection: $mode) {
                    ForEach(ProgressAvatarMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                if mode == .single {
                    Picker("Modell", selection: $showsTarget) {
                        Text("Aktuell").tag(false)
                        Text("Ziel").tag(true)
                    }
                    .pickerStyle(.segmented)
                } else {
                    comparisonControls
                }

                sceneCard

                if mode == .single, !showsTarget, snapshots.count >= 2 {
                    timeline
                }

                valuesCard

                Button {
                    isEditingTarget = true
                } label: {
                    Label("Zielwerte anpassen", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
            .padding(Theme.screenPadding)
        }
        .background(Theme.background)
        .onChange(of: sceneKey, initial: true) { _, _ in refreshScene() }
        .sheet(isPresented: $isEditingTarget) { targetEditor }
    }

    private var comparisonControls: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Picker("Vergleich", selection: $comparison) {
                ForEach(ProgressAvatarComparison.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if comparison == .timepoints {
                let all = snapshots
                if all.count >= 2 {
                    HStack {
                        Picker("Vorher", selection: Binding(get: { beforeID ?? all[0].id }, set: { beforeID = $0 })) {
                            ForEach(all) { Text(Fmt.mediumDate($0.date)).tag($0.id) }
                        }
                        Spacer()
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        Spacer()
                        Picker("Nachher", selection: Binding(get: { afterID ?? all[all.count - 1].id }, set: { afterID = $0 })) {
                            ForEach(all) { Text(Fmt.mediumDate($0.date)).tag($0.id) }
                        }
                    }
                    .pickerStyle(.menu)
                } else {
                    Text("Für einen Vergleich von Zeitpunkten braucht es mindestens zwei Messungen. Angezeigt wird Aktuell & Ziel.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var sceneCard: some View {
        VStack(spacing: 0) {
            ProgressSceneContainer(avatar: avatar)
                .frame(height: 440)
                .overlay(alignment: .bottom) {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(ProgressAvatarAngle.allCases) { a in
                                Button(a.title) {
                                    angle = a
                                    avatar.resetCamera()
                                    avatar.setRotation(a.angle)
                                }
                                .font(.footnote.weight(angle == a ? .semibold : .regular))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .glassEffect(angle == a ? Glass.regular.tint(Theme.accent.opacity(0.25)).interactive() : Glass.regular.interactive(), in: .capsule)
                                .buttonStyle(.plain)
                            }
                            GlassIconButton(systemImage: "minus.magnifyingglass", accessibilityLabel: "Verkleinern", size: 36) {
                                avatar.zoom(in: false)
                            }
                            GlassIconButton(systemImage: "plus.magnifyingglass", accessibilityLabel: "Vergrössern", size: 36) {
                                avatar.zoom(in: true)
                            }
                        }
                    }
                    .padding(.bottom, Theme.Space.s)
                }

            HStack(spacing: Theme.Space.m) {
                ForEach(Array(displayed.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 6) {
                        Circle().fill(item.color).frame(width: 8, height: 8)
                        Text(item.title).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(Theme.Space.s)
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var timeline: some View {
        Card {
            CardHeader(title: "Zeitleiste", symbol: "clock")
            let all = snapshots
            Slider(value: Binding(get: { timelineIndex < 0 ? Double(all.count - 1) : timelineIndex },
                                  set: { timelineIndex = $0 }),
                   in: 0...Double(max(all.count - 1, 1)), step: 1)
            HStack {
                Text(Fmt.mediumDate(all[0].date))
                Spacer()
                Text(Fmt.mediumDate(currentSnapshot.date)).fontWeight(.semibold)
                Spacer()
                Text(Fmt.mediumDate(all[all.count - 1].date))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var valuesCard: some View {
        Card {
            CardHeader(title: "Dargestellte Werte", symbol: "ruler")
            let items = displayed
            ForEach(ProgressBodyShape.fieldTitles, id: \.key) { field in
                HStack {
                    Text(field.title).font(.subheadline)
                    Spacer()
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        let estimated = item.shape.estimated.contains(field.key)
                        Text("\(Fmt.number(item.shape.value(field.key))) cm\(estimated ? "*" : "")")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(estimated ? Color.secondary : item.color)
                            .frame(minWidth: 72, alignment: .trailing)
                    }
                }
            }
            Text("* geschätzt aus Grösse und Gewicht, nicht gemessen")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var targetEditor: some View {
        NavigationStack {
            Form {
                Section {
                    NumberField(title: "Zielgewicht", value: binding($targetWeight), unit: "kg")
                } footer: {
                    Text(profile?.targetWeightKg != nil ? "Leer lassen, um dein Wunschgewicht aus dem Profil zu verwenden." : "Nur für die Darstellung – verändert keine Berechnungen.")
                }
                Section("Zielumfänge (optional)") {
                    NumberField(title: "Schultern", value: binding($targetShoulder), unit: "cm")
                    NumberField(title: "Brust", value: binding($targetChest), unit: "cm")
                    NumberField(title: "Taille", value: binding($targetWaist), unit: "cm")
                    NumberField(title: "Hüfte", value: binding($targetHip), unit: "cm")
                    NumberField(title: "Oberschenkel", value: binding($targetThigh), unit: "cm")
                    NumberField(title: "Oberarm", value: binding($targetArm), unit: "cm")
                }
                Section {
                    Button("Zielwerte zurücksetzen", role: .destructive) {
                        targetWeight = 0; targetShoulder = 0; targetChest = 0
                        targetWaist = 0; targetHip = 0; targetThigh = 0; targetArm = 0
                    }
                }
            }
            .navigationTitle("Zieldarstellung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { isEditingTarget = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func binding(_ source: Binding<Double>) -> Binding<Double?> {
        Binding(get: { source.wrappedValue > 0 ? source.wrappedValue : nil },
                set: { source.wrappedValue = $0 ?? 0 })
    }

    private func refreshScene() {
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        let traits = UITraitCollection(userInterfaceStyle: style)
        let items = displayed
        let overlay = mode == .overlay
        let specs: [ProgressAvatarScene.BodySpec] = items.enumerated().map { index, item in
            let color = UIColor(item.color).resolvedColor(with: traits)
            let offset: Float
            if items.count == 2 && mode == .sideBySide {
                offset = index == 0 ? -0.4 : 0.4
            } else {
                offset = 0
            }
            return ProgressAvatarScene.BodySpec(shape: item.shape, color: color,
                                                opacity: overlay && items.count == 2 ? 0.5 : 1, xOffset: offset)
        }
        avatar.update(specs)
    }
}
