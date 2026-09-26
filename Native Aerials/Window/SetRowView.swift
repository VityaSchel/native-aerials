import SwiftUI

struct SetRowView: View {
	let row: SetRow
	let images: [String: CGImage]
	let choose: (TileItem) -> Void
	let chooseMerged: (SetRow) -> Void
	let remove: (AerialChoice) -> Void

	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	private var slide: Animation {
		reduceMotion ? .easeInOut(duration: 0.3) : .smooth(duration: 0.6)
	}

	private var morphs: Bool { row.isMerged && !reduceMotion }

	private func mergeAnimation(_ animation: Animation?) -> Animation? {
		row.animatesMerge ? animation : nil
	}

	private var chromeFade: Animation? {
		if reduceMotion {
			return slide
		}
		return row.isMerged ? nil : slide.delay(0.4)
	}

	private var captionFade: Animation {
		row.isMerged ? TileChrome.animation : slide.delay(reduceMotion ? 0 : 0.3)
	}

	var body: some View {
		ZStack(alignment: .topLeading) {
			ForEach(Array(row.tiles.enumerated()), id: \.element.id) { column, tile in
				variantTile(tile, column: column)
			}
			mergedTile
				.offset(x: TileMetrics.mergedOffset)
		}
		.frame(width: TileMetrics.rowWidth, alignment: .topLeading)
		.accessibilityElement(children: .contain)
		.accessibilityLabel(row.name)
	}

	private func variantTile(_ tile: TileItem, column: Int) -> some View {
		let offset = TileMetrics.offset(ofColumn: column)
		return VStack(spacing: TileMetrics.captionSpacing) {
			Button {
				choose(tile)
			} label: {
				TileFace(isSelected: row.isMerged ? row.isSelected : tile.isSelected, isMerged: row.isMerged, animatesMerge: row.animatesMerge) {
					TileArtwork(image: images[tile.id], hasSource: tile.thumbnail != nil || tile.status == .loading)
						.slice(column, of: row.tiles.count, amount: morphs ? 1 : 0)
				}
				.overlay {
					ZStack {
						TileChrome(isSelected: tile.isSelected)
						TileBadges(status: tile.status, flash: tile.flash)
					}
					.animation(mergeAnimation(chromeFade)) { chrome in
						chrome.opacity(row.isMerged ? 0 : 1)
					}
				}
				.missingFlash(tile.flash)
				.contentShape(TileMetrics.shape)
			}
			.buttonStyle(TileButtonStyle())
			.accessibilityLabel(tile.name)
			.accessibilityValue(tile.status.accessibilityValue)
			.accessibilityHint(tile.status.accessibilityHint)
			.accessibilityAddTraits(tile.isSelected ? .isSelected : [])
			.removableTile(tile.canRemove && !row.isMerged) {
				remove(.video(tile.id))
			}
			.disabled(row.isMerged || tile.status == .loading)
			.offset(x: morphs ? TileMetrics.mergedOffset - offset : 0)
			TileCaption(text: tile.name)
				.opacity(row.isMerged ? 0 : 1)
				.animation(mergeAnimation(captionFade), value: row.isMerged)
		}
		.opacity(reduceMotion && row.isMerged ? 0 : 1)
		.accessibilityHidden(row.isMerged)
		.offset(x: offset)
		.animation(mergeAnimation(slide), value: row.isMerged)
	}

	private var mergedTile: some View {
		VStack(spacing: TileMetrics.captionSpacing) {
			Button {
				chooseMerged(row)
			} label: {
				ZStack {
					if reduceMotion {
						TileFace(isSelected: row.isSelected) {
							MergedArtwork(tiles: row.tiles, images: images)
						}
					}
					TileChrome(isSelected: row.isSelected)
						.frame(width: row.isMerged || reduceMotion ? TileMetrics.size.width : TileMetrics.rowWidth)
						.animation(mergeAnimation(slide), value: row.isMerged)
					TileBadges(status: .ready)
				}
				.frame(width: TileMetrics.size.width, height: TileMetrics.size.height)
				.contentShape(TileMetrics.shape)
			}
			.buttonStyle(TileButtonStyle())
			.accessibilityLabel(row.name)
			.accessibilityHint("Sets a wallpaper that follows the sun")
			.accessibilityAddTraits(row.isSelected ? .isSelected : [])
			.removableTile(row.canRemove && row.isMerged) {
				remove(.automatic(row.id))
			}
			.disabled(!row.isMerged)
			TileCaption(text: row.name)
		}
		.frame(width: TileMetrics.size.width)
		.opacity(row.isMerged ? 1 : 0)
		.accessibilityHidden(!row.isMerged)
		.animation(mergeAnimation(mergedFade), value: row.isMerged)
	}

	private var mergedFade: Animation {
		if reduceMotion {
			return slide
		}
		return row.isMerged ? .easeOut(duration: 0.2).delay(0.5) : .easeOut(duration: 0.1)
	}
}

struct TileCaption: View {
	let text: String

	var body: some View {
		Text(text)
			.font(TileMetrics.captionFont)
			.foregroundStyle(.primary)
			.multilineTextAlignment(.center)
			.lineLimit(TileMetrics.captionLineLimit)
			.fixedSize(horizontal: false, vertical: true)
			.frame(width: TileMetrics.size.width, alignment: .top)
			.accessibilityHidden(true)
	}
}
