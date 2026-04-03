import SwiftUI

enum DesignTokens {
    // MARK: - Spacing (matches CSS --space-*)
    static let spaceXS: CGFloat = 4
    static let spaceSM: CGFloat = 8
    static let spaceMD: CGFloat = 16
    static let spaceLG: CGFloat = 24
    static let spaceXL: CGFloat = 32
    static let space2XL: CGFloat = 48

    // MARK: - Corner Radius (matches CSS --border-radius*)
    static let cornerRadius: CGFloat = 12
    static let cornerRadiusSM: CGFloat = 8
    static let cornerRadiusPill: CGFloat = 100

    // MARK: - Typography
    static let heroTempSize: CGFloat = 96
    static let phraseSize: CGFloat = 20
    static let sectionTitleSize: CGFloat = 18
    static let bodySize: CGFloat = 16
    static let captionSize: CGFloat = 12
    static let smallSize: CGFloat = 14

    // MARK: - Layout
    static let maxWidth: CGFloat = 900
    static let headerHeight: CGFloat = 64

    // MARK: - Weather Icon Size
    static let heroIconSize: CGFloat = 100
    static let hourlyIconSize: CGFloat = 28
    static let dailyIconSize: CGFloat = 24
    static let detailIconSize: CGFloat = 20
}
