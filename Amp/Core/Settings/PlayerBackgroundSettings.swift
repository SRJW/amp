import Foundation

enum PlayerGradientStyle: String, CaseIterable, Codable, Identifiable {
    case classic
    case deepChromatic
    case frostedArtwork

    var id: String { rawValue }

    var label: String {
        switch self {
        case .classic: "Classic"
        case .deepChromatic: "Deep chromatic"
        case .frostedArtwork: "Frosted artwork"
        }
    }

    var description: String {
        switch self {
        case .classic: "Soft muted single-tone fade beneath the album cover."
        case .deepChromatic: "Rich 3-stop hue-shifted gradient that deepens at the bottom."
        case .frostedArtwork: "Full-bleed blurred continuation of the album cover with a luminous haze."
        }
    }
}

/// Defaults reproduce the existing player; these affect appearance only.
struct PlayerBackgroundSettings: Codable, Equatable {
    var fadeStart = 0.75
    var blur = 24.0
    var details = 0.0
    var intensity = 1.0
    var saturation = 1.0
    var gradient = 0.0
    var gradientColor: UInt32 = 0xFF000000
    var gradientStyle: PlayerGradientStyle = .classic
    var navBarCapsule = false
    var buttonOpacity = 1.0

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fadeStart = try c.decodeIfPresent(Double.self, forKey: .fadeStart) ?? 0.75
        blur = try c.decodeIfPresent(Double.self, forKey: .blur) ?? 24
        details = try c.decodeIfPresent(Double.self, forKey: .details) ?? 0
        intensity = try c.decodeIfPresent(Double.self, forKey: .intensity) ?? 1
        saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 1
        gradient = try c.decodeIfPresent(Double.self, forKey: .gradient) ?? 0
        gradientColor = try c.decodeIfPresent(UInt32.self, forKey: .gradientColor) ?? 0xFF000000
        gradientStyle = (try? c.decodeIfPresent(PlayerGradientStyle.self, forKey: .gradientStyle)) ?? .classic
        navBarCapsule = (try? c.decodeIfPresent(Bool.self, forKey: .navBarCapsule)) ?? false
        buttonOpacity = (try? c.decodeIfPresent(Double.self, forKey: .buttonOpacity)) ?? 1.0
    }
}

enum PlayerBackgroundControls {
    static let previewHeight = 180.0
    static let title = "Player artwork & background"
    static let blurStyleSection = "Blur style"
    static let controlsSection = "Controls & contour"
    static let fineTuningSection = "Fine-tuning"
    static let gradientStyle = "Backdrop gradient"
    static let navBarCapsule = "Navigation bar contour"
    static let navBarCapsuleDescription = "Adds an artwork-tinted capsule behind the bottom controls in the player."
    static let buttonOpacity = "Control button opacity"
    static let buttonOpacityDescription = "Opacity of the circles behind Play, Pause, and skip controls. Set to 0% for borderless icons."
    static let gradient = "Tint overlay"
    static let gradientDescription = "Optional dark or colored wash over the lower edge."
    static let gradientColor = "Tint color"
    static let fade = "Artwork fade"
    static let fadeDescription = "Where the sharp cover begins to dissolve into the backdrop."
    static let blur = "Background blur"
    static let blurDescription = "Softness of the blurred artwork layer."
    static let details = "Background details"
    static let detailsDescription = "Amount of blurred cover texture visible in the backdrop."
    static let intensity = "Background intensity"
    static let intensityDescription = "Overall brightness of the lower backdrop."
    static let saturation = "Background saturation"
    static let saturationDescription = "Color vividness of the backdrop."
    static let reset = "Restore background defaults"
    static let blurRange = 0.0...60.0
    static let unitRange = 0.0...1.0
    static let saturationRange = 0.0...2.0
}
