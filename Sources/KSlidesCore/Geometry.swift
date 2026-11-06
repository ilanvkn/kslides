import Foundation

public enum GeometryKind: String, Codable, CaseIterable, Sendable {
    case circle, square, sphere, cube
    public var label: String { rawValue.capitalized }
    public var isRound: Bool { self == .circle || self == .sphere }
    public var is3D: Bool { self == .sphere || self == .cube }
}

public struct GeometryScene: Codable, Equatable, Sendable {
    public var kind: GeometryKind = .sphere
    public var size: Double = 1
    public var yaw: Double = -35
    public var pitch: Double = 25
    public var unit: String = "units"
    public var texture: String?
    public init() {}
    public func validated() throws -> Self {
        guard size.isFinite, (0.05...1000).contains(size), yaw.isFinite, (-180...180).contains(yaw), pitch.isFinite, (-80...80).contains(pitch) else { throw StudioError.invalid("Use a size from 0.05 to 1,000 and a valid viewpoint.") }
        guard !unit.isEmpty, unit.count <= 16, unit.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(.whitespaces).contains($0) }) else { throw StudioError.invalid("Use a short measurement unit such as cm or units.") }
        if let texture { guard texture == URL(fileURLWithPath:texture).lastPathComponent, !texture.hasPrefix("."), texture.count <= 100 else { throw StudioError.invalid("Textures must be managed artwork filenames.") } }
        return self
    }
    public var measurements: [String:Double] {
        switch kind {
        case .circle: ["radius":size,"diameter":2*size,"area":Double.pi*size*size,"circumference":2*Double.pi*size]
        case .square: ["edge":size,"area":size*size,"perimeter":4*size]
        case .sphere: ["radius":size,"diameter":2*size,"surface_area":4*Double.pi*size*size,"volume":4*Double.pi*pow(size,3)/3]
        case .cube: ["edge":size,"face_area":size*size,"surface_area":6*size*size,"volume":pow(size,3)]
        }
    }
    public var dimensionLabel: String { "\(kind.isRound ? "Radius" : "Side length") = \(size.formatted(.number.locale(Locale(identifier:"en_US")).precision(.fractionLength(0...8)))) \(unit)" }
    public var formula: String {
        switch kind {
        case .circle: "Area = πr² ≈ \(Self.number(measurements["area"]!)) \(unit)²"
        case .square: "Area = s² \(Self.equality(measurements["area"]!)) \(Self.number(measurements["area"]!)) \(unit)²"
        case .sphere: "Volume = (4/3)πr³ ≈ \(Self.number(measurements["volume"]!)) \(unit)³"
        case .cube: "Volume = s³ \(Self.equality(measurements["volume"]!)) \(Self.number(measurements["volume"]!)) \(unit)³"
        }
    }
    public var secondaryFormula: String {
        switch kind {
        case .circle: "Circumference = 2πr ≈ \(Self.number(measurements["circumference"]!)) \(unit)"
        case .square: "Perimeter = 4s \(Self.equality(measurements["perimeter"]!)) \(Self.number(measurements["perimeter"]!)) \(unit)"
        case .sphere: "Surface area = 4πr² ≈ \(Self.number(measurements["surface_area"]!)) \(unit)²"
        case .cube: "Surface area = 6s² \(Self.equality(measurements["surface_area"]!)) \(Self.number(measurements["surface_area"]!)) \(unit)²"
        }
    }
    public static func number(_ value: Double) -> String { value.formatted(.number.locale(Locale(identifier:"en_US")).precision(.fractionLength(0...(abs(value)<0.01 ? 8 : 2)))) }
    private static func equality(_ value: Double) -> String {
        let displayed = Double(number(value).replacingOccurrences(of:",",with:"")) ?? .nan
        return abs(displayed-value) <= max(1,abs(value))*1e-12 ? "=" : "≈"
    }
}

public struct GeometryJob: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var lessonID: UUID
    public var slideID: UUID?
    public var expectedRevision: Int
    public var scene: GeometryScene
    public var title: String
    public var state = "queued"
    public var message = "Waiting for the local rendering connection"
    public var createdAt = Date()
    public var updatedAt = Date()
    public var lease: UUID?
    public var appliedSlideID: UUID?
    public init(lessonID: UUID, slideID: UUID?, expectedRevision: Int, scene: GeometryScene, title: String) {
        self.lessonID = lessonID; self.slideID = slideID; self.expectedRevision = expectedRevision; self.scene = scene; self.title = title
    }
}
