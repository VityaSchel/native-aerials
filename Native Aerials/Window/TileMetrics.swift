import SwiftUI

nonisolated enum TileMetrics {
	static let size = CGSize(width: 108.5, height: 72)
	static let cornerRadius: CGFloat = 4.5
	static let hairlineWidth: CGFloat = 0.5
	static let imageSize = CGSize(width: size.width - 2 * hairlineWidth, height: size.height - 2 * hairlineWidth)
	static let hairlineStroke: CGFloat = 1
	static let hairlineOpacity = 0.08

	static let ringWidth: CGFloat = 2
	static let ringOutset: CGFloat = 0.5
	static let ringGap: CGFloat = 0.75
	static let ringCenterOutset = ringOutset - ringWidth / 2
	static let ringRadius = cornerRadius + ringCenterOutset
	static let selectedInset = ringWidth - ringOutset + ringGap
	static let selectedImageRadius = ringRadius - ringGap

	static let badgeSize: CGFloat = 13
	static let menuHitSize: CGFloat = 21
	static let badgeFontSize: CGFloat = 11
	static let badgeInset = hairlineWidth + 5
	static let badgeShadowOpacity = 0.65
	static let badgeShadowRadius: CGFloat = 2

	static let sliceLean: CGFloat = 0.2
	static let seamWidth: CGFloat = 1
	static let seamOpacity = 0.7

	static let captionFont = Font.caption
	static let captionSpacing: CGFloat = 3
	static let captionLineLimit = 2

	static let columns = SunRole.allCases.count
	static let columnSpacing: CGFloat = 9
	static let rowSpacing: CGFloat = 16
	static let windowPadding: CGFloat = 20
	static let footnoteSpacing: CGFloat = 14
	static let footnoteLineLimit = 3

	static let rowWidth = CGFloat(columns) * size.width + CGFloat(columns - 1) * columnSpacing
	static let mergedOffset = (rowWidth - size.width) / 2

	static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous) }

	static func offset(ofColumn column: Int) -> CGFloat {
		CGFloat(column) * (size.width + columnSpacing)
	}
}
