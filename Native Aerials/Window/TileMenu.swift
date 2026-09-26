import SwiftUI

struct TileMoreMenu: View {
	static let removeTitle = "Remove Download"

	let remove: () -> Void

	var body: some View {
		Menu {
			Button(Self.removeTitle, action: remove)
		} label: {
			BadgeSymbol(name: "ellipsis")
				.frame(width: TileMetrics.menuHitSize, height: TileMetrics.menuHitSize)
				.contentShape(Rectangle())
		}
		.menuStyle(.button)
		.buttonStyle(.plain)
		.menuIndicator(.hidden)
		.fixedSize()
		.accessibilityLabel("More Options")
	}
}

struct RemovableTile: ViewModifier {
	let canRemove: Bool
	let remove: () -> Void

	@State private var isHovered = false

	func body(content: Content) -> some View {
		content
			.accessibilityActions {
				if canRemove {
					Button(TileMoreMenu.removeTitle, action: remove)
				}
			}
			.overlay(alignment: .bottomTrailing) {
				if canRemove && isHovered {
					TileMoreMenu(remove: remove)
						.padding([.bottom, .trailing], TileMetrics.badgeInset - (TileMetrics.menuHitSize - TileMetrics.badgeSize) / 2)
				}
			}
			.onHover { isHovered = $0 }
			.contextMenu {
				if canRemove {
					Button(TileMoreMenu.removeTitle, action: remove)
				}
			}
	}
}

extension View {
	func removableTile(_ canRemove: Bool, remove: @escaping () -> Void) -> some View {
		modifier(RemovableTile(canRemove: canRemove, remove: remove))
	}
}
