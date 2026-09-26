import SwiftUI

struct TileBadges: View {
	let status: TileStatus
	var flash = 0

	var body: some View {
		Color.clear
			.frame(width: TileMetrics.size.width, height: TileMetrics.size.height)
			.overlay(alignment: .bottomLeading) {
				BadgeSymbol(name: "play.rectangle.fill")
					.padding([.bottom, .leading], TileMetrics.badgeInset)
			}
			.overlay(alignment: .bottomTrailing) {
				KeyframeAnimator(initialValue: 0.0, trigger: flash) { glow in
					BadgeSymbol(name: "arrow.down.circle", glow: glow)
				} keyframes: { _ in
					FlashKeyframes()
				}
				.opacity(status == .missing ? 1 : 0)
				.padding([.bottom, .trailing], TileMetrics.badgeInset)
			}
			.overlay(alignment: .topTrailing) {
				if case .downloading(let percent) = status {
					ProgressView(value: Double(percent), total: 100)
						.progressViewStyle(.circular)
						.controlSize(.small)
						.padding([.top, .trailing], TileMetrics.badgeInset)
						.transition(.opacity)
				}
			}
			.animation(.easeOut(duration: 0.2), value: status)
			.allowsHitTesting(false)
			.accessibilityHidden(true)
	}
}

struct BadgeSymbol: View {
	let name: String
	var glow = 0.0

	var body: some View {
		ZStack {
			symbol
				.foregroundStyle(.primary)
				.environment(\.colorScheme, .dark)
				.opacity(1 - glow)
			if glow > 0 {
				symbol
					.foregroundStyle(.red)
					.opacity(glow)
			}
		}
		.shadow(color: .black.opacity(TileMetrics.badgeShadowOpacity), radius: TileMetrics.badgeShadowRadius)
		.frame(width: TileMetrics.badgeSize, height: TileMetrics.badgeSize)
	}

	private var symbol: some View {
		Image(systemName: name)
			.font(.system(size: TileMetrics.badgeFontSize, weight: .medium))
	}
}
