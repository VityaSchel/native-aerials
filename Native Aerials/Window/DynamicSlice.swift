import SwiftUI

nonisolated struct DynamicSlice: Shape {
	var index: Int
	var count: Int
	var amount: Double
	var isSeam = false

	var animatableData: Double {
		get { amount }
		set { amount = newValue }
	}

	func path(in rect: CGRect) -> Path {
		let left = edge(index, in: rect, resting: rect.minX - rect.width)
		var path = Path()
		path.move(to: CGPoint(x: left.bottom, y: rect.maxY))
		path.addLine(to: CGPoint(x: left.top, y: rect.minY))
		guard !isSeam else {
			return path
		}
		let right = edge(index + 1, in: rect, resting: rect.maxX + rect.width)
		path.addLine(to: CGPoint(x: right.top, y: rect.minY))
		path.addLine(to: CGPoint(x: right.bottom, y: rect.maxY))
		path.closeSubpath()
		return path
	}

	private func edge(_ boundary: Int, in rect: CGRect, resting: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
		guard boundary > 0, boundary < count else {
			return (resting, resting)
		}
		let x = rect.minX + rect.width * CGFloat(boundary) / CGFloat(count)
		let shift = rect.height * TileMetrics.sliceLean / 2
		let progress = CGFloat(min(max(amount, 0), 1))
		return (resting + (x + shift - resting) * progress, resting + (x - shift - resting) * progress)
	}
}

extension View {
	func slice(_ index: Int, of count: Int, amount: Double) -> some View {
		clipShape(DynamicSlice(index: index, count: count, amount: amount))
			.overlay {
				DynamicSlice(index: index, count: count, amount: amount, isSeam: true)
					.stroke(.white.opacity(TileMetrics.seamOpacity), lineWidth: TileMetrics.seamWidth)
			}
	}
}

struct MergedArtwork: View {
	let tiles: [TileItem]
	let images: [String: CGImage]

	var body: some View {
		ZStack {
			ForEach(Array(tiles.enumerated()), id: \.element.id) { column, tile in
				TileArtwork(image: images[tile.id], hasSource: true)
					.slice(column, of: tiles.count, amount: 1)
			}
		}
	}
}
