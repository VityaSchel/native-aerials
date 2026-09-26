import SwiftUI

nonisolated struct TileImageShape: Shape {
	var inset: CGFloat
	var radius: CGFloat

	init(isSelected: Bool) {
		inset = isSelected ? TileMetrics.selectedInset : TileMetrics.hairlineWidth
		radius = isSelected ? TileMetrics.selectedImageRadius : TileMetrics.cornerRadius - TileMetrics.hairlineWidth
	}

	var animatableData: AnimatablePair<CGFloat, CGFloat> {
		get { AnimatablePair(inset, radius) }
		set { (inset, radius) = (newValue.first, newValue.second) }
	}

	func path(in rect: CGRect) -> Path {
		RoundedRectangle(cornerRadius: radius, style: .continuous)
			.path(in: rect.insetBy(dx: inset, dy: inset))
	}
}

struct TileArtwork: View {
	let image: CGImage?
	let hasSource: Bool

	var body: some View {
		Group {
			if let image {
				Image(decorative: image, scale: 2)
					.resizable()
					.aspectRatio(contentMode: .fill)
					.frame(width: TileMetrics.imageSize.width, height: TileMetrics.imageSize.height)
					.clipped()
			} else {
				Rectangle()
					.fill(.quaternary)
					.overlay {
						if !hasSource {
							Image(systemName: "photo.badge.exclamationmark")
								.font(.title3)
								.foregroundStyle(.secondary)
						}
					}
			}
		}
		.frame(width: TileMetrics.size.width, height: TileMetrics.size.height)
		.clipped()
	}
}

struct TileFace<Artwork: View>: View {
	let isSelected: Bool
	var isMerged = false
	var animatesMerge = true
	@ViewBuilder let artwork: Artwork

	var body: some View {
		artwork
			.frame(width: TileMetrics.size.width, height: TileMetrics.size.height)
			.animation(TileChrome.animation) { content in
				content
					.clipShape(TileImageShape(isSelected: isSelected))
					.transaction(value: isMerged) { transaction in
						if !animatesMerge {
							transaction.animation = nil
						}
					}
			}
	}
}

struct TileChrome: View {
	static let animation = Animation.easeOut(duration: 0.15)

	let isSelected: Bool

	@Environment(\.colorScheme) private var colorScheme
	@Environment(\.appearsActive) private var appearsActive

	var body: some View {
		ZStack {
			TileMetrics.shape
				.strokeBorder(hairlineColor, lineWidth: TileMetrics.hairlineStroke)
				.animation(Self.animation) { hairline in
					hairline.opacity(isSelected ? 0 : 1)
				}
			RoundedRectangle(cornerRadius: TileMetrics.ringRadius, style: .continuous)
				.stroke(ringColor, lineWidth: TileMetrics.ringWidth)
				.padding(-TileMetrics.ringCenterOutset)
				.animation(Self.animation) { ring in
					ring.opacity(isSelected ? 1 : 0)
				}
		}
		.allowsHitTesting(false)
	}

	private var hairlineColor: Color {
		(colorScheme == .dark ? Color.white : .black).opacity(TileMetrics.hairlineOpacity)
	}

	private var ringColor: Color {
		Color(nsColor: appearsActive ? .selectedContentBackgroundColor : .unemphasizedSelectedContentBackgroundColor)
	}
}

struct TileButtonStyle: ButtonStyle {
	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.opacity(configuration.isPressed ? 0.8 : 1)
	}
}

nonisolated struct FlashKeyframes: Keyframes {
	var body: some Keyframes<Double> {
		CubicKeyframe(1, duration: 0.12)
		LinearKeyframe(1, duration: 0.9)
		CubicKeyframe(0, duration: 0.6)
	}
}

struct MissingFlash: ViewModifier {
	let trigger: Int

	func body(content: Content) -> some View {
		content.overlay {
			KeyframeAnimator(initialValue: 0.0, trigger: trigger) { glow in
				RoundedRectangle(cornerRadius: TileMetrics.ringRadius, style: .continuous)
					.stroke(.red, lineWidth: TileMetrics.ringWidth)
					.padding(-TileMetrics.ringCenterOutset)
					.opacity(glow)
			} keyframes: { _ in
				FlashKeyframes()
			}
			.allowsHitTesting(false)
		}
	}
}

extension View {
	func missingFlash(_ trigger: Int) -> some View {
		modifier(MissingFlash(trigger: trigger))
	}
}
