import SwiftUI

struct AerialsPanel: View {
	let rows: [SetRow]
	let isLoaded: Bool
	let images: [String: CGImage]
	let footnote: Footnote?
	let choose: (TileItem) -> Void
	let chooseMerged: (SetRow) -> Void
	let remove: (AerialChoice) -> Void
	let open: (SettingsPane) -> Void

	@State private var shownFootnote: Footnote?

	private static let fade = Animation.easeOut(duration: 0.2)

	var body: some View {
		VStack(spacing: TileMetrics.footnoteSpacing) {
			VStack(spacing: TileMetrics.rowSpacing) {
				ForEach(rows) { row in
					SetRowView(row: row, images: images, choose: choose, chooseMerged: chooseMerged, remove: remove)
				}
			}
			.id(isLoaded)
			.opacity(isLoaded ? 1 : 0)
			if let shownFootnote {
				FootnoteView(footnote: shownFootnote, open: open)
					.transition(.opacity.animation(Self.fade))
			}
		}
		.frame(width: TileMetrics.rowWidth)
		.padding(TileMetrics.windowPadding)
		.onChange(of: footnote, initial: true) { _, footnote in
			withAnimation(footnote == nil ? Self.fade.delay(0.2) : Self.fade) {
				shownFootnote = footnote
			}
			if let footnote {
				AccessibilityNotification.Announcement(footnote.text).post()
			}
		}
	}
}

struct FootnoteView: View {
	private static let actionURL = URL(string: "native-aerials:open-settings")!

	let footnote: Footnote
	let open: (SettingsPane) -> Void

	var body: some View {
		Text(attributed)
			.font(.callout)
			.multilineTextAlignment(.center)
			.lineLimit(TileMetrics.footnoteLineLimit)
			.fixedSize(horizontal: false, vertical: true)
			.frame(maxWidth: .infinity)
			.environment(\.openURL, OpenURLAction { _ in
				footnote.action.map(open)
				return .handled
			})
	}

	private var attributed: AttributedString {
		var text = AttributedString(footnote.text)
		text.foregroundColor = color(footnote.tone)
		guard let action = footnote.action else {
			return text
		}
		var link = AttributedString(action.linkTitle)
		link.link = Self.actionURL
		return text + AttributedString(" ") + link
	}

	private func color(_ tone: Footnote.Tone) -> Color {
		switch tone {
		case .info: .secondary
		case .warning: .orange
		case .error: .red
		}
	}
}
