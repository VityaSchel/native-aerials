import CoreGraphics
import Foundation
import ImageIO
import Observation

@Observable
final class ThumbnailStore {
	private(set) var images: [String: CGImage] = [:]
	@ObservationIgnored private var sources: [String: URL] = [:]

	func update(_ wanted: [String: URL], reloadingAll: Bool = false) async {
		let changed = reloadingAll ? wanted : wanted.filter { sources[$0.key] != $0.value }
		let removed = sources.keys.filter { wanted[$0] == nil }
		guard !changed.isEmpty || !removed.isEmpty else {
			return
		}
		sources = wanted
		let loaded = await ThumbnailDecoder.decode(changed)
		for id in removed where sources[id] == nil {
			images[id] = nil
		}
		for (id, url) in changed where sources[id] == url {
			images[id] = loaded[id]
		}
	}
}

nonisolated enum ThumbnailDecoder {
	static let maxPixelSize = 428

	@concurrent
	static func decode(_ sources: [String: URL]) async -> [String: CGImage] {
		await withTaskGroup(of: (String, CGImage?).self) { group in
			for (id, url) in sources {
				group.addTask {
					(id, image(at: url))
				}
			}
			var images: [String: CGImage] = [:]
			for await (id, image) in group {
				images[id] = image
			}
			return images
		}
	}

	static func image(at url: URL) -> CGImage? {
		guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
			return nil
		}
		let options: [CFString: Any] = [
			kCGImageSourceCreateThumbnailFromImageAlways: true,
			kCGImageSourceCreateThumbnailWithTransform: true,
			kCGImageSourceShouldCacheImmediately: true,
			kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
		]
		return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
	}
}
