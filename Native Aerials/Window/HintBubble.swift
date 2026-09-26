import AppKit
import SwiftUI

struct HintBubble: View {
	let text: String
	var thumbnail: NSImage?

	var body: some View {
		HStack(spacing: 8) {
			if let thumbnail {
				Image(nsImage: thumbnail)
					.resizable()
					.aspectRatio(contentMode: .fill)
					.frame(width: 48, height: 32)
					.clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
			}
			Text(text)
				.font(.callout)
		}
		.padding(EdgeInsets(top: 7, leading: thumbnail == nil ? 12 : 7, bottom: 7 + HintShape.arrowHeight, trailing: 12))
		.background(VisualEffectBackground(material: .popover))
		.clipShape(HintShape())
		.fixedSize()
		.accessibilityHidden(true)
	}
}

nonisolated struct HintShape: Shape {
	static let arrowHeight: CGFloat = 8

	func path(in rect: CGRect) -> Path {
		let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - Self.arrowHeight)
		let arrow = Path { path in
			path.move(to: CGPoint(x: rect.midX - Self.arrowHeight - 1, y: body.maxY - 1))
			path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
			path.addLine(to: CGPoint(x: rect.midX + Self.arrowHeight + 1, y: body.maxY - 1))
		}
		return Path(roundedRect: body, cornerRadius: 10, style: .continuous).union(arrow)
	}
}
